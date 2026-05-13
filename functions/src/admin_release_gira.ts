/**
 * Admin: libera reserva de comisión de prepago de una gira y marca el pool cancelado_por_admin.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { logAdminAudit } from "./audit.js";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

function roleFromUserDoc(data: AnyMap | undefined): string {
  if (!data) return "";
  const rol = data.rol;
  return typeof rol === "string" ? rol : "";
}

async function getRole(uid: string): Promise<string> {
  const snap = await db().collection("usuarios").doc(uid).get();
  let rolUsuario = roleFromUserDoc(snap.data() as AnyMap | undefined).trim().toLowerCase();
  if (rolUsuario === "administrador") rolUsuario = "admin";
  if (rolUsuario) return rolUsuario;

  const rolSnap = await db().collection("roles").doc(uid).get();
  const rolRaw = String((rolSnap.data() as AnyMap | undefined)?.rol ?? "").trim().toLowerCase();
  if (rolRaw === "administrador") return "admin";
  return rolRaw;
}

async function ensureIdempotencyStart(
  key: string,
  op: string,
  uid: string,
): Promise<{
  done: boolean;
  result?: AnyMap;
  ref: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
}> {
  const ref = db().collection("idempotency_keys").doc(`${op}_${key}`);
  const snap = await ref.get();
  if (snap.exists) {
    const data = (snap.data() ?? {}) as AnyMap;
    if (data.status === "done" && typeof data.result === "object" && data.result) {
      return { done: true, result: data.result as AnyMap, ref };
    }
  }
  await ref.set(
    {
      op,
      uid,
      status: "started",
      startedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { done: false, ref };
}

async function markIdempotencyDone(
  ref: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>,
  result: AnyMap,
): Promise<void> {
  await ref.set(
    {
      status: "done",
      result,
      doneAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function numOr0(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return 0;
}

export const adminReleaseGiraReservation = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const roleNorm = String(await getRole(uidActor) ?? "").trim().toLowerCase();
  if (roleNorm !== "admin") {
    throw new HttpsError("permission-denied", "Solo administradores");
  }

  const idem = await ensureIdempotencyStart(idemKey, "admin_release_gira_reservation", uidActor);
  if (idem.done) return idem.result;

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (snap.data() ?? {}) as AnyMap;

    const estado = String(pool.estado ?? "").trim().toLowerCase();
    if (estado === "en_ruta" || estado === "finalizado") {
      throw new HttpsError("failed-precondition", "No se puede liberar una gira en ruta o finalizada");
    }

    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "").trim();
    if (!ownerTaxistaId) throw new HttpsError("failed-precondition", "Pool sin dueño");

    const etapa = String(pool.prepagoComisionEtapa ?? "").trim().toLowerCase();
    const reserved = Math.max(0, numOr0(pool.comisionGiraEstimadaRd));
    if (reserved <= 1e-9 || etapa !== "reservada_creacion") {
      tx.update(poolRef, {
        estado: "cancelado_por_admin",
        motivoCancelacion: "Liberación admin (sin reserva activa de comisión)",
        canceladoAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { ok: true, poolId, comisionDevuelta: 0, skippedRefund: true };
    }

    const billeRef = db().collection("billeteras_taxista").doc(ownerTaxistaId);
    const billeSnap = await tx.get(billeRef);
    const bille = (billeSnap.data() ?? {}) as AnyMap;
    const prep = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
    const reserv = Math.max(0, numOr0(bille.saldoReservadoParaGiras));
    if (reserv + 1e-9 < reserved) {
      logger.error("[GIRA_PREPAGO] adminRelease saldo reservado insuficiente", { poolId, reserved, reserv });
      throw new HttpsError("failed-precondition", "Inconsistencia de saldo reservado; contactá ingeniería.");
    }

    tx.set(
      billeRef,
      {
        saldoPrepagoComisionRd: Number((prep + reserved).toFixed(2)),
        saldoReservadoParaGiras: Number((reserv - reserved).toFixed(2)),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    tx.update(poolRef, {
      estado: "cancelado_por_admin",
      prepagoComisionEtapa: "devuelta_admin",
      comisionGiraEstimadaRd: 0,
      motivoCancelacion: "Liberación administrativa de reserva de comisión",
      canceladoAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    const led = db().collection("ledger_giras").doc();
    tx.set(led, {
      tipo: "liberacion_admin",
      poolId,
      uidTaxista: ownerTaxistaId,
      monto: reserved,
      actorUid: uidActor,
      createdAt: FieldValue.serverTimestamp(),
    });

    logger.info("[GIRA_PREPAGO] adminReleaseGiraReservation", { poolId, comisionDevuelta: reserved });
    return { ok: true, poolId, comisionDevuelta: reserved };
  });

  await markIdempotencyDone(idem.ref, result);
  logAdminAudit({
    action: "admin_release_gira_reservation",
    actorUid: uidActor,
    resourceType: "viajes_pool",
    resourceId: poolId,
    metadata: { result: result as AnyMap },
  });
  return result;
});
