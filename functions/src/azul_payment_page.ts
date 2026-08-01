/**
 * Página de Pago AZUL — AuthHash HMAC-SHA512 (UTF-16 LE) y formulario POST.
 * @see docs/azul/PAGINA_DE_PAGO_RESUMEN.md
 */
import { createHmac, timingSafeEqual } from "node:crypto";

export type AzulEnvironment = "sandbox" | "production";

export type AzulPaymentFormInput = {
  merchantId: string;
  merchantName: string;
  orderNumber: string;
  amountCents: number;
  itbisCents?: number;
  approvedUrl: string;
  declinedUrl: string;
  cancelUrl: string;
  customField1Value?: string;
};

export type AzulPaymentFormFields = {
  MerchantId: string;
  MerchantName: string;
  MerchantType: string;
  CurrencyCode: string;
  OrderNumber: string;
  Amount: string;
  ITBIS: string;
  ApprovedUrl: string;
  DeclinedUrl: string;
  CancelUrl: string;
  UseCustomField1: string;
  CustomField1Label: string;
  CustomField1Value: string;
  UseCustomField2: string;
  CustomField2Label: string;
  CustomField2Value: string;
  AuthHash: string;
};

/** Monto AZUL: centavos enteros sin separador (15000 = RD$150.00). */
export function formatAzulAmountCents(cents: number): string {
  const n = Math.max(0, Math.round(cents));
  return String(n);
}

/**
 * ITBIS AZUL: mismo formato que Amount.
 * Transporte exento → "000" (no "0"); manual AZUL Payment Page.
 */
export function formatAzulItbisCents(cents: number): string {
  const n = Math.max(0, Math.round(cents));
  if (n === 0) return "000";
  return String(n);
}

export function azulPaymentPageActionUrl(environment: AzulEnvironment): string {
  return environment === "production"
    ? "https://pagos.azul.com.do/PaymentPage/Default.aspx"
    : "https://pruebas.azul.com.do/PaymentPage/Default.aspx";
}

export function cloudFunctionsBaseUrl(projectId = "flygo-rd", region = "us-central1"): string {
  return `https://${region}-${projectId}.cloudfunctions.net`;
}

export function azulReturnUrls(projectId = "flygo-rd", region = "us-central1"): {
  approvedUrl: string;
  declinedUrl: string;
  cancelUrl: string;
} {
  const base = cloudFunctionsBaseUrl(projectId, region);
  return {
    approvedUrl: `${base}/azulReturnApproved`,
    declinedUrl: `${base}/azulReturnDeclined`,
    cancelUrl: `${base}/azulReturnCancel`,
  };
}

function utf16LeBuffer(text: string): Buffer {
  return Buffer.from(text, "utf16le");
}

/** Hash solicitud (ida a Payment Page). */
export function computeAzulAuthHashRequest(
  fields: Omit<AzulPaymentFormFields, "AuthHash">,
  authKey: string,
): string {
  const concat =
    fields.MerchantId +
    fields.MerchantName +
    fields.MerchantType +
    fields.CurrencyCode +
    fields.OrderNumber +
    fields.Amount +
    fields.ITBIS +
    fields.ApprovedUrl +
    fields.DeclinedUrl +
    fields.CancelUrl +
    fields.UseCustomField1 +
    fields.CustomField1Label +
    fields.CustomField1Value +
    fields.UseCustomField2 +
    fields.CustomField2Label +
    fields.CustomField2Value +
    authKey;
  return createHmac("sha512", authKey).update(utf16LeBuffer(concat)).digest("hex");
}

export type AzulReturnQuery = {
  OrderNumber: string;
  Amount: string;
  AuthorizationCode: string;
  DateTime: string;
  ResponseCode: string;
  IsoCode: string;
  ResponseMessage: string;
  ErrorDescription: string;
  RRN: string;
  AuthHash: string;
};

export function parseAzulReturnQuery(raw: Record<string, unknown>): AzulReturnQuery {
  const pick = (...keys: string[]): string => {
    for (const k of keys) {
      const v = raw[k];
      if (v !== undefined && v !== null && String(v).trim() !== "") {
        return String(v).trim();
      }
    }
    return "";
  };
  return {
    OrderNumber: pick("OrderNumber", "orderNumber"),
    Amount: pick("Amount", "amount"),
    AuthorizationCode: pick("AuthorizationCode", "authorizationCode", "AuthCode"),
    DateTime: pick("DateTime", "dateTime"),
    ResponseCode: pick("ResponseCode", "responseCode"),
    IsoCode: pick("IsoCode", "isoCode", "ISOCode"),
    ResponseMessage: pick("ResponseMessage", "responseMessage"),
    ErrorDescription: pick("ErrorDescription", "errorDescription"),
    RRN: pick("RRN", "rrn"),
    AuthHash: pick("AuthHash", "authHash"),
  };
}

