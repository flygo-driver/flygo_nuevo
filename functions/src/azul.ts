/**
 * Fase 6 — AZUL E-Commerce (cableado; credenciales en Secret Manager / config).
 * Sin credenciales: callables responden AZUL_NOT_CONFIGURED (flags OFF = omitido).
 */
import { FieldValue, getFirestore, type Transaction } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import {
  buildAzulOrderIdDeterministic,
  debeAplicarTransicionAzul,
  extraerAzulEventId,
  extraerAzulOrderId,
  extraerMetadatosReciboAzul,
  normalizarEstadoAzul,
  sanitizeEventId,
  sesionAzulReutilizable,
  type AzulPagoEstado,
} from "./azul_webhook_logic.js";
import { getFinanceConfig } from "./finance.js";
import {
  elegibleLiquidacionSemanalCache,
  metodoPagoNormalizadoDesde,
} from "./liquidacion_semanal_viaje.js";
import { precioCentsViaje } from "./conciliacion.js";
import { buildAzulPaymentLaunchUrl } from "./azul_payment_page.js";
import {
  aplicarCapturaAzulRecargaTaxista,
  aplicarFalloAzulRecargaTaxista,
  esPagoAzulRecargaTaxista,
} from "./azul_recarga_taxista.js";
import { azulRuntimeSecrets } from "./azul_secrets.js";
import {
  AZUL_DEMO_CERT_URL,
  buildAzulCertificationInfoHtml,
} from "./azul_certification_page.js";

type AnyMap = Record<string, unknown>;

function bolaIdDesdeViajeDoc(v: AnyMap): string {
  if (String(v.tipoServicio ?? "").trim() !== "bola_ahorro") return "";
  return String(v.bolaPuebloId ?? v.bolaId ?? "").trim();
}

function patchBolaMetodoPagoEnTx(
  tx: Transaction,
  v: AnyMap,
  patch: Record<string, unknown>,
): void {
  const bolaId = bolaIdDesdeViajeDoc(v);
  if (!bolaId) return;
  tx.set(getFirestore().collection("bolas_pueblo").doc(bolaId), patch, { merge: true });
}

const db = () => getFirestore();

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

export type AzulRuntimeConfig = {
  configured: boolean;
  useStub: boolean;
  storeId: string;
  environment: "sandbox" | "production";
};

/** Lee credenciales AZUL (Secret Manager / env). Stub hasta afiliación. */
export function readAzulRuntimeConfig(): AzulRuntimeConfig {
  const storeId = String(process.env.AZUL_STORE_ID ?? "").trim();
  const authKey = String(process.env.AZUL_AUTH_KEY ?? "").trim();
  const useStub = process.env.AZUL_USE_STUB === "true" || process.env.AZUL_USE_STUB === "1";
  const envRaw = String(process.env.AZUL_ENV ?? "sandbox").trim().toLowerCase();
  const environment = envRaw === "production" ? "production" : "sandbox";
  const configured = (storeId.length > 0 && authKey.length > 0) || useStub;
  return { configured, useStub, storeId, environment };
}

async function assertClienteDuenoViaje(uid: string, viajeId: string): Promise<AnyMap> {
  const snap = await db().collection("viajes").doc(viajeId).get();
  if (!snap.exists) throw new HttpsError("not-found", "Viaje no encontrado");
  const d = (snap.data() ?? {}) as AnyMap;
  const uidCliente = String(d.uidCliente ?? d.clienteId ?? "").trim();
  if (uidCliente !== uid) {
    throw new HttpsError("permission-denied", "No autorizado para este viaje");
  }
  return d;
}

function metodoEsTarjeta(metodoPago: unknown): boolean {
  const m = String(metodoPago ?? "").toLowerCase();
  return m.includes("tarjeta") || m.includes("card");
}

/** Alineado con EstadosViaje.normalizar (Flutter). */
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
  if (
    s === "en_camino_pickup" ||
    s === "en_camino" ||
    s === "encaminopickup" ||
    s === "encamino_pickup" ||
    s === "encamino"
  ) {
    return "en_camino_pickup";
  }
  if (s === "finalizado" || s === "completado") return "completado";
  if (s === "cancelado" || s === "cancelled") return "cancelado";
  return s;
}

