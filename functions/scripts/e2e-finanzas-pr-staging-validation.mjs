/**
 * Validación E2E PR1 + PR1.1 + PR2 (emulador o staging con ADC).
 *
 * Emulador:
 *   firebase emulators:start --only firestore,functions,auth --project flygo-e2e-pr
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
 *   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
 *   FUNCTIONS_EMULATOR=true
 *   node functions/scripts/e2e-finanzas-pr-staging-validation.mjs
 *
 * Staging remoto (requiere gcloud auth application-default login):
 *   GOOGLE_CLOUD_PROJECT=flygo-9abd2 node functions/scripts/e2e-finanzas-pr-staging-validation.mjs
 */
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { initializeApp, getApps, applicationDefault } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

import { esElegibleLiquidacionSemanal } from "../lib/liquidacion_semanal_viaje.js";
import {
  aprobarLiquidacionSemanal,
  generarLiquidacionSemanalTaxista,
  previousIsoWeekPeriodo,
} from "../lib/liquidacion_semanal.js";

const __dir = dirname(fileURLToPath(import.meta.url));
const projectId =
  process.env.GOOGLE_CLOUD_PROJECT ||
  process.env.GCLOUD_PROJECT ||
  "flygo-e2e-pr";
const useEmulator = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

if (!getApps().length) {
  initializeApp(
    useEmulator
      ? { projectId }
      : { projectId, credential: applicationDefault() },
  );
}

const db = getFirestore();

const evidence = {
  meta: {
    projectId,
    useEmulator,
    startedAt: new Date().toISOString(),
    checklist: {},
  },
  before: {},
  after: {},
  rollback: {},
  findings: [],
  recommendation: null,
};

function step(name, ok, detail) {
  evidence.meta.checklist[name] = { ok, detail };
  const mark = ok ? "PASS" : "FAIL";
  console.log(`[${mark}] ${name}: ${detail}`);
}

function cents(rd) {
  return Math.round(rd * 100);
}

/** Invoca handler onCall v2 directamente (mismo código que producción). */
async function callCf(handler, uidActor, data) {
  return handler.run({
    auth: { uid: uidActor, token: {} },
    data,
    rawRequest: {},
  });
}

function saldoRetirableCents(viajes) {
  let total = 0;
  for (const v of viajes) {
    if (esElegibleLiquidacionSemanal(v)) {
      const g = v.ganancia_cents ?? cents(v.gananciaTaxista ?? v.ganancia ?? 0);
      total += g;
    }
  }
  return total;
}

function simulaGenerarPagoSemanalLegacy(viajes, excluirEfectivo) {
  const elegibles = viajes.filter((v) => {
    if (v.liquidado === true) return false;
    if (!excluirEfectivo) return true;
    return esElegibleLiquidacionSemanal(v);
  });
  return {
    viajesIncluidos: elegibles.map((v) => v._id),
    count: elegibles.length,
  };
}

