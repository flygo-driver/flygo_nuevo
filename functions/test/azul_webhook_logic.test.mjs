import assert from "node:assert/strict";
import test from "node:test";
import {
  buildAzulOrderIdDeterministic,
  buildAzulOrderIdRecargaTaxista,
  debeAplicarTransicionAzul,
  extraerAzulEventId,
  extraerAzulOrderId,
  normalizarEstadoAzul,
  sesionAzulReutilizable,
} from "../lib/azul_webhook_logic.js";

test("normalizarEstadoAzul mapea variantes", () => {
  assert.equal(normalizarEstadoAzul("Approved"), "captured");
  assert.equal(normalizarEstadoAzul("authorised"), "authorized");
  assert.equal(normalizarEstadoAzul("REFUND"), "refunded");
});

test("debeAplicarTransicionAzul respeta orden authorized → captured → refunded", () => {
  assert.equal(debeAplicarTransicionAzul("pending", "authorized").aplicar, true);
  assert.equal(debeAplicarTransicionAzul("authorized", "captured").aplicar, true);
  assert.equal(debeAplicarTransicionAzul("captured", "refunded").aplicar, true);
  assert.equal(debeAplicarTransicionAzul("captured", "authorized").aplicar, false);
  assert.equal(debeAplicarTransicionAzul("authorized", "authorized").aplicar, false);
  assert.equal(debeAplicarTransicionAzul("refunded", "captured").aplicar, false);
});

test("buildAzulOrderIdDeterministic es estable por viaje", () => {
  const a = buildAzulOrderIdDeterministic("viaje123", 50000, false);
  const b = buildAzulOrderIdDeterministic("viaje123", 50000, false);
  assert.equal(a, b);
  assert.match(a, /^AZUL-viaje123-/);
});

test("buildAzulOrderIdRecargaTaxista es estable", () => {
  const a = buildAzulOrderIdRecargaTaxista("rec123", 20000, false);
  const b = buildAzulOrderIdRecargaTaxista("rec123", 20000, false);
  assert.equal(a, b);
  assert.match(a, /^AZUL-REC-/);
});

test("sesionAzulReutilizable incluye pending_configuration", () => {
  assert.equal(sesionAzulReutilizable("pending_configuration"), true);
  assert.equal(sesionAzulReutilizable("captured"), false);
});

test("extraerAzulOrderId y eventId desde body", () => {
  const body = { OrderNumber: "ORD-1", eventId: "evt-99", status: "Captured" };
  assert.equal(extraerAzulOrderId(body), "ORD-1");
  assert.equal(extraerAzulEventId(body, "ORD-1", "captured"), "evt-99");
});

test("extraerMetadatosReciboAzul parsea auth y últimos 4", async () => {
  const { extraerMetadatosReciboAzul } = await import("../lib/azul_webhook_logic.js");
  const meta = extraerMetadatosReciboAzul({
    AuthorizationCode: "OK123456",
    CardBrand: "Visa",
    CardNumber: "************1234",
    RRN: "RRN-9988",
    ResponseCode: "00",
  });
  assert.equal(meta.authorizationCode, "OK123456");
  assert.equal(meta.cardBrand, "Visa");
  assert.equal(meta.cardLast4, "1234");
  assert.equal(meta.rrn, "RRN-9988");
  assert.equal(meta.responseCode, "00");
});
