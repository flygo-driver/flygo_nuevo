import { FieldValue, Timestamp, getFirestore, type DocumentReference } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";

import { logAdminAudit } from "./audit.js";
import { getFinanceConfig } from "./finance.js";
import {
  esElegibleLiquidacionSemanal,
  metodoPagoNormalizadoDesde,
} from "./liquidacion_semanal_viaje.js";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

const RD_OFFSET_MS = -4 * 60 * 60 * 1000;
const REGLA_ELEGIBILIDAD = "liquidacion_semanal_v1";

type MetodoTotales = {
  viajesCount: number;
  totalBrutoCents: number;
  comisionRaiCents: number;
  totalNetoCents: number;
};

type TotalesPorMetodo = {
  transferencia: MetodoTotales;
  tarjeta: MetodoTotales;
};

function emptyMetodoTotales(): MetodoTotales {
  return { viajesCount: 0, totalBrutoCents: 0, comisionRaiCents: 0, totalNetoCents: 0 };
}

function emptyTotalesPorMetodo(): TotalesPorMetodo {
  return { transferencia: emptyMetodoTotales(), tarjeta: emptyMetodoTotales() };
}

function normalizeRole(raw: unknown): string {
  const r = String(raw ?? "").trim().toLowerCase();
  return r === "administrador" ? "admin" : r;
}

async function getRole(uid: string): Promise<string> {
  const u = await db().collection("usuarios").doc(uid).get();
  const r1 = normalizeRole((u.data() as AnyMap | undefined)?.rol);
  if (r1) return r1;
  const r = await db().collection("roles").doc(uid).get();
  return normalizeRole((r.data() as AnyMap | undefined)?.rol);
}

async function assertAdmin(uid: string): Promise<void> {
  if ((await getRole(uid)) !== "admin") {
    throw new HttpsError("permission-denied", "Solo admin");
  }
}

