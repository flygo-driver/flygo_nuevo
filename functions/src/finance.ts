import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { ledgerComisionViajeEfectivoCf, comisionViajeEfectivoLedgerRef } from "./taxista_prepago_ledger.js";
import type { DocumentSnapshot, Transaction } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { logAdminAudit } from "./audit.js";
import { comisionCentsDesdePrecioCents, getComisionViajePorcentajeCached } from "./comision_viaje_pct.js";
import {
  aplicarIncentivoComisionEnFinalizar,
  getComisionIncentivosTaxistaConfigCached,
  statsDocRef,
} from "./comision_incentivos_taxista.js";
import { assertMultiparadaCompletaParaFinalizar } from "./multiparada.js";
import {
  elegibleLiquidacionSemanalCache,
  esElegibleLiquidacionSemanal,
  metodoPagoNormalizado,
  metodoPagoNormalizadoDesde,
} from "./liquidacion_semanal_viaje.js";
import { assertTaxistaAptoParaClaimPool } from "./taxista_operacion_gate.js";

const db = () => getFirestore();
const messaging = () => getMessaging();

/** Mismo canal Android que otros pushes al conductor (ver scheduled_pool_notify). */
const ANDROID_CHANNEL_TAXISTA = "rai_driver_notifications";

/** Deuda legacy `comisionPendiente` (ya no crece con viajes nuevos): al llegar aquí se bloquea. */
const UMBRAL_COMISION_LEGACY_RD = 500;
/** Tope de deuda acumulada por comisiones de pool pendientes de validar por admin. */
const UMBRAL_DEUDA_POOL_RD = 500;
/** Tras el primer viaje en efectivo gratis, hace falta este saldo prepago mínimo para pool / tomar viajes. */
const MIN_SALDO_PREPAGO_COMISION_RD = 200;
/** Aviso preventivo antes del bloqueo por prepago. */
const UMBRAL_AVISO_PREVENTIVO_PREPAGO_RD = 250;
const COMISION_PREPAGO_CONFIG_TTL_MS = 60_000;

let _cfgCache: {
  loadedAt: number;
  minimoOperativoRd: number;
  umbralPreventivoRd: number;
} | null = null;

let _financeCfgCache: {
  loadedAt: number;
  excluirEfectivoDePagoSemanal: boolean;
  useLiquidacionesSemanales: boolean;
  escrituraPagosTaxistasLegacy: boolean;
  generarLiquidacionesSemanalesAuto: boolean;
  transferenciaRecaudoEnCuentaRai: boolean;
  conciliacionAutomaticaHabilitada: boolean;
  transferenciaExigeVerificadoParaFinalizar: boolean;
  qrRecaudoPopularHabilitado: boolean;
  pagosConTarjetaAzulHabilitados: boolean;
} | null = null;

type AnyMap = Record<string, unknown>;

function toCents(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return Math.round(v * 100);
  return 0;
}

function fromCents(c: number): number {
  return c / 100;
}

function roleFromUserDoc(data: AnyMap | undefined): string {
  if (!data) return "";
  const rol = data.rol;
  return typeof rol === "string" ? rol : "";
}

function comisionPendienteRdFromBilletera(data: AnyMap | undefined): number {
  if (!data) return 0;
  const v = data.comisionPendiente;
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
}

function saldoPrepagoRdFromBilletera(data: AnyMap | undefined): number {
  if (!data) return 0;
  const v = data.saldoPrepagoComisionRd;
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
}

function saldoReservadoGirasRdFromBilletera(data: AnyMap | undefined): number {
  if (!data) return 0;
  const v = data.saldoReservadoParaGiras;
  if (typeof v === "number" && Number.isFinite(v)) return Math.max(0, v);
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? Math.max(0, n) : 0;
  }
  return 0;
}

/** Prepago disponible para viajes normales + giras (prepago − reservado en giras). */
function saldoDisponiblePrepagoRdFromBilletera(data: AnyMap | undefined): number {
  const prep = saldoPrepagoRdFromBilletera(data);
  const res = saldoReservadoGirasRdFromBilletera(data);
  return Math.max(0, prep - res);
}

/** Snapshot inmutable en `viajes` al cierre: perfil bancario + cédula del taxista. */
function snapshotPerfilTaxistaParaFactura(uData: AnyMap | undefined): {
  bancoTaxista: string;
  numeroCuentaTaxista: string;
  tipoCuentaTaxista: string;
  titularCuentaTaxista: string;
  ciTaxista: string;
} {
  const u = uData ?? {};
  return {
    bancoTaxista: String(u.banco ?? "").trim(),
    numeroCuentaTaxista: String(u.numeroCuenta ?? "").trim(),
    tipoCuentaTaxista: String(u.tipoCuenta ?? "").trim(),
    titularCuentaTaxista: String(u.titularCuenta ?? u.titular ?? "").trim(),
    ciTaxista: String(u.ciTaxista ?? u.cedula ?? u.cedulaTaxista ?? "").trim(),
  };
}

function numOr(n: unknown, fallback: number): number {
  if (typeof n === "number" && Number.isFinite(n)) return n;
  if (typeof n === "string") {
    const p = Number(n);
    if (Number.isFinite(p)) return p;
  }
  return fallback;
}

function financeBool(raw: unknown, defaultValue: boolean): boolean {
  if (raw === undefined || raw === null) return defaultValue;
  return raw === true;
}

/** `config/finance` — flags financieros (Fase 1 + PR2). */
export async function getFinanceConfig(): Promise<{
  excluirEfectivoDePagoSemanal: boolean;
  useLiquidacionesSemanales: boolean;
  escrituraPagosTaxistasLegacy: boolean;
  generarLiquidacionesSemanalesAuto: boolean;
  transferenciaRecaudoEnCuentaRai: boolean;
  conciliacionAutomaticaHabilitada: boolean;
  transferenciaExigeVerificadoParaFinalizar: boolean;
  qrRecaudoPopularHabilitado: boolean;
  pagosConTarjetaAzulHabilitados: boolean;
}> {
  const now = Date.now();
  if (_financeCfgCache && now - _financeCfgCache.loadedAt < COMISION_PREPAGO_CONFIG_TTL_MS) {
    return {
      excluirEfectivoDePagoSemanal: _financeCfgCache.excluirEfectivoDePagoSemanal,
      useLiquidacionesSemanales: _financeCfgCache.useLiquidacionesSemanales,
      escrituraPagosTaxistasLegacy: _financeCfgCache.escrituraPagosTaxistasLegacy,
      generarLiquidacionesSemanalesAuto: _financeCfgCache.generarLiquidacionesSemanalesAuto,
      transferenciaRecaudoEnCuentaRai: _financeCfgCache.transferenciaRecaudoEnCuentaRai,
      conciliacionAutomaticaHabilitada: _financeCfgCache.conciliacionAutomaticaHabilitada,
      transferenciaExigeVerificadoParaFinalizar:
        _financeCfgCache.transferenciaExigeVerificadoParaFinalizar,
      qrRecaudoPopularHabilitado: _financeCfgCache.qrRecaudoPopularHabilitado,
      pagosConTarjetaAzulHabilitados: _financeCfgCache.pagosConTarjetaAzulHabilitados,
    };
  }
  try {
    const snap = await db().collection("config").doc("finance").get();
    const data = (snap.data() ?? {}) as AnyMap;
    const cfg = {
      excluirEfectivoDePagoSemanal: financeBool(data.excluirEfectivoDePagoSemanal, true),
      useLiquidacionesSemanales: financeBool(data.useLiquidacionesSemanales, false),
      escrituraPagosTaxistasLegacy: financeBool(data.escrituraPagosTaxistasLegacy, true),
      generarLiquidacionesSemanalesAuto: financeBool(data.generarLiquidacionesSemanalesAuto, false),
      transferenciaRecaudoEnCuentaRai: financeBool(data.transferenciaRecaudoEnCuentaRai, false),
      conciliacionAutomaticaHabilitada: financeBool(data.conciliacionAutomaticaHabilitada, false),
      transferenciaExigeVerificadoParaFinalizar: financeBool(
        data.transferenciaExigeVerificadoParaFinalizar,
        false,
      ),
      qrRecaudoPopularHabilitado: financeBool(data.qrRecaudoPopularHabilitado, false),
      pagosConTarjetaAzulHabilitados: financeBool(data.pagosConTarjetaAzulHabilitados, false),
    };
    _financeCfgCache = { loadedAt: now, ...cfg };
    return cfg;
  } catch (e) {
    console.error("[getFinanceConfig]", e);
    return {
      excluirEfectivoDePagoSemanal: true,
      useLiquidacionesSemanales: false,
      escrituraPagosTaxistasLegacy: true,
      generarLiquidacionesSemanalesAuto: false,
      transferenciaRecaudoEnCuentaRai: false,
      conciliacionAutomaticaHabilitada: false,
      transferenciaExigeVerificadoParaFinalizar: false,
      qrRecaudoPopularHabilitado: false,
      pagosConTarjetaAzulHabilitados: false,
    };
  }
}

/** PR2: bloquea approve/reject legacy cuando liquidaciones semanales está activo. */
async function assertLegacyPagosTaxistasFlowsDisabled(): Promise<void> {
  const { useLiquidacionesSemanales } = await getFinanceConfig();
  if (useLiquidacionesSemanales) {
    throw new HttpsError(
      "failed-precondition",
      "El flujo legacy pagos_taxistas está deshabilitado. Use aprobarLiquidacionSemanal.",
    );
  }
}

