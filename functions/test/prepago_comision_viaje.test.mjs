import test from "node:test";
import assert from "node:assert/strict";
import {
  PREPAGO_INSUFICIENTE_COMISION_VIAJE,
  comisionEstimadaRdDesdeViaje,
  prepagoInsuficienteParaViajeEfectivo,
  viajeAplicaComisionPrepago,
  viajeEsEfectivoParaComisionPrepago,
} from "../lib/prepago_comision_viaje.js";

test("viajeAplicaComisionPrepago — métodos RAI estándar", () => {
  assert.equal(viajeAplicaComisionPrepago({ metodoPago: "Efectivo" }), true);
  assert.equal(viajeAplicaComisionPrepago({ metodoPago: "Transferencia" }), true);
  assert.equal(viajeAplicaComisionPrepago({ metodoPago: "Tarjeta" }), true);
  assert.equal(viajeAplicaComisionPrepago({ metodoPago: "" }), true);
});

test("viajeAplicaComisionPrepago — exclusiones", () => {
  assert.equal(
    viajeAplicaComisionPrepago({ tipoServicio: "bola_ahorro", metodoPago: "Efectivo" }),
    false,
  );
  assert.equal(
    viajeAplicaComisionPrepago({ recaudoCentral: true, metodoPago: "Efectivo" }),
    true,
    "giras recaudo central: comisión igual del prepago del taxista",
  );
});

test("viajeEsEfectivoParaComisionPrepago delega al modelo unificado", () => {
  assert.equal(viajeEsEfectivoParaComisionPrepago({ metodoPago: "Transferencia" }), true);
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

test("prepago parcial permitido: no bloquea aunque comisión > saldo", () => {
  const viaje = { metodoPago: "Efectivo", precio: 2000 };
  const bille = {
    primerViajeComisionGratisConsumido: true,
    saldoPrepagoComisionRd: 200,
    comisionPendiente: 0,
  };
  assert.equal(
    prepagoInsuficienteParaViajeEfectivo({
      billeData: bille,
      viajeData: viaje,
      globalComisionPct: 18,
      permitirViajeConPrepagoParcial: true,
    }),
    false,
  );
});

test("primer viaje gratis: no exige prepago por comisión", () => {
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

test("transferencia: aplica prepago igual que efectivo", () => {
  assert.equal(
    prepagoInsuficienteParaViajeEfectivo({
      billeData: { saldoPrepagoComisionRd: 0, primerViajeComisionGratisConsumido: true },
      viajeData: { metodoPago: "Transferencia", precio: 2000 },
      globalComisionPct: 18,
    }),
    true,
  );
});

test("código de error exportado", () => {
  assert.equal(PREPAGO_INSUFICIENTE_COMISION_VIAJE, "prepago-insuficiente-comision-viaje");
});
