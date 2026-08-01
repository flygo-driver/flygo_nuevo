/**
 * AZUL — recarga prepago taxista con tarjeta (Payment Page, flag OFF en producción).
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { readAzulRuntimeConfig } from "./azul.js";
import { azulRuntimeSecrets } from "./azul_secrets.js";
import {
  buildAzulOrderIdRecargaTaxista,
  debeAplicarTransicionAzul,
  normalizarEstadoAzul,
  type AzulReciboMetadatos,
} from "./azul_webhook_logic.js";
import { buildAzulPaymentLaunchUrl } from "./azul_payment_page.js";
import { getFinanceConfig } from "./finance.js";
import { syncTaxistaBloqueoOperativo } from "./finance.js";
import { acreditarRecargaPrepagoEnTx } from "./recarga_prepago_credit.js";

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

async function assertTaxista(uid: string): Promise<void> {
  const role = await getRole(uid);
  if (role !== "taxista") throw new HttpsError("permission-denied", "Solo taxistas");
}

function paymentUrlsForRecarga(azulOrderId: string, useStub: boolean): {
  paymentPageUrl: string;
  paymentLaunchUrl: string;
} {
  if (!azulOrderId) return { paymentPageUrl: "", paymentLaunchUrl: "" };
  if (useStub) {
    const stub = `https://pruebas.azul.com.do/PaymentPage/?order=${encodeURIComponent(azulOrderId)}`;
    return { paymentPageUrl: stub, paymentLaunchUrl: stub };
  }
  const launch = buildAzulPaymentLaunchUrl(azulOrderId);
  return { paymentPageUrl: launch, paymentLaunchUrl: launch };
}

async function assertRecargaAzulHabilitada(): Promise<void> {
  const financeCfg = await getFinanceConfig();
  if (!financeCfg.recargaPrepagoAzulHabilitados) {
    throw new HttpsError(
      "failed-precondition",
      "recargaPrepagoAzulHabilitados=false",
    );
  }
}

async function buscarRecargaPorAzulOrderId(azulOrderId: string): Promise<{
  recargaId: string;
  data: AnyMap;
} | null> {
  const order = String(azulOrderId ?? "").trim();
  if (!order) return null;
  const q = await db()
    .collection("recargas_comision_taxista")
    .where("azulOrderId", "==", order)
    .limit(1)
    .get();
  if (q.empty) return null;
  const doc = q.docs[0];
  return { recargaId: doc.id, data: (doc.data() ?? {}) as AnyMap };
}

async function buscarRecargaAbierta(uid: string): Promise<boolean> {
  const estados = ["pendiente_verificacion", "pendiente_pago_azul"];
  for (const estado of estados) {
    const q = await db()
      .collection("recargas_comision_taxista")
      .where("uidTaxista", "==", uid)
      .where("estado", "==", estado)
      .limit(1)
      .get();
    if (!q.empty) return true;
  }
  return false;
}

/** Taxista: inicia recarga prepago con tarjeta (AZUL Payment Page). */
export const azulCreateRecargaTaxistaSession = onCall({ secrets: azulRuntimeSecrets }, async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  await assertTaxista(uid);

  const financeCfg = await getFinanceConfig();
  if (!financeCfg.recargaPrepagoAzulHabilitados) {
    return {
      ok: true,
      omitido: true,
      motivo: "recargaPrepagoAzulHabilitados=false",
      wired: true,
    };
  }

  const montoRdRaw = request.data?.montoRd;
  const montoRd = typeof montoRdRaw === "number" ? montoRdRaw : Number(montoRdRaw ?? 0);
  if (!Number.isFinite(montoRd) || montoRd < 200) {
    throw new HttpsError("invalid-argument", "Monto mínimo RD$200");
  }

  const azul = readAzulRuntimeConfig();
  if (!azul.configured) {
    throw new HttpsError(
      "failed-precondition",
      "AZUL_NOT_CONFIGURED: configure AZUL_STORE_ID y AZUL_AUTH_KEY.",
    );
  }

  if (await buscarRecargaAbierta(uid)) {
    throw new HttpsError(
      "failed-precondition",
      "Ya tienes una recarga en curso. Completa o cancela antes de iniciar otra.",
    );
  }

  const montoCents = Math.round(montoRd * 100);
  const uSnap = await db().collection("usuarios").doc(uid).get();
  const nombreTaxista = String((uSnap.data() as AnyMap | undefined)?.nombre ?? "Taxista").trim();

  const now = FieldValue.serverTimestamp();
  const recargaRef = db().collection("recargas_comision_taxista").doc();
  const recargaId = recargaRef.id;
  const pagoAzulId = `azul_recarga_${recargaId}`;
  const azulOrderId = buildAzulOrderIdRecargaTaxista(recargaId, montoCents, azul.useStub);
  const urls = paymentUrlsForRecarga(azulOrderId, azul.useStub);

  const bSnap = await db().collection("billeteras_taxista").doc(uid).get();
  const bill = (bSnap.data() ?? {}) as AnyMap;

  await db().runTransaction(async (tx) => {
    tx.set(recargaRef, {
      uidTaxista: uid,
      nombreTaxista: nombreTaxista || "Taxista",
      comisionPendienteAlEnviar: Number(bill.comisionPendiente ?? 0) || 0,
      saldoPrepagoAlEnviar: Number(bill.saldoPrepagoComisionRd ?? 0) || 0,
      montoDeclaradoRd: Number(montoRd.toFixed(2)),
      montoElegidoRd: Number(montoRd.toFixed(2)),
      metodoPago: "tarjeta",
      estado: "pendiente_pago_azul",
      provider: "azul",
      pagoAzulId,
      azulOrderId,
      createdAt: now,
      updatedAt: now,
    });

    tx.set(
      db().collection("pagos_azul").doc(pagoAzulId),
      {
        tipo: "recarga_taxista",
        recargaId,
        uidTaxista: uid,
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
  });

  logger.info("[azulCreateRecargaTaxistaSession]", { uid, recargaId, azulOrderId, montoRd });

  return {
    ok: true,
    wired: true,
    recargaId,
    pagoAzulId,
    azulOrderId,
    montoRd: Number(montoRd.toFixed(2)),
    montoCents,
    paymentPageUrl: urls.paymentPageUrl,
    paymentLaunchUrl: urls.paymentLaunchUrl,
    useStub: azul.useStub,
    message: azul.useStub
      ? "Sesión stub AZUL recarga (staging)."
      : "Abrí el navegador para pagar la recarga con tarjeta de débito.",
  };
});

/** Aplica captura AZUL de recarga taxista → acredita prepago + desbloqueo automático. */
export async function aplicarCapturaAzulRecargaTaxista(input: {
  recargaId: string;
  pagoAzulId: string;
  azulOrderId: string;
  actorUid: string;
  reciboMeta?: AzulReciboMetadatos;
}): Promise<{ uidTaxista: string; yaEstabaPagada: boolean }> {
  await assertRecargaAzulHabilitada();

  const pagoRef = db().collection("pagos_azul").doc(input.pagoAzulId);
  let uidTaxista = "";
  let yaEstabaPagada = false;

  await db().runTransaction(async (tx) => {
    const pSnap = await tx.get(pagoRef);
    if (!pSnap.exists) throw new HttpsError("not-found", "Pago AZUL recarga no encontrado");
    const p = (pSnap.data() ?? {}) as AnyMap;
    if (String(p.tipo ?? "") !== "recarga_taxista") {
      throw new HttpsError("failed-precondition", "Pago AZUL no es recarga_taxista");
    }
    uidTaxista = String(p.uidTaxista ?? "").trim();
    const estadoPago = normalizarEstadoAzul(p.estado);
    if (estadoPago === "captured") {
      const credit = await acreditarRecargaPrepagoEnTx(tx, {
        recargaId: input.recargaId,
        actorUid: input.actorUid,
        estadosPermitidos: ["pendiente_pago_azul"],
        metodoVerificacion: "azul_tarjeta",
        pagoAzulId: input.pagoAzulId,
        azulOrderId: input.azulOrderId,
      });
      yaEstabaPagada = credit.yaEstabaPagada;
      uidTaxista = credit.uidTaxista;
      return;
    }

    const trans = debeAplicarTransicionAzul(p.estado, "captured");
    if (!trans.aplicar) {
      return;
    }

    const credit = await acreditarRecargaPrepagoEnTx(tx, {
      recargaId: input.recargaId,
      actorUid: input.actorUid,
      estadosPermitidos: ["pendiente_pago_azul"],
      metodoVerificacion: "azul_tarjeta",
      pagoAzulId: input.pagoAzulId,
      azulOrderId: input.azulOrderId,
    });
    yaEstabaPagada = credit.yaEstabaPagada;
    uidTaxista = credit.uidTaxista;

    const now = FieldValue.serverTimestamp();
    const pagoPatch: AnyMap = {
      estado: "captured",
      capturedAt: now,
      updatedAt: now,
    };
    const meta = input.reciboMeta;
    if (meta?.authorizationCode) pagoPatch.authorizationCode = meta.authorizationCode;
    if (meta?.cardBrand) pagoPatch.cardBrand = meta.cardBrand;
    if (meta?.cardLast4) pagoPatch.cardLast4 = meta.cardLast4;
    if (meta?.rrn) pagoPatch.rrn = meta.rrn;
    if (meta?.responseCode) pagoPatch.responseCode = meta.responseCode;
    tx.update(pagoRef, pagoPatch);
  });

  if (uidTaxista) {
    await syncTaxistaBloqueoOperativo(uidTaxista);
  }

  return { uidTaxista, yaEstabaPagada };
}

/** Marca recarga AZUL fallida/cancelada (no acredita). */
export async function aplicarFalloAzulRecargaTaxista(input: {
  recargaId: string;
  pagoAzulId: string;
  azulOrderId: string;
}): Promise<void> {
  const now = FieldValue.serverTimestamp();
  const recRef = db().collection("recargas_comision_taxista").doc(input.recargaId);
  const pagoRef = db().collection("pagos_azul").doc(input.pagoAzulId);

  await db().runTransaction(async (tx) => {
    const rSnap = await tx.get(recRef);
    const pSnap = await tx.get(pagoRef);
    if (!rSnap.exists || !pSnap.exists) return;

    const r = (rSnap.data() ?? {}) as AnyMap;
    const estado = String(r.estado ?? "").trim().toLowerCase();
    if (estado === "pagado") return;

    const trans = debeAplicarTransicionAzul(pSnap.data()?.estado, "failed");
    if (trans.aplicar) {
      tx.update(pagoRef, { estado: "failed", failedAt: now, updatedAt: now });
    }
    if (estado === "pendiente_pago_azul") {
      tx.update(recRef, {
        estado: "rechazado",
        notaAdmin: "Pago con tarjeta no completado",
        updatedAt: now,
      });
    }
  });
}

/** Staging: simula captura recarga AZUL (solo admin + AZUL_USE_STUB). */
export const azulSimularCapturaRecargaStub = onCall({ secrets: azulRuntimeSecrets }, async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const role = await getRole(request.auth.uid);
  if (role !== "admin") throw new HttpsError("permission-denied", "Solo admin");

  const azul = readAzulRuntimeConfig();
  if (!azul.useStub) {
    throw new HttpsError("failed-precondition", "Solo con AZUL_USE_STUB=true");
  }

  const recargaId =
    typeof request.data?.recargaId === "string" ? request.data.recargaId.trim() : "";
  if (!recargaId) throw new HttpsError("invalid-argument", "Falta recargaId");

  const pagoAzulId = `azul_recarga_${recargaId}`;
  const pSnap = await db().collection("pagos_azul").doc(pagoAzulId).get();
  const p = (pSnap.data() ?? {}) as AnyMap;
  const azulOrderId = String(p.azulOrderId ?? buildAzulOrderIdRecargaTaxista(recargaId, Number(p.montoCents ?? 0), true));

  await aplicarCapturaAzulRecargaTaxista({
    recargaId,
    pagoAzulId,
    azulOrderId,
    actorUid: request.auth.uid,
    reciboMeta: {
      authorizationCode: "OK-STUB-REC",
      cardBrand: "Visa",
      cardLast4: "4242",
      rrn: `STUB-REC-${Date.now()}`,
      responseCode: "00",
    },
  });

  return { ok: true, recargaId, estado: "pagado" };
});