export async function getComisionPrepagoConfig(): Promise<{ minimoOperativoRd: number; umbralPreventivoRd: number }> {
  const now = Date.now();
  if (_cfgCache && now - _cfgCache.loadedAt < COMISION_PREPAGO_CONFIG_TTL_MS) {
    return {
      minimoOperativoRd: _cfgCache.minimoOperativoRd,
      umbralPreventivoRd: _cfgCache.umbralPreventivoRd,
    };
  }
  try {
    const snap = await db().collection("config").doc("comision_prepago").get();
    const data = (snap.data() ?? {}) as AnyMap;
    const minimoOperativoRd = numOr(data.minimoOperativoRd, MIN_SALDO_PREPAGO_COMISION_RD);
    const umbralPreventivoRd = numOr(data.umbralPreventivoRd, UMBRAL_AVISO_PREVENTIVO_PREPAGO_RD);
    _cfgCache = {
      loadedAt: now,
      minimoOperativoRd,
      umbralPreventivoRd,
    };
    return { minimoOperativoRd, umbralPreventivoRd };
  } catch (e) {
    console.error("[getComisionPrepagoConfig]", e);
    return {
      minimoOperativoRd: MIN_SALDO_PREPAGO_COMISION_RD,
      umbralPreventivoRd: UMBRAL_AVISO_PREVENTIVO_PREPAGO_RD,
    };
  }
}

/**
 * Pool / aceptar viaje: bloqueo estricto (modelo empresarial).
 * - Cualquier `comisionPendiente` > 0 → bloqueo inmediato (sin zona gris 0–500).
 * - Tras el 1.er viaje efectivo gratis: saldo prepago disponible < mínimo operativo → bloqueo.
 */
function bloqueoOperativoPrepago(
  data: AnyMap | undefined,
  minimoOperativoRd: number = MIN_SALDO_PREPAGO_COMISION_RD,
): boolean {
  const pend = comisionPendienteRdFromBilletera(data);
  if (pend > 1e-6) return true;
  if (data?.primerViajeComisionGratisConsumido !== true) return false;
  return saldoDisponiblePrepagoRdFromBilletera(data) + 1e-9 < minimoOperativoRd;
}

function comisionPendienteDesdeSnap(snap: DocumentSnapshot | undefined): number {
  if (!snap?.exists) return 0;
  return comisionPendienteRdFromBilletera(snap.data() as AnyMap | undefined);
}

