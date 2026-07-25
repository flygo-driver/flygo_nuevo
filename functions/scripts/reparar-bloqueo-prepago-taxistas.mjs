/**
 * Repara desincronización entre billetera/pools y `usuarios.tienePagoPendiente`.
 *
 * Caso típico: `comisionPendiente > 0` pero `tienePagoPendiente = false` porque el
 * fallback del cliente no puede escribir esa bandera (Firestore rules) y el trigger
 * `onBilleteraTaxistaWritten` no estaba desplegado.
 *
 * Requiere ADC + build de functions:
 *   cd functions && npm run build
 *   gcloud auth application-default login
 *
 * Uso:
 *   node functions/scripts/reparar-bloqueo-prepago-taxistas.mjs --dry-run
 *   node functions/scripts/reparar-bloqueo-prepago-taxistas.mjs --apply
 *   node functions/scripts/reparar-bloqueo-prepago-taxistas.mjs --apply --uid <taxistaUid>
 *   node functions/scripts/reparar-bloqueo-prepago-taxistas.mjs --apply --project flygo-rd
 */
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const MIN_SALDO_PREPAGO_RD = 200;
const UMBRAL_DEUDA_POOL_RD = 500;

const args = process.argv.slice(2);
const apply = args.includes("--apply");
const dryRun = !apply || args.includes("--dry-run");
const uidIdx = args.indexOf("--uid");
const singleUid = uidIdx >= 0 ? String(args[uidIdx + 1] ?? "").trim() : "";
const projectIdx = args.indexOf("--project");
const projectId =
  (projectIdx >= 0 ? args[projectIdx + 1] : null) ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "flygo-rd";

const num = (v) => {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
};
const round2 = (n) => Math.round(num(n) * 100) / 100;
const str = (v) => (v == null ? "" : String(v).trim());

function saldoPrepagoRd(d) {
  return round2(num(d?.saldoPrepagoComisionRd));
}
function saldoReservadoRd(d) {
  return round2(Math.max(0, num(d?.saldoReservadoParaGiras)));
}
function saldoDisponibleRd(d) {
  return round2(Math.max(0, saldoPrepagoRd(d) - saldoReservadoRd(d)));
}
function comisionPendienteRd(d) {
  return round2(num(d?.comisionPendiente));
}
function primerViajeGratisConsumido(d) {
  return d?.primerViajeComisionGratisConsumido === true;
}

function bloqueoOperativoPrepago(bille, cfg) {
  const pend = comisionPendienteRd(bille);
  if (pend > 1e-6) return true;
  if (!primerViajeGratisConsumido(bille)) return false;
  const disp = saldoDisponibleRd(bille);
  if (cfg.permitirViajeConPrepagoParcial) return disp <= 1e-9;
  return disp + 1e-9 < cfg.minimoOperativoRd;
}

async function cargarConfig(db) {
  const [prepSnap, comSnap] = await Promise.all([
    db.collection("config").doc("comision_prepago").get(),
    db.collection("config").doc("comision").get(),
  ]);
  const prep = prepSnap.data() ?? {};
  let pct = num(comSnap.data()?.porcentaje);
  if (pct > 0 && pct <= 1.001) pct *= 100;
  if (pct <= 0) pct = 20;
  return {
    minimoOperativoRd: num(prep.minimoOperativoRd) || MIN_SALDO_PREPAGO_RD,
    permitirViajeConPrepagoParcial: prep.permitirViajeConPrepagoParcial !== false,
    comisionPct: pct,
  };
}

async function deudaPoolRd(db, uid) {
  let total = 0;
  try {
    const poolSnap = await db
      .collection("viajes_pool")
      .where("ownerTaxistaId", "==", uid)
      .where("comisionPendientePagoAdmin", "==", true)
      .limit(500)
      .get();
    for (const p of poolSnap.docs) {
      const d = p.data();
      total += num(d.montoComisionPendienteAdmin ?? d.montoComision);
    }
  } catch (e) {
    console.warn(`  AVISO pool query ${uid}: ${e.message}`);
  }
  return round2(total);
}

