import assert from "node:assert/strict";
import test from "node:test";
import {
  debeAutoConfirmarPoolConciliacion,
  evaluarMatchConciliacionViaje,
  precioCentsViaje,
} from "../lib/conciliacion.js";
import { generarReferenciaRecaudoViaje } from "../lib/viaje_referencia.js";
import { generarReferenciaRecaudoPool } from "../lib/pool_referencia.js";

test("precioCentsViaje prefiere precio_cents", () => {
  assert.equal(precioCentsViaje({ precio_cents: 125000, precio: 1 }), 125000);
  assert.equal(precioCentsViaje({ precio: 500.5 }), 50050);
});

test("evaluarMatchConciliacionViaje ref+monto exacto", () => {
  const ref = generarReferenciaRecaudoViaje("viaje_abc_001");
  const r = evaluarMatchConciliacionViaje({
    referenciaMovimiento: ref,
    montoMovimientoCents: 50000,
    referenciaViaje: ref,
    montoViajeCents: 50000,
  });
  assert.equal(r.ok, true);
  assert.deepEqual(r.matchReglas, ["ref_exacta", "monto_exacto"]);
  assert.equal(r.matchScore, 1);
});

test("evaluarMatchConciliacionViaje ref ok monto distinto", () => {
  const ref = generarReferenciaRecaudoViaje("viaje_abc_002");
  const r = evaluarMatchConciliacionViaje({
    referenciaMovimiento: ref,
    montoMovimientoCents: 51000,
    referenciaViaje: ref,
    montoViajeCents: 50000,
  });
  assert.equal(r.ok, true);
  assert.ok(r.matchReglas.includes("monto_discrepancia"));
  assert.equal(r.diferenciaCents, 1000);
});

test("evaluarMatchConciliacionViaje rechaza ref distinta", () => {
  const r = evaluarMatchConciliacionViaje({
    referenciaMovimiento: generarReferenciaRecaudoViaje("a"),
    montoMovimientoCents: 50000,
    referenciaViaje: generarReferenciaRecaudoViaje("b"),
    montoViajeCents: 50000,
  });
  assert.equal(r.ok, false);
});

test("debeAutoConfirmarPoolConciliacion solo RAI-P monto exacto con flags", () => {
  const flagsOn = {
    conciliacionAutomaticaHabilitada: true,
    poolRecaudoAutoVerificarConciliacion: true,
  };
  const ref = generarReferenciaRecaudoPool("pool1", "res1");
  const match = evaluarMatchConciliacionViaje({
    referenciaMovimiento: ref,
    montoMovimientoCents: 200000,
    referenciaViaje: ref,
    montoViajeCents: 200000,
  });
  assert.equal(debeAutoConfirmarPoolConciliacion(match.matchReglas, flagsOn), true);
  assert.equal(
    debeAutoConfirmarPoolConciliacion(match.matchReglas, {
      ...flagsOn,
      poolRecaudoAutoVerificarConciliacion: false,
    }),
    false,
  );
  assert.equal(
    debeAutoConfirmarPoolConciliacion(
      ["ref_exacta", "monto_discrepancia"],
      flagsOn,
    ),
    false,
  );
});