export function esPagoAzulRecargaTaxista(data: AnyMap | undefined): boolean {
  return String(data?.tipo ?? "").trim() === "recarga_taxista";
}

/** Taxista: reconcilia recarga AZUL al volver de la app (acredita + desbloqueo). */
export const azulVerifyRecargaTaxista = onCall({ secrets: azulRuntimeSecrets }, async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;

  const recargaId =
    typeof request.data?.recargaId === "string" ? request.data.recargaId.trim() : "";
  if (!recargaId) throw new HttpsError("invalid-argument", "Falta recargaId");

  const financeCfg = await getFinanceConfig();
  if (!financeCfg.recargaPrepagoAzulHabilitados) {
    return { ok: true, omitido: true, motivo: "recargaPrepagoAzulHabilitados=false" };
  }

  const recSnap = await db().collection("recargas_comision_taxista").doc(recargaId).get();
  if (!recSnap.exists) throw new HttpsError("not-found", "Recarga no encontrada");
  const rec = (recSnap.data() ?? {}) as AnyMap;
  const uidTaxista = String(rec.uidTaxista ?? "").trim();
  const role = await getRole(uid);
  if (role !== "admin" && uid !== uidTaxista) {
    throw new HttpsError("permission-denied", "No autorizado");
  }

  const pagoAzulId = String(rec.pagoAzulId ?? `azul_recarga_${recargaId}`).trim();
  const azulOrderId = String(rec.azulOrderId ?? "").trim();
  let estadoRecarga = String(rec.estado ?? "").trim().toLowerCase();
  let reconciled = false;

  const pagoSnap = await db().collection("pagos_azul").doc(pagoAzulId).get();
  const p = (pagoSnap.data() ?? {}) as AnyMap;
  const pEstado = normalizarEstadoAzul(p.estado);

  if (estadoRecarga === "pendiente_pago_azul" && pEstado === "captured") {
    try {
      await aplicarCapturaAzulRecargaTaxista({
        recargaId,
        pagoAzulId,
        azulOrderId: azulOrderId || String(p.azulOrderId ?? ""),
        actorUid: uid,
      });
      reconciled = true;
    } catch (e) {
      logger.warn("[azulVerifyRecargaTaxista] reconcile captured→pagado falló", {
        recargaId,
        err: e,
      });
    }
  }

  const recFresh = await db().collection("recargas_comision_taxista").doc(recargaId).get();
  estadoRecarga = String(
    ((recFresh.data() ?? {}) as AnyMap).estado ?? estadoRecarga,
  )
    .trim()
    .toLowerCase();
  const captured = estadoRecarga === "pagado";

  const tienePagoPendiente = uidTaxista
    ? await syncTaxistaBloqueoOperativo(uidTaxista)
    : false;

  return {
    ok: true,
    recargaId,
    estado: estadoRecarga,
    captured,
    reconciled,
    tienePagoPendiente,
    desbloqueado: !tienePagoPendiente,
    pagoEstado: String(p.estado ?? "unknown"),
    pagoAzulId,
    azulOrderId: azulOrderId || String(p.azulOrderId ?? ""),
  };
});

export { buscarRecargaPorAzulOrderId };