function estadoPermiteCambioTarjetaAEfectivo(estadoNorm: string, completado: boolean): boolean {
  if (completado || estadoNorm === "completado") return true;
  return (
    estadoNorm === "aceptado" ||
    estadoNorm === "en_camino_pickup" ||
    estadoNorm === "a_bordo" ||
    estadoNorm === "en_curso"
  );
}

function viajeTarjetaSinCobrar(d: AnyMap): boolean {
  const ep = String(d.estadoPago ?? "").trim().toLowerCase();
  const paymentObj = (d.payment ?? {}) as AnyMap;
  const ps = String(paymentObj.status ?? "").trim().toLowerCase();
  return ep !== "verificado" && ps !== "captured";
}

function paymentUrlsForOrder(
  azulOrderId: string,
  azul: AzulRuntimeConfig,
): { paymentPageUrl: string; paymentLaunchUrl: string } {
  if (!azulOrderId) return { paymentPageUrl: "", paymentLaunchUrl: "" };
  if (azul.useStub) {
    const stub = `https://pruebas.azul.com.do/PaymentPage/?order=${encodeURIComponent(azulOrderId)}`;
    return { paymentPageUrl: stub, paymentLaunchUrl: stub };
  }
  const launch = buildAzulPaymentLaunchUrl(azulOrderId);
  return { paymentPageUrl: launch, paymentLaunchUrl: launch };
}

async function buscarPagoAzulPorOrderId(azulOrderId: string): Promise<{
  pagoAzulId: string;
  data: AnyMap;
} | null> {
  const order = String(azulOrderId ?? "").trim();
  if (!order) return null;

  const q = await db()
    .collection("pagos_azul")
    .where("azulOrderId", "==", order)
    .limit(1)
    .get();
  if (!q.empty) {
    const doc = q.docs[0];
    return { pagoAzulId: doc.id, data: (doc.data() ?? {}) as AnyMap };
  }
  return null;
}

function sanitizeWebhookBody(body: AnyMap): AnyMap {
  const copy: AnyMap = {};
  for (const [k, v] of Object.entries(body)) {
    if (typeof v === "string" && v.length > 500) {
      copy[k] = `${v.slice(0, 500)}…`;
    } else if (v !== null && typeof v === "object" && !Array.isArray(v)) {
      copy[k] = sanitizeWebhookBody(v as AnyMap);
    } else {
      copy[k] = v;
    }
  }
  return copy;
}

