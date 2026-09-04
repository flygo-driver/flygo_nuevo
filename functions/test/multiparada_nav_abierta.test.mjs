import test from "node:test";
import assert from "node:assert/strict";
import {
  multiparadaParadasAbiertasSet,
  multiparadaRecogidaAbierta,
} from "../lib/multiparada.js";

test("multiparada: visitadas cuentan como abiertas (compatibilidad)", () => {
  const d = {
    multiparadaParadasAbiertas: [1],
    multiparadaParadasVisitadas: [{ legIndex: 0 }],
    waypoints: [{ lat: 1, lon: 1 }, { lat: 2, lon: 2 }],
    latDestino: 3,
    lonDestino: 3,
  };
  const abiertas = multiparadaParadasAbiertasSet(d, 3);
  assert.equal(abiertas.has(0), true);
  assert.equal(abiertas.has(1), true);
  assert.equal(abiertas.has(2), false);
});

test("multiparada: recogida abierta por pickup confirmado", () => {
  assert.equal(
    multiparadaRecogidaAbierta({ multiparadaRecogidaAbierta: true }),
    true,
  );
  assert.equal(
    multiparadaRecogidaAbierta({ clienteAbordo: true }),
    true,
  );
  assert.equal(multiparadaRecogidaAbierta({}), false);
});
