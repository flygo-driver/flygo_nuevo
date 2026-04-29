import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { ledgerComisionViajeEfectivoCf } from "./taxista_prepago_ledger.js";
import type { DocumentSnapshot } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = () => getFirestore();
const messaging = () => getMessaging();

/** Mismo canal Android que otros pushes al conductor (ver scheduled_pool_notify). */
const ANDROID_CHANNEL_TAXISTA = "rai_driver_notifications";

/** Deuda legacy `comisionPendiente` (ya no crece con viajes nuevos): al llegar aquí se bloquea. */
const UMBRAL_COMISION_LEGACY_RD = 500;
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

type AnyMap = Record<string, unknown>;

function toCents(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return Math.round(v * 100);
  return 0;
}

function fromCents(c: number): number {
  return c / 100;
}

function comision20(precioCents: number): number {
  return Math.floor((precioCents * 20 + 50) / 100);
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

function numOr(n: unknown, fallback: number): number {
  if (typeof n === "number" && Number.isFinite(n)) return n;
  if (typeof n === "string") {
    const p = Number(n);
    if (Number.isFinite(p)) return p;
  }
  return fallback;
}

async function getComisionPrepagoConfig(): Promise<{ minimoOperativoRd: number; umbralPreventivoRd: number }> {
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
 * Pool / aceptar viaje: deuda legacy ≥ 500; o prepago activo (primer efectivo ya consumido y sin deuda legacy) con saldo < mínimo.
 * Mientras quede `comisionPendiente` legacy (>0 y <500), no exigimos saldo prepago (migración suave).
 */
function bloqueoOperativoPrepago(data: AnyMap | undefined): boolean {
  const pend = comisionPendienteRdFromBilletera(data);
  if (pend + 1e-9 >= UMBRAL_COMISION_LEGACY_RD) return true;
  if (pend > 1e-6) return false;
  if (data?.primerViajeComisionGratisConsumido !== true) return false;
  return saldoPrepagoRdFromBilletera(data) + 1e-9 < MIN_SALDO_PREPAGO_COMISION_RD;
}

function comisionPendienteDesdeSnap(snap: DocumentSnapshot | undefined): number {
  if (!snap?.exists) return 0;
  return comisionPendienteRdFromBilletera(snap.data() as AnyMap | undefined);
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
    await enviarPushComisionTaxista(
      uid,
      "Falta crédito prepago",
      `Tu saldo de comisión (efectivo) quedó en RD$${saldoDespues.toFixed(2)}. Recarga RD$${minimo.toFixed(0)} o más desde Mis pagos para seguir en pool y tomar viajes (el 20% de cada viaje en efectivo se descuenta de tu saldo).`,
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
  const billeSnap = await db().collection("billeteras_taxista").doc(uidTaxista).get();
  const bloqueoComision = bloqueoOperativoPrepago(billeSnap.data() as AnyMap | undefined);
  // Misma regla que la app: prepago bajo (tras primer efectivo) o deuda legacy ≥ tope.
  const tienePagoPendiente = bloqueoComision;
  await db().collection("usuarios").doc(uidTaxista).set(
    {
      tienePagoPendiente,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return tienePagoPendiente;
}

/** Misma lógica que `PoolRepo.syncPoolsPorPagoSemanal` en la app (cierra pools si comisión ≥ tope). */
async function syncPoolsPorPagoSemanal(ownerTaxistaId: string, tienePagoPendiente: boolean): Promise<void> {
  const trimmed = ownerTaxistaId.trim();
  if (!trimmed) return;
  const snap = await db().collection("viajes_pool").where("ownerTaxistaId", "==", trimmed).get();
  if (snap.empty) return;
  const chunkSize = 450;
  for (let i = 0; i < snap.docs.length; i += chunkSize) {
    const chunk = snap.docs.slice(i, i + chunkSize);
    const b = db().batch();
    for (const docSnap of chunk) {
      const d = (docSnap.data() ?? {}) as AnyMap;
      const estadoActual = String(d.estado ?? "abierto");
      const canceladoPorPagoSemanal = d.canceladoPorPagoSemanal === true;
      const estadoPrevio = String(d.estadoPrevioPorPagoSemanal ?? estadoActual);
      if (tienePagoPendiente) {
        if (estadoActual === "cancelado" && canceladoPorPagoSemanal) continue;
        if (estadoActual === "cancelado" && !canceladoPorPagoSemanal) continue;
        b.update(docSnap.ref, {
          estado: "cancelado",
          canceladoPorPagoSemanal: true,
          estadoPrevioPorPagoSemanal: estadoActual,
          canceladoPorPagoSemanalEn: FieldValue.serverTimestamp(),
        });
      } else if (estadoActual === "cancelado" && canceladoPorPagoSemanal) {
        b.update(docSnap.ref, {
          estado: estadoPrevio.length > 0 ? estadoPrevio : "abierto",
          canceladoPorPagoSemanal: false,
          estadoPrevioPorPagoSemanal: FieldValue.delete(),
          canceladoPorPagoSemanalEn: FieldValue.delete(),
        });
      }
    }
    await b.commit();
  }
}

/** Tras sumar comisión por bola finalizada (Cloud Function `finalizarBolaPueblo`). */
export async function syncTaxistaComisionTrasBola(uidTaxista: string): Promise<void> {
  const uid = uidTaxista.trim();
  if (!uid) return;
  const tienePagoPendiente = await syncTienePagoPendiente(uid);
  await syncPoolsPorPagoSemanal(uid, tienePagoPendiente);
}

async function getRole(uid: string): Promise<string> {
  const snap = await db().collection("usuarios").doc(uid).get();
  return roleFromUserDoc(snap.data() as AnyMap | undefined);
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

  const viajeRef = db().collection("viajes").doc(viajeId);
  const result = await db().runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const d = (vSnap.data() ?? {}) as AnyMap;

    const uidTaxista = String(d.uidTaxista ?? d.taxistaId ?? "");
    const uidCliente = String(d.uidCliente ?? d.clienteId ?? "");
    const estado = String(d.estado ?? "");
    const completado = d.completado === true;
    if (role === "taxista" && uidTaxista !== uidActor) {
      throw new HttpsError("permission-denied", "No autorizado para este viaje");
    }

    if (completado || estado === "completado") {
      return { ok: true, viajeId, alreadyCompleted: true, uidTaxista };
    }
    if (estado !== "en_curso") {
      throw new HttpsError("failed-precondition", "El viaje no está en curso");
    }

    const precioCentsDb = typeof d.precio_cents === "number" ? Math.trunc(d.precio_cents) : null;
    const comisionCentsDb = typeof d.comision_cents === "number" ? Math.trunc(d.comision_cents) : null;
    const gananciaCentsDb = typeof d.ganancia_cents === "number" ? Math.trunc(d.ganancia_cents) : null;

    const precioCents = (precioCentsDb !== null && precioCentsDb > 0)
      ? precioCentsDb
      : toCents(d.precioFinal ?? d.precio ?? d.total ?? 0);
    const comisionCents = (comisionCentsDb !== null && comisionCentsDb >= 0)
      ? comisionCentsDb
      : comision20(precioCents);
    const gananciaCents = (gananciaCentsDb !== null && gananciaCentsDb >= 0)
      ? gananciaCentsDb
      : Math.max(0, precioCents - comisionCents);

    const metodo = String(d.metodoPago ?? "").toLowerCase().trim();
    const esEfectivo = metodo.includes("efectivo");
    const metodoAsiento = esEfectivo ? "efectivo" : (metodo.includes("transfer") ? "transferencia" : "tarjeta");
    const pagoRegistrado = d.pagoRegistrado === true;

    if (!pagoRegistrado) {
      tx.update(viajeRef, {
        metodoPago: esEfectivo ? "Efectivo" : (metodo.includes("transfer") ? "Transferencia" : "Tarjeta"),
        "payment.status": esEfectivo ? "cash_collected" : "bank_transfer_received",
        "payment.provider": esEfectivo ? "cash" : "transfer",
        "payment.updatedAt": FieldValue.serverTimestamp(),
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

      const billeRef = db().collection("billeteras_taxista").doc(uidTaxista);
      const billeSnap = await tx.get(billeRef);
      const bData = (billeSnap.data() ?? {}) as AnyMap;
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
          });
        } else {
          let p = pend;
          let saldo = saldoIni;
          const fromPend = Math.min(p, comisionRd);
          p = Number.parseFloat((p - fromPend).toFixed(2));
          const rem = comisionRd - fromPend;
          saldo = Math.max(0, Number.parseFloat((saldo - rem).toFixed(2)));
          billePatch.comisionPendiente = p;
          billePatch.saldoPrepagoComisionRd = saldo;
          billePatch.primerViajeComisionGratisConsumido = true;
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
          });
        }
      }
      tx.set(billeRef, billePatch, { merge: true });

      const asientoRef = db().collection("pagos").doc(`viaje_${viajeId}_asiento`);
      const asientoSnap = await tx.get(asientoRef);
      if (!asientoSnap.exists) {
        tx.set(asientoRef, {
          tipo: "taxista",
          viajeId,
          uidTaxista,
          monto: esEfectivo ? -fromCents(comisionCents) : fromCents(gananciaCents),
          totalCents: precioCents,
          comisionCents,
          gananciaCents,
          comisionPlataformaPct: 20,
          fuenteAsiento: "finalizar_viaje_seguro_cf",
          metodo: metodoAsiento,
          estado: esEfectivo ? "comision_pendiente" : "por_liquidar",
          fecha: new Date().toISOString(),
          provider: esEfectivo ? "cash" : "transfer",
          createdAt: FieldValue.serverTimestamp(),
        });
      }
    }

    tx.update(viajeRef, {
      estado: "completado",
      completado: true,
      activo: false,
      precio_cents: precioCents,
      comision_cents: comisionCents,
      ganancia_cents: gananciaCents,
      precio: fromCents(precioCents),
      comision: fromCents(comisionCents),
      gananciaTaxista: fromCents(gananciaCents),
      comisionCalculada: true,
      comisionCalculadaEn: FieldValue.serverTimestamp(),
      finalizadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
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
    return { ok: true, viajeId, alreadyCompleted: false, uidTaxista };
  });

  const uidT = String((result as AnyMap).uidTaxista ?? "");
  if (uidT && (result as AnyMap).alreadyCompleted !== true) {
    const tiene = await syncTienePagoPendiente(uidT);
    await syncPoolsPorPagoSemanal(uidT, tiene);
  }

  await markIdempotencyDone(idem.ref, result);
  return result;
});

