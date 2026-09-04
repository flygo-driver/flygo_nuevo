// El pool no separa por subtipo de vehículo: un Carro puede tomar un viaje
// pedido como Jeepeta. Cuando eso pasa el cliente debe pagar la tarifa del
// vehículo que de verdad lo recoge, nunca más de lo que aceptó al pedir.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

import {
  PISO_AJUSTE_PRECIO_VEHICULO,
  ajustePrecioPorVehiculoAsignado,
  normalizarTipoVehiculo,
} from "../lib/viaje_precio_tipo_vehiculo.js";

const aquí = path.dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(path.join(aquí, "..", "..", "firestore.rules"), "utf8");

// 10 km: Carro 50+22·10=270, Jeepeta 80+30·10=380, Minivan 100+32·10=420.
const MAPA_10KM = {
  Carro: 27000,
  Jeepeta: 38000,
  Minivan: 42000,
  Minibús: 47000,
  AutobusGuagua: 65000,
};

test("normaliza los nombres que escriben app y perfiles de chofer", () => {
  assert.equal(normalizarTipoVehiculo("jeepeta"), "Jeepeta");
  assert.equal(normalizarTipoVehiculo("  JEEPETA "), "Jeepeta");
  assert.equal(normalizarTipoVehiculo("Carro"), "Carro");
  assert.equal(normalizarTipoVehiculo("Minibus"), "Minibús");
  assert.equal(normalizarTipoVehiculo("Guagua"), "AutobusGuagua");
  assert.equal(normalizarTipoVehiculo("Autobús"), "AutobusGuagua");
  assert.equal(normalizarTipoVehiculo("Motor"), "motor");
  assert.equal(normalizarTipoVehiculo(""), "");
  assert.equal(normalizarTipoVehiculo(null), "");
});

test("pidió Jeepeta y llegó un Carro: paga la tarifa del Carro", () => {
  const r = ajustePrecioPorVehiculoAsignado({
    tipoSolicitado: "Jeepeta",
    tipoAsignado: "carro",
    precioAcordadoCents: 38000,
    preciosPorTipo: MAPA_10KM,
  });
  assert.ok(r);
  assert.equal(r.cents, 27000);
  assert.equal(r.tipoSolicitado, "Jeepeta");
  assert.equal(r.tipoAsignado, "Carro");
});

test("mismo tipo pedido: no toca el precio", () => {
  assert.equal(
    ajustePrecioPorVehiculoAsignado({
      tipoSolicitado: "Carro",
      tipoAsignado: "CARRO",
      precioAcordadoCents: 27000,
      preciosPorTipo: MAPA_10KM,
    }),
    null,
  );
});

test("llega un vehículo más caro: el cliente NO paga de más", () => {
  assert.equal(
    ajustePrecioPorVehiculoAsignado({
      tipoSolicitado: "Carro",
      tipoAsignado: "Minivan",
      precioAcordadoCents: 27000,
      preciosPorTipo: MAPA_10KM,
    }),
    null,
  );
});

test("sin mapa de precios no inventa nada", () => {
  for (const mapa of [null, undefined, {}, { Carro: "270" }, { Carro: NaN }]) {
    assert.equal(
      ajustePrecioPorVehiculoAsignado({
        tipoSolicitado: "Jeepeta",
        tipoAsignado: "Carro",
        precioAcordadoCents: 38000,
        preciosPorTipo: mapa,
      }),
      null,
    );
  }
});

test("respeta el piso aunque el mapa venga corrupto o manipulado", () => {
  const r = ajustePrecioPorVehiculoAsignado({
    tipoSolicitado: "Jeepeta",
    tipoAsignado: "Carro",
    precioAcordadoCents: 38000,
    preciosPorTipo: { ...MAPA_10KM, Carro: 1 },
  });
  assert.ok(r);
  assert.equal(r.cents, Math.round(38000 * PISO_AJUSTE_PRECIO_VEHICULO));
});

test("precio acordado inválido: no ajusta", () => {
  for (const precio of [0, -100, NaN, null, "380"]) {
    assert.equal(
      ajustePrecioPorVehiculoAsignado({
        tipoSolicitado: "Jeepeta",
        tipoAsignado: "Carro",
        precioAcordadoCents: precio,
        preciosPorTipo: MAPA_10KM,
      }),
      null,
    );
  }
});

test("motor y turismo quedan fuera del ajuste", () => {
  assert.equal(
    ajustePrecioPorVehiculoAsignado({
      tipoSolicitado: "Carro",
      tipoAsignado: "Motor",
      precioAcordadoCents: 27000,
      preciosPorTipo: { ...MAPA_10KM, motor: 8000 },
    }),
    null,
  );
});

test("las reglas blindan la tarifa por tipo contra escrituras de la app", () => {
  for (const campo of [
    "tipoVehiculoSolicitado",
    "preciosPorTipoVehiculoCents",
    "precioAjustadoPorVehiculo",
    "precioAntesAjusteVehiculoCents",
  ]) {
    assert.ok(
      rules.includes(`"${campo}"`),
      `falta ${campo} en viajeCamposFinancierosProtegidos`,
    );
  }
});
