import assert from "node:assert/strict";
import test from "node:test";
import {
  buildAzulOrderIdDeterministic,
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

test("sesionAzulReutilizable incluye pending_configuration", () => {
  assert.equal(sesionAzulReutilizable("pending_configuration"), true);
  assert.equal(sesionAzulReutilizable("captured"), false);
});

test("extraerAzulOrderId y eventId desde body", () => {
  const body = { OrderNumber: "ORD-1", eventId: "evt-99", status: "Captured" };
  assert.equal(extraerAzulOrderId(body), "ORD-1");
  assert.equal(extraerAzulEventId(body, "ORD-1", "captured"), "evt-99");
});