/** Hash respuesta (redirect Approved/Declined/Cancel). */
export function computeAzulAuthHashResponse(query: AzulReturnQuery, authKey: string): string {
  const concat =
    query.OrderNumber +
    query.Amount +
    query.AuthorizationCode +
    query.DateTime +
    query.ResponseCode +
    query.IsoCode +
    query.ResponseMessage +
    query.ErrorDescription +
    query.RRN +
    authKey;
  return createHmac("sha512", authKey).update(utf16LeBuffer(concat)).digest("hex");
}

export function verifyAzulAuthHashResponse(query: AzulReturnQuery, authKey: string): boolean {
  const received = query.AuthHash.trim().toLowerCase();
  if (!received) return false;
  const expected = computeAzulAuthHashResponse(query, authKey).toLowerCase();
  try {
    const a = Buffer.from(expected, "utf8");
    const b = Buffer.from(received, "utf8");
    if (a.length !== b.length) return false;
    return timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

export function azulReturnIsoAprobado(isoCode: string, responseMessage: string): boolean {
  const iso = isoCode.trim();
  if (iso === "00") return true;
  const msg = responseMessage.trim().toUpperCase();
  return msg === "APROBADA" || msg === "APPROVED";
}

export function buildAzulPaymentFormFields(
  input: AzulPaymentFormInput,
  authKey: string,
  projectId = "flygo-rd",
  region = "us-central1",
): AzulPaymentFormFields {
  const urls = azulReturnUrls(projectId, region);
  const customValue = String(input.customField1Value ?? "").trim();
  const useCustom1 = customValue.length > 0 ? "1" : "0";
  const base: Omit<AzulPaymentFormFields, "AuthHash"> = {
    MerchantId: input.merchantId,
    MerchantName: input.merchantName,
    MerchantType: "ECommerce",
    CurrencyCode: "$",
    OrderNumber: input.orderNumber,
    Amount: formatAzulAmountCents(input.amountCents),
    ITBIS: formatAzulItbisCents(input.itbisCents ?? 0),
    ApprovedUrl: input.approvedUrl || urls.approvedUrl,
    DeclinedUrl: input.declinedUrl || urls.declinedUrl,
    CancelUrl: input.cancelUrl || urls.cancelUrl,
    UseCustomField1: useCustom1,
    CustomField1Label: useCustom1 === "1" ? "viajeId" : "",
    CustomField1Value: customValue,
    UseCustomField2: "0",
    CustomField2Label: "",
    CustomField2Value: "",
  };
  const AuthHash = computeAzulAuthHashRequest(base, authKey);
  return { ...base, AuthHash };
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** URL GET en Cloud Functions → HTML auto-POST a AZUL (desde app vía navegador). */
export function buildAzulPaymentLaunchUrl(azulOrderId: string): string {
  const base = cloudFunctionsBaseUrl();
  return `${base}/azulPaymentLaunch?order=${encodeURIComponent(azulOrderId)}`;
}

export function buildAzulAutoPostHtml(
  actionUrl: string,
  fields: AzulPaymentFormFields,
): string {
  const inputs = Object.entries(fields)
    .map(
      ([name, value]) =>
        `<input type="hidden" name="${escapeHtml(name)}" value="${escapeHtml(String(value))}" />`,
    )
    .join("\n");
  return `<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Redirigiendo a AZUL…</title>
  <style>
    body{font-family:system-ui,sans-serif;background:#0d1117;color:#e6edf3;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:24px;text-align:center}
    .box{max-width:360px}
    h1{font-size:1.1rem;margin:0 0 8px;color:#7ee787}
    p{margin:0;font-size:0.9rem;color:#8b949e;line-height:1.45}
  </style>
</head>
<body onload="document.getElementById('azulPay').submit()">
  <div class="box">
    <h1>RAI Driver · AZUL</h1>
    <p>Conectando con la pasarela segura de pago…</p>
    <p style="margin-top:12px;font-size:0.8rem">Si no avanza, tocá Continuar.</p>
    <form id="azulPay" method="post" action="${escapeHtml(actionUrl)}">
      ${inputs}
      <noscript><button type="submit">Continuar al pago</button></noscript>
    </form>
  </div>
</body>
</html>`;
}
