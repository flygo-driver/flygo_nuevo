import test from "node:test";
import assert from "node:assert/strict";
import {
  totalLegsMultiparada,
  esViajeMultiparada,
} from "../lib/multiparada.js";

test("viaje multiparada: total legs = waypoints + destino final", () => {
  const d = {
    waypoints: [
      { lat: 18.48, lon: -69.93, label: "Parada 1" },
      { lat: 18.49, lon: -69.94, label: "Parada 2" },
    ],
    latDestino: 18.5,
    lonDestino: -69.95,
    destino: "Final",
  };
  assert.equal(totalLegsMultiparada(d), 3);
  assert.equal(esViajeMultiparada(d), true);
});

test("viaje sin waypoints no es multiparada operativa", () => {
  const d = {
    latDestino: 18.5,
    lonDestino: -69.95,
    destino: "Solo destino",
  };
  assert.equal(totalLegsMultiparada(d), 0);
  assert.equal(esViajeMultiparada(d), false);
});
