/**
 * Tras validar pago B2B de la empresa, habilita viajes corporativos en liquidación semanal del chofer.
 */
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { elegibleLiquidacionSemanalCache } from "./liquidacion_semanal_viaje.js";

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function parseTs(v: unknown): Date | null {
  if (v instanceof Timestamp) return v.toDate();
  if (v instanceof Date) return v;
  if (typeof v === "string") {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

/** Mismo período corporativo (tolerancia 2 min en inicio). */
function viajePertenecePeriodoPagado(
  v: AnyMap,
  periodoInicio: Date | null,
  periodoFin: Date | null,
): boolean {
  if (!periodoInicio && !periodoFin) return true;

  const vIni = parseTs(v.corporativoPeriodoInicio);
  if (vIni && periodoInicio) {
    if (Math.abs(vIni.getTime() - periodoInicio.getTime()) <= 120_000) return true;
  }

  const finViaje =
    parseTs(v.finalizadoEn) ??
    parseTs(v.completadoEn) ??
    parseTs(v.actualizadoEn);
  if (finViaje && periodoInicio && periodoFin) {
    const t = finViaje.getTime();
    return t >= periodoInicio.getTime() && t <= periodoFin.getTime() + 86_400_000;
  }

  return false;
}

export type HabilitarLiqCorpArgs = {
  empresaId: string;
  periodoInicio?: Date | null;
  periodoFin?: Date | null;
  pagadoPorUid: string;
  liquidacionEmpresaId?: string;
  pagoEmpresaId?: string;
};

/**
 * Marca viajes corporativos contabilizados como elegibles para `liquidaciones_semanales`
 * (estadoPago verificado + transferencia) cuando RAI confirma el pago de la empresa.
 */
export async function habilitarViajesCorporativosParaLiquidacionSemanal(
  args: HabilitarLiqCorpArgs,
): Promise<{ actualizados: number }> {
  const empresaId = str(args.empresaId);
  if (!empresaId) return { actualizados: 0 };

  const db = getFirestore();
  let snap: FirebaseFirestore.QuerySnapshot;
  try {
    snap = await db
      .collection("viajes")
      .where("corporativoEmpresaId", "==", empresaId)
      .where("completado", "==", true)
      .limit(400)
      .get();
  } catch (e) {
    logger.error("[CORP_LIQ] query viajes", { empresaId, e });
    return { actualizados: 0 };
  }

  if (snap.empty) return { actualizados: 0 };

  const batch = db.batch();
  let actualizados = 0;
  const now = FieldValue.serverTimestamp();

  for (const doc of snap.docs) {
    const d = (doc.data() ?? {}) as AnyMap;
    if (d.corporativo !== true) continue;
    if (d.corporativoContabilizado !== true) continue;
    if (d.liquidado === true) continue;
    if (!viajePertenecePeriodoPagado(d, args.periodoInicio ?? null, args.periodoFin ?? null)) {
      continue;
    }

    const ep = str(d.estadoPago).toLowerCase();
    if (ep === "verificado" && d.corporativoPagoEmpresaValidadoEn) continue;

    const merged: AnyMap = {
      ...d,
      estadoPago: "verificado",
      metodoPagoNormalizado: "transferencia",
      liquidado: false,
    };
    const patch: AnyMap = {
      estadoPago: "verificado",
      metodoPagoNormalizado: "transferencia",
      corporativoPagoEmpresaValidadoEn: now,
      corporativoPagoEmpresaValidadoPor: args.pagadoPorUid,
      elegibleLiquidacionSemanal: elegibleLiquidacionSemanalCache(merged),
      "settlement.status": "verified",
      updatedAt: now,
      actualizadoEn: now,
    };
    if (!str(d.metodoPago)) {
      patch.metodoPago = "Transferencia corporativa";
    }
    if (args.liquidacionEmpresaId) {
      patch.corporativoLiquidacionEmpresaId = args.liquidacionEmpresaId;
    }
    if (args.pagoEmpresaId) {
      patch.corporativoPagoEmpresaId = args.pagoEmpresaId;
    }

    batch.set(doc.ref, patch, { merge: true });
    actualizados += 1;
    if (actualizados >= 400) break;
  }

  if (actualizados > 0) {
    await batch.commit();
    logger.info("[CORP_LIQ] viajes habilitados liquidación semanal", {
      empresaId,
      actualizados,
      liquidacionEmpresaId: args.liquidacionEmpresaId ?? null,
    });
  }

  return { actualizados };
}
