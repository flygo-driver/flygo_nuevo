/**
 * Fase 6 — AZUL E-Commerce (cableado; credenciales en Secret Manager / config).
 * Sin credenciales: callables responden AZUL_NOT_CONFIGURED (flags OFF = omitido).
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import {
  buildAzulOrderIdDeterministic,
  debeAplicarTransicionAzul,
  extraerAzulEventId,
  extraerAzulOrderId,
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

type AnyMap = Record<string, unknown>;

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

function paymentPageUrlForOrder(azulOrderId: string, useStub: boolean): string {
  if (!useStub || !azulOrderId) return "";
  return `https://pruebas.azul.com.do/PaymentPage/?order=${encodeURIComponent(azulOrderId)}`;
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
export const azulCreatePaymentSession = onCall(async (request) => {
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
        return {
          ok: true,
          wired: true,
          reused: true,
          viajeId,
          pagoAzulId,
          azulOrderId,
          montoCents: Number(p.montoCents ?? montoCents),
          paymentPageUrl: paymentPageUrlForOrder(azulOrderId, azul.useStub),
          useStub: azul.useStub,
        };
      }
    }
  }

  const now = FieldValue.serverTimestamp();
  const azulOrderId = buildAzulOrderIdDeterministic(viajeId, montoCents, azul.useStub);
  const paymentPageUrl = paymentPageUrlForOrder(azulOrderId, azul.useStub);

  await pagoRef.set(
    {
      viajeId,
      uidCliente: uid,
      azulOrderId,
      montoCents,
      moneda: "DOP",
      estado: azul.useStub ? "pending" : "pending_configuration",
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
    paymentPageUrl,
    useStub: azul.useStub,
    message: azul.useStub
      ? "Sesión stub AZUL (staging). Conecte API real en azul.ts."
      : "Pendiente integración API AZUL en servidor.",
  };
});

/** Poll estado pago AZUL (cliente o admin). */
export const azulVerifyPayment = onCall(async (request) => {
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
  return {
    ok: true,
    viajeId,
    pagoAzulId,
    estado: String(p.estado ?? "unknown"),
    azulOrderId: String(p.azulOrderId ?? ""),
    paymentStatus: String(((v.payment ?? {}) as AnyMap).status ?? ""),
    estadoPago: String(v.estadoPago ?? ""),
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

async function aplicarEstadoIntermedioAzul(input: {
  viajeId: string;
  pagoAzulId: string;
  azulOrderId: string;
  estadoNuevo: AzulPagoEstado;
}): Promise<void> {
  const viajeRef = db().collection("viajes").doc(input.viajeId);
  const pagoRef = db().collection("pagos_azul").doc(input.pagoAzulId);
  const now = FieldValue.serverTimestamp();

  await db().runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    const pSnap = await tx.get(pagoRef);
    if (!vSnap.exists || !pSnap.exists) return;

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
    tx.update(viajeRef, viajePatch);
  });
}

/** Webhook AZUL (HTTPS). Validar firma cuando haya credenciales reales. */
export const azulWebhook = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }
  const financeCfg = await getFinanceConfig();
  if (!financeCfg.pagosConTarjetaAzulHabilitados) {
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
  const pagoAzulId = pago.pagoAzulId;
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

  if (estadoNuevo === "captured" && viajeId) {
    await aplicarCapturaAzulEnViaje({
      viajeId,
      pagoAzulId,
      azulOrderId,
      actorUid: "azul_webhook",
    });
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

    const trans = debeAplicarTransicionAzul(p.estado, "captured");
    if (!trans.aplicar && normalizarEstadoAzul(p.estado) !== "captured") return;

    const patchViaje: AnyMap = {
      estadoPago: "verificado",
      pagoAzulId: input.pagoAzulId,
      "payment.provider": "azul",
      "payment.status": "captured",
      "payment.azulOrderId": input.azulOrderId,
      "payment.azulCapturedAt": now,
      "payment.updatedAt": now,
      updatedAt: now,
      actualizadoEn: now,
    };
    const metodoNorm = metodoPagoNormalizadoDesde(v);
    if (metodoNorm === "tarjeta" || metodoNorm === "transferencia") {
      patchViaje.elegibleLiquidacionSemanal = elegibleLiquidacionSemanalCache({
        ...v,
        ...patchViaje,
        liquidado: v.liquidado === true,
      });
    }

    tx.update(viajeRef, patchViaje);
    tx.update(pagoRef, {
      estado: "captured",
      capturedAt: now,
      updatedAt: now,
    });
  });
}

/** Staging: simula captura AZUL tras pago stub (solo admin o AZUL_USE_STUB). */
export const azulSimularCapturaStub = onCall(async (request) => {
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
  });

  return { ok: true, viajeId, estado: "captured" };
});
