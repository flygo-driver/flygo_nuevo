import assert from "node:assert/strict";
import test from "node:test";
import {
  esReferenciaRecaudoValida,
  generarReferenciaRecaudoViaje,
} from "../lib/viaje_referencia.js";

test("generarReferenciaRecaudoViaje formato RAI-V", () => {
  const ref = generarReferenciaRecaudoViaje("abc123xyz789");
  assert.match(ref, /^RAI-V-[A-Z0-9]{1,8}-[0-9A-F]{2}$/);
  assert.equal(ref.startsWith("RAI-V-ABC123XY-"), true);
});

test("generarReferenciaRecaudoViaje idempotente", () => {
  const id = "viaje_test_001";
  assert.equal(generarReferenciaRecaudoViaje(id), generarReferenciaRecaudoViaje(id));
});

test("esReferenciaRecaudoValida rechaza vacío y basura", () => {
  assert.equal(esReferenciaRecaudoValida(""), false);
  assert.equal(esReferenciaRecaudoValida("RAI-POOL-123"), false);
  assert.equal(esReferenciaRecaudoValida(generarReferenciaRecaudoViaje("x")), true);
});

test("generarReferenciaRecaudoViaje rechaza id vacío", () => {
  assert.throws(() => generarReferenciaRecaudoViaje(""), /viajeId vacío/);
});
