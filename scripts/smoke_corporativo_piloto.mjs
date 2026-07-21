/**
 * Smoke test automático (Firestore) — piloto Laboratorio Referencia.
 * Complementa el checklist manual en docs/RAI_CORPORATIVO_GO_LIVE.md §7.
 *
 *   node scripts/smoke_corporativo_piloto.mjs
 */
import admin from "./lib/firebase_admin.mjs";

const projectId = "flygo-rd";
const EMPRESA = "5GztuEyAkIm18CfDI4Vu";
const CHOFER = "4CyXCaseJwPkiIj9snV8ABVkcJ92";
const ENCARGADO = "hRVmsfmCgvfd9UxR3dHbQS6dQhi1";

admin.initializeApp({ projectId });
const db = admin.firestore();

const checks = [];

function ok(msg) {
  checks.push({ ok: true, msg });
  console.log(`  OK  ${msg}`);
}
function fail(msg) {
  checks.push({ ok: false, msg });
  console.log(`  FAIL ${msg}`);
}

async function main() {
  console.log("=== Smoke corporativo piloto ===\n");

  const empSnap = await db.collection("empresas_corporativas").doc(EMPRESA).get();
  if (!empSnap.exists) {
    fail(`Empresa ${EMPRESA} no existe`);
  } else {
    const e = empSnap.data() ?? {};
    ok(`Empresa: ${e.nombre ?? e.nombreComercial ?? EMPRESA}`);
    if (e.activa === false) fail("Empresa inactiva");
    else ok("Empresa activa");
    const encs = Array.isArray(e.encargadoUids) ? e.encargadoUids : [];
    if (encs.includes(ENCARGADO)) ok("Encargado piloto en encargadoUids");
    else fail(`Encargado ${ENCARGADO} no está en encargadoUids`);
  }

  const plSnap = await db
    .collection("empresas_corporativas")
    .doc(EMPRESA)
    .collection("plantillas_ruta")
    .where("activa", "!=", false)
    .limit(5)
    .get();

  if (plSnap.empty) {
    fail("Sin plantillas_ruta activas");
  } else {
    ok(`${plSnap.size} plantilla(s) activa(s)`);
    for (const pl of plSnap.docs) {
      const d = pl.data();
      const hora = String(d.horaRecogidaGrupo ?? d.horaRecogida ?? "");
      const chofer = String(d.choferPreferidoUid ?? "");
      const pas = Array.isArray(d.pasajeros)
        ? d.pasajeros.filter((p) => p?.activo !== false).length
        : 0;
      if (hora) ok(`Plantilla ${pl.id}: hora ${hora}`);
      else fail(`Plantilla ${pl.id}: sin hora`);
      if (chofer === CHOFER) ok(`Plantilla ${pl.id}: chofer asignado`);
      else fail(`Plantilla ${pl.id}: chofer distinto o vacío (${chofer || "—"})`);
      if (pas > 0) ok(`Plantilla ${pl.id}: ${pas} pasajero(s) activo(s)`);
      else fail(`Plantilla ${pl.id}: sin pasajeros activos`);
    }
  }

  const opSnap = await db.collection("chofer_operacion").doc(CHOFER).get();
  if (!opSnap.exists) {
    fail("chofer_operacion/{chofer} no existe — encargado debe Guardar ruta");
  } else {
    const op = opSnap.data() ?? {};
    const fijas = Array.isArray(op.rutasFijas) ? op.rutasFijas : [];
    const hoy = Array.isArray(op.viajesHoy) ? op.viajesHoy : [];
    ok(`chofer_operacion: ${fijas.length} ruta(s) fija(s), ${hoy.length} viaje(s) hoy`);
    if (fijas.length === 0) fail("Sin rutasFijas en chofer_operacion");
  }

  const choferSnap = await db.collection("usuarios").doc(CHOFER).get();
  if (choferSnap.exists) {
    const u = choferSnap.data() ?? {};
    const rol = String(u.rol ?? "").toLowerCase();
    if (rol === "taxista" || rol === "driver") ok("Chofer rol taxista");
    else fail(`Chofer rol inesperado: ${rol}`);
    if (String(u.viajeActivoId ?? "").trim()) {
      fail(`Chofer tiene viajeActivoId colgado: ${u.viajeActivoId}`);
    } else ok("Chofer sin viajeActivoId colgado");
  } else {
    fail("Usuario chofer no existe");
  }

  const vq = await db
    .collection("viajes")
    .where("corporativoEmpresaId", "==", EMPRESA)
    .limit(20)
    .get();
  let activosHoy = 0;
  let canceladosSupersedidos = 0;
  for (const doc of vq.docs) {
    const d = doc.data();
    const e = String(d.estado ?? "").toLowerCase();
    if (String(d.corporativoSupersedidoPor ?? "").trim()) canceladosSupersedidos++;
    if (e !== "cancelado" && e !== "rechazado" && d.completado !== true) activosHoy++;
  }
  ok(`Viajes empresa: ${activosHoy} activo(s), ${canceladosSupersedidos} superseded/cancelados recientes`);
  if (activosHoy > 3) {
    fail("Demasiados viajes activos — correr reset_piloto_corporativo.mjs");
  }

  console.log("\n=== Resumen ===");
  const passed = checks.filter((c) => c.ok).length;
  const failed = checks.filter((c) => !c.ok).length;
  console.log(`Pasaron: ${passed} · Fallaron: ${failed}`);
  if (failed > 0) {
    console.log("\nManual: encargado Guardar ruta → chofer refresh → reintentar smoke.");
    process.exit(1);
  }
  console.log("\nListo para demo piloto (completar pasos 4–6 en teléfono).");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