function toDateFromUnknown(v: unknown): Date | null {
  if (v && typeof v === "object" && typeof (v as { toDate?: unknown }).toDate === "function") {
    try {
      return (v as { toDate: () => Date }).toDate();
    } catch (_) {
      return null;
    }
  }
  if (v instanceof Date) return v;
  if (typeof v === "string" || typeof v === "number") {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

/** FCM a tokens en push_tokens/{uid} (misma convención que scheduled_pool_notify). No lanza si no hay tokens. */
async function enviarPushComisionTaxista(
  uid: string,
  title: string,
  body: string,
  dataType: string,
): Promise<void> {
  const tokSnap = await db().collection("push_tokens").doc(uid).get();
  const raw = tokSnap.data()?.tokens;
  const tokens = Array.isArray(raw)
    ? raw.filter((t): t is string => typeof t === "string" && t.length > 10)
    : [];
  if (tokens.length === 0) return;

  await messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: {
      type: dataType,
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
    android: {
      notification: {
        channelId: ANDROID_CHANNEL_TAXISTA,
        sound: "default",
      },
    },
    apns: {
      payload: {
        aps: { sound: "default" },
      },
    },
  });
}

async function enviarPushAdminsComision(
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  const adminsSnap = await db().collection("usuarios").where("rol", "==", "admin").limit(80).get();
  if (adminsSnap.empty) return;

  for (const admin of adminsSnap.docs) {
    const uid = admin.id.trim();
    if (!uid) continue;
    try {
      const tokSnap = await db().collection("push_tokens").doc(uid).get();
      const raw = tokSnap.data()?.tokens;
      const tokens = Array.isArray(raw)
        ? raw.filter((t): t is string => typeof t === "string" && t.length > 10)
        : [];
      if (tokens.length === 0) continue;
      await messaging().sendEachForMulticast({
        tokens,
        notification: { title, body },
        data: {
          ...data,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          notification: {
            channelId: ANDROID_CHANNEL_TAXISTA,
            sound: "default",
          },
        },
        apns: {
          payload: {
            aps: { sound: "default" },
          },
        },
      });
    } catch (e) {
      console.error("[enviarPushAdminsComision]", uid, e);
    }
  }
}

function saldoPrepagoDesdeSnap(snap: DocumentSnapshot | undefined): number {
  if (!snap?.exists) return 0;
  return saldoPrepagoRdFromBilletera(snap.data() as AnyMap | undefined);
}

/** Aviso al cruzar por debajo del mínimo de saldo prepago (solo si ya no hay deuda legacy). */
async function notificarSaldoPrepagoInsuficiente(
  uid: string,
  pendDespues: number,
  saldoAntes: number,
  saldoDespues: number,
): Promise<void> {
  const eps = 1e-6;
  try {
    const cfg = await getComisionPrepagoConfig();
    const minimo = cfg.minimoOperativoRd;
    if (pendDespues > eps) return;
    if (saldoAntes + eps < minimo) return;
    if (saldoDespues + eps >= minimo) return;
    const pct = await getComisionViajePorcentajeCached();
    const pctLabel = Number.isInteger(pct) ? `${pct}` : pct.toFixed(1);
    await enviarPushComisionTaxista(
      uid,
      "Falta crédito prepago",
      `Tu saldo de comisión (efectivo) quedó en RD$${saldoDespues.toFixed(2)}. Recarga RD$${minimo.toFixed(0)} o más desde Mis pagos para seguir en pool y tomar viajes (el ${pctLabel}% de cada viaje en efectivo se descuenta de tu saldo).`,
      "taxista_prepago_comision_bajo_min",
    );
  } catch (e) {
    console.error("[notificarSaldoPrepagoInsuficiente]", uid, e);
  }
}

/** Aviso preventivo al taxista cuando cruza debajo del umbral de alerta (aún sin bloqueo). */
async function notificarSaldoPrepagoPreventivo(
  uid: string,
  pendDespues: number,
  saldoAntes: number,
  saldoDespues: number,
  prepagoActivo: boolean,
): Promise<void> {
  const eps = 1e-6;
  try {
    const cfg = await getComisionPrepagoConfig();
    const minimo = cfg.minimoOperativoRd;
    const umbralPreventivo = cfg.umbralPreventivoRd;
    if (!prepagoActivo) return;
    if (pendDespues > eps) return;
    if (saldoAntes + eps < umbralPreventivo) return;
    if (saldoDespues + eps >= umbralPreventivo) return;
    if (saldoDespues + eps < minimo) return;
    await enviarPushComisionTaxista(
      uid,
      "Tu saldo prepago está por agotarse",
      `Te quedan RD$${saldoDespues.toFixed(2)} de saldo prepago. Recarga pronto desde Mis pagos para evitar bloqueo (mínimo operativo RD$${minimo.toFixed(0)}).`,
      "taxista_prepago_comision_preventivo",
    );
  } catch (e) {
    console.error("[notificarSaldoPrepagoPreventivo]", uid, e);
  }
}

async function notificarComisionPendienteInmediata(
  uid: string,
  pendAntes: number,
  pendDespues: number,
): Promise<void> {
  const eps = 1e-6;
  try {
    if (pendAntes > eps || pendDespues <= eps) return;
    await enviarPushComisionTaxista(
      uid,
      "Cuenta suspendida — comisión pendiente",
      `Quedó RD$${pendDespues.toFixed(2)} en comisión efectivo pendiente. Deposita y envía comprobante en Mis pagos; al verificar el admin podrás volver a operar.`,
      "taxista_comision_pendiente_bloqueo",
    );
  } catch (e) {
    console.error("[notificarComisionPendienteInmediata]", uid, e);
  }
}

async function notificarLegacyComisionTope(uid: string, pendAntes: number, pendDespues: number): Promise<void> {
  const eps = 1e-6;
  try {
    if (pendAntes + eps < UMBRAL_COMISION_LEGACY_RD && pendDespues + eps >= UMBRAL_COMISION_LEGACY_RD) {
      await enviarPushComisionTaxista(
        uid,
        "Tope de comisión (histórico)",
        `Tienes RD$${pendDespues.toFixed(2)} en comisión efectivo pendiente (tope RD$${UMBRAL_COMISION_LEGACY_RD.toFixed(0)}). Deposita y envía comprobante en Mis pagos; al verificar el admin se regulariza.`,
        "taxista_comision_legacy_bloqueo_500",
      );
    }
  } catch (e) {
    console.error("[notificarLegacyComisionTope]", uid, e);
  }
}

/** Devuelve el valor final de `tienePagoPendiente` escrito en `usuarios`. */
async function syncTienePagoPendiente(uidTaxista: string): Promise<boolean> {
  const uid = uidTaxista.trim();
  if (!uid) {
    logger.warn("[syncTienePagoPendiente] uid vacío; omitido");
    return false;
  }
  const prepagoCfg = await getComisionPrepagoConfig();
  const billeSnap = await db().collection("billeteras_taxista").doc(uid).get();
  const bloqueoComision = bloqueoOperativoPrepago(
    billeSnap.data() as AnyMap | undefined,
    prepagoCfg.minimoOperativoRd,
  );
  // Deuda de pool pendiente de validación admin (acumulada por taxista).
  let deudaPoolPendienteRd = 0;
  try {
    const poolsPendSnap = await db()
      .collection("viajes_pool")
      .where("ownerTaxistaId", "==", uid)
      .where("comisionPendientePagoAdmin", "==", true)
      .limit(500)
      .get();
    for (const doc of poolsPendSnap.docs) {
      const d = (doc.data() ?? {}) as AnyMap;
      const v = d.montoComisionPendienteAdmin ?? d.montoComision;
      if (typeof v === "number" && Number.isFinite(v)) deudaPoolPendienteRd += v;
      else if (typeof v === "string") {
        const n = Number(v);
        if (Number.isFinite(n)) deudaPoolPendienteRd += n;
      }
    }
  } catch (e) {
    // Índice compuesto faltante u otro error: no bloquear finalización de viaje.
    logger.warn("[syncTienePagoPendiente] consulta pool omitida", { uid, err: e });
  }
  const bloqueoPool = deudaPoolPendienteRd + 1e-9 >= UMBRAL_DEUDA_POOL_RD;
  // Misma regla + deuda pool: prepago bajo/legacy o deuda pool acumulada >= tope.
  const tienePagoPendiente = bloqueoComision || bloqueoPool;
  await db().collection("usuarios").doc(uid).set(
    {
      tienePagoPendiente,
      deudaPoolPendienteRd: Number(deudaPoolPendienteRd.toFixed(2)),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return tienePagoPendiente;
}

/** Misma lógica que `refundGiraReservaPagoSemanal` / `cancelPoolTrip`, inlined para sync servidor. */
function numOr0Gira(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number.parseFloat(v);
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
}

async function devolverPrepagoGiraReservadaSiAplica(
  tx: Transaction,
  poolId: string,
  pool: AnyMap,
  motivoLedger: string,
): Promise<number> {
  const reserved = Math.max(0, numOr0Gira(pool.comisionGiraEstimadaRd));
  const etapa = String(pool.prepagoComisionEtapa ?? "").trim().toLowerCase();
  if (reserved <= 1e-9 || etapa !== "reservada_creacion") return 0;
  const owner = String(pool.ownerTaxistaId ?? "").trim();
  if (!owner) return 0;

  const billeRef = db().collection("billeteras_taxista").doc(owner);
  const bs = await tx.get(billeRef);
  const bille = (bs.data() ?? {}) as AnyMap;
  const prep = Math.max(0, numOr0Gira(bille.saldoPrepagoComisionRd));
  const reserv = Math.max(0, numOr0Gira(bille.saldoReservadoParaGiras));
  if (reserv + 1e-9 < reserved) {
    logger.warn("[GIRA_PREPAGO] sync pago semanal: reserv insuficiente", { poolId, reserv, reserved });
    return 0;
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
  tx.update(db().collection("viajes_pool").doc(poolId), {
    prepagoComisionEtapa: "devuelta_pago_semanal",
    comisionGiraEstimadaRd: 0,
    updatedAt: FieldValue.serverTimestamp(),
  });
  const led = db().collection("ledger_giras").doc();
  tx.set(led, {
    tipo: "devolucion_reserva",
    poolId,
    uidTaxista: owner,
    monto: reserved,
    motivo: motivoLedger,
    createdAt: FieldValue.serverTimestamp(),
  });
  return reserved;
}

/** Misma lógica que `PoolRepo.syncPoolsPorPagoSemanal` en la app (cierra pools si comisión ≥ tope). */
async function syncPoolsPorPagoSemanal(ownerTaxistaId: string, tienePagoPendiente: boolean): Promise<void> {
  const trimmed = ownerTaxistaId.trim();
  if (!trimmed) return;
  const snap = await db().collection("viajes_pool").where("ownerTaxistaId", "==", trimmed).get();
  if (snap.empty) return;

  for (const docSnap of snap.docs) {
    const d = (docSnap.data() ?? {}) as AnyMap;
    const estadoActual = String(d.estado ?? "abierto");
    const canceladoPorPagoSemanal = d.canceladoPorPagoSemanal === true;
    const estadoPrevio = String(d.estadoPrevioPorPagoSemanal ?? estadoActual);

    if (tienePagoPendiente) {
      if (estadoActual === "cancelado" && canceladoPorPagoSemanal) continue;
      if (estadoActual === "cancelado" && !canceladoPorPagoSemanal) continue;
      try {
        await db().runTransaction(async (tx) => {
          const fresh = await tx.get(docSnap.ref);
          if (!fresh.exists) return;
          const p = (fresh.data() ?? {}) as AnyMap;
          const est = String(p.estado ?? "abierto");
          if (est === "cancelado" && p.canceladoPorPagoSemanal === true) return;
          if (est === "cancelado" && p.canceladoPorPagoSemanal !== true) return;

          await devolverPrepagoGiraReservadaSiAplica(
            tx,
            docSnap.id,
            p,
            "pago_semanal_cierra_pool",
          );

          tx.update(docSnap.ref, {
            estado: "cancelado",
            canceladoPorPagoSemanal: true,
            estadoPrevioPorPagoSemanal: est,
            canceladoPorPagoSemanalEn: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
        });
      } catch (e) {
        logger.error("[syncPoolsPorPagoSemanal] cancel+refund pool", { poolId: docSnap.id, e });
      }
    } else if (estadoActual === "cancelado" && canceladoPorPagoSemanal) {
      try {
        await db().runTransaction(async (tx) => {
          const fresh = await tx.get(docSnap.ref);
          if (!fresh.exists) return;
          const p = (fresh.data() ?? {}) as AnyMap;
          if (p.estado !== "cancelado" || p.canceladoPorPagoSemanal !== true) return;
          const prev = String(p.estadoPrevioPorPagoSemanal ?? "").trim();
          tx.update(docSnap.ref, {
            estado: prev.length > 0 ? prev : "abierto",
            canceladoPorPagoSemanal: false,
            estadoPrevioPorPagoSemanal: FieldValue.delete(),
            canceladoPorPagoSemanalEn: FieldValue.delete(),
            updatedAt: FieldValue.serverTimestamp(),
          });
        });
      } catch (e) {
        logger.error("[syncPoolsPorPagoSemanal] restore pool", { poolId: docSnap.id, e });
      }
    }
  }
}

/** Tras sumar comisión por bola finalizada (Cloud Function `finalizarBolaPueblo`). */
export async function syncTaxistaComisionTrasBola(uidTaxista: string): Promise<void> {
  const uid = uidTaxista.trim();
  if (!uid) return;
  const tienePagoPendiente = await syncTienePagoPendiente(uid);
  await syncPoolsPorPagoSemanal(uid, tienePagoPendiente);
}

/** Recalcula y aplica bloqueo operativo completo (bandera + pools). */
export async function syncTaxistaBloqueoOperativo(uidTaxista: string): Promise<boolean> {
  const uid = uidTaxista.trim();
  if (!uid) return false;
  const tienePagoPendiente = await syncTienePagoPendiente(uid);
  await syncPoolsPorPagoSemanal(uid, tienePagoPendiente);
  return tienePagoPendiente;
}

async function getRole(uid: string): Promise<string> {
  const snap = await db().collection("usuarios").doc(uid).get();
  let rolUsuario = roleFromUserDoc(snap.data() as AnyMap | undefined).trim().toLowerCase();
  if (rolUsuario === "administrador") rolUsuario = "admin";
  // Misma convención que Firestore rules / app: chofer legacy "driver" = taxista.
  if (rolUsuario === "driver") rolUsuario = "taxista";
  if (rolUsuario) return rolUsuario;

  const rolSnap = await db().collection("roles").doc(uid).get();
  let rolRaw = String((rolSnap.data() as AnyMap | undefined)?.rol ?? "").trim().toLowerCase();
  if (rolRaw === "administrador") rolRaw = "admin";
  if (rolRaw === "driver") rolRaw = "taxista";
  return rolRaw;
}

/** Alineado con EstadosViaje.normalizar (Flutter): alias legacy y espacios. */
function normalizeEstadoViajeDoc(raw: unknown): string {
  const s = String(raw ?? "").trim().toLowerCase().replace(/\s+/g, "_");
  if (s === "encurso" || s === "en_curso" || s === "en_curzo") return "en_curso";
  if (
    s === "a_bordo" ||
    s === "abordo" ||
    s === "a_bordo_pickup" ||
    s === "cliente_a_bordo"
  ) {
    return "a_bordo";
  }
  if (s === "finalizado" || s === "completado") return "completado";
  return s;
}

/** Taxista puede cerrar contablemente si ya va al destino o quedó a bordo con PIN (sin bug de estado). */
function estadoPermiteFinalizarTaxista(estadoNorm: string): boolean {
  return estadoNorm === "en_curso" || estadoNorm === "a_bordo";
}

/** Viaje espejo Bola Ahorro (`tipoServicio == bola_ahorro`): alinea tablero `bolas_pueblo`. */
function bolaIdDesdeViajeEspejo(d: AnyMap): string {
  if (String(d.tipoServicio ?? "").trim() !== "bola_ahorro") return "";
  return String(d.bolaPuebloId ?? d.bolaId ?? "").trim();
}

function patchBolaPuebloTrasViajeEspejoFinalizado(
  viajeId: string,
  viajeData: AnyMap,
  esEfectivo: boolean,
  facturaSaldoPrepagoComisionRd: number | null,
): Record<string, unknown> | null {
  const bolaId = bolaIdDesdeViajeEspejo(viajeData);
  if (!bolaId) return null;

  const estadoPagoRaw = viajeData.estadoPago;
  const estadoPago = String(
    estadoPagoRaw ?? (esEfectivo ? "pagado" : "pendiente"),
  ).trim();

  const patch: Record<string, unknown> = {
    estado: "finalizada",
    estadoViajeBola: "finalizada",
    finalizadaEn: FieldValue.serverTimestamp(),
    comisionAplicada: true,
    viajeCompletadoId: viajeId,
    updatedAt: FieldValue.serverTimestamp(),
    metodoPago: esEfectivo ? "efectivo" : "transferencia",
    estadoPago,
    confirmacionTaxistaFinal: true,
    confirmacionClienteFinal: true,
  };

  const saldo =
    facturaSaldoPrepagoComisionRd ?? viajeData.facturaSaldoPrepagoComisionRd;
  if (typeof saldo === "number" && Number.isFinite(saldo)) {
    patch.facturaSaldoPrepagoComisionRd = saldo;
  }
  const comp = String(viajeData.comprobanteTransferenciaUrl ?? "").trim();
  if (comp) patch.comprobanteTransferenciaUrl = comp;
  if (viajeData.transferenciaConfirmada === true) {
    patch.transferenciaConfirmada = true;
  }
  return patch;
}

async function syncBolaPuebloTrasViajeEspejoFinalizado(
  viajeId: string,
  viajeData: AnyMap,
): Promise<void> {
  const metodo = String(viajeData.metodoPago ?? "").toLowerCase().trim();
  const esEfectivo = metodo.length === 0 || metodo.includes("efectivo");
  const saldoRaw = viajeData.facturaSaldoPrepagoComisionRd;
  const saldo =
    typeof saldoRaw === "number" && Number.isFinite(saldoRaw) ? saldoRaw : null;
  const patch = patchBolaPuebloTrasViajeEspejoFinalizado(
    viajeId,
    viajeData,
    esEfectivo,
    saldo,
  );
  if (!patch) return;
  const bolaId = bolaIdDesdeViajeEspejo(viajeData);
  await db().collection("bolas_pueblo").doc(bolaId).set(patch, { merge: true });
  logger.info("[BOLA_AHORRO] sync bola finalizada desde viaje espejo", { viajeId, bolaId });
}

async function ensureIdempotencyStart(
  key: string,
  op: string,
  uid: string,
): Promise<{ done: boolean; result?: AnyMap; ref: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData> }> {
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

export const finalizarViajeSeguro = onCall(async (request) => {
  try {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const viajeIdRaw = request.data?.viajeId;
  const idemRaw = request.data?.idempotencyKey;
  const viajeId = typeof viajeIdRaw === "string" ? viajeIdRaw.trim() : "";
  const idemKey = typeof idemRaw === "string" ? idemRaw.trim() : "";
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "finalizar_viaje_seguro", uidActor);
  if (idem.done) return idem.result;

  const comisionViajePct = await getComisionViajePorcentajeCached();
  const incentivosCfg = await getComisionIncentivosTaxistaConfigCached();

  const viajeRef = db().collection("viajes").doc(viajeId);
  const result = await db().runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const d = (vSnap.data() ?? {}) as AnyMap;

    const uidTaxista = String(d.uidTaxista ?? d.taxistaId ?? "").trim();
    const uidCliente = String(d.uidCliente ?? d.clienteId ?? "").trim();
    const estado = normalizeEstadoViajeDoc(d.estado);
    const completado = d.completado === true;
    if (!uidTaxista) {
      throw new HttpsError(
        "failed-precondition",
        "El viaje no tiene conductor asignado (uidTaxista vacío). Revisá el documento en Firestore o reasigná el viaje.",
      );
    }
    if (role === "taxista" && uidTaxista !== uidActor) {
      throw new HttpsError("permission-denied", "No autorizado para este viaje");
    }

    if (completado || estado === "completado") {
      return { ok: true, viajeId, alreadyCompleted: true, uidTaxista };
    }
    assertMultiparadaCompletaParaFinalizar(d);

    const financeCfg = await getFinanceConfig();
    const metodoPre = String(d.metodoPago ?? "").toLowerCase().trim();
    const esTransferPre = metodoPre.includes("transfer");
    const usaRecaudoRai =
      String(d.referenciaRecaudo ?? "").trim().length > 0 ||
      String(d.recaudoDestino ?? "").trim().toLowerCase() === "rai";
    if (
      financeCfg.transferenciaExigeVerificadoParaFinalizar &&
      esTransferPre &&
      usaRecaudoRai
    ) {
      const ep = String(d.estadoPago ?? "").trim().toLowerCase();
      if (ep !== "verificado" && d.transferenciaConfirmada !== true) {
        throw new HttpsError(
          "failed-precondition",
          "No se puede finalizar: la transferencia a cuenta RAI aún no está verificada por conciliación bancaria.",
        );
      }
    }

    const esTarjetaPre =
      metodoPre.includes("tarjeta") || metodoPre.includes("card");
    if (financeCfg.pagosConTarjetaAzulHabilitados && esTarjetaPre) {
      const paymentObj = (d.payment ?? {}) as AnyMap;
      const payStatus = String(paymentObj.status ?? "").trim().toLowerCase();
      const ep = String(d.estadoPago ?? "").trim().toLowerCase();
      if (ep !== "verificado" && payStatus !== "captured") {
        throw new HttpsError(
          "failed-precondition",
          "No se puede finalizar: el pago con tarjeta (AZUL) aún no está capturado.",
        );
      }
    }

    if (!estadoPermiteFinalizarTaxista(estado)) {
      const rawEst = String(d.estado ?? "");
      logger.warn("[FINALIZAR_ERROR] finalizarViajeSeguro estado no finalizable", {
        viajeId,
        uidActor,
        estadoRaw: rawEst,
        estadoNorm: estado,
        completado,
        codigoVerificado: d.codigoVerificado === true,
      });
      throw new HttpsError(
        "failed-precondition",
        `No se puede finalizar ahora: el viaje está en estado "${rawEst || estado}". ` +
          "Tenés que tener el cliente a bordo con código verificado e iniciar la ruta al destino, o ya estar en ruta. Si ya lo hiciste, esperá un segundo y reintentá.",
      );
    }

    const precioCentsDb = typeof d.precio_cents === "number" ? Math.trunc(d.precio_cents) : null;
    const comisionCentsDb = typeof d.comision_cents === "number" ? Math.trunc(d.comision_cents) : null;
    const gananciaCentsDb = typeof d.ganancia_cents === "number" ? Math.trunc(d.ganancia_cents) : null;

    const metodo = String(d.metodoPago ?? "").toLowerCase().trim();
    const esEfectivo = metodo.includes("efectivo");
    const metodoAsiento = esEfectivo ? "efectivo" : (metodo.includes("transfer") ? "transferencia" : "tarjeta");
    const pagoRegistrado = d.pagoRegistrado === true;

    const precioCents = (precioCentsDb !== null && precioCentsDb > 0)
      ? precioCentsDb
      : toCents(d.precioFinal ?? d.precio ?? d.total ?? 0);

    const billeRef = db().collection("billeteras_taxista").doc(uidTaxista);
    const asientoRef = db().collection("pagos").doc(`viaje_${viajeId}_asiento`);
    const userTaxRef = db().collection("usuarios").doc(uidTaxista);
    const statsRef = statsDocRef(uidTaxista);

    // Firestore: todas las lecturas de la transacción antes de cualquier escritura.
    const uSnap = await tx.get(userTaxRef);
    const billeSnapPre = await tx.get(billeRef);
    const statsSnap = await tx.get(statsRef);
    let asientoSnapPre: DocumentSnapshot | null = null;
    let ledgerMovSnapPre: DocumentSnapshot | null = null;
    if (!pagoRegistrado) {
      asientoSnapPre = await tx.get(asientoRef);
      if (esEfectivo) {
        ledgerMovSnapPre = await tx.get(comisionViajeEfectivoLedgerRef(uidTaxista, viajeId));
      }
    }

    let comisionPctAplicada = comisionViajePct;
    let incentivoViajePatch: AnyMap = {};
    if (!pagoRegistrado) {
      const inc = aplicarIncentivoComisionEnFinalizar({
        cfg: incentivosCfg,
        globalPct: comisionViajePct,
        statsData: (statsSnap.data() ?? {}) as AnyMap,
        now: new Date(),
      });
      comisionPctAplicada = inc.pctEfectiva;
      incentivoViajePatch = inc.viajePatch;
      tx.set(statsRef, inc.statsPatch, { merge: true });
    }

    // Tras `pagoRegistrado`, conservar partidas ya cerradas (idempotencia).
    const comisionCents =
      pagoRegistrado && comisionCentsDb !== null && comisionCentsDb >= 0
        ? comisionCentsDb
        : comisionCentsDesdePrecioCents(precioCents, comisionPctAplicada);
    const gananciaCents =
      pagoRegistrado && gananciaCentsDb !== null && gananciaCentsDb >= 0
        ? gananciaCentsDb
        : Math.max(0, precioCents - comisionCents);

    const uData = (uSnap.data() ?? {}) as AnyMap;
    const perfilFacturaSnap = snapshotPerfilTaxistaParaFactura(uData);

    /** Saldo prepago comisión tras este cierre (solo viajes en efectivo); `null` = no aplica (transferencia/tarjeta). */
    let facturaSaldoPrepagoComisionRd: number | null = null;
    if (esEfectivo) {
      facturaSaldoPrepagoComisionRd = Number.parseFloat(
        saldoPrepagoRdFromBilletera((billeSnapPre.data() ?? {}) as AnyMap).toFixed(2),
      );
    }

    if (!pagoRegistrado) {
      tx.update(viajeRef, {
        metodoPago: esEfectivo ? "Efectivo" : (metodo.includes("transfer") ? "Transferencia" : "Tarjeta"),
        "payment.status": esEfectivo ? "cash_collected" : "bank_transfer_received",
        "payment.provider": esEfectivo ? "cash" : "transfer",
        "payment.updatedAt": FieldValue.serverTimestamp(),
        estadoPago: esEfectivo ? "pagado" : "pendiente",
        precio_cents: precioCents,
        comision_cents: comisionCents,
        ganancia_cents: gananciaCents,
        precio: fromCents(precioCents),
        total: fromCents(precioCents),
        comision: fromCents(comisionCents),
        comisionFlygo: fromCents(comisionCents),
        gananciaTaxista: fromCents(gananciaCents),
        pagoRegistrado: true,
        liquidado: false,
        pagoDetalle: {
          taxistaId: uidTaxista,
          metodo: metodoAsiento,
          total_cents: precioCents,
          comision_cents: comisionCents,
          ganancia_cents: gananciaCents,
          createdAt: FieldValue.serverTimestamp(),
        },
        "settlement.commission": fromCents(comisionCents),
        "settlement.driverAmount": fromCents(gananciaCents),
        "settlement.status": "pending",
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      });

      const bData = (billeSnapPre.data() ?? {}) as AnyMap;
      const billePatch: Record<string, unknown> = {
        ultimoViajeId: viajeId,
        ultimaComisionCents: comisionCents,
        ultimaGananciaCents: gananciaCents,
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (esEfectivo) {
        const pend = comisionPendienteRdFromBilletera(bData);
        const flag = bData.primerViajeComisionGratisConsumido === true;
        const saldoIni = saldoPrepagoRdFromBilletera(bData);
        const comisionRd = fromCents(comisionCents);
        if (!flag && pend < 1e-6) {
          billePatch.primerViajeComisionGratisConsumido = true;
          facturaSaldoPrepagoComisionRd = Number.parseFloat(saldoIni.toFixed(2));
          await ledgerComisionViajeEfectivoCf(tx, {
            uidTaxista,
            viajeId,
            fuente: "finalizar_viaje_seguro_cf",
            comisionTotalRd: comisionRd,
            pendienteAntes: pend,
            saldoPrepagoAntes: saldoIni,
            pendienteDespues: pend,
            saldoPrepagoDespues: saldoIni,
            primerEfectivoSinDescuento: true,
            existingMovSnap: ledgerMovSnapPre ?? undefined,
          });
        } else {
          let p = pend;
          let saldo = saldoIni;
          const fromPend = Math.min(p, comisionRd);
          p = Number.parseFloat((p - fromPend).toFixed(2));
          const rem = Number.parseFloat((comisionRd - fromPend).toFixed(2));
          const prepagoLibreIni = saldoDisponiblePrepagoRdFromBilletera(bData);
          const cubiertoPrepago = rem <= prepagoLibreIni ? rem : prepagoLibreIni;
          const faltantePrepago = Number.parseFloat((rem - cubiertoPrepago).toFixed(2));
          saldo = Number.parseFloat((saldo - cubiertoPrepago).toFixed(2));
          p = Number.parseFloat((p + faltantePrepago).toFixed(2));
          billePatch.comisionPendiente = p;
          billePatch.saldoPrepagoComisionRd = saldo;
          billePatch.primerViajeComisionGratisConsumido = true;
          facturaSaldoPrepagoComisionRd = Number.parseFloat(saldo.toFixed(2));
          await ledgerComisionViajeEfectivoCf(tx, {
            uidTaxista,
            viajeId,
            fuente: "finalizar_viaje_seguro_cf",
            comisionTotalRd: comisionRd,
            pendienteAntes: pend,
            saldoPrepagoAntes: saldoIni,
            pendienteDespues: p,
            saldoPrepagoDespues: saldo,
            primerEfectivoSinDescuento: false,
            existingMovSnap: ledgerMovSnapPre ?? undefined,
          });
        }
      }
      tx.set(billeRef, billePatch, { merge: true });

      if (asientoSnapPre && !asientoSnapPre.exists) {
        tx.set(asientoRef, {
          tipo: "taxista",
          viajeId,
          uidTaxista,
          monto: esEfectivo ? -fromCents(comisionCents) : fromCents(gananciaCents),
          totalCents: precioCents,
          comisionCents,
          gananciaCents,
          comisionPlataformaPct: comisionPctAplicada,
          fuenteAsiento: "finalizar_viaje_seguro_cf",
          metodo: metodoAsiento,
          estado: esEfectivo ? "comision_pendiente" : "por_liquidar",
          fecha: new Date().toISOString(),
          provider: esEfectivo ? "cash" : "transfer",
          createdAt: FieldValue.serverTimestamp(),
        });
      }
    }

    const metodoNorm = metodoPagoNormalizado(
      pagoRegistrado ? String(d.metodoPago ?? metodo) : metodo,
    );
    const estadoPagoCierre = esEfectivo
      ? "pagado"
      : String(d.estadoPago ?? (pagoRegistrado ? d.estadoPago : "pendiente") ?? "pendiente");
    const elegibilidadSemanal = {
      metodoPagoNormalizado: metodoNorm,
      estadoPago: estadoPagoCierre,
      liquidado: d.liquidado === true,
    };

    tx.update(viajeRef, {
      estado: "completado",
      completado: true,
      activo: false,
      precio_cents: precioCents,
      comision_cents: comisionCents,
      ganancia_cents: gananciaCents,
      comisionPorcentaje: comisionPctAplicada,
      ...incentivoViajePatch,
      precio: fromCents(precioCents),
      comision: fromCents(comisionCents),
      gananciaTaxista: fromCents(gananciaCents),
      comisionCalculada: true,
      comisionCalculadaEn: FieldValue.serverTimestamp(),
      finalizadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
      metodoPagoNormalizado: metodoNorm,
      elegibleLiquidacionSemanal: elegibleLiquidacionSemanalCache(elegibilidadSemanal),
      // Snapshot perfil + saldo prepago post-cierre (factura inmutable).
      bancoTaxista: perfilFacturaSnap.bancoTaxista,
      numeroCuentaTaxista: perfilFacturaSnap.numeroCuentaTaxista,
      tipoCuentaTaxista: perfilFacturaSnap.tipoCuentaTaxista,
      titularCuentaTaxista: perfilFacturaSnap.titularCuentaTaxista,
      ciTaxista: perfilFacturaSnap.ciTaxista,
      facturaSaldoPrepagoComisionRd,
    });

    tx.set(
      db().collection("usuarios").doc(uidTaxista),
      {
        viajeActivoId: "",
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    if (uidCliente) {
      tx.set(
        db().collection("usuarios").doc(uidCliente),
        {
          viajeActivoId: "",
          updatedAt: FieldValue.serverTimestamp(),
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    const bolaPatch = patchBolaPuebloTrasViajeEspejoFinalizado(
      viajeId,
      d,
      esEfectivo,
      facturaSaldoPrepagoComisionRd,
    );
    if (bolaPatch) {
      const bolaId = bolaIdDesdeViajeEspejo(d);
      tx.set(db().collection("bolas_pueblo").doc(bolaId), bolaPatch, { merge: true });
    }

    return { ok: true, viajeId, alreadyCompleted: false, uidTaxista };
  });

  if ((result as AnyMap).alreadyCompleted === true) {
    try {
      const vHeal = await viajeRef.get();
      const vd = (vHeal.data() ?? {}) as AnyMap;
      if (vHeal.exists && (vd.completado === true || normalizeEstadoViajeDoc(vd.estado) === "completado")) {
        await syncBolaPuebloTrasViajeEspejoFinalizado(viajeId, vd);
      }
    } catch (healErr: unknown) {
      logger.warn("[BOLA_AHORRO] sync bola heal post-alreadyCompleted falló", { viajeId, healErr });
    }
  }

  const uidT = String((result as AnyMap).uidTaxista ?? "").trim();
  if (uidT && (result as AnyMap).alreadyCompleted !== true) {
    try {
      await syncTaxistaBloqueoOperativo(uidT);
    } catch (syncErr: unknown) {
      logger.error("[FINALIZAR_WARN] syncTaxistaBloqueoOperativo falló (viaje ya cerrado en tx)", {
        uidT,
        viajeId,
        syncErr,
      });
    }
  }

  try {
    await markIdempotencyDone(idem.ref, result as AnyMap);
  } catch (idemErr: unknown) {
    logger.error("[FINALIZAR_WARN] markIdempotencyDone falló", { viajeId, idemErr });
  }
  } catch (e: unknown) {
    if (e instanceof HttpsError) throw e;
    const msg = e instanceof Error ? e.message : String(e);
    logger.error("[FINALIZAR_FATAL] finalizarViajeSeguro", e);
    throw new HttpsError(
      "internal",
      `Error interno al finalizar: ${msg}`,
    );
  }
});
export const reportarTransferenciaClienteSeguro = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const role = await getRole(uidActor);
  if (role !== "cliente" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const viajeId = String(request.data?.viajeId ?? "").trim();
  const comprobanteUrl = String(request.data?.comprobanteUrl ?? "").trim();
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");
  if (!comprobanteUrl) throw new HttpsError("invalid-argument", "Falta comprobanteUrl");

  const viajeRef = db().collection("viajes").doc(viajeId);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(viajeRef);
    if (!snap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const d = (snap.data() ?? {}) as AnyMap;
    const uidCliente = String(d.uidCliente ?? d.clienteId ?? "").trim();
    if (role !== "admin" && uidCliente !== uidActor) {
      throw new HttpsError("permission-denied", "No autorizado para este viaje");
    }
    tx.update(viajeRef, {
      comprobanteTransferenciaUrl: comprobanteUrl,
      transferenciaConfirmada: false,
      estadoPago: "pagado",
      "payment.status": "pending_admin_confirmation",
      "payment.provider": "transfer",
      "payment.updatedAt": FieldValue.serverTimestamp(),
      transferenciaReportadaEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    });
  });
  return { ok: true, viajeId };
});

// Admin valida transferencia sin tocar estado del viaje.
export const confirmarTransferenciaAdminSeguro = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const role = await getRole(uidActor);
  if (role !== "admin") throw new HttpsError("permission-denied", "Solo admin");

  const viajeId = String(request.data?.viajeId ?? "").trim();
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const viajeRef = db().collection("viajes").doc(viajeId);
  const viajeSnap = await viajeRef.get();
  if (!viajeSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
  const viajeData = (viajeSnap.data() ?? {}) as AnyMap;
  const metodoNorm = metodoPagoNormalizadoDesde(viajeData);
  const elegibilidadSemanal = {
    metodoPagoNormalizado: metodoNorm,
    estadoPago: "verificado",
    liquidado: viajeData.liquidado === true,
  };
  await viajeRef.set({
    transferenciaConfirmada: true,
    estadoPago: "verificado",
    metodoPagoNormalizado: metodoNorm,
    elegibleLiquidacionSemanal: elegibleLiquidacionSemanalCache(elegibilidadSemanal),
    "payment.status": "bank_transfer_validated",
    "payment.provider": "transfer",
    "payment.updatedAt": FieldValue.serverTimestamp(),
    pagoATaxistaPendiente: false,
    pagoTaxistaPendiente: false,
    updatedAt: FieldValue.serverTimestamp(),
    actualizadoEn: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, viajeId };
});

// Taxista confirma que recibió la transferencia del cliente.
// Misma escritura que `confirmarTransferenciaAdminSeguro`, pero validando
// que el actor sea precisamente el `uidTaxista` del viaje. El admin sigue
// pudiendo validar como respaldo (la CF de admin no se ha tocado).
export const confirmarTransferenciaTaxistaSeguro = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const uidActor = request.auth.uid;
  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const viajeId = String(request.data?.viajeId ?? "").trim();
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const viajeRef = db().collection("viajes").doc(viajeId);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(viajeRef);
    if (!snap.exists) {
      throw new HttpsError("not-found", "Viaje no existe");
    }
    const d = (snap.data() ?? {}) as AnyMap;

    // El admin puede confirmar cualquiera; el taxista solo el suyo.
    const uidTaxistaDoc = String(d.uidTaxista ?? "").trim();
    if (role !== "admin" && uidTaxistaDoc !== uidActor) {
      throw new HttpsError(
        "permission-denied",
        "No autorizado para este viaje"
      );
    }

    // Solo tiene sentido confirmar si ya hay comprobante reportado por el cliente.
    const comprobante = String(d.comprobanteTransferenciaUrl ?? "").trim();
    if (!comprobante) {
      throw new HttpsError(
        "failed-precondition",
        "Aún no hay comprobante reportado por el cliente"
      );
    }

    // Idempotencia básica: si ya estaba confirmada, devolver ok sin reescribir.
    if (d.transferenciaConfirmada === true) {
      return;
    }

    const metodoNorm = metodoPagoNormalizadoDesde(d);
    const elegibilidadSemanal = {
      metodoPagoNormalizado: metodoNorm,
      estadoPago: "verificado",
      liquidado: d.liquidado === true,
    };
    tx.update(viajeRef, {
      transferenciaConfirmada: true,
      transferenciaConfirmadaPor: role === "admin" ? "admin" : "taxista",
      transferenciaConfirmadaAt: FieldValue.serverTimestamp(),
      estadoPago: "verificado",
      metodoPagoNormalizado: metodoNorm,
      elegibleLiquidacionSemanal: elegibleLiquidacionSemanalCache(elegibilidadSemanal),
      "payment.status": "bank_transfer_validated",
      "payment.provider": "transfer",
      "payment.updatedAt": FieldValue.serverTimestamp(),
      pagoATaxistaPendiente: false,
      pagoTaxistaPendiente: false,
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    });
  });
  return { ok: true, viajeId };
});

export const rechazarTransferenciaAdminSeguro = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const role = await getRole(uidActor);
  if (role !== "admin") throw new HttpsError("permission-denied", "Solo admin");

  const viajeId = String(request.data?.viajeId ?? "").trim();
  const motivo = String(request.data?.motivo ?? "").trim();
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const viajeRef = db().collection("viajes").doc(viajeId);
  await viajeRef.set({
    transferenciaConfirmada: false,
    estadoPago: "pendiente",
    "payment.status": "bank_transfer_rejected",
    "payment.provider": "transfer",
    "payment.updatedAt": FieldValue.serverTimestamp(),
    pagoATaxistaPendiente: false,
    pagoTaxistaPendiente: false,
    motivoRechazoTransferencia: motivo,
    transferenciaRechazadaEn: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    actualizadoEn: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, viajeId };
});

export const approvePayment = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  if ((await getRole(uid)) !== "admin") throw new HttpsError("permission-denied", "Solo admin");
  await assertLegacyPagosTaxistasFlowsDisabled();

  const pagoId = typeof request.data?.pagoId === "string" ? request.data.pagoId.trim() : "";
  const notaAdmin = typeof request.data?.notaAdmin === "string" ? request.data.notaAdmin.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!pagoId) throw new HttpsError("invalid-argument", "Falta pagoId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "approve_payment", uid);
  if (idem.done) return idem.result;

  const { excluirEfectivoDePagoSemanal } = await getFinanceConfig();

  const pagoRef = db().collection("pagos_taxistas").doc(pagoId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(pagoRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pago no encontrado");
    const data = (snap.data() ?? {}) as AnyMap;
    const estado = String(data.estado ?? "").trim().toLowerCase();
    const uidTaxista = String(data.uidTaxista ?? "");
    if (!uidTaxista) throw new HttpsError("failed-precondition", "Pago sin uidTaxista");
    const fechaInicioSemana =
      toDateFromUnknown(data.fechaInicioSemana) ??
      toDateFromUnknown(data.fechaInicio);
    const fechaFinSemana =
      toDateFromUnknown(data.fechaFinSemana) ??
      toDateFromUnknown(data.fechaFin);

    if (estado === "pagado") return { ok: true, pagoId, alreadyProcessed: true, estado: "pagado" };
    if (estado === "rechazado") throw new HttpsError("failed-precondition", "Pago ya rechazado");
    if (estado !== "pendiente" && estado !== "pendiente_verificacion") {
      throw new HttpsError("failed-precondition", `Estado no válido: ${estado}`);
    }

    let viajesLiquidados: string[] = [];
    if (fechaInicioSemana && fechaFinSemana) {
      const viajesSnap = await tx.get(
        db()
          .collection("viajes")
          .where("uidTaxista", "==", uidTaxista)
          .where("completado", "==", true)
          .where("finalizadoEn", ">=", fechaInicioSemana)
          .where("finalizadoEn", "<=", fechaFinSemana)
          .orderBy("finalizadoEn", "desc")
          .limit(200),
      );
      viajesLiquidados = excluirEfectivoDePagoSemanal
        ? viajesSnap.docs
            .filter((doc) => esElegibleLiquidacionSemanal((doc.data() ?? {}) as AnyMap))
            .map((doc) => doc.id)
        : viajesSnap.docs.map((doc) => doc.id);
    }

    tx.update(pagoRef, {
      estado: "pagado",
      fechaPago: FieldValue.serverTimestamp(),
      verificadoPor: uid,
      verificadoEn: FieldValue.serverTimestamp(),
      notaAdmin,
      fechaInicioSemana: fechaInicioSemana ?? null,
      fechaFinSemana: fechaFinSemana ?? null,
      viajesLiquidados,
      updatedAt: FieldValue.serverTimestamp(),
    });

    tx.set(
      db().collection("usuarios").doc(uidTaxista),
      {
        semanaPendiente: null,
        ultimoPago: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return { ok: true, pagoId, alreadyProcessed: false, estado: "pagado" };
  });

  const pagoSnap = await pagoRef.get();
  const uidTaxista = String((pagoSnap.data() ?? {}).uidTaxista ?? "");
  if (uidTaxista) {
    const tiene = await syncTienePagoPendiente(uidTaxista);
    await syncPoolsPorPagoSemanal(uidTaxista, tiene);
  }
  await markIdempotencyDone(idem.ref, result);
  logAdminAudit({
    action: "approve_payment",
    actorUid: uid,
    resourceType: "pago_taxista",
    resourceId: pagoId,
    metadata: {
      notaAdminLen: notaAdmin.length,
      result: result as AnyMap,
    },
  });
  return result;
});

export const rejectPayment = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  if ((await getRole(uid)) !== "admin") throw new HttpsError("permission-denied", "Solo admin");
  await assertLegacyPagosTaxistasFlowsDisabled();

  const pagoId = typeof request.data?.pagoId === "string" ? request.data.pagoId.trim() : "";
  const notaAdminRaw = typeof request.data?.notaAdmin === "string" ? request.data.notaAdmin.trim() : "";
  const notaAdmin = notaAdminRaw || "Comprobante no válido";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!pagoId) throw new HttpsError("invalid-argument", "Falta pagoId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "reject_payment", uid);
  if (idem.done) return idem.result;

  const pagoRef = db().collection("pagos_taxistas").doc(pagoId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(pagoRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pago no encontrado");
    const data = (snap.data() ?? {}) as AnyMap;
    const estado = String(data.estado ?? "").trim().toLowerCase();

    if (estado === "rechazado") return { ok: true, pagoId, alreadyProcessed: true, estado: "rechazado" };
    if (estado === "pagado") throw new HttpsError("failed-precondition", "Pago ya aprobado");
    if (estado !== "pendiente" && estado !== "pendiente_verificacion") {
      throw new HttpsError("failed-precondition", `Estado no válido: ${estado}`);
    }

    tx.update(pagoRef, {
      estado: "rechazado",
      notaAdmin,
      verificadoPor: uid,
      verificadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, pagoId, alreadyProcessed: false, estado: "rechazado" };
  });

  const pagoSnap = await pagoRef.get();
  const uidTaxista = String((pagoSnap.data() ?? {}).uidTaxista ?? "");
  if (uidTaxista) {
    const tiene = await syncTienePagoPendiente(uidTaxista);
    await syncPoolsPorPagoSemanal(uidTaxista, tiene);
  }
  await markIdempotencyDone(idem.ref, result);
  logAdminAudit({
    action: "reject_payment",
    actorUid: uid,
    resourceType: "pago_taxista",
    resourceId: pagoId,
    metadata: {
      notaAdminLen: notaAdmin.length,
      result: result as AnyMap,
    },
  });
  return result;
});

type PoolModoConductor = "motor" | "vehiculo";

function poolModoConductorFromUser(u: AnyMap): PoolModoConductor {
  let raw = String(u.tipoServicio ?? "").trim().toLowerCase();
  if (!raw && u.vehiculo && typeof u.vehiculo === "object") {
    raw = String((u.vehiculo as AnyMap).tipoServicio ?? "").trim().toLowerCase();
  }
  return raw === "motor" ? "motor" : "vehiculo";
}

function viajeCoincideModoConductor(viajeTipo: string, modo: PoolModoConductor): boolean {
  const t = viajeTipo.trim().toLowerCase() || "normal";
  if (modo === "motor") return t === "motor";
  return t !== "motor" && t !== "turismo";
}

const CANAL_TURISMO_POOL = "turismo_pool";

function esTurismoPoolTomable(d: AnyMap): boolean {
  const tipo = String(d.tipoServicio ?? "").trim().toLowerCase();
  const canal = String(d.canalAsignacion ?? "").trim().toLowerCase();
  if (tipo !== "turismo" || canal !== CANAL_TURISMO_POOL) return false;
  if (String(d.uidTaxista ?? d.taxistaId ?? "").trim()) return false;
  const estado = String(d.estado ?? "").trim().toLowerCase();
  const estadosOk = new Set([
    "pendiente",
    "pendiente_pago",
    "pendiente_admin",
    "pendienteadmin",
    "buscando",
    "disponible",
  ]);
  return estadosOk.has(estado);
}

function choferTurismoEstadoOperativo(estadoRaw: unknown): boolean {
  const e = String(estadoRaw ?? "").trim().toLowerCase();
  return e === "aprobado" || e === "activo";
}

export const aceptarViajeSeguro = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const viajeId = typeof request.data?.viajeId === "string" ? request.data.viajeId.trim() : "";
  const nombreTaxista = typeof request.data?.nombreTaxista === "string" ? request.data.nombreTaxista.trim() : "";
  const telefono = typeof request.data?.telefono === "string" ? request.data.telefono.trim() : "";
  const placa = typeof request.data?.placa === "string" ? request.data.placa.trim() : "";
  const tipoVehiculo = typeof request.data?.tipoVehiculo === "string" ? request.data.tipoVehiculo.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "aceptar_viaje_seguro", uidActor);
  if (idem.done) return idem.result;

  const prepagoCfg = await getComisionPrepagoConfig();

  const viajeRef = db().collection("viajes").doc(viajeId);
  const userRef = db().collection("usuarios").doc(uidActor);
  const result = await db().runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const d = (vSnap.data() ?? {}) as AnyMap;

    const estado = String(d.estado ?? "");
    const uidTaxistaActual = String(d.uidTaxista ?? "");
    const taxistaIdActual = String(d.taxistaId ?? "");
    const now = new Date();

    const estadoPermitido = estado === "pendiente" || estado === "pendiente_pago" || estado === "pendiente_admin" || estado === "buscando" || estado === "disponible";
    if (!estadoPermitido) throw new HttpsError("failed-precondition", "estado-no-pendiente");

    if (uidTaxistaActual || taxistaIdActual) {
      if (uidTaxistaActual === uidActor || taxistaIdActual === uidActor) {
        return { ok: true, viajeId, alreadyTaken: true };
      }
      throw new HttpsError("failed-precondition", "ya-asignado");
    }

    const acceptAfter = d.acceptAfter;
    if (acceptAfter && typeof (acceptAfter as { toDate?: () => Date }).toDate === "function") {
      const aa = (acceptAfter as { toDate: () => Date }).toDate();
      if (aa > now) throw new HttpsError("failed-precondition", "acceptAfter-futuro");
    }

    const reservadoPor = String(d.reservadoPor ?? "");
    const reservadoHastaRaw = d.reservadoHasta;
    if (reservadoPor && reservadoPor !== uidActor) {
      const reservadoHasta = reservadoHastaRaw && typeof (reservadoHastaRaw as { toDate?: () => Date }).toDate === "function"
        ? (reservadoHastaRaw as { toDate: () => Date }).toDate()
        : null;
      const vigente = !reservadoHasta || reservadoHasta > now;
      if (vigente) throw new HttpsError("failed-precondition", "reservado-otro");
    }

    const uSnap = await tx.get(userRef);
    const uData = (uSnap.data() ?? {}) as AnyMap;
    assertTaxistaAptoParaClaimPool(uData);
    if (uData.tienePagoPendiente === true) {
      throw new HttpsError("failed-precondition", "bloqueado-pago-semanal");
    }
    const billeSnap = await tx.get(db().collection("billeteras_taxista").doc(uidActor));
    if (bloqueoOperativoPrepago(billeSnap.data() as AnyMap | undefined, prepagoCfg.minimoOperativoRd)) {
      throw new HttpsError("failed-precondition", "bloqueado-comision-efectivo");
    }
    const viajeActivoId = String(uData.viajeActivoId ?? "");
    if (viajeActivoId) throw new HttpsError("failed-precondition", "taxista-ocupado");

    const poolModo = poolModoConductorFromUser(uData);
    const viajeTipo = String(d.tipoServicio ?? "normal");
    const esTurismoPool = esTurismoPoolTomable(d);
    if (esTurismoPool) {
      const choferSnap = await tx.get(db().collection("choferes_turismo").doc(uidActor));
      if (!choferTurismoEstadoOperativo((choferSnap.data() as AnyMap | undefined)?.estado)) {
        throw new HttpsError("failed-precondition", "chofer-turismo-no-aprobado");
      }
    } else if (!viajeCoincideModoConductor(viajeTipo, poolModo)) {
      throw new HttpsError("failed-precondition", "tipo-servicio-no-coincide");
    }

    const uidCliente = String(d.uidCliente ?? d.clienteId ?? "").trim();

    const tel = telefono || String(uData.telefono ?? "");
    const placaFinal = placa || String(uData.placa ?? "");
    const tipo = tipoVehiculo || String(uData.tipoVehiculo ?? "");
    const marca = String(uData.marca ?? uData.vehiculoMarca ?? "");
    const modelo = String(uData.modelo ?? uData.vehiculoModelo ?? "");
    const color = String(uData.color ?? uData.vehiculoColor ?? "");

    const tipoServicio = String(d.tipoServicio ?? "normal");
    let tipoVehiculoFormateado = tipo;
    if (tipoServicio === "motor") tipoVehiculoFormateado = "🛵 MOTOR 🛵";
    else if (tipoServicio === "turismo") tipoVehiculoFormateado = "🏝️ TURISMO 🏝️";
    else if (tipoServicio === "normal") tipoVehiculoFormateado = "🚗 NORMAL";

    tx.update(viajeRef, {
      uidTaxista: uidActor,
      taxistaId: uidActor,
      nombreTaxista: nombreTaxista || String(uData.nombre ?? uData.displayName ?? "taxista"),
      telefono: tel,
      placa: placaFinal,
      tipoVehiculo: tipoVehiculoFormateado,
      tipoVehiculoOriginal: tipo,
      marca,
      modelo,
      color,
      latTaxista: 0.0,
      lonTaxista: 0.0,
      driverLat: 0.0,
      driverLon: 0.0,
      estado: "aceptado",
      aceptado: true,
      rechazado: false,
      activo: true,
      aceptadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
      reservadoPor: "",
      reservadoHasta: null,
      ignoradosPor: FieldValue.delete(),
    });

    tx.set(userRef, {
      viajeActivoId: viajeId,
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    }, { merge: true });

    if (esTurismoPool) {
      tx.set(
        db().collection("choferes_turismo").doc(uidActor),
        {
          disponible: false,
          viajeActualId: viajeId,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      if (uidCliente) {
        tx.set(
          db().collection("usuarios").doc(uidCliente),
          {
            viajeActivoId: viajeId,
            updatedAt: FieldValue.serverTimestamp(),
            actualizadoEn: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
    }

    return { ok: true, viajeId, alreadyTaken: false, esTurismoPool };
  });

  await markIdempotencyDone(idem.ref, result as AnyMap);
  return result;
});

/** Taxista ignora un viaje del pool (misma intención que update client-side de `ignoradosPor`). */
export const ignorarViajePoolSeguro = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const viajeId = typeof request.data?.viajeId === "string" ? request.data.viajeId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "ignorar_viaje_pool_seguro", uidActor);
  if (idem.done) return idem.result;

  const viajeRef = db().collection("viajes").doc(viajeId);
  const result = await db().runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const d = (vSnap.data() ?? {}) as AnyMap;
    const uidAsignado = String(d.uidTaxista ?? d.taxistaId ?? "").trim();
    if (uidAsignado && uidAsignado !== uidActor) {
      throw new HttpsError("permission-denied", "Viaje asignado a otro chofer");
    }
    tx.update(viajeRef, {
      ignoradosPor: FieldValue.arrayUnion(uidActor),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    });
    return { ok: true, viajeId };
  });

  await markIdempotencyDone(idem.ref, result as AnyMap);
  return result;
});