/** Cliente: inicia sesión de pago AZUL (hosted page / API). */
export const azulCreatePaymentSession = onCall({ secrets: azulRuntimeSecrets }, async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  const viajeId =
    typeof request.data?.viajeId === "string" ? request.data.viajeId.trim() : "";
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const financeCfg = await getFinanceConfig();
  if (!financeCfg.pagosConTarjetaAzulHabilitados) {
    return {
      ok: true,
      omitido: true,
      motivo: "pagosConTarjetaAzulHabilitados=false",
      wired: true,
    };
  }

  const viaje = await assertClienteDuenoViaje(uid, viajeId);
  if (!metodoEsTarjeta(viaje.metodoPago)) {
    throw new HttpsError("failed-precondition", "El viaje no es método Tarjeta");
  }

  const ep = String(viaje.estadoPago ?? "").trim().toLowerCase();
  const paymentObj = (viaje.payment ?? {}) as AnyMap;
  if (ep === "verificado" || String(paymentObj.status ?? "") === "captured") {
    return { ok: true, alreadyPaid: true, viajeId };
  }

  const azul = readAzulRuntimeConfig();
  if (!azul.configured) {
    throw new HttpsError(
      "failed-precondition",
      "AZUL_NOT_CONFIGURED: configure AZUL_STORE_ID y AZUL_AUTH_KEY (o AZUL_USE_STUB=true en staging).",
    );
  }

  const montoCents = precioCentsViaje(viaje);
  if (montoCents <= 0) {
    throw new HttpsError("failed-precondition", "Monto del viaje inválido");
  }

  const pagoAzulId = `azul_${viajeId}`;
  const pagoRef = db().collection("pagos_azul").doc(pagoAzulId);
  const existingPago = await pagoRef.get();
  if (existingPago.exists) {
    const p = (existingPago.data() ?? {}) as AnyMap;
    const estadoPago = p.estado;
    const captured = normalizarEstadoAzul(estadoPago) === "captured";
    if (captured) {
      return { ok: true, alreadyPaid: true, viajeId, pagoAzulId };
    }
    if (sesionAzulReutilizable(estadoPago)) {
      const azulOrderId = String(p.azulOrderId ?? "").trim();
      if (azulOrderId) {
        logger.info("[azulCreatePaymentSession] reutiliza sesión pendiente", {
          viajeId,
          azulOrderId,
          estado: estadoPago,
        });
        const urls = paymentUrlsForOrder(azulOrderId, azul);
        return {
          ok: true,
          wired: true,
          reused: true,
          viajeId,
          pagoAzulId,
          azulOrderId,
          montoCents: Number(p.montoCents ?? montoCents),
          paymentPageUrl: urls.paymentPageUrl,
          paymentLaunchUrl: urls.paymentLaunchUrl,
          useStub: azul.useStub,
        };
      }
    }
  }

  const now = FieldValue.serverTimestamp();
  const azulOrderId = buildAzulOrderIdDeterministic(viajeId, montoCents, azul.useStub);
  const urls = paymentUrlsForOrder(azulOrderId, azul);

  await pagoRef.set(
    {
      viajeId,
      uidCliente: uid,
      azulOrderId,
      montoCents,
      moneda: "DOP",
      estado: "pending",
      environment: azul.environment,
      provider: "azul",
      wiredStub: azul.useStub,
      createdAt: now,
      updatedAt: now,
    },
    { merge: true },
  );

  await db()
    .collection("viajes")
    .doc(viajeId)
    .set(
      {
        pagoAzulId,
        "payment.provider": "azul",
        "payment.status": "pending",
        "payment.azulOrderId": azulOrderId,
        "payment.updatedAt": now,
        updatedAt: now,
        actualizadoEn: now,
      },
      { merge: true },
    );

  logger.info("[azulCreatePaymentSession]", { viajeId, azulOrderId, useStub: azul.useStub });

  return {
    ok: true,
    wired: true,
    viajeId,
    pagoAzulId,
    azulOrderId,
    montoCents,
    paymentPageUrl: urls.paymentPageUrl,
    paymentLaunchUrl: urls.paymentLaunchUrl,
    useStub: azul.useStub,
    message: azul.useStub
      ? "Sesión stub AZUL (staging)."
      : "Abrí el navegador para completar el pago en AZUL.",
  };
});

/** Poll estado pago AZUL (cliente o admin). */
export const azulVerifyPayment = onCall({ secrets: azulRuntimeSecrets }, async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const viajeId =
    typeof request.data?.viajeId === "string" ? request.data.viajeId.trim() : "";
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const financeCfg = await getFinanceConfig();
  if (!financeCfg.pagosConTarjetaAzulHabilitados) {
    return { ok: true, omitido: true, motivo: "pagosConTarjetaAzulHabilitados=false" };
  }

  const viajeSnap = await db().collection("viajes").doc(viajeId).get();
  if (!viajeSnap.exists) throw new HttpsError("not-found", "Viaje no encontrado");
  const v = (viajeSnap.data() ?? {}) as AnyMap;
  const uid = request.auth.uid;
  const role = await getRole(uid);
  const uidCliente = String(v.uidCliente ?? v.clienteId ?? "").trim();
  const uidTaxista = String(v.uidTaxista ?? v.taxistaId ?? "").trim();
  if (role !== "admin" && uid !== uidCliente && uid !== uidTaxista) {
    throw new HttpsError("permission-denied", "No autorizado");
  }

  const pagoAzulId = String(v.pagoAzulId ?? "").trim();
  if (!pagoAzulId) {
    return { ok: true, estado: "sin_sesion", viajeId };
  }
  const pagoSnap = await db().collection("pagos_azul").doc(pagoAzulId).get();
  const p = (pagoSnap.data() ?? {}) as AnyMap;
  const pEstado = normalizarEstadoAzul(p.estado);
  let estadoPago = String(v.estadoPago ?? "").trim().toLowerCase();
  let captured = estadoPago === "verificado";
  let reconciled = false;

  if (!captured && pEstado === "captured") {
    try {
      await aplicarCapturaAzulEnViaje({
        viajeId,
        pagoAzulId,
        azulOrderId: String(p.azulOrderId ?? ""),
        actorUid: uid,
      });
      reconciled = true;
      captured = true;
    } catch (e) {
      logger.warn("[azulVerifyPayment] reconcile captured→verificado falló", {
        viajeId,
        err: e,
      });
    }
  }

  const vFresh = await db().collection("viajes").doc(viajeId).get();
  const vf = (vFresh.data() ?? {}) as AnyMap;
  estadoPago = String(vf.estadoPago ?? estadoPago).trim().toLowerCase();
  captured = captured || estadoPago === "verificado";

  return {
    ok: true,
    viajeId,
    pagoAzulId,
    estado: String(p.estado ?? "unknown"),
    azulOrderId: String(p.azulOrderId ?? ""),
    paymentStatus: String(((vf.payment ?? {}) as AnyMap).status ?? ""),
    estadoPago: String(vf.estadoPago ?? ""),
    captured,
    reconciled,
  };
});

