/**
 * Libera cupos de reservas por transferencia que vencieron (expiresAt) sin comprobante.
 * Escala a muchas giras sin depender de que alguien pulse "Limpiar vencidas" en la app.
 */
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

function firmSeatsFromReservaDocs(
  docs: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>[],
  skipId: string,
): number {
  let firm = 0;
  for (const d of docs) {
    if (d.id === skipId) continue;
    const r = (d.data() ?? {}) as AnyMap;
    const e = String(r.estado ?? "").toLowerCase().trim();
    const m = String(r.metodoPago ?? "").toLowerCase().trim();
    const s = Number(r.seats ?? 0);
    if (!Number.isFinite(s) || s <= 0) continue;
    if (e === "pagado") firm += s;
    else if (e === "reservado" && m === "efectivo") firm += s;
  }
  return firm;
}

export const scheduledCleanupExpiredPoolReservations = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "America/Santo_Domingo",
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    const now = Timestamp.now();
    let snap: FirebaseFirestore.QuerySnapshot;
    try {
      snap = await db()
        .collectionGroup("reservas")
        .where("estado", "==", "reservado")
        .where("expiresAt", "<", now)
        .limit(200)
        .get();
    } catch (e) {
      logger.error("scheduledCleanupExpiredPoolReservations: query failed", e);
      return;
    }

    if (snap.empty) return;

    let processed = 0;
    for (const resDoc of snap.docs) {
      const poolRef = resDoc.ref.parent.parent;
      if (!poolRef || poolRef.path.split("/")[0] !== "viajes_pool") continue;

      try {
        await db().runTransaction(async (tx) => {
          const rSnap = await tx.get(resDoc.ref);
          if (!rSnap.exists) return;
          const r = (rSnap.data() ?? {}) as AnyMap;
          if (String(r.estado ?? "").toLowerCase().trim() !== "reservado") return;

          const exp = r.expiresAt;
          if (!(exp instanceof Timestamp) || exp.toMillis() >= now.toMillis()) return;

          const seats = Number(r.seats ?? 0);
          const total = Number(r.total ?? 0);
          if (!Number.isFinite(seats) || seats <= 0) return;

          const poolSnap = await tx.get(poolRef);
          if (!poolSnap.exists) return;
          const p = (poolSnap.data() ?? {}) as AnyMap;

          const occ = Number(p.asientosReservados ?? 0);
          const newOcc = Math.max(0, occ - seats);
          const montoRes = Number(p.montoReservado ?? 0);
          const decTotal = Number.isFinite(total) ? total : 0;
          const newMontoRes = Math.max(0, montoRes - decTotal);

          const allRes = await tx.get(poolRef.collection("reservas").limit(500));
          const firmSalida = firmSeatsFromReservaDocs(allRes.docs, resDoc.id);

          const estadoPool = String(p.estado ?? "").toLowerCase().trim();
          const patch: AnyMap = {
            asientosReservados: newOcc,
            montoReservado: newMontoRes,
            asientosFirmesSalida: firmSalida,
            updatedAt: FieldValue.serverTimestamp(),
          };
          if (estadoPool === "lleno") patch.estado = "abierto";

          tx.update(poolRef, patch);
          tx.update(resDoc.ref, {
            estado: "cancelado",
            canceladoPor: "vencimiento_reserva",
            canceladoAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
        });
        processed++;
      } catch (e) {
        logger.warn("scheduledCleanupExpiredPoolReservations: skip one doc", {
          reservaId: resDoc.id,
          err: String(e),
        });
      }
    }

    if (processed > 0) {
      logger.info("scheduledCleanupExpiredPoolReservations done", { processed });
    }
  },
);
