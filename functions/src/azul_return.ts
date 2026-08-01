/**
 * HTTP AZUL: lanzamiento Payment Page + URLs de retorno (Approved/Declined/Cancel).
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import {
  aplicarCapturaAzulRecargaTaxista,
  aplicarFalloAzulRecargaTaxista,
  buscarRecargaPorAzulOrderId,
  esPagoAzulRecargaTaxista,
} from "./azul_recarga_taxista.js";
import {
  aplicarCapturaAzulEnViaje,
  aplicarEstadoIntermedioAzul,
  readAzulRuntimeConfig,
} from "./azul.js";
import { getFinanceConfig } from "./finance.js";
import {
  azulPaymentPageActionUrl,
  buildAzulAutoPostHtml,
  buildAzulPaymentFormFields,
  parseAzulReturnQuery,
  verifyAzulAuthHashResponse,
  azulReturnIsoAprobado,
} from "./azul_payment_page.js";
import { extraerMetadatosReciboAzul } from "./azul_webhook_logic.js";
import { azulRuntimeSecrets, getAzulAuthKey, getAzulMerchantName } from "./azul_secrets.js";
import {
  AZUL_DEMO_CERT_URL,
  buildAzulCertificationInfoHtml,
} from "./azul_certification_page.js";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();

const HOSTING_RESULT_BASE = "https://flygo-rd.web.app/azul/resultado";

function queryFromRequest(req: { query: unknown }): Record<string, string> {
  const out: Record<string, string> = {};
  const q = req.query as Record<string, unknown>;
  for (const [k, v] of Object.entries(q ?? {})) {
    if (Array.isArray(v)) out[k] = String(v[0] ?? "");
    else out[k] = String(v ?? "");
  }
  return out;
}

async function buscarPagoPorOrderId(azulOrderId: string): Promise<{
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
  if (q.empty) return null;
  const doc = q.docs[0];
  return { pagoAzulId: doc.id, data: (doc.data() ?? {}) as AnyMap };
}

function redirectResultadoHtml(input: {
  titulo: string;
  mensaje: string;
  viajeId?: string;
  recargaId?: string;
  rol?: "cliente" | "taxista";
  estado: "aprobado" | "declinado" | "cancelado" | "error";
}): string {
  const parts: string[] = [`estado=${encodeURIComponent(input.estado)}`];
  if (input.viajeId) {
    parts.push(`viajeId=${encodeURIComponent(input.viajeId)}`);
  }
  if (input.recargaId) {
    parts.push(`recargaId=${encodeURIComponent(input.recargaId)}`);
  }
  const rol = input.rol ?? (input.recargaId ? "taxista" : "cliente");
  parts.push(`rol=${encodeURIComponent(rol)}`);
  const deep = `${HOSTING_RESULT_BASE}?${parts.join("&")}`;
  return `<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>${input.titulo}</title>
<meta http-equiv="refresh" content="2;url=${deep}" />
<style>body{font-family:system-ui,sans-serif;background:#0d1117;color:#e6edf3;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:24px;text-align:center}
.box{max-width:400px}h1{font-size:1.15rem;margin:0 0 10px;color:#7ee787}p{margin:0;color:#8b949e;line-height:1.45;font-size:0.92rem}a{color:#58a6ff}</style></head>
<body><div class="box"><h1>${input.titulo}</h1><p>${input.mensaje}</p>
<p style="margin-top:16px"><a href="${deep}">Volver a RAI Driver</a></p></div></body></html>`;
}

async function resolverIdsRecargaAzul(input: {
  pago: { pagoAzulId: string; data: AnyMap } | null;
  azulOrderId: string;
  rawQuery: Record<string, string>;
}): Promise<{ esRecarga: boolean; recargaId: string; pagoAzulId: string; viajeId: string }> {
  const esRecarga = esPagoAzulRecargaTaxista(input.pago?.data);
  let recargaId = String(input.pago?.data.recargaId ?? input.rawQuery.recargaId ?? "").trim();
  let pagoAzulId = input.pago?.pagoAzulId ?? "";
  const viajeId = String(input.pago?.data.viajeId ?? input.rawQuery.viajeId ?? "").trim();

  if ((!recargaId || !pagoAzulId) && input.azulOrderId) {
    const rec = await buscarRecargaPorAzulOrderId(input.azulOrderId);
    if (rec) {
      recargaId = recargaId || rec.recargaId;
      pagoAzulId =
        pagoAzulId ||
        String(rec.data.pagoAzulId ?? `azul_recarga_${rec.recargaId}`).trim();
    }
  }
  if (!pagoAzulId && recargaId) {
    pagoAzulId = `azul_recarga_${recargaId}`;
  }

  const esRecargaFinal = esRecarga || recargaId.length > 0;
  return { esRecarga: esRecargaFinal, recargaId, pagoAzulId, viajeId };
}

async function azulPagoPermitido(data: AnyMap | undefined): Promise<boolean> {
  const financeCfg = await getFinanceConfig();
  if (esPagoAzulRecargaTaxista(data)) {
    return financeCfg.recargaPrepagoAzulHabilitados;
  }
  return financeCfg.pagosConTarjetaAzulHabilitados;
}

async function assertAzulHabilitado(): Promise<boolean> {
  const financeCfg = await getFinanceConfig();
  return (
    financeCfg.pagosConTarjetaAzulHabilitados || financeCfg.recargaPrepagoAzulHabilitados
  );
}

const DEMO_BANCO_MONTO_CENTS = 15000;

function buildDemoBancoOrderId(): string {
  return `RAI-DEMO-${Date.now()}`;
}

async function responderAzulPaymentLaunchHtml(
  res: { setHeader: (k: string, v: string) => void; status: (n: number) => { send: (b: string) => void } },
  azulOrderId: string,
): Promise<boolean> {
  const cfg = readAzulRuntimeConfig();
  const authKey = getAzulAuthKey();
  if (cfg.useStub || !cfg.storeId || !authKey) {
    res.status(503).send("AZUL no configurado (credenciales o stub).");
    return false;
  }

  const pago = await buscarPagoPorOrderId(azulOrderId);
  if (!pago) {
    res.status(404).send("Orden de pago no encontrada.");
    return false;
  }
  if (!(await azulPagoPermitido(pago.data))) {
    res.status(403).send("Este tipo de pago AZUL está deshabilitado.");
    return false;
  }

  const esRecarga = esPagoAzulRecargaTaxista(pago.data);
  const viajeId = String(pago.data.viajeId ?? "").trim();
  const recargaId = String(pago.data.recargaId ?? "").trim();
  const montoCents = Number(pago.data.montoCents ?? 0);
  const merchantName = getAzulMerchantName();
  const customField1Value = esRecarga ? recargaId : viajeId;

  const fields = buildAzulPaymentFormFields(
    {
      merchantId: cfg.storeId,
      merchantName,
      orderNumber: azulOrderId,
      amountCents: montoCents,
      itbisCents: 0,
      approvedUrl: "",
      declinedUrl: "",
      cancelUrl: "",
      customField1Value,
    },
    authKey,
  );

  const actionUrl = azulPaymentPageActionUrl(cfg.environment);
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.status(200).send(buildAzulAutoPostHtml(actionUrl, fields));
  return true;
}

/** GET — auto-POST a Página de Pago AZUL (desde app vía navegador). */
export const azulPaymentLaunch = onRequest({ secrets: azulRuntimeSecrets }, async (req, res) => {
  const endpoint = "https://us-central1-flygo-rd.cloudfunctions.net/azulPaymentLaunch";

  if (req.method !== "GET") {
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.status(200).send(
      buildAzulCertificationInfoHtml({
        titulo: "Lanzamiento POST AZUL",
        endpoint,
        metodo: "GET con parámetro <code>?order=ORDEN_AZUL</code>",
        uso: "La app abre esta URL después de crear la orden. El servidor devuelve HTML con auto-POST firmado hacia la Página de Pago AZUL.",
        nota: "No se abre manualmente en el navegador sin orden. Para probar el flujo completo en sandbox usá la demo.",
        demoUrl: AZUL_DEMO_CERT_URL,
        estado: "ok",
      }),
    );
    return;
  }

  const azulOrderId = String(req.query.order ?? req.query.OrderNumber ?? "").trim();
  if (!azulOrderId) {
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.status(200).send(
      buildAzulCertificationInfoHtml({
        titulo: "Lanzamiento POST AZUL",
        endpoint: `${endpoint}?order=ORDEN_AZUL`,
        metodo: "GET con <code>?order=</code> (generado por la app o demo)",
        uso: "Endpoint interno del flujo de pago. AZUL no lo visita directamente; redirige al usuario con el formulario POST firmado.",
        nota: "Si abrís solo la URL base sin <code>?order=</code>, es normal ver esta página. No indica error.",
        demoUrl: AZUL_DEMO_CERT_URL,
        estado: "ok",
      }),
    );
    return;
  }

  if (!(await assertAzulHabilitado())) {
    res.status(403).send("Pagos con tarjeta deshabilitados.");
    return;
  }

  await responderAzulPaymentLaunchHtml(res, azulOrderId);
});