async function registrarEventoWebhookAzul(input: {
  eventId: string;
  azulOrderId: string;
  estado: AzulPagoEstado | null;
  motivo: string;
  applied: boolean;
  body: AnyMap;
  pagoAzulId?: string;
  viajeId?: string;
}): Promise<void> {
  const docId = sanitizeEventId(input.eventId) || `evt_${Date.now()}`;
  await db()
    .collection("webhook_eventos_azul")
    .doc(docId)
    .set(
      {
        eventId: input.eventId,
        azulOrderId: input.azulOrderId,
        estado: input.estado,
        motivo: input.motivo,
        applied: input.applied,
        pagoAzulId: input.pagoAzulId ?? null,
        viajeId: input.viajeId ?? null,
        bodySanitized: sanitizeWebhookBody(input.body),
        processedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}

export async function aplicarEstadoIntermedioAzul(input: {
  viajeId: string;
  pagoAzulId: string;
  azulOrderId: string;
  estadoNuevo: AzulPagoEstado;
  lastError?: string;
}): Promise<void> {
  const viajeRef = db().collection("viajes").doc(input.viajeId);
  const pagoRef = db().collection("pagos_azul").doc(input.pagoAzulId);
  const now = FieldValue.serverTimestamp();

  await db().runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    const pSnap = await tx.get(pagoRef);
    if (!vSnap.exists || !pSnap.exists) return;

    const v = (vSnap.data() ?? {}) as AnyMap;
    if (metodoPagoNormalizadoDesde(v) !== "tarjeta") return;

    const p = (pSnap.data() ?? {}) as AnyMap;
    const trans = debeAplicarTransicionAzul(p.estado, input.estadoNuevo);
    if (!trans.aplicar) return;

    const pagoPatch: AnyMap = {
      estado: input.estadoNuevo,
      updatedAt: now,
    };
    if (input.estadoNuevo === "authorized") pagoPatch.authorizedAt = now;
    if (input.estadoNuevo === "refunded") pagoPatch.refundedAt = now;
    if (input.estadoNuevo === "failed") pagoPatch.failedAt = now;
    const err = String(input.lastError ?? "").trim();
    if (input.estadoNuevo === "failed" && err) {
      pagoPatch.lastError = err.slice(0, 500);
    }

    tx.update(pagoRef, pagoPatch);

    const viajePatch: AnyMap = {
      "payment.provider": "azul",
      "payment.status": input.estadoNuevo,
      "payment.azulOrderId": input.azulOrderId,
      "payment.updatedAt": now,
      updatedAt: now,
      actualizadoEn: now,
    };
    if (input.estadoNuevo === "refunded") {
      viajePatch["payment.refundedAt"] = now;
    }
    if (input.estadoNuevo === "failed" && err) {
      viajePatch["payment.azulLastError"] = err.slice(0, 500);
    }
    tx.update(viajeRef, viajePatch);
  });
}