export const approvePayment = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  if ((await getRole(uid)) !== "admin") throw new HttpsError("permission-denied", "Solo admin");

  const pagoId = typeof request.data?.pagoId === "string" ? request.data.pagoId.trim() : "";
  const notaAdmin = typeof request.data?.notaAdmin === "string" ? request.data.notaAdmin.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!pagoId) throw new HttpsError("invalid-argument", "Falta pagoId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "approve_payment", uid);
  if (idem.done) return idem.result;

  const pagoRef = db().collection("pagos_taxistas").doc(pagoId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(pagoRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pago no encontrado");
    const data = (snap.data() ?? {}) as AnyMap;
    const estado = String(data.estado ?? "").trim().toLowerCase();
    const uidTaxista = String(data.uidTaxista ?? "");
    if (!uidTaxista) throw new HttpsError("failed-precondition", "Pago sin uidTaxista");

    if (estado === "pagado") return { ok: true, pagoId, alreadyProcessed: true, estado: "pagado" };
    if (estado === "rechazado") throw new HttpsError("failed-precondition", "Pago ya rechazado");
    if (estado !== "pendiente" && estado !== "pendiente_verificacion") {
      throw new HttpsError("failed-precondition", `Estado no válido: ${estado}`);
    }

    tx.update(pagoRef, {
      estado: "pagado",
      fechaPago: FieldValue.serverTimestamp(),
      verificadoPor: uid,
      verificadoEn: FieldValue.serverTimestamp(),
      notaAdmin,
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
  return result;
});

export const rejectPayment = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  if ((await getRole(uid)) !== "admin") throw new HttpsError("permission-denied", "Solo admin");

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
  return result;
});

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
    if (uData.tienePagoPendiente === true) {
      throw new HttpsError("failed-precondition", "bloqueado-pago-semanal");
    }
    const billeSnap = await tx.get(db().collection("billeteras_taxista").doc(uidActor));
    if (bloqueoOperativoPrepago(billeSnap.data() as AnyMap | undefined)) {
      throw new HttpsError("failed-precondition", "bloqueado-comision-efectivo");
    }
    const viajeActivoId = String(uData.viajeActivoId ?? "");
    if (viajeActivoId) throw new HttpsError("failed-precondition", "taxista-ocupado");

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

    return { ok: true, viajeId, alreadyTaken: false };
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

    tx.update(viajeRef, {
      estado: "pendiente",
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
    });

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
  await notificarLegacyComisionTope(uid, pendAntes, pendDespues);
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