export const cancelarViajeTaxistaSeguro = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const viajeId = typeof request.data?.viajeId === "string" ? request.data.viajeId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "cancelar_viaje_taxista_seguro", uidActor);
  if (idem.done) return idem.result;

  const viajeRef = db().collection("viajes").doc(viajeId);
  const userRef = db().collection("usuarios").doc(uidActor);

  const result = await db().runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const d = (vSnap.data() ?? {}) as AnyMap;

    const uidTxRaw = String(d.uidTaxista ?? "");
    const taxistaIdRaw = String(d.taxistaId ?? "");
    const uidTx = uidTxRaw.trim() ? uidTxRaw.trim() : taxistaIdRaw.trim();
    if (role === "taxista" && uidTx !== uidActor) {
      throw new HttpsError("permission-denied", "No autorizado para este viaje");
    }

    const estado = String(d.estado ?? "");
    const cancelable = estado === "aceptado" || estado === "en_camino_pickup" || estado === "enCaminoPickup";
    if (!cancelable) {
      throw new HttpsError("failed-precondition", "No se puede cancelar en este estado");
    }

    const esTurismo = String(d.tipoServicio ?? "").trim() === "turismo";
    const estadoTrasCancel = esTurismo ? "pendiente_admin" : "pendiente";

    const cancelPatch: Record<string, unknown> = {
      estado: estadoTrasCancel,
      aceptado: false,
      rechazado: false,
      activo: false,
      uidTaxista: "",
      taxistaId: "",
      nombreTaxista: "",
      telefono: "",
      placa: "",
      marca: "",
      modelo: "",
      color: "",
      republicado: true,
      canceladoPor: "taxista",
      canceladoTaxistaEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
      pickupConfirmadoEn: FieldValue.delete(),
      inicioEnRutaEn: FieldValue.delete(),
      finalizadoEn: FieldValue.delete(),
      reservadoPor: "",
      reservadoHasta: null,
      ignoradosPor: FieldValue.arrayUnion([uidActor]),
    };
    if (esTurismo) {
      cancelPatch.codigoVerificado = false;
      cancelPatch.codigoVerificadoEn = FieldValue.delete();
      cancelPatch.asignacionAutomatica = FieldValue.delete();
      cancelPatch.asignadoPor = FieldValue.delete();
      cancelPatch.asignadoEn = FieldValue.delete();
      cancelPatch.aceptadoEn = FieldValue.delete();
    }

    tx.update(viajeRef, cancelPatch);

    tx.set(userRef, {
      viajeActivoId: "",
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true, viajeId };
  });

  await markIdempotencyDone(idem.ref, result as AnyMap);
  return result;
});