/** Webhook AZUL (HTTPS). Validar firma cuando haya credenciales reales. */
export const azulWebhook = onRequest({ secrets: azulRuntimeSecrets }, async (req, res) => {
  if (req.method !== "POST") {
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.status(200).send(
      buildAzulCertificationInfoHtml({
        titulo: "Webhook AZUL",
        endpoint: "https://us-central1-flygo-rd.cloudfunctions.net/azulWebhook",
        metodo: "POST (servidor-a-servidor desde AZUL)",
        uso: "AZUL notifica captura/estado del pago. No es para abrir en navegador.",
        nota: "Ver GET en navegador es solo verificación de que el endpoint existe. Las notificaciones reales llegan por POST.",
        demoUrl: AZUL_DEMO_CERT_URL,
        estado: "ok",
      }),
    );
    return;
  }
  const financeCfg = await getFinanceConfig();
  if (
    !financeCfg.pagosConTarjetaAzulHabilitados &&
    !financeCfg.recargaPrepagoAzulHabilitados
  ) {
    res.status(200).json({ ok: true, omitido: true });
    return;
  }

  const body = (req.body ?? {}) as AnyMap;
  const azulOrderId = extraerAzulOrderId(body);
  const estadoRaw =
    body.status ?? body.Status ?? body.estado ?? body.paymentStatus ?? body.PaymentStatus;
  const estadoNuevo = normalizarEstadoAzul(estadoRaw);
  const eventId = extraerAzulEventId(body, azulOrderId, estadoNuevo);
  const eventDocId = sanitizeEventId(eventId);

  if (!azulOrderId) {
    logger.warn("[azulWebhook] sin azulOrderId", { eventId });
    await registrarEventoWebhookAzul({
      eventId,
      azulOrderId: "",
      estado: estadoNuevo,
      motivo: "sin_azul_order_id",
      applied: false,
      body,
    });
    res.status(200).json({ ok: true, ignored: true, motivo: "sin_azul_order_id" });
    return;
  }

  const eventRef = db().collection("webhook_eventos_azul").doc(eventDocId);
  const existingEvent = await eventRef.get();
  if (existingEvent.exists) {
    logger.info("[azulWebhook] evento duplicado (eventId)", { eventId, azulOrderId });
    res.status(200).json({ ok: true, duplicate: true, dedup: "eventId", eventId });
    return;
  }

  if (!estadoNuevo) {
    await registrarEventoWebhookAzul({
      eventId,
      azulOrderId,
      estado: null,
      motivo: "estado_no_reconocido",
      applied: false,
      body,
    });
    res.status(200).json({ ok: true, ignored: true, motivo: "estado_no_reconocido" });
    return;
  }

  const pago = await buscarPagoAzulPorOrderId(azulOrderId);
  if (!pago) {
    await registrarEventoWebhookAzul({
      eventId,
      azulOrderId,
      estado: estadoNuevo,
      motivo: "pago_no_encontrado",
      applied: false,
      body,
    });
    logger.warn("[azulWebhook] pago no encontrado", { azulOrderId, eventId });
    res.status(200).json({ ok: true, ignored: true, motivo: "pago_no_encontrado" });
    return;
  }

  const viajeId = String(pago.data.viajeId ?? "").trim();
  const recargaId = String(pago.data.recargaId ?? "").trim();
  const esRecarga = esPagoAzulRecargaTaxista(pago.data);
  const pagoAzulId = pago.pagoAzulId;

  if (esRecarga && !financeCfg.recargaPrepagoAzulHabilitados) {
    await registrarEventoWebhookAzul({
      eventId,
      azulOrderId,
      estado: estadoNuevo,
      motivo: "recarga_prepago_azul_off",
      applied: false,
      body,
      pagoAzulId,
      viajeId: recargaId,
    });
    res.status(200).json({ ok: true, ignored: true, motivo: "recarga_prepago_azul_off" });
    return;
  }
  if (!esRecarga && !financeCfg.pagosConTarjetaAzulHabilitados) {
    await registrarEventoWebhookAzul({
      eventId,
      azulOrderId,
      estado: estadoNuevo,
      motivo: "pagos_tarjeta_azul_off",
      applied: false,
      body,
      pagoAzulId,
      viajeId,
    });
    res.status(200).json({ ok: true, ignored: true, motivo: "pagos_tarjeta_azul_off" });
    return;
  }
  const trans = debeAplicarTransicionAzul(pago.data.estado, estadoNuevo);

  if (!trans.aplicar) {
    await registrarEventoWebhookAzul({
      eventId,
      azulOrderId,
      estado: estadoNuevo,
      motivo: trans.motivo,
      applied: false,
      body,
      pagoAzulId,
      viajeId,
    });
    logger.info("[azulWebhook] transición ignorada", {
      azulOrderId,
      eventId,
      motivo: trans.motivo,
      estadoNuevo,
      estadoActual: pago.data.estado,
    });
    res.status(200).json({ ok: true, ignored: true, motivo: trans.motivo });
    return;
  }

  if (estadoNuevo === "captured") {
    const reciboMeta = extraerMetadatosReciboAzul(body);
    if (esRecarga && recargaId) {
      await aplicarCapturaAzulRecargaTaxista({
        recargaId,
        pagoAzulId,
        azulOrderId,
        actorUid: "azul_webhook",
        reciboMeta,
      });
    } else if (viajeId) {
      await aplicarCapturaAzulEnViaje({
        viajeId,
        pagoAzulId,
        azulOrderId,
        actorUid: "azul_webhook",
        reciboMeta,
      });
    }
  } else if (esRecarga && recargaId) {
    if (estadoNuevo === "failed") {
      await aplicarFalloAzulRecargaTaxista({ recargaId, pagoAzulId, azulOrderId });
    }
  } else if (viajeId) {
    await aplicarEstadoIntermedioAzul({
      viajeId,
      pagoAzulId,
      azulOrderId,
      estadoNuevo,
    });
  }

  await registrarEventoWebhookAzul({
    eventId,
    azulOrderId,
    estado: estadoNuevo,
    motivo: trans.motivo,
    applied: true,
    body,
    pagoAzulId,
    viajeId,
  });

  logger.info("[azulWebhook] procesado", { azulOrderId, eventId, estado: estadoNuevo });
  res.status(200).json({ ok: true, processed: true, estado: estadoNuevo, azulOrderId });
});

