import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  esElegibleLiquidacionSemanal,
  metodoPagoNormalizado,
  metodoPagoNormalizadoDesde,
} from "../lib/liquidacion_semanal_viaje.js";

describe("liquidacion_semanal_viaje", () => {
  it("normaliza variantes de metodoPago", () => {
    assert.equal(metodoPagoNormalizado("Efectivo"), "efectivo");
    assert.equal(metodoPagoNormalizado("Transferencia bancaria"), "transferencia");
    assert.equal(metodoPagoNormalizado("Tarjeta"), "tarjeta");
  });

  it("efectivo nunca es elegible aunque estadoPago sea pagado", () => {
    assert.equal(
      esElegibleLiquidacionSemanal({
        metodoPagoNormalizado: "efectivo",
        estadoPago: "pagado",
        liquidado: false,
      }),
      false,
    );
  });

  it("transferencia pendiente no es elegible", () => {
    assert.equal(
      esElegibleLiquidacionSemanal({
        metodoPago: "Transferencia",
        estadoPago: "pendiente",
        liquidado: false,
      }),
      false,
    );
  });

  it("transferencia verificada es elegible", () => {
    assert.equal(
      esElegibleLiquidacionSemanal({
        metodoPagoNormalizado: "transferencia",
        estadoPago: "verificado",
        liquidado: false,
      }),
      true,
    );
  });

  it("tarjeta verificada liquidada no es elegible", () => {
    assert.equal(
      esElegibleLiquidacionSemanal({
        metodoPagoNormalizado: "tarjeta",
        estadoPago: "verificado",
        liquidado: true,
      }),
      false,
    );
  });

  it("ignora elegibleLiquidacionSemanal cache si contradice regla", () => {
    assert.equal(
      esElegibleLiquidacionSemanal({
        metodoPagoNormalizado: "efectivo",
        estadoPago: "verificado",
        liquidado: false,
        elegibleLiquidacionSemanal: true,
      }),
      false,
    );
    assert.equal(
      esElegibleLiquidacionSemanal({
        metodoPagoNormalizado: "transferencia",
        estadoPago: "pendiente",
        liquidado: false,
        elegibleLiquidacionSemanal: true,
      }),
      false,
    );
  });

  it("metodoPagoNormalizadoDesde prefiere campo almacenado", () => {
    assert.equal(
      metodoPagoNormalizadoDesde({
        metodoPagoNormalizado: "tarjeta",
        metodoPago: "Efectivo",
      }),
      "tarjeta",
    );
  });
});
