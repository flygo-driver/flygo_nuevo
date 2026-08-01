import assert from "node:assert/strict";
import test from "node:test";
import {
  azulPaymentPageActionUrl,
  azulReturnIsoAprobado,
  buildAzulAutoPostHtml,
  buildAzulPaymentFormFields,
  buildAzulPaymentLaunchUrl,
  computeAzulAuthHashRequest,
  computeAzulAuthHashResponse,
  formatAzulAmountCents,
  formatAzulItbisCents,
  parseAzulReturnQuery,
  verifyAzulAuthHashResponse,
} from "../lib/azul_payment_page.js";

const TEST_AUTH_KEY = "test-auth-key-12345";

test("formatAzulAmountCents sin decimales", () => {
  assert.equal(formatAzulAmountCents(15000), "15000");
  assert.equal(formatAzulAmountCents(0), "0");
});

test("formatAzulItbisCents exento usa 000", () => {
  assert.equal(formatAzulItbisCents(0), "000");
  assert.equal(formatAzulItbisCents(2057), "2057");
});

test("azulPaymentPageActionUrl sandbox vs production", () => {
  assert.match(azulPaymentPageActionUrl("sandbox"), /pruebas\.azul\.com\.do/);
  assert.match(azulPaymentPageActionUrl("production"), /pagos\.azul\.com\.do/);
});

test("buildAzulPaymentLaunchUrl incluye order", () => {
  const url = buildAzulPaymentLaunchUrl("ORD-ABC");
  assert.match(url, /azulPaymentLaunch/);
  assert.match(url, /order=ORD-ABC/);
});

test("buildAzulPaymentFormFields genera AuthHash y URLs de retorno", () => {
  const fields = buildAzulPaymentFormFields(
    {
      merchantId: "99999999999",
      merchantName: "Comercio prueba",
      orderNumber: "ORD-1",
      amountCents: 50000,
      itbisCents: 0,
      approvedUrl: "",
      declinedUrl: "",
      cancelUrl: "",
      customField1Value: "viaje_xyz",
    },
    TEST_AUTH_KEY,
  );
  assert.equal(fields.MerchantId, "99999999999");
  assert.equal(fields.Amount, "50000");
  assert.equal(fields.ITBIS, "000");
  assert.equal(fields.UseCustomField1, "1");
  assert.equal(fields.CustomField1Value, "viaje_xyz");
  assert.match(fields.ApprovedUrl, /azulReturnApproved/);
  assert.ok(fields.AuthHash.length > 20);
});

test("AuthHash request es determinístico", () => {
  const base = {
    MerchantId: "1",
    MerchantName: "Test",
    MerchantType: "ECommerce",
    CurrencyCode: "$",
    OrderNumber: "O1",
    Amount: "100",
    ITBIS: "000",
    ApprovedUrl: "https://example.com/ok",
    DeclinedUrl: "https://example.com/no",
    CancelUrl: "https://example.com/cancel",
    UseCustomField1: "0",
    CustomField1Label: "",
    CustomField1Value: "",
    UseCustomField2: "0",
    CustomField2Label: "",
    CustomField2Value: "",
  };
  const a = computeAzulAuthHashRequest(base, TEST_AUTH_KEY);
  const b = computeAzulAuthHashRequest(base, TEST_AUTH_KEY);
  assert.equal(a, b);
  assert.notEqual(a, computeAzulAuthHashRequest(base, "otra-key"));
});

test("verifyAzulAuthHashResponse valida hash de retorno", () => {
  const query = {
    OrderNumber: "ORD-9",
    Amount: "25000",
    AuthorizationCode: "OK123",
    DateTime: "2026-07-18 12:00:00",
    ResponseCode: "1",
    IsoCode: "00",
    ResponseMessage: "APROBADA",
    ErrorDescription: "",
    RRN: "RRN-1",
    AuthHash: "",
  };
  query.AuthHash = computeAzulAuthHashResponse(query, TEST_AUTH_KEY);
  assert.equal(verifyAzulAuthHashResponse(query, TEST_AUTH_KEY), true);
  assert.equal(verifyAzulAuthHashResponse({ ...query, AuthHash: "bad" }, TEST_AUTH_KEY), false);
});

test("parseAzulReturnQuery acepta variantes de claves", () => {
  const q = parseAzulReturnQuery({
    orderNumber: "X1",
    isoCode: "00",
    authorizationCode: "AUTH",
  });
  assert.equal(q.OrderNumber, "X1");
  assert.equal(q.IsoCode, "00");
  assert.equal(q.AuthorizationCode, "AUTH");
});

test("azulReturnIsoAprobado", () => {
  assert.equal(azulReturnIsoAprobado("00", ""), true);
  assert.equal(azulReturnIsoAprobado("", "APROBADA"), true);
  assert.equal(azulReturnIsoAprobado("05", "DECLINADA"), false);
});

test("buildAzulAutoPostHtml incluye form POST", () => {
  const html = buildAzulAutoPostHtml("https://pruebas.azul.com.do/PaymentPage/", {
    MerchantId: "1",
    MerchantName: "T",
    MerchantType: "ECommerce",
    CurrencyCode: "$",
    OrderNumber: "O",
    Amount: "100",
    ITBIS: "000",
    ApprovedUrl: "https://a",
    DeclinedUrl: "https://d",
    CancelUrl: "https://c",
    UseCustomField1: "0",
    CustomField1Label: "",
    CustomField1Value: "",
    UseCustomField2: "0",
    CustomField2Label: "",
    CustomField2Value: "",
    AuthHash: "abc",
  });
  assert.match(html, /method="post"/i);
  assert.match(html, /name="MerchantId"/);
  assert.match(html, /action="https:\/\/pruebas\.azul\.com\.do/);
});