/** Aplica captura AZUL confirmada (webhook o stub admin). */
export async function aplicarCapturaAzulEnViaje(input: {
  viajeId: string;
  pagoAzulId: string;
  azulOrderId: string;
  actorUid: string;
  reciboMeta?: import("./azul_webhook_logic.js").AzulReciboMetadatos;
}): Promise<void> {
  const viajeRef = db().collection("viajes").doc(input.viajeId);
  const pagoRef = db().collection("pagos_azul").doc(input.pagoAzulId);
  const now = FieldValue.serverTimestamp();

  await db().runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    const pSnap = await tx.get(pagoRef);
    if (!vSnap.exists || !pSnap.exists) {
      throw new HttpsError("not-found", "Viaje o pago AZUL no encontrado");
    }
    const v = (vSnap.data() ?? {}) as AnyMap;
    const p = (pSnap.data() ?? {}) as AnyMap;
    const ep = String(v.estadoPago ?? "").trim().toLowerCase();
    if (ep === "verificado") return;

    const metodoNorm = metodoPagoNormalizadoDesde(v);
    if (metodoNorm !== "tarjeta") {
      logger.warn("[aplicarCapturaAzulEnViaje] ignorado: viaje ya no es tarjeta", {
        viajeId: input.viajeId,
        metodoNorm,
      });
      return;
    }

    const trans = debeAplicarTransicionAzul(p.estado, "captured");
    if (!trans.aplicar && normalizarEstadoAzul(p.estado) !== "captured") return;

    const uidCliente = String(v.uidCliente ?? v.clienteId ?? "").trim();
    const montoDeuda =
      typeof v.cobroClienteMontoRd === "number" && Number.isFinite(v.cobroClienteMontoRd)
        ? Number(v.cobroClienteMontoRd)
        : precioCentsViaje(v) / 100;

    const patchViaje: AnyMap = {
      estadoPago: "verificado",
      pagoAzulId: input.pagoAzulId,
      cobroClientePendiente: false,
      cobroClienteEstado: "pagado",
      "payment.provider": "azul",
      "payment.status": "captured",
      "payment.azulOrderId": input.azulOrderId,
      "payment.azulCapturedAt": now,
      "payment.updatedAt": now,
      updatedAt: now,
      actualizadoEn: now,
    };
    const meta = input.reciboMeta;
    if (meta?.authorizationCode) patchViaje["payment.azulAuthCode"] = meta.authorizationCode;
    if (meta?.cardBrand) patchViaje["payment.azulCardBrand"] = meta.cardBrand;
    if (meta?.cardLast4) patchViaje["payment.azulCardLast4"] = meta.cardLast4;
    if (meta?.rrn) patchViaje["payment.azulRrn"] = meta.rrn;
    if (meta?.responseCode) patchViaje["payment.azulResponseCode"] = meta.responseCode;

    const pagoPatch: AnyMap = {
      estado: "captured",
      capturedAt: now,
      updatedAt: now,
    };
    if (meta?.authorizationCode) pagoPatch.authorizationCode = meta.authorizationCode;
    if (meta?.cardBrand) pagoPatch.cardBrand = meta.cardBrand;
    if (meta?.cardLast4) pagoPatch.cardLast4 = meta.cardLast4;
    if (meta?.rrn) pagoPatch.rrn = meta.rrn;
    if (meta?.responseCode) pagoPatch.responseCode = meta.responseCode;
    if (metodoNorm === "tarjeta" || metodoNorm === "transferencia") {
      patchViaje.elegibleLiquidacionSemanal = elegibleLiquidacionSemanalCache({
        ...v,
        ...patchViaje,
        liquidado: v.liquidado === true,
      });
    }

    if (uidCliente && v.cobroClientePendiente === true) {
      tx.set(
        db().collection("usuarios").doc(uidCliente),
        {
          tieneCobroViajePendiente: false,
          deudaViajesClienteRd: FieldValue.increment(-montoDeuda),
          updatedAt: now,
        },
        { merge: true },
      );
    }

    tx.update(viajeRef, patchViaje);
    tx.update(pagoRef, pagoPatch);
    patchBolaMetodoPagoEnTx(tx, v, {
      metodoPago: "tarjeta",
      estadoPago: "verificado",
      updatedAt: now,
    });
  });
}