/**
 * GET — demo certificación banco: misma lógica que la app (azulPaymentLaunch),
 * sin HTML estático con hash desactualizado.
 */
export const azulPreviewDemo = onRequest({ secrets: azulRuntimeSecrets }, async (req, res) => {
  if (req.method !== "GET") {
    res.status(405).send("Method Not Allowed");
    return;
  }
  if (!(await assertAzulHabilitado())) {
    res.status(403).send("Pagos con tarjeta deshabilitados.");
    return;
  }

  const cfg = readAzulRuntimeConfig();
  if (cfg.environment === "production") {
    res.status(403).send("Vista previa solo disponible en sandbox.");
    return;
  }

  const azulOrderId = buildDemoBancoOrderId();
  const pagoId = `azul_demo_${azulOrderId}`;

  const now = FieldValue.serverTimestamp();
  await db()
    .collection("pagos_azul")
    .doc(pagoId)
    .set(
      {
        azulOrderId,
        viajeId: "viaje_demo_certificacion_banco",
        montoCents: DEMO_BANCO_MONTO_CENTS,
        moneda: "DOP",
        estado: "pending",
        environment: cfg.environment,
        provider: "azul",
        tipo: "demo_banco",
        createdAt: now,
        updatedAt: now,
      },
      { merge: true },
    );

  logger.info("[azulPreviewDemo] orden demo banco", { azulOrderId, pagoId });
  await responderAzulPaymentLaunchHtml(res, azulOrderId);
});

