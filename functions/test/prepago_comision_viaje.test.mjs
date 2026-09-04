import test from "node:test";
import assert from "node:assert/strict";
import {
  PREPAGO_INSUFICIENTE_COMISION_VIAJE,
  comisionEstimadaRdDesdeViaje,
  prepagoInsuficienteParaViajeEfectivo,
  viajeAplicaComisionPrepago,
  viajeEsEfectivoParaComisionPrepago,
  viajeRecaudoEnCuentaRai,
} from "../lib/prepago_comision_viaje.js";

test("viajeAplicaComisionPrepago — efectivo y transferencia P2P al conductor", () => {
  assert.equal(viajeAplicaComisionPrepago({ metodoPago: "Efectivo" }), true);
  assert.equal(viajeAplicaComisionPrepago({ metodoPago: "Transferencia" }), true);
  assert.equal(viajeAplicaComisionPrepago({ metodoPago: "Tarjeta" }), false);
  assert.equal(viajeAplicaComisionPrepago({ metodoPago: "" }), true);
});

test("viajeAplicaComisionPrepago — tarjeta / recaudo RAI → liquidación semanal", () => {
  assert.equal(
    viajeAplicaComisionPrepago({
      metodoPago: "Transferencia",
      recaudoDestino: "rai",
    }),
    false,
  );
  assert.equal(
    viajeAplicaComisionPrepago({
      metodoPago: "Transferencia",
      referenciaRecaudo: "REF-123",
    }),
    false,
  );
  assert.equal(viajeRecaudoEnCuentaRai({ recaudoDestino: "rai" }), true);
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

test("viajeEsEfectivoParaComisionPrepago — alias efectivo + transferencia", () => {
  assert.equal(viajeEsEfectivoParaComisionPrepago({ metodoPago: "Transferencia" }), true);
  assert.equal(viajeEsEfectivoParaComisionPrepago({ metodoPago: "Efectivo" }), true);
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

test("turismo: aceptar sin prepago completo (cobro al finalizar viaje)", () => {
  const viaje = { tipoServicio: "turismo", metodoPago: "Efectivo", precio: 2000 };
  const bille = {
    primerViajeComisionGratisConsumido: true,
    saldoPrepagoComisionRd: 20,
    comisionPendiente: 0,
  };
  assert.equal(
    prepagoInsuficienteParaViajeEfectivo({
      billeData: bille,
      viajeData: viaje,
      globalComisionPct: 18,
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

test("transferencia P2P: exige prepago igual que efectivo", () => {
  assert.equal(
    prepagoInsuficienteParaViajeEfectivo({
      billeData: { saldoPrepagoComisionRd: 0, primerViajeComisionGratisConsumido: true },
      viajeData: { metodoPago: "Transferencia", precio: 2000 },
      globalComisionPct: 18,
    }),
    true,
  );
});

test("tarjeta: no exige prepago (liquidación semanal)", () => {
  assert.equal(
    prepagoInsuficienteParaViajeEfectivo({
      billeData: { saldoPrepagoComisionRd: 0, primerViajeComisionGratisConsumido: true },
      viajeData: { metodoPago: "Tarjeta", precio: 2000 },
      globalComisionPct: 18,
    }),
    false,
  );
});

test("transferencia a cuenta RAI: no exige prepago", () => {
  assert.equal(
    prepagoInsuficienteParaViajeEfectivo({
      billeData: { saldoPrepagoComisionRd: 0, primerViajeComisionGratisConsumido: true },
      viajeData: {
        metodoPago: "Transferencia",
        precio: 2000,
        recaudoDestino: "rai",
      },
      globalComisionPct: 18,
    }),
    false,
  );
});

test("código de error exportado", () => {
  assert.equal(PREPAGO_INSUFICIENTE_COMISION_VIAJE, "prepago-insuficiente-comision-viaje");
});