/** Staging: simula captura AZUL tras pago stub (solo admin o AZUL_USE_STUB). */
export const azulSimularCapturaStub = onCall({ secrets: azulRuntimeSecrets }, async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const role = await getRole(request.auth.uid);
  if (role !== "admin") throw new HttpsError("permission-denied", "Solo admin");

  const azul = readAzulRuntimeConfig();
  if (!azul.useStub) {
    throw new HttpsError("failed-precondition", "Solo con AZUL_USE_STUB=true");
  }

  const viajeId =
    typeof request.data?.viajeId === "string" ? request.data.viajeId.trim() : "";
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const vSnap = await db().collection("viajes").doc(viajeId).get();
  if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no encontrado");
  const v = (vSnap.data() ?? {}) as AnyMap;
  const pagoAzulId = String(v.pagoAzulId ?? `azul_${viajeId}`).trim();
  const payObj = (v.payment ?? {}) as AnyMap;
  const azulOrderId = String(payObj.azulOrderId ?? buildAzulOrderIdDeterministic(viajeId, precioCentsViaje(v), true)).trim();

  await aplicarCapturaAzulEnViaje({
    viajeId,
    pagoAzulId,
    azulOrderId,
    actorUid: request.auth.uid,
    reciboMeta: {
      authorizationCode: "OK-STUB",
      cardBrand: "Visa",
      cardLast4: "4242",
      rrn: `STUB-${Date.now()}`,
      responseCode: "00",
    },
  });

  return { ok: true, viajeId, estado: "captured" };
});

/**
 * Cliente: tarjeta sin cobrar → cambia a efectivo (estilo Uber/DiDi).
 * El conductor ve el monto a cobrar en mano; AZUL tardío no pisa el cambio.
 */
