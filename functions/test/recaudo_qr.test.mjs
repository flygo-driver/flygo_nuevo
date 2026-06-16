import assert from "node:assert/strict";
import test from "node:test";
import { buildQrRecaudoPayloadStub } from "../lib/recaudo_qr.js";

test("buildQrRecaudoPayloadStub incluye ref y monto", () => {
  const { payload, tipo, version } = buildQrRecaudoPayloadStub({
    referenciaRecaudo: "RAI-V-ABC12345-7F",
    montoCents: 125000,
    viajeId: "viaje_test_123",
  });
  assert.equal(version, "1");
  assert.equal(tipo, "popular_stub_v1");
  assert.match(payload, /RAI-RECAUDO/);
  assert.match(payload, /ref=RAI-V-ABC12345-7F/);
  assert.match(payload, /amt=1250\.00/);
});