async function calcularEsperado(db, uid, cfg) {
  const [billeSnap, uSnap] = await Promise.all([
    db.collection("billeteras_taxista").doc(uid).get(),
    db.collection("usuarios").doc(uid).get(),
  ]);
  const bille = billeSnap.exists ? billeSnap.data() ?? {} : {};
  const u = uSnap.exists ? uSnap.data() ?? {} : {};
  const bloqueoComision = bloqueoOperativoPrepago(bille, cfg);
  const deudaPool = await deudaPoolRd(db, uid);
  const bloqueoPool = deudaPool + 1e-9 >= UMBRAL_DEUDA_POOL_RD;
  const tienePagoPendiente = bloqueoComision || bloqueoPool;
  return {
    uid,
    nombre: str(u.nombre) || str(u.displayName) || "(sin nombre)",
    rol: str(u.rol),
    actual: u.tienePagoPendiente === true,
    esperado: tienePagoPendiente,
    deudaPool,
    comisionPendiente: comisionPendienteRd(bille),
    bloqueoComision,
    bloqueoPool,
    deudaPoolActual: round2(num(u.deudaPoolPendienteRd)),
  };
}

initializeApp({ credential: applicationDefault(), projectId });
const db = getFirestore();

console.log(`\n=== Reparar bloqueo prepago · ${projectId} ===`);
console.log(`Modo: ${apply ? "APLICAR (escribe Firestore)" : "dry-run (solo informe)"}`);
if (singleUid) console.log(`UID: ${singleUid}`);

const cfg = await cargarConfig(db);
let syncFn = null;
if (apply) {
  try {
    const mod = await import("../lib/finance.js");
    syncFn = mod.syncTaxistaBloqueoOperativo;
    if (typeof syncFn !== "function") {
      throw new Error("syncTaxistaBloqueoOperativo no exportado");
    }
  } catch (e) {
    console.error(
      "\nERROR: ejecutá `cd functions && npm run build` antes de --apply.\n",
      e.message ?? e,
    );
    process.exit(2);
  }
}

const uids = new Set();
if (singleUid) {
  uids.add(singleUid);
} else {
  const [billeSnap, bloqueadosSnap] = await Promise.all([
    db.collection("billeteras_taxista").get(),
    db.collection("usuarios").where("tienePagoPendiente", "==", true).limit(500).get(),
  ]);
  for (const d of billeSnap.docs) uids.add(d.id);
  for (const d of bloqueadosSnap.docs) uids.add(d.id);
}

const desync = [];
for (const uid of uids) {
  const row = await calcularEsperado(db, uid, cfg);
  const flagDesync = row.actual !== row.esperado;
  const deudaDesync = Math.abs(row.deudaPool - row.deudaPoolActual) > 0.02;
  if (!flagDesync && !deudaDesync) continue;
  desync.push({ ...row, flagDesync, deudaDesync });
}

if (desync.length === 0) {
  console.log("\n✓ No hay taxistas desalineados.\n");
  process.exit(0);
}

console.log(`\nEncontrados ${desync.length} taxista(s) desalineado(s):\n`);
for (const r of desync) {
  console.log(`${r.uid} — ${r.nombre}`);
  console.log(
    `  comisionPendiente RD$ ${r.comisionPendiente} | bloqueoComision=${r.bloqueoComision} bloqueoPool=${r.bloqueoPool}`,
  );
  if (r.flagDesync) {
    console.log(
      `  tienePagoPendiente: actual=${r.actual} → esperado=${r.esperado}`,
    );
  }
  if (r.deudaDesync) {
    console.log(
      `  deudaPoolPendienteRd: actual=${r.deudaPoolActual} → esperado=${r.deudaPool}`,
    );
  }
  console.log("");
}

if (!apply) {
  console.log("Para corregir en Firestore:");
  console.log(
    `  node functions/scripts/reparar-bloqueo-prepago-taxistas.mjs --apply --project ${projectId}`,
  );
  console.log("");
  process.exit(0);
}

let ok = 0;
let fail = 0;
for (const r of desync) {
  try {
    const tiene = await syncFn(r.uid);
    const okRow = tiene === r.esperado;
    console.log(
      `${okRow ? "✓" : "⚠"} ${r.uid}: sync → tienePagoPendiente=${tiene}`,
    );
    if (okRow) ok += 1;
    else fail += 1;
  } catch (e) {
    fail += 1;
    console.error(`✗ ${r.uid}: ${e.message ?? e}`);
  }
}

console.log(`\nReparación: ${ok} ok, ${fail} con aviso/error.\n`);
process.exit(fail > 0 ? 1 : 0);