/** Tras cualquier cambio en la billetera, re-sincroniza bandera y pools (prepago / legacy). */
export const onBilleteraTaxistaWritten = onDocumentWritten("billeteras_taxista/{uid}", async (event) => {
  const uid = String(event.params?.uid ?? "").trim();
  if (!uid) return;
  const afterData = (event.data?.after.data() ?? {}) as AnyMap;
  const pendAntes = comisionPendienteDesdeSnap(event.data?.before);
  const pendDespues = comisionPendienteDesdeSnap(event.data?.after);
  const saldoAntes = saldoPrepagoDesdeSnap(event.data?.before);
  const saldoDespues = saldoPrepagoDesdeSnap(event.data?.after);
  const prepagoActivo = afterData.primerViajeComisionGratisConsumido === true;
  try {
    const tiene = await syncTienePagoPendiente(uid);
    await syncPoolsPorPagoSemanal(uid, tiene);
  } catch (e) {
    console.error("[onBilleteraTaxistaWritten]", uid, e);
  }
  await notificarSaldoPrepagoPreventivo(uid, pendDespues, saldoAntes, saldoDespues, prepagoActivo);
  await notificarSaldoPrepagoInsuficiente(uid, pendDespues, saldoAntes, saldoDespues);
  await notificarComisionPendienteInmediata(uid, pendAntes, pendDespues);
  await notificarLegacyComisionTope(uid, pendAntes, pendDespues);
});