async function procesarRetornoAzul(
  req: { query: unknown },
  tipo: "approved" | "declined" | "cancel",
): Promise<{ html: string; status: number }> {
  if (!(await assertAzulHabilitado())) {
    return {
      status: 403,
      html: redirectResultadoHtml({
        titulo: "Pago no disponible",
        mensaje: "Los pagos con tarjeta están desactivados.",
        estado: "error",
      }),
    };
  }

  const cfg = readAzulRuntimeConfig();
  const authKey = getAzulAuthKey();
  if (!authKey || cfg.useStub) {
    return {
      status: 503,
      html: redirectResultadoHtml({
        titulo: "AZUL no configurado",
        mensaje: "Faltan credenciales en el servidor.",
        estado: "error",
      }),
    };
  }

  const rawQuery = queryFromRequest(req);
  const parsed = parseAzulReturnQuery(rawQuery);
  const azulOrderId = parsed.OrderNumber;

  if (!azulOrderId) {
    const nombres: Record<typeof tipo, string> = {
      approved: "Retorno aprobado (ApprovedUrl)",
      declined: "Retorno declinado (DeclinedUrl)",
      cancel: "Retorno cancelado (CancelUrl)",
    };
    const urls: Record<typeof tipo, string> = {
      approved: "https://us-central1-flygo-rd.cloudfunctions.net/azulReturnApproved",
      declined: "https://us-central1-flygo-rd.cloudfunctions.net/azulReturnDeclined",
      cancel: "https://us-central1-flygo-rd.cloudfunctions.net/azulReturnCancel",
    };
    return {
      status: 200,
      html: buildAzulCertificationInfoHtml({
        titulo: nombres[tipo],
        endpoint: urls[tipo],
        metodo: "GET (redirect desde AZUL con OrderNumber, AuthHash, etc.)",
        uso: "AZUL redirige al usuario aquí después del pago. El servidor valida AuthHash y actualiza el estado del viaje.",
        nota: "Si abrís esta URL en el navegador sin parámetros de AZUL, es normal ver esta página. No indica error — registrá esta URL en el panel AZUL.",
        demoUrl: AZUL_DEMO_CERT_URL,
        estado: "ok",
      }),
    };
  }

  const hashOk = verifyAzulAuthHashResponse(parsed, authKey);
  if (!hashOk) {
    logger.warn("[azulReturn] AuthHash inválido", { azulOrderId, tipo });
    return {
      status: 400,
      html: redirectResultadoHtml({
        titulo: "Verificación fallida",
        mensaje: "No se pudo validar la respuesta de AZUL.",
        estado: "error",
      }),
    };
  }

  const pago = await buscarPagoPorOrderId(azulOrderId);
  if (pago && !(await azulPagoPermitido(pago.data))) {
    return {
      status: 403,
      html: redirectResultadoHtml({
        titulo: "Pago no disponible",
        mensaje: "Este tipo de pago con tarjeta está desactivado.",
        estado: "error",
      }),
    };
  }

  const esRecarga = esPagoAzulRecargaTaxista(pago?.data);
  const viajeId = String(pago?.data.viajeId ?? rawQuery.viajeId ?? "").trim();
  const recargaId = String(pago?.data.recargaId ?? rawQuery.recargaId ?? "").trim();
  const pagoAzulId = pago?.pagoAzulId ?? "";

  if (tipo === "approved" && azulReturnIsoAprobado(parsed.IsoCode, parsed.ResponseMessage)) {
    const body: AnyMap = { ...rawQuery };
    const reciboMeta = extraerMetadatosReciboAzul(body);
    const ids = await resolverIdsRecargaAzul({ pago, azulOrderId, rawQuery });
    if (ids.esRecarga && ids.recargaId && ids.pagoAzulId) {
      try {
        await aplicarCapturaAzulRecargaTaxista({
          recargaId: ids.recargaId,
          pagoAzulId: ids.pagoAzulId,
          azulOrderId,
          actorUid: "azul_return_approved",
          reciboMeta,
        });
      } catch (e) {
        logger.error("[azulReturn] aplicarCapturaAzulRecargaTaxista falló", {
          azulOrderId,
          recargaId: ids.recargaId,
          err: e,
        });
      }
      return {
        status: 200,
        html: redirectResultadoHtml({
          titulo: "Pago aprobado",
          mensaje:
            "Tu recarga con tarjeta fue procesada. Volvé a RAI Conductor (Mis pagos).",
          recargaId: ids.recargaId,
          rol: "taxista",
          estado: "aprobado",
        }),
      };
    } else if (ids.viajeId && ids.pagoAzulId) {
      await aplicarCapturaAzulEnViaje({
        viajeId: ids.viajeId,
        pagoAzulId: ids.pagoAzulId,
        azulOrderId,
        actorUid: "azul_return_approved",
        reciboMeta,
      });
    }
    return {
      status: 200,
      html: redirectResultadoHtml({
        titulo: "Pago aprobado",
        mensaje: "Tu pago con tarjeta fue procesado. Volvé a la app RAI Driver.",
        viajeId: ids.viajeId || viajeId || undefined,
        rol: "cliente",
        estado: "aprobado",
      }),
    };
  }

  if (tipo === "declined" && pagoAzulId) {
    if (esRecarga && recargaId) {
      await aplicarFalloAzulRecargaTaxista({ recargaId, pagoAzulId, azulOrderId });
      return {
        status: 200,
        html: redirectResultadoHtml({
          titulo: "Pago declinado",
          mensaje: parsed.ErrorDescription || parsed.ResponseMessage || "El banco no aprobó el pago.",
          recargaId,
          rol: "taxista",
          estado: "declinado",
        }),
      };
    } else if (viajeId) {
      await aplicarEstadoIntermedioAzul({
        viajeId,
        pagoAzulId,
        azulOrderId,
        estadoNuevo: "failed",
        lastError:
          parsed.ErrorDescription ||
          parsed.ResponseMessage ||
          "El banco no aprobó el pago.",
      });
    }
    return {
      status: 200,
      html: redirectResultadoHtml({
        titulo: "Pago declinado",
        mensaje: parsed.ErrorDescription || parsed.ResponseMessage || "El banco no aprobó el pago.",
        viajeId: viajeId || undefined,
        rol: "cliente",
        estado: "declinado",
      }),
    };
  }

  if (tipo === "cancel" && pagoAzulId) {
    if (esRecarga && recargaId) {
      await aplicarFalloAzulRecargaTaxista({ recargaId, pagoAzulId, azulOrderId });
      return {
        status: 200,
        html: redirectResultadoHtml({
          titulo: "Pago cancelado",
          mensaje: "Cancelaste el pago. Podés intentar de nuevo desde Mis pagos.",
          recargaId,
          rol: "taxista",
          estado: "cancelado",
        }),
      };
    } else if (viajeId) {
      await aplicarEstadoIntermedioAzul({
        viajeId,
        pagoAzulId,
        azulOrderId,
        estadoNuevo: "failed",
        lastError:
          parsed.ErrorDescription ||
          parsed.ResponseMessage ||
          "El banco no aprobó el pago.",
      });
    }
    return {
      status: 200,
      html: redirectResultadoHtml({
        titulo: "Pago cancelado",
        mensaje: "Cancelaste el pago. Podés intentar de nuevo desde la app.",
        viajeId: viajeId || undefined,
        rol: "cliente",
        estado: "cancelado",
      }),
    };
  }

  const idsFallback = await resolverIdsRecargaAzul({ pago, azulOrderId, rawQuery });
  if (idsFallback.esRecarga) {
    return {
      status: 200,
      html: redirectResultadoHtml({
        titulo: "Pago no completado",
        mensaje: parsed.ResponseMessage || "No se pudo completar el pago.",
        recargaId: idsFallback.recargaId || recargaId || undefined,
        rol: "taxista",
        estado: tipo === "cancel" ? "cancelado" : "declinado",
      }),
    };
  }

  return {
    status: 200,
    html: redirectResultadoHtml({
      titulo: "Pago no completado",
      mensaje: parsed.ResponseMessage || "No se pudo completar el pago.",
      viajeId: viajeId || undefined,
      rol: "cliente",
      estado: tipo === "cancel" ? "cancelado" : "declinado",
    }),
  };
}

export const azulReturnApproved = onRequest({ secrets: azulRuntimeSecrets }, async (req, res) => {
  const { html, status } = await procesarRetornoAzul(req, "approved");
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.status(status).send(html);
});

export const azulReturnDeclined = onRequest({ secrets: azulRuntimeSecrets }, async (req, res) => {
  const { html, status } = await procesarRetornoAzul(req, "declined");
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.status(status).send(html);
});

export const azulReturnCancel = onRequest({ secrets: azulRuntimeSecrets }, async (req, res) => {
  const { html, status } = await procesarRetornoAzul(req, "cancel");
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.status(status).send(html);
});
