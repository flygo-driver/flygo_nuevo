/**
 * Cierra giras por cupos cuyo día de salida ya pasó (calendario America/Santo_Domingo).
 * - Sin iniciar (abierto, confirmado, etc.) → cancelado + libera reservas.
 * - En ruta olvidada → finalizado automático (organizador debió cerrar manualmente).
 *
 * No penaliza contadores de abuso del organizador (cierre sistema).
 */
import { FieldValue, getFirestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

const OPEN_ESTADOS = new Set([
  "abierto",
  "preconfirmado",
  "confirmado",
  "lleno",
  "activo",
  "disponible",
  "buscando",
]);

const TERMINAL_ESTADOS = new Set([
  "finalizado",
  "cancelado",
  "cancelado_por_admin",
]);

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function numOr0(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/** Inicio del día calendario actual en Santo Domingo (pools con salida antes = día ya pasó). */
function startOfTodaySantoDomingo(now: Date): Date {
  const ymd = now.toLocaleDateString("en-CA", { timeZone: "America/Santo_Domingo" });
  return new Date(`${ymd}T00:00:00-04:00`);
}

function patchPoolCanceladoGira(motivo: string): AnyMap {
  return {
    estado: "cancelado",
    asientosReservados: 0,
    asientosPagados: 0,
    montoReservado: 0,
    montoPagado: 0,
    asientosFirmesSalida: 0,
    canceladoAt: FieldValue.serverTimestamp(),
    motivoCancelacion: motivo.trim() || "cancelacion",
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function marcarReservasCanceladasPorGiraTx(
  tx: Transaction,
  reservaDocs: FirebaseFirestore.QueryDocumentSnapshot[],
  motivo: string,
): number {
  let n = 0;
  const motivoTxt = motivo.trim() || "cancelacion";
  for (const doc of reservaDocs) {
    const r = (doc.data() ?? {}) as AnyMap;
    const estadoRes = str(r.estado).toLowerCase();
    if (
      estadoRes === "cancelado" ||
      estadoRes === "cancelado_cliente" ||
      estadoRes === "cancelado_gira"
    ) {
      continue;
    }
    if (estadoRes !== "reservado" && estadoRes !== "pagado") continue;
    tx.update(doc.ref, {
      estado: "cancelado_gira",
      canceladoPor: "sistema",
      canceladoEn: FieldValue.serverTimestamp(),
      motivoCancelacion: motivoTxt,
      updatedAt: FieldValue.serverTimestamp(),
    });
    n += 1;
  }
  return n;
}

async function autoCerrarPoolSinInicio(
  poolRef: FirebaseFirestore.DocumentReference,
  pool: AnyMap,
): Promise<{ action: string; reservasCanceladas: number }> {
  const motivo =
    "Cierre automático: pasó el día de salida sin iniciar la gira.";
  const ownerTaxistaId = str(pool.ownerTaxistaId);
  const reserved = Math.max(0, numOr0(pool.comisionGiraEstimadaRd));
  const etapa = str(pool.prepagoComisionEtapa).toLowerCase();

  return db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) return { action: "skip_missing", reservasCanceladas: 0 };
    const fresh = (snap.data() ?? {}) as AnyMap;
    const estado = str(fresh.estado).toLowerCase();
    if (TERMINAL_ESTADOS.has(estado) || fresh.autoCerradoPostSalida === true) {
      return { action: "skip_terminal", reservasCanceladas: 0 };
    }
    if (!OPEN_ESTADOS.has(estado)) {
      return { action: "skip_estado", reservasCanceladas: 0 };
    }

    const reservasSnap = await tx.get(poolRef.collection("reservas"));
    const reservasCanceladas = marcarReservasCanceladasPorGiraTx(
      tx,
      reservasSnap.docs,
      motivo,
    );

    const autoPatch: AnyMap = {
      ...patchPoolCanceladoGira(motivo),
      autoCerradoPostSalida: true,
      autoCerradoEn: FieldValue.serverTimestamp(),
      autoCerradoMotivo: "fecha_salida_pasada_sin_inicio",
      canceladoPor: "sistema",
    };

    if (reserved > 1e-9 && etapa === "reservada_creacion" && ownerTaxistaId) {
      const billeRef = db().collection("billeteras_taxista").doc(ownerTaxistaId);
      const billeSnap = await tx.get(billeRef);
      const bille = (billeSnap.data() ?? {}) as AnyMap;
      const prep = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
      const reservWallet = Math.max(0, numOr0(bille.saldoReservadoParaGiras));
      if (reservWallet + 1e-9 >= reserved) {
        tx.set(
          billeRef,
          {
            saldoPrepagoComisionRd: Number((prep + reserved).toFixed(2)),
            saldoReservadoParaGiras: Number((reservWallet - reserved).toFixed(2)),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        autoPatch.prepagoComisionEtapa = "devuelta_auto_cierre_post_salida";
        autoPatch.comisionGiraEstimadaRd = 0;
      } else {
        logger.warn("[GIRA_AUTO_CIERRE] prepago inconsistente", {
          poolId: poolRef.id,
          reservWallet,
          reserved,
        });
        autoPatch.prepagoComisionEtapa = "inconsistente_auto_sin_devolver";
      }
    }

    tx.update(poolRef, autoPatch);
    return { action: "cancelado", reservasCanceladas };
  });
}

async function autoFinalizarPoolEnRuta(
  poolRef: FirebaseFirestore.DocumentReference,
): Promise<{ action: string }> {
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) return { action: "skip_missing" };
    const pool = (snap.data() ?? {}) as AnyMap;
    const estado = str(pool.estado).toLowerCase();
    if (TERMINAL_ESTADOS.has(estado) || pool.autoCerradoPostSalida === true) {
      return { action: "skip_terminal" };
    }
    if (estado !== "en_ruta") return { action: "skip_estado" };

    const patch: AnyMap = {
      estado: "finalizado",
      finalizadoAt: FieldValue.serverTimestamp(),
      autoCerradoPostSalida: true,
      autoCerradoEn: FieldValue.serverTimestamp(),
      autoCerradoMotivo: "fecha_salida_pasada_en_ruta",
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (str(pool.recaudoModelo).toLowerCase() === "central") {
      patch.liquidacionOrganizadorEstado = "pendiente_revision_auto";
      patch.autoCerradoNota =
        "Cierre automático post-salida; revisar liquidación en ADM si hubo recaudo.";
    }
    tx.update(poolRef, patch);
    return { action: "finalizado" };
  });
}

export const scheduledAutoClosePoolsPostDeparture = onSchedule(
  {
    schedule: "every 6 hours",
    timeZone: "America/Santo_Domingo",
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    const now = new Date();
    const cutoff = Timestamp.fromDate(startOfTodaySantoDomingo(now));

    let snap: FirebaseFirestore.QuerySnapshot;
    try {
      snap = await db()
        .collection("viajes_pool")
        .where("fechaSalida", "<", cutoff)
        .limit(120)
        .get();
    } catch (e) {
      logger.error("[GIRA_AUTO_CIERRE] query failed", e);
      return;
    }

    if (snap.empty) return;

    let cancelados = 0;
    let finalizados = 0;
    let omitidos = 0;

    for (const doc of snap.docs) {
      const pool = (doc.data() ?? {}) as AnyMap;
      const estado = str(pool.estado).toLowerCase();
      if (TERMINAL_ESTADOS.has(estado) || pool.autoCerradoPostSalida === true) {
        omitidos += 1;
        continue;
      }

      try {
        if (OPEN_ESTADOS.has(estado)) {
          const r = await autoCerrarPoolSinInicio(doc.ref, pool);
          if (r.action === "cancelado") cancelados += 1;
          else omitidos += 1;
        } else if (estado === "en_ruta") {
          const r = await autoFinalizarPoolEnRuta(doc.ref);
          if (r.action === "finalizado") finalizados += 1;
          else omitidos += 1;
        } else {
          omitidos += 1;
        }
      } catch (e) {
        logger.error("[GIRA_AUTO_CIERRE] pool failed", { poolId: doc.id, e });
      }
    }

    if (cancelados > 0 || finalizados > 0) {
      logger.info("[GIRA_AUTO_CIERRE] done", {
        cancelados,
        finalizados,
        omitidos,
        scanned: snap.size,
      });
    }
  },
);
