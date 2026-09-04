import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { prepagoInsuficienteParaViajeEfectivo } from "../lib/prepago_comision_viaje.js";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

const billeteraSinSaldo = {
  primerViajeComisionGratisConsumido: true,
  saldoPrepagoComisionRd: 20,
  comisionPendiente: 0,
};
const viajeEfectivo = {
  tipoServicio: "normal",
  metodoPago: "Efectivo",
  precio: 1000,
};

test("sin flag explícito el prepago se evalúa estricto", () => {
  assert.equal(
    prepagoInsuficienteParaViajeEfectivo({
      billeData: billeteraSinSaldo,
      viajeData: viajeEfectivo,
      globalComisionPct: 20,
    }),
    true,
    "RD$20 de prepago no cubre RD$200 de comisión: debe rechazar",
  );
});

test("multiparada y motor heredan la misma exigencia de prepago", () => {
  for (const viaje of [
    { ...viajeEfectivo, waypoints: [{ orden: 1 }, { orden: 2 }] },
    { ...viajeEfectivo, tipoServicio: "motor" },
    { ...viajeEfectivo, programado: true },
  ]) {
    assert.equal(
      prepagoInsuficienteParaViajeEfectivo({
        billeData: billeteraSinSaldo,
        viajeData: viaje,
        globalComisionPct: 20,
      }),
      true,
    );
  }
});

test("bola y corporativo siguen exentos del prepago por viaje", () => {
  for (const viaje of [
    { ...viajeEfectivo, tipoServicio: "bola_ahorro" },
    { ...viajeEfectivo, corporativo: true },
    { ...viajeEfectivo, categoria: "corporativo" },
  ]) {
    assert.equal(
      prepagoInsuficienteParaViajeEfectivo({
        billeData: billeteraSinSaldo,
        viajeData: viaje,
        globalComisionPct: 20,
      }),
      false,
    );
  }
});

test("config y app arrancan en modo estricto", () => {
  const finance = readFileSync(
    join(repoRoot, "functions", "src", "finance.ts"),
    "utf8",
  );
  assert.ok(
    finance.includes("data.permitirViajeConPrepagoParcial === true"),
    "getComisionPrepagoConfig debe exigir true explícito",
  );
  assert.ok(
    !finance.includes("data.permitirViajeConPrepagoParcial !== false"),
    "el default permisivo debe estar eliminado",
  );

  const dart = readFileSync(
    join(repoRoot, "lib", "servicios", "comision_prepago_config_service.dart"),
    "utf8",
  );
  assert.ok(dart.includes("permitirViajeConPrepagoParcial = false;"));
  assert.ok(
    dart.includes("data['permitirViajeConPrepagoParcial'] == true"),
    "el cliente Flutter debe leer el flag como opt-in",
  );
});

test("aprobar/rechazar recarga es idempotente y reconcilia el bloqueo", () => {
  const src = readFileSync(
    join(repoRoot, "functions", "src", "recarga_admin.ts"),
    "utf8",
  );
  assert.ok(src.includes("alreadyRejected"));
  assert.ok(src.includes("reintentoIdempotente"));
  assert.ok(
    src.includes("reconciliarBloqueoTaxista"),
    "el bloqueo debe reconciliarse también en reintentos",
  );
  assert.ok(
    src.includes("notificarTaxistaRecarga"),
    "el chofer debe recibir aviso de aprobación/rechazo",
  );
  const rechazo = src.slice(src.indexOf("export const rejectRecargaComision"));
  const uidAntesDelReturn =
    rechazo.indexOf("uidTaxista = String(m.uidTaxista") <
    rechazo.indexOf('estado === "rechazado"');
  assert.ok(
    uidAntesDelReturn,
    "el uid debe leerse antes de cortar por estado ya rechazado",
  );
});