function toDateFromUnknown(v: unknown): Date | null {
  if (v instanceof Timestamp) return v.toDate();
  if (v instanceof Date) return v;
  if (typeof v === "string") {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function centsFromViaje(data: AnyMap, fieldCents: string, fieldRd: string): number {
  const c = data[fieldCents];
  if (typeof c === "number" && Number.isFinite(c)) return Math.trunc(c);
  const n = data[fieldRd];
  if (typeof n === "number" && Number.isFinite(n)) return Math.round(n * 100);
  return 0;
}

/** Fecha/hora civil en República Dominicana (UTC-4 fijo). */
function rdPartsFromUtc(utc: Date): { y: number; m: number; d: number; dow: number } {
  const local = new Date(utc.getTime() + RD_OFFSET_MS);
  return {
    y: local.getUTCFullYear(),
    m: local.getUTCMonth(),
    d: local.getUTCDate(),
    dow: local.getUTCDay(),
  };
}

function utcFromRd(y: number, m: number, d: number, h = 0, min = 0, s = 0, ms = 0): Date {
  return new Date(Date.UTC(y, m, d, h, min, s, ms) - RD_OFFSET_MS);
}

/** Semana ISO (año-semana) a partir de fecha civil RD. */
export function isoWeekFromRdDate(y: number, m: number, d: number): { isoYear: number; isoWeek: number } {
  const target = utcFromRd(y, m, d, 12);
  const day = target.getUTCDay() || 7;
  const thursday = new Date(target.getTime());
  thursday.setUTCDate(thursday.getUTCDate() + 4 - day);
  const isoYear = thursday.getUTCFullYear();
  const yearStart = new Date(Date.UTC(isoYear, 0, 1));
  const isoWeek = Math.ceil((((thursday.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
  return { isoYear, isoWeek };
}

export function periodoIsoString(isoYear: number, isoWeek: number): string {
  return `${isoYear}-W${isoWeek.toString().padStart(2, "0")}`;
}

/** Lunes 00:00 — domingo 23:59:59.999 (civil RD) del periodo ISO. */
export function isoWeekBoundsRd(isoYear: number, isoWeek: number): { inicio: Date; fin: Date } {
  const jan4 = new Date(Date.UTC(isoYear, 0, 4, 12));
  const jan4Day = jan4.getUTCDay() || 7;
  const mondayWeek1 = new Date(jan4.getTime());
  mondayWeek1.setUTCDate(jan4.getUTCDate() - jan4Day + 1);
  const monday = new Date(mondayWeek1.getTime() + (isoWeek - 1) * 7 * 86400000);
  const p = rdPartsFromUtc(monday);
  const inicio = utcFromRd(p.y, p.m, p.d, 0, 0, 0, 0);
  const sunday = new Date(monday.getTime() + 6 * 86400000);
  const ps = rdPartsFromUtc(sunday);
  const fin = utcFromRd(ps.y, ps.m, ps.d, 23, 59, 59, 999);
  return { inicio, fin };
}

export function previousIsoWeekPeriodo(anchorUtc = new Date()): {
  periodo: string;
  periodoInicio: Date;
  periodoFin: Date;
} {
  const p = rdPartsFromUtc(anchorUtc);
  const cur = isoWeekFromRdDate(p.y, p.m, p.d);
  let isoYear = cur.isoYear;
  let isoWeek = cur.isoWeek - 1;
  if (isoWeek < 1) {
    isoYear -= 1;
    isoWeek = 52;
  }
  const bounds = isoWeekBoundsRd(isoYear, isoWeek);
  return {
    periodo: periodoIsoString(isoYear, isoWeek),
    periodoInicio: bounds.inicio,
    periodoFin: bounds.fin,
  };
}

function snapshotCuentaDestino(u: AnyMap): { snapshot: AnyMap; completa: boolean } {
  const banco = String(u.banco ?? u.bancoTaxista ?? "").trim();
  const numeroCuenta = String(u.numeroCuenta ?? u.numeroCuentaTaxista ?? "").trim();
  const tipoCuenta = String(u.tipoCuenta ?? u.tipoCuentaTaxista ?? "").trim();
  const titular = String(u.titularCuenta ?? u.titularCuentaTaxista ?? u.nombre ?? "").trim();
  const ci = String(u.ci ?? u.ciTaxista ?? "").trim();
  const completa = banco.length > 0 && numeroCuenta.length > 0 && titular.length > 0;
  return {
    snapshot: {
      banco,
      numeroCuenta,
      tipoCuenta,
      titular,
      ci,
      capturadoEn: FieldValue.serverTimestamp(),
    },
    completa,
  };
}

function viajeSinLiquidarPrevio(data: AnyMap): boolean {
  if (data.liquidado === true) return false;
  const lid = String(data.liquidacionSemanalId ?? "").trim();
  return lid.length === 0;
}

/** Revalida elegibilidad; idempotente si el viaje ya quedó bajo esta liquidación. */
function viajeAptoParaAprobar(data: AnyMap, liquidacionId: string): boolean {
  if (data.liquidado === true) {
    return String(data.liquidacionSemanalId ?? "").trim() === liquidacionId;
  }
  if (!viajeSinLiquidarPrevio(data)) return false;
  return esElegibleLiquidacionSemanal(data);
}

async function ensureIdempotencyStart(
  key: string,
  op: string,
  uid: string,
): Promise<{ done: boolean; result?: AnyMap; ref: DocumentReference }> {
  const ref = db().collection("idempotency_keys").doc(`${op}_${key}`);
  const snap = await ref.get();
  if (snap.exists) {
    const data = (snap.data() ?? {}) as AnyMap;
    if (data.status === "done" && typeof data.result === "object" && data.result) {
      return { done: true, result: data.result as AnyMap, ref };
    }
  }
  await ref.set(
    { op, uid, status: "started", startedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  return { done: false, ref };
}

async function markIdempotencyDone(
  ref: DocumentReference,
  result: AnyMap,
): Promise<void> {
  await ref.set(
    { status: "done", result, doneAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
}

type BuildLinea = {
  viajeId: string;
  data: AnyMap;
  metodo: "transferencia" | "tarjeta";
  precioCents: number;
  comisionCents: number;
  gananciaCents: number;
  finalizadoEn: Date | null;
};

async function fetchViajesElegiblesPeriodo(
  uidTaxista: string,
  periodoInicio: Date,
  periodoFin: Date,
): Promise<{ elegibles: BuildLinea[]; efectivoExcluidos: number }> {
  const snap = await db()
    .collection("viajes")
    .where("uidTaxista", "==", uidTaxista)
    .where("completado", "==", true)
    .where("finalizadoEn", ">=", periodoInicio)
    .where("finalizadoEn", "<=", periodoFin)
    .get();

  const elegibles: BuildLinea[] = [];
  let efectivoExcluidos = 0;

  for (const doc of snap.docs) {
    const data = (doc.data() ?? {}) as AnyMap;
    if (!esElegibleLiquidacionSemanal(data)) {
      const norm = metodoPagoNormalizadoDesde(data);
      if (norm === "efectivo") efectivoExcluidos++;
      continue;
    }
    const metodo = metodoPagoNormalizadoDesde(data);
    if (metodo !== "transferencia" && metodo !== "tarjeta") continue;
    elegibles.push({
      viajeId: doc.id,
      data,
      metodo,
      precioCents: centsFromViaje(data, "precio_cents", "precio"),
      comisionCents: centsFromViaje(data, "comision_cents", "comision"),
      gananciaCents: centsFromViaje(data, "ganancia_cents", "gananciaTaxista"),
      finalizadoEn: toDateFromUnknown(data.finalizadoEn),
    });
  }

  return { elegibles, efectivoExcluidos };
}

function aggregateTotales(lineas: BuildLinea[]): {
  viajeIds: string[];
  totalBrutoCents: number;
  comisionRaiCents: number;
  totalNetoCents: number;
  totalesPorMetodo: TotalesPorMetodo;
} {
  const viajeIds: string[] = [];
  let totalBrutoCents = 0;
  let comisionRaiCents = 0;
  let totalNetoCents = 0;
  const totalesPorMetodo = emptyTotalesPorMetodo();

  for (const l of lineas) {
    viajeIds.push(l.viajeId);
    totalBrutoCents += l.precioCents;
    comisionRaiCents += l.comisionCents;
    totalNetoCents += l.gananciaCents;
    const bucket = totalesPorMetodo[l.metodo];
    bucket.viajesCount += 1;
    bucket.totalBrutoCents += l.precioCents;
    bucket.comisionRaiCents += l.comisionCents;
    bucket.totalNetoCents += l.gananciaCents;
  }

  return { viajeIds, totalBrutoCents, comisionRaiCents, totalNetoCents, totalesPorMetodo };
}

async function buildLiquidacionSemanalForTaxista(params: {
  uidTaxista: string;
  periodo: string;
  periodoInicio: Date;
  periodoFin: Date;
  generadoPor: string;
}): Promise<{ ok: boolean; liquidacionId: string; skipped?: string }> {
  const { uidTaxista, periodo, periodoInicio, periodoFin, generadoPor } = params;
  const liquidacionId = `${uidTaxista}_${periodo}`;
  const liqRef = db().collection("liquidaciones_semanales").doc(liquidacionId);

  const existing = await liqRef.get();
  if (existing.exists) {
    const st = String((existing.data() ?? {}).estado ?? "");
    if (st === "pagado" || st === "cancelado") {
      return { ok: true, liquidacionId, skipped: `estado_${st}` };
    }
  }

  const userSnap = await db().collection("usuarios").doc(uidTaxista).get();
  const userData = (userSnap.data() ?? {}) as AnyMap;
  const nombreTaxista = String(userData.nombre ?? "Sin nombre").trim();
  const cuenta = snapshotCuentaDestino(userData);

  const { elegibles, efectivoExcluidos } = await fetchViajesElegiblesPeriodo(
    uidTaxista,
    periodoInicio,
    periodoFin,
  );

  if (elegibles.length === 0) {
    return { ok: true, liquidacionId, skipped: "sin_viajes_elegibles" };
  }

  const agg = aggregateTotales(elegibles);
  if (agg.totalBrutoCents !== agg.comisionRaiCents + agg.totalNetoCents) {
    throw new HttpsError(
      "failed-precondition",
      "Inconsistencia de totales bruto/comisión/neto",
    );
  }

  const estado = cuenta.completa ? "pendiente_pago" : "borrador";
  const idempotencyKey = `gen_liq_sem_${uidTaxista}_${periodo}`;

  await db().runTransaction(async (tx) => {
    const liqSnap = await tx.get(liqRef);
    if (liqSnap.exists) {
      const st = String((liqSnap.data() ?? {}).estado ?? "");
      if (st === "pagado" || st === "cancelado") return;
    }

    tx.set(
      liqRef,
      {
        uidTaxista,
        nombreTaxista,
        periodo,
        periodoInicio: Timestamp.fromDate(periodoInicio),
        periodoFin: Timestamp.fromDate(periodoFin),
        estado,
        viajeIds: agg.viajeIds,
        viajesCount: agg.viajeIds.length,
        viajesEfectivoExcluidosCount: efectivoExcluidos,
        totalBrutoCents: agg.totalBrutoCents,
        comisionRaiCents: agg.comisionRaiCents,
        totalNetoCents: agg.totalNetoCents,
        totalesPorMetodo: agg.totalesPorMetodo,
        moneda: "DOP",
        incluyeSoloMetodos: ["transferencia", "tarjeta"],
        reglaElegibilidad: REGLA_ELEGIBILIDAD,
        generadoEn: FieldValue.serverTimestamp(),
        generadoPor,
        idempotencyKey,
        cuentaDestinoSnapshot: cuenta.snapshot,
        cuentaDestinoCompleta: cuenta.completa,
        version: 1,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    for (const l of elegibles) {
      const lineaRef = liqRef.collection("lineas").doc(l.viajeId);
      tx.set(
        lineaRef,
        {
          viajeId: l.viajeId,
          uidTaxista,
          metodoPagoNormalizado: l.metodo,
          estadoPago: String(l.data.estadoPago ?? "").trim(),
          estadoViajeSnapshot: String(l.data.estado ?? "").trim(),
          precioCents: l.precioCents,
          comisionCents: l.comisionCents,
          gananciaCents: l.gananciaCents,
          finalizadoEn: l.finalizadoEn ? Timestamp.fromDate(l.finalizadoEn) : null,
          elegibleAlGenerar: true,
          createdAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
  });

  return { ok: true, liquidacionId };
}

export const generarLiquidacionesSemanales = onSchedule(
  {
    schedule: "0 6 * * 1",
    timeZone: "America/Santo_Domingo",
  },
  async () => {
    const cfg = await getFinanceConfig();
    if (!cfg.useLiquidacionesSemanales || !cfg.generarLiquidacionesSemanalesAuto) {
      logger.info("[generarLiquidacionesSemanales] omitido por config/finance");
      return;
    }

    const { periodo, periodoInicio, periodoFin } = previousIsoWeekPeriodo();
    const taxistas = await db().collection("usuarios").where("rol", "==", "taxista").get();
    let creadas = 0;
    let omitidas = 0;

    for (const doc of taxistas.docs) {
      try {
        const res = await buildLiquidacionSemanalForTaxista({
          uidTaxista: doc.id,
          periodo,
          periodoInicio,
          periodoFin,
          generadoPor: "system",
        });
        if (res.skipped === "sin_viajes_elegibles") omitidas++;
        else creadas++;
      } catch (e) {
        logger.error("[generarLiquidacionesSemanales] taxista", doc.id, e);
      }
    }

    logger.info("[generarLiquidacionesSemanales] listo", { periodo, creadas, omitidas });
  },
);

export const generarLiquidacionSemanalTaxista = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  await assertAdmin(uidActor);

  const uidTaxista = String(request.data?.uidTaxista ?? "").trim();
  const periodo = String(request.data?.periodo ?? "").trim();
  if (!uidTaxista) throw new HttpsError("invalid-argument", "Falta uidTaxista");

  let periodoInicio: Date;
  let periodoFin: Date;
  let periodoStr = periodo;

  if (periodoStr) {
    const m = /^(\d{4})-W(\d{2})$/.exec(periodoStr);
    if (!m) throw new HttpsError("invalid-argument", "periodo inválido (YYYY-Www)");
    const bounds = isoWeekBoundsRd(Number(m[1]), Number(m[2]));
    periodoInicio = bounds.inicio;
    periodoFin = bounds.fin;
  } else {
    const prev = previousIsoWeekPeriodo();
    periodoStr = prev.periodo;
    periodoInicio = prev.periodoInicio;
    periodoFin = prev.periodoFin;
  }

  const result = await buildLiquidacionSemanalForTaxista({
    uidTaxista,
    periodo: periodoStr,
    periodoInicio,
    periodoFin,
    generadoPor: uidActor,
  });

  logAdminAudit({
    action: "generar_liquidacion_semanal_taxista",
    actorUid: uidActor,
    resourceType: "liquidacion_semanal",
    resourceId: result.liquidacionId,
    metadata: result as AnyMap,
  });

  return result;
});

export const aprobarLiquidacionSemanal = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  await assertAdmin(uidActor);

  const liquidacionId = String(request.data?.liquidacionId ?? "").trim();
  const notaAdmin = String(request.data?.notaAdmin ?? "").trim();
  const referenciaAch = String(request.data?.referenciaAch ?? "").trim();
  const idemKey = String(request.data?.idempotencyKey ?? "").trim();
  if (!liquidacionId) throw new HttpsError("invalid-argument", "Falta liquidacionId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "aprobar_liquidacion_semanal", uidActor);
  if (idem.done) return idem.result;

  const liqRef = db().collection("liquidaciones_semanales").doc(liquidacionId);

  const result = await db().runTransaction(async (tx) => {
    const liqSnap = await tx.get(liqRef);
    if (!liqSnap.exists) throw new HttpsError("not-found", "Liquidación no encontrada");
    const liq = (liqSnap.data() ?? {}) as AnyMap;
    const estado = String(liq.estado ?? "").trim();
    if (estado === "pagado") {
      return { ok: true, liquidacionId, alreadyProcessed: true, estado: "pagado" };
    }
    if (estado === "cancelado") {
      throw new HttpsError("failed-precondition", "Liquidación cancelada");
    }
    if (estado !== "pendiente_pago" && estado !== "borrador") {
      throw new HttpsError("failed-precondition", `Estado no válido: ${estado}`);
    }

    const viajeIds = ((liq.viajeIds as unknown[]) ?? [])
      .map((x) => String(x ?? "").trim())
      .filter((x) => x.length > 0);

    const viajeSnaps = await Promise.all(
      viajeIds.map((id) => tx.get(db().collection("viajes").doc(id))),
    );

    const rechazados: string[] = [];
    const aprobados: string[] = [];

    for (const vs of viajeSnaps) {
      if (!vs.exists) {
        rechazados.push(vs.id);
        continue;
      }
      const vd = (vs.data() ?? {}) as AnyMap;
      if (!viajeAptoParaAprobar(vd, liquidacionId)) {
        rechazados.push(vs.id);
        continue;
      }
      aprobados.push(vs.id);
    }

    if (rechazados.length > 0) {
      throw new HttpsError(
        "failed-precondition",
        `Viajes no elegibles o ya liquidados: ${rechazados.slice(0, 5).join(",")}`,
      );
    }

    if (aprobados.length === 0) {
      throw new HttpsError("failed-precondition", "Sin viajes elegibles para aprobar");
    }

    const now = FieldValue.serverTimestamp();
    for (const viajeId of aprobados) {
      const vs = viajeSnaps.find((s) => s.id === viajeId);
      const vd = (vs?.data() ?? {}) as AnyMap;
      if (vd.liquidado === true && String(vd.liquidacionSemanalId ?? "") === liquidacionId) {
        continue;
      }
      tx.update(db().collection("viajes").doc(viajeId), {
        liquidado: true,
        liquidacionSemanalId: liquidacionId,
        liquidadoEn: now,
        liquidadoPorUid: uidActor,
        updatedAt: now,
        actualizadoEn: now,
      });
    }

    tx.update(liqRef, {
      estado: "pagado",
      pagadoEn: now,
      pagadoPorUid: uidActor,
      notaAdmin,
      ...(referenciaAch ? { referenciaAch } : {}),
      viajeIds: aprobados,
      viajesCount: aprobados.length,
      updatedAt: now,
    });

    return {
      ok: true,
      liquidacionId,
      alreadyProcessed: false,
      estado: "pagado",
      viajesLiquidados: aprobados,
    };
  });

  await markIdempotencyDone(idem.ref, result as AnyMap);
  logAdminAudit({
    action: "aprobar_liquidacion_semanal",
    actorUid: uidActor,
    resourceType: "liquidacion_semanal",
    resourceId: liquidacionId,
    metadata: result as AnyMap,
  });
  return result;
});

export const cancelarLiquidacionSemanal = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  await assertAdmin(uidActor);

  const liquidacionId = String(request.data?.liquidacionId ?? "").trim();
  const motivo = String(request.data?.motivo ?? "").trim();
  if (!liquidacionId) throw new HttpsError("invalid-argument", "Falta liquidacionId");
  if (motivo.length < 6) throw new HttpsError("invalid-argument", "Motivo requerido (min 6)");

  const liqRef = db().collection("liquidaciones_semanales").doc(liquidacionId);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(liqRef);
    if (!snap.exists) throw new HttpsError("not-found", "Liquidación no encontrada");
    const st = String((snap.data() ?? {}).estado ?? "");
    if (st === "pagado") throw new HttpsError("failed-precondition", "Ya pagada");
    if (st === "cancelado") return;
    tx.update(liqRef, {
      estado: "cancelado",
      canceladoEn: FieldValue.serverTimestamp(),
      canceladoPorUid: uidActor,
      motivoCancelacion: motivo,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  logAdminAudit({
    action: "cancelar_liquidacion_semanal",
    actorUid: uidActor,
    resourceType: "liquidacion_semanal",
    resourceId: liquidacionId,
    metadata: { motivo },
  });

  return { ok: true, liquidacionId, estado: "cancelado" };
});

export const obtenerLiquidacionSemanalTaxista = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const role = await getRole(uidActor);
  const uidTaxista = String(request.data?.uidTaxista ?? uidActor).trim();
  if (role !== "admin" && uidTaxista !== uidActor) {
    throw new HttpsError("permission-denied", "No autorizado");
  }

  const periodo = String(request.data?.periodo ?? "").trim();
  if (periodo) {
    const id = `${uidTaxista}_${periodo}`;
    const snap = await db().collection("liquidaciones_semanales").doc(id).get();
    return { ok: true, liquidacion: snap.exists ? { id: snap.id, ...snap.data() } : null };
  }

  const q = await db()
    .collection("liquidaciones_semanales")
    .where("uidTaxista", "==", uidTaxista)
    .orderBy("periodoFin", "desc")
    .limit(12)
    .get();

  const list = q.docs.map((d) => ({ id: d.id, ...(d.data() as AnyMap) }));
  return { ok: true, liquidaciones: list };
});
