// Ida y vuelta: el cliente paga ×1.8 por el regreso. Si el regreso no se hace,
// el viaje tiene que cobrarse como solo ida.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

import {
  FACTOR_IDA_Y_VUELTA,
  precioSoloIdaCents,
} from "../lib/viaje_ida_vuelta.js";

const aquí = path.dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(path.join(aquí, "..", "..", "firestore.rules"), "utf8");

test("usa el precio de solo ida guardado al crear el viaje", () => {
  assert.equal(
    precioSoloIdaCents({
      precioActualCents: 54000,
      precioSoloIdaGuardadoCents: 30000,
    }),
    30000,
  );
});

test("sin valor guardado deshace el recargo del regreso", () => {
  const idaVuelta = Math.round(30000 * FACTOR_IDA_Y_VUELTA);
  assert.equal(
    precioSoloIdaCents({
      precioActualCents: idaVuelta,
      precioSoloIdaGuardadoCents: null,
    }),
    30000,
  );
});

test("no devuelve nada si el guardado no baja el precio", () => {
  for (const guardado of [54000, 60000, 0, -1]) {
    const r = precioSoloIdaCents({
      precioActualCents: 54000,
      precioSoloIdaGuardadoCents: guardado,
    });
    // Con guardado inválido cae al ÷1.8, que sí baja.
    if (guardado > 0 && guardado < 54000) continue;
    if (guardado <= 0) {
      assert.equal(r, Math.round(54000 / FACTOR_IDA_Y_VUELTA));
    } else {
      assert.equal(r, null);
    }
  }
});

test("precio inválido no genera devoluciones", () => {
  for (const precio of [0, -500, NaN, null, undefined]) {
    assert.equal(
      precioSoloIdaCents({
        precioActualCents: precio,
        precioSoloIdaGuardadoCents: 30000,
      }),
      null,
    );
  }
});

test("viaje gratis por promo no se toca", () => {
  assert.equal(
    precioSoloIdaCents({
      precioActualCents: 0,
      precioSoloIdaGuardadoCents: 0,
    }),
    null,
  );
});

test("las reglas impiden que la app mueva el tramo de regreso", () => {
  for (const campo of [
    "precioSoloIdaCents",
    "regresoPendiente",
    "regresoEnCurso",
    "regresoNoRealizado",
  ]) {
    assert.ok(
      rules.includes(`"${campo}"`),
      `falta ${campo} en viajeCamposFinancierosProtegidos`,
    );
  }
});