/** Re-sincroniza bloqueo operativo cuando cambian deudas/comisión en pools del taxista. */
export const onViajesPoolCommissionWritten = onDocumentWritten("viajes_pool/{poolId}", async (event) => {
  const before = (event.data?.before.data() ?? {}) as AnyMap;
  const after = (event.data?.after.data() ?? {}) as AnyMap;
  const ownerBefore = String(before.ownerTaxistaId ?? "").trim();
  const ownerAfter = String(after.ownerTaxistaId ?? "").trim();

  const changedRelevant =
    ownerBefore !== ownerAfter ||
    before.comisionPendientePagoAdmin !== after.comisionPendientePagoAdmin ||
    before.montoComision !== after.montoComision ||
    before.comisionEstado !== after.comisionEstado;
  if (!changedRelevant) return;

  const owners = new Set<string>();
  if (ownerBefore) owners.add(ownerBefore);
  if (ownerAfter) owners.add(ownerAfter);
  if (owners.size === 0) return;

  for (const uid of owners) {
    try {
      const tiene = await syncTienePagoPendiente(uid);
      await syncPoolsPorPagoSemanal(uid, tiene);
    } catch (e) {
      console.error("[onViajesPoolCommissionWritten]", uid, e);
    }
  }
});

/** Avisa a admins cuando un taxista pasa a bloqueado por comisión (`tienePagoPendiente: true`). */
export const onUsuarioTaxistaBloqueoComision = onDocumentWritten("usuarios/{uid}", async (event) => {
  const uid = String(event.params?.uid ?? "").trim();
  if (!uid) return;
  const before = (event.data?.before.data() ?? {}) as AnyMap;
  const after = (event.data?.after.data() ?? {}) as AnyMap;

  const rol = String(after.rol ?? before.rol ?? "").trim().toLowerCase();
  if (rol !== "taxista" && rol !== "driver") return;

  const antes = before.tienePagoPendiente === true;
  const despues = after.tienePagoPendiente === true;
  if (antes || !despues) return; // Solo transición false -> true.

  const nombre = String(after.nombre ?? "").trim() || uid;
  const telefono = String(after.telefono ?? "").trim();
  const billeSnap = await db().collection("billeteras_taxista").doc(uid).get();
  const bille = (billeSnap.data() ?? {}) as AnyMap;
  const pend = comisionPendienteRdFromBilletera(bille);
  const saldo = saldoPrepagoRdFromBilletera(bille);

  const title = "Taxista bloqueado por comisión";
  const body =
    `${nombre} (${uid}) quedó bloqueado. ` +
    `Saldo prepago RD$${saldo.toFixed(2)}, pendiente RD$${pend.toFixed(2)}.` +
    (telefono ? ` Tel: ${telefono}.` : "");

  await enviarPushAdminsComision(title, body, {
    type: "admin_taxista_bloqueado_comision",
    uidTaxista: uid,
    nombreTaxista: nombre,
    saldoPrepagoRd: saldo.toFixed(2),
    comisionPendienteRd: pend.toFixed(2),
  });
});

