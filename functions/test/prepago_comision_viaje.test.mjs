import test from "node:test";
import assert from "node:assert/strict";
import {
  PREPAGO_INSUFICIENTE_COMISION_VIAJE,
  comisionEstimadaRdDesdeViaje,
  prepagoInsuficienteParaViajeEfectivo,
  viajeEsEfectivoParaComisionPrepago,
} from "../lib/prepago_comision_viaje.js";

test("viajeEsEfectivoParaComisionPrepago", () => {
  assert.equal(viajeEsEfectivoParaComisionPrepago({ metodoPago: "Efectivo" }), true);
  assert.equal(viajeEsEfectivoParaComisionPrepago({ metodoPago: "Transferencia" }), false);
});

test("prepago insuficiente: comisión mayor que saldo", () => {
  const viaje = { metodoPago: "Efectivo", precio: 2000 };
  const bille = {
    primerViajeComisionGratisConsumido: true,
    saldoPrepagoComisionRd: 200,
    comisionPendiente: 0,
  };
  assert.equal(comisionEstimadaRdDesdeViaje(viaje, 18), 360);
  assert.equal(
    prepagoInsuficienteParaViajeEfectivo({
      billeData: bille,
      viajeData: viaje,
      globalComisionPct: 18,
    }),
    true,
  );
});

test("primer viaje efectivo gratis: no exige prepago por comisión", () => {
  const viaje = { metodoPago: "Efectivo", precio: 2000 };
  const bille = { saldoPrepagoComisionRd: 0, comisionPendiente: 0 };
  assert.equal(
    prepagoInsuficienteParaViajeEfectivo({
      billeData: bille,
      viajeData: viaje,
      globalComisionPct: 18,
    }),
    false,
  );
});

test("transferencia: no aplica", () => {
  assert.equal(
    prepagoInsuficienteParaViajeEfectivo({
      billeData: { saldoPrepagoComisionRd: 0, primerViajeComisionGratisConsumido: true },
      viajeData: { metodoPago: "Transferencia", precio: 2000 },
      globalComisionPct: 18,
    }),
    false,
  );
});

test("código de error exportado", () => {
  assert.equal(PREPAGO_INSUFICIENTE_COMISION_VIAJE, "prepago-insuficiente-comision-viaje");
});