async function main() {
  const runId = randomUUID().slice(0, 8);
  const adminUid = `e2e_admin_${runId}`;
  const taxistaUid = `e2e_taxista_${runId}`;
  const { periodo, periodoInicio, periodoFin } = previousIsoWeekPeriodo();
  const midPeriodo = new Date(
    periodoInicio.getTime() +
      (periodoFin.getTime() - periodoInicio.getTime()) / 2,
  );

  // --- 1. Taxista de prueba (solo Firestore; CF valida rol en usuarios/) ---
  await db.collection("usuarios").doc(adminUid).set({
    rol: "admin",
    nombre: "E2E Admin",
  });
  await db.collection("usuarios").doc(taxistaUid).set({
    rol: "taxista",
    nombre: "E2E Taxista PR",
    banco: "Popular",
    numeroCuenta: "1234567890",
    titularCuenta: "E2E Taxista PR",
    tipoCuenta: "ahorro",
  });
  step("1_taxista_prueba", true, `admin=${adminUid} taxista=${taxistaUid}`);

  // PR2 flags ON
  await db.collection("config").doc("finance").set(
    {
      excluirEfectivoDePagoSemanal: true,
      useLiquidacionesSemanales: true,
      escrituraPagosTaxistasLegacy: false,
      generarLiquidacionesSemanalesAuto: false,
    },
    { merge: true },
  );

  // --- 2. Registrar viajes ---
  const efectivo1 = {
    uidTaxista: taxistaUid,
    completado: true,
    estado: "finalizado",
    metodoPago: "Efectivo",
    metodoPagoNormalizado: "efectivo",
    estadoPago: "pagado",
    precio: 10,
    precio_cents: 1000,
    comision: 1.5,
    comision_cents: 150,
    gananciaTaxista: 8.5,
    ganancia_cents: 850,
    finalizadoEn: Timestamp.fromDate(midPeriodo),
    liquidado: false,
  };
  const efectivo2 = {
    ...efectivo1,
    precio: 12,
    precio_cents: 1200,
    comision_cents: 180,
    ganancia_cents: 1020,
  };
  const transferencia = {
    uidTaxista: taxistaUid,
    completado: true,
    estado: "finalizado",
    metodoPago: "Transferencia",
    metodoPagoNormalizado: "transferencia",
    estadoPago: "verificado",
    precio: 20,
    precio_cents: 2000,
    comision: 3,
    comision_cents: 300,
    gananciaTaxista: 17,
    ganancia_cents: 1700,
    finalizadoEn: Timestamp.fromDate(midPeriodo),
    liquidado: false,
  };

  const refE1 = await db.collection("viajes").add(efectivo1);
  const refE2 = await db.collection("viajes").add(efectivo2);
  const refT = await db.collection("viajes").add(transferencia);
  step(
    "2_registrar_viajes",
    true,
    `efectivo=${refE1.id},${refE2.id} transferencia=${refT.id}`,
  );

  evidence.before.viajes = {
    [refE1.id]: efectivo1,
    [refE2.id]: efectivo2,
    [refT.id]: transferencia,
  };

  // --- 3. Generar liquidación semanal ---
  let gen;
  try {
    gen = await callCf(generarLiquidacionSemanalTaxista, adminUid, {
      uidTaxista: taxistaUid,
      periodo,
    });
  } catch (e) {
    step("3_generar_liquidacion", false, String(e));
    throw e;
  }
  const liquidacionId = gen.liquidacionId;
  step("3_generar_liquidacion", true, `liquidacionId=${liquidacionId}`);

  const liqSnap = await db
    .collection("liquidaciones_semanales")
    .doc(liquidacionId)
    .get();
  const liq = liqSnap.data() ?? {};
  evidence.after.liquidacion_generada = { id: liquidacionId, ...liq };

  // --- 4. Verificaciones liquidación ---
  const viajeIds = (liq.viajeIds ?? []).map(String);
  const onlyDigital =
    viajeIds.length === 1 && viajeIds[0] === refT.id && !viajeIds.includes(refE1.id);
  step(
    "4a_viajeIds_solo_digital",
    onlyDigital,
    `viajeIds=${JSON.stringify(viajeIds)}`,
  );

  const exclCount = liq.viajesEfectivoExcluidosCount ?? 0;
  step(
    "4b_efectivo_excluidos_count",
    exclCount === 2,
    `viajesEfectivoExcluidosCount=${exclCount}`,
  );

  const netoOk = liq.totalNetoCents === 1700;
  step(
    "4c_total_neto_cents",
    netoOk,
    `totalNetoCents=${liq.totalNetoCents} esperado=1700`,
  );

  const brutoOk =
    liq.totalBrutoCents ===
    (liq.comisionRaiCents ?? 0) + (liq.totalNetoCents ?? 0);
  step(
    "4d_bruto_eq_comision_mas_neto",
    brutoOk,
    `bruto=${liq.totalBrutoCents} comision=${liq.comisionRaiCents} neto=${liq.totalNetoCents}`,
  );

  // --- 5. Aprobar liquidación ---
  const idemKey = `e2e_aprobar_${liquidacionId}_${Date.now()}`;
  const apr = await callCf(aprobarLiquidacionSemanal, adminUid, {
    liquidacionId,
    idempotencyKey: idemKey,
    notaAdmin: "e2e validation",
    referenciaAch: "ACH-E2E-001",
  });
  step("5_aprobar_liquidacion", apr.ok === true, JSON.stringify(apr));

  // --- 6. Confirmar Firestore post-aprobación ---
  const [vE1, vE2, vT, liqPaid] = await Promise.all([
    refE1.get(),
    refE2.get(),
    refT.get(),
    db.collection("liquidaciones_semanales").doc(liquidacionId).get(),
  ]);
  const dE1 = vE1.data() ?? {};
  const dE2 = vE2.data() ?? {};
  const dT = vT.data() ?? {};
  const dLiq = liqPaid.data() ?? {};

  evidence.after.viajes = {
    [refE1.id]: dE1,
    [refE2.id]: dE2,
    [refT.id]: dT,
  };
  evidence.after.liquidacion_pagada = { id: liquidacionId, ...dLiq };

  const tOk =
    dT.liquidado === true &&
    String(dT.liquidacionSemanalId ?? "") === liquidacionId &&
    dT.liquidadoEn != null;
  step(
    "6_viaje_digital_liquidado",
    tOk,
    `liquidado=${dT.liquidado} liqId=${dT.liquidacionSemanalId} liquidadoEn=${Boolean(dT.liquidadoEn)}`,
  );

  // --- 7. Efectivo no liquidado digitalmente ---
  const e1Ok = dE1.liquidado !== true && !dE1.liquidacionSemanalId;
  const e2Ok = dE2.liquidado !== true && !dE2.liquidacionSemanalId;
  const notInLiq =
    !viajeIds.includes(refE1.id) && !viajeIds.includes(refE2.id);
  const retirable = saldoRetirableCents([dE1, dE2, dT]);
  const retirableOk = retirable === 0; // digital ya liquidado → no retirable
  const legacyPago = simulaGenerarPagoSemanalLegacy([dE1, dE2, dT], true);
  const noPagoSemanalEfectivo =
    !legacyPago.viajesIncluidos.includes(refE1.id) &&
    !legacyPago.viajesIncluidos.includes(refE2.id);

  step("7a_efectivo_no_en_viajeIds", notInLiq, `viajeIds=${JSON.stringify(viajeIds)}`);
  step(
    "7b_efectivo_no_liquidado_digital",
    e1Ok && e2Ok,
    `e1.liquidado=${dE1.liquidado} e2.liquidado=${dE2.liquidado}`,
  );
  step(
    "7c_saldo_retirable_sin_digital_pendiente",
    retirableOk,
    `ganRetirableCents=${retirable}`,
  );
  step(
    "7d_efectivo_no_pago_semanal",
    noPagoSemanalEfectivo,
    `legacyIncluye=${JSON.stringify(legacyPago.viajesIncluidos)}`,
  );

  // --- 8. Rollback PR1 ---
  await db.collection("config").doc("finance").set(
    {
      useLiquidacionesSemanales: false,
      escrituraPagosTaxistasLegacy: true,
      excluirEfectivoDePagoSemanal: true,
    },
    { merge: true },
  );
  const cfgRb = (await db.collection("config").doc("finance").get()).data();
  const viajeNuevoDigital = {
    _id: "sim_new_transfer",
    uidTaxista: taxistaUid,
    completado: true,
    metodoPagoNormalizado: "transferencia",
    estadoPago: "verificado",
    liquidado: false,
    ganancia_cents: 500,
  };
  const legacyRb = simulaGenerarPagoSemanalLegacy(
    [dE1, dE2, viajeNuevoDigital],
    cfgRb.excluirEfectivoDePagoSemanal !== false,
  );
  const rbOk =
    cfgRb.useLiquidacionesSemanales === false &&
    cfgRb.escrituraPagosTaxistasLegacy === true &&
    legacyRb.count === 1 &&
    legacyRb.viajesIncluidos[0] === "sim_new_transfer";
  evidence.rollback = { config: cfgRb, legacyRb };
  step(
    "8_rollback_pr1",
    rbOk,
    `flags useLiq=${cfgRb.useLiquidacionesSemanales} legacyWrite=${cfgRb.escrituraPagosTaxistasLegacy} elegibles=${legacyRb.count}`,
  );

  const fails = Object.values(evidence.meta.checklist).filter((x) => !x.ok);
  evidence.meta.finishedAt = new Date().toISOString();
  evidence.meta.passCount = Object.values(evidence.meta.checklist).filter(
    (x) => x.ok,
  ).length;
  evidence.meta.failCount = fails.length;
  evidence.recommendation =
    fails.length === 0
      ? useEmulator
        ? "GO_CONDICIONAL: E2E emulador PASS. Ejecutar mismo script en flygo-9abd2 con ADC + deploy PR2 antes de activación permanente."
        : "GO: E2E staging remoto PASS."
      : "NO_GO: corregir fallos del checklist.";

  if (fails.length) evidence.findings.push(...fails.map((f) => f.detail));

  const outPath = join(__dir, `e2e-finanzas-pr-evidence-${runId}.json`);
  writeFileSync(outPath, JSON.stringify(evidence, null, 2));
  console.log(`\nEvidencia: ${outPath}`);
  console.log(`Recomendación: ${evidence.recommendation}`);

  if (fails.length) process.exit(1);
}

main().catch((e) => {
  console.error("E2E validation aborted:", e);
  const outPath = join(__dir, "e2e-finanzas-pr-evidence-ERROR.json");
  writeFileSync(
    outPath,
    JSON.stringify({ error: String(e), stack: e?.stack, evidence }, null, 2),
  );
  console.error(`Evidencia parcial: ${outPath}`);
  process.exit(1);
});