/** Taxista (propio uid) o admin: escribe `usuarios.tienePagoPendiente` vía Admin SDK. */
export const sincronizarBloqueoOperativoTaxista = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  const targetRaw = request.data?.uidTaxista;
  const targetUid =
    typeof targetRaw === "string" && targetRaw.trim() ? targetRaw.trim() : actorUid;

  if (targetUid !== actorUid) {
    const actorRole = await getRole(actorUid);
    if (actorRole !== "admin") {
      throw new HttpsError("permission-denied", "Solo admin puede sincronizar otro taxista");
    }
  } else {
    const selfRole = await getRole(actorUid);
    if (selfRole !== "taxista" && selfRole !== "admin") {
      throw new HttpsError("permission-denied", "Solo taxista o admin");
    }
  }

  const tienePagoPendiente = await syncTaxistaBloqueoOperativo(targetUid);
  return { ok: true, uidTaxista: targetUid, tienePagoPendiente };
});

/** Endpoint liviano para escritorio: valida sesión admin y entrega resumen sin usar Firestore SDK en cliente. */
export const desktopAdminSessionInfo = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  const role = await getRole(uid);
  const isAdmin = role === "admin" || role === "administrador";
  if (!isAdmin) {
    throw new HttpsError("permission-denied", "Solo admin");
  }

  const [pendientesSnap, pagadosHoySnap, bloqueadosSnap, comisionPendienteSnap] = await Promise.all([
    db().collection("pagos_taxistas").where("estado", "in", ["pendiente", "pendiente_verificacion"]).limit(200).get(),
    db().collection("pagos_taxistas").where("estado", "==", "pagado").limit(200).get(),
    db().collection("usuarios").where("tienePagoPendiente", "==", true).limit(200).get(),
    db().collection("billeteras_taxista").where("comisionPendiente", ">", 0).limit(200).get(),
  ]);

  const payload = {
    ok: true,
    uid,
    role,
    resumen: {
      pagosPendientes: pendientesSnap.size,
      pagosPagadosMuestra: pagadosHoySnap.size,
      bloqueosActivosMuestra: bloqueadosSnap.size,
      comisionPorVencerMuestra: comisionPendienteSnap.size,
    },
    serverTimeMs: Date.now(),
  };

  logAdminAudit({
    action: "desktop_admin_session_info",
    actorUid: uid,
    resourceType: "session",
    resourceId: uid,
    metadata: {
      resumen: payload.resumen,
    },
  });

  return payload;
});

/** Alias HTTPS: misma implementación que `finalizarViajeSeguro` (callable `completarViajePorTaxista` en cliente). */
export const completarViajePorTaxista = finalizarViajeSeguro;