export const cambiarTarjetaAEfectivoViaje = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  const viajeId =
    typeof request.data?.viajeId === "string" ? request.data.viajeId.trim() : "";
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const viajeRef = db().collection("viajes").doc(viajeId);
  const viaje = await assertClienteDuenoViaje(uid, viajeId);

  if (!metodoEsTarjeta(viaje.metodoPago)) {
    throw new HttpsError("failed-precondition", "El viaje no está en método Tarjeta");
  }
  if (!viajeTarjetaSinCobrar(viaje)) {
    throw new HttpsError("failed-precondition", "La tarjeta ya fue cobrada por AZUL");
  }

  const completado = viaje.completado === true;
  const estadoNorm = normalizeEstadoViajeDoc(viaje.estado);
  if (estadoNorm === "cancelado") {
    throw new HttpsError("failed-precondition", "El viaje está cancelado");
  }
  if (!estadoPermiteCambioTarjetaAEfectivo(estadoNorm, completado)) {
    throw new HttpsError(
      "failed-precondition",
      "Solo podés cambiar a efectivo con el viaje activo o en la factura pendiente.",
    );
  }

  const uidTaxista = String(viaje.uidTaxista ?? viaje.taxistaId ?? "").trim();
  if (!uidTaxista && !completado) {
    throw new HttpsError("failed-precondition", "Aún no hay conductor asignado");
  }

  const pagoAzulId = String(viaje.pagoAzulId ?? `azul_${viajeId}`).trim();
  const pagoRef = db().collection("pagos_azul").doc(pagoAzulId);
  const now = FieldValue.serverTimestamp();

  await db().runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no encontrado");
    const v = (vSnap.data() ?? {}) as AnyMap;

    const uidCliente = String(v.uidCliente ?? v.clienteId ?? "").trim();
    if (uidCliente !== uid) {
      throw new HttpsError("permission-denied", "No autorizado para este viaje");
    }
    if (!metodoEsTarjeta(v.metodoPago) || !viajeTarjetaSinCobrar(v)) {
      throw new HttpsError("failed-precondition", "El pago con tarjeta ya no está pendiente");
    }

    const montoDeuda =
      typeof v.cobroClienteMontoRd === "number" && Number.isFinite(v.cobroClienteMontoRd)
        ? Number(v.cobroClienteMontoRd)
        : precioCentsViaje(v) / 100;

    const patchViaje: AnyMap = {
      metodoPago: "Efectivo",
      metodoPagoNormalizado: "efectivo",
      metodoPagoAnterior: "tarjeta",
      tarjetaCambioEfectivoEn: now,
      metodoPagoUpdatedBy: uid,
      metodoPagoUpdatedAt: now,
      cobroClientePendiente: false,
      cobroClienteEstado: "regularizado",
      "payment.provider": "cash",
      "payment.status": "cash_collected",
      "payment.supersededByEfectivo": true,
      "payment.supersededAt": now,
      "payment.updatedAt": now,
      updatedAt: now,
      actualizadoEn: now,
    };
    tx.update(viajeRef, patchViaje);

    if (uidCliente && v.cobroClientePendiente === true) {
      tx.set(
        db().collection("usuarios").doc(uidCliente),
        {
          tieneCobroViajePendiente: false,
          deudaViajesClienteRd: FieldValue.increment(-montoDeuda),
          updatedAt: now,
        },
        { merge: true },
      );
    }

    const pSnap = await tx.get(pagoRef);
    if (pSnap.exists) {
      tx.update(pagoRef, {
        estado: "failed",
        supersededByEfectivo: true,
        supersededAt: now,
        lastError: "Cliente cambió a pago en efectivo",
        updatedAt: now,
      });
    }
    patchBolaMetodoPagoEnTx(tx, v, {
      metodoPago: "efectivo",
      metodoPagoUpdatedBy: uid,
      metodoPagoUpdatedAt: now,
      updatedAt: now,
    });
  });

  logger.info("[cambiarTarjetaAEfectivoViaje] ok", { viajeId, uid });
  return { ok: true, viajeId, metodoPago: "Efectivo" };
});
