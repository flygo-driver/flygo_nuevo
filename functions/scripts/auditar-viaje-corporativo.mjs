/**
 * Auditoría B2B: un viaje corporativo vs desglose tarifario y acumulados.
 *
 * Requiere credenciales ADC (mismo proyecto que producción):
 *   gcloud auth application-default login
 *
 * Uso:
 *   node functions/scripts/auditar-viaje-corporativo.mjs <viajeId>
 *   node functions/scripts/auditar-viaje-corporativo.mjs <viajeId> --project flygo-rd
 *
 * Ejemplo:
 *   node functions/scripts/auditar-viaje-corporativo.mjs abc123xyz --project flygo-rd
 */
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

const args = process.argv.slice(2);
const listMode = args.includes("--list");
const viajeId = args.find((a) => !a.startsWith("--"));
const projectIdx = args.indexOf("--project");
const limitIdx = args.indexOf("--limit");
const listLimit = limitIdx >= 0 ? Math.max(1, parseInt(args[limitIdx + 1] ?? "10", 10)) : 10;
const projectId =
  (projectIdx >= 0 ? args[projectIdx + 1] : null) ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "flygo-rd";

if (!viajeId && !listMode) {
  console.error(
    "Uso:\n" +
      "  node functions/scripts/auditar-viaje-corporativo.mjs <viajeId> [--project flygo-rd]\n" +
      "  node functions/scripts/auditar-viaje-corporativo.mjs --list [--limit 10] [--project flygo-rd]\n\n" +
      "  <viajeId> = ID real del documento en colección viajes (no uses TU_VIAJE_ID).",
  );
  process.exit(1);
}

const num = (v) => {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
};

const round2 = (n) => Math.round(num(n) * 100) / 100;

const str = (v) => (v == null ? "" : String(v).trim());

function desgloseDesdeViaje(d) {
  const ex = d.extras && typeof d.extras === "object" ? d.extras : {};
  return ex.corporativoTarifaDesglose && typeof ex.corporativoTarifaDesglose === "object"
    ? ex.corporativoTarifaDesglose
    : d.corporativoTarifaDesglose && typeof d.corporativoTarifaDesglose === "object"
      ? d.corporativoTarifaDesglose
      : {};
}

function liquidacionEsperadaDesdeViaje(d, comisionPct = 10) {
  const desglose = desgloseDesdeViaje(d);
  const baseRd = round2(
    num(desglose.precioBaseServicioRd ?? desglose.subtotalFacturaRd),
  );
  let pagoChoferRd = round2(
    num(desglose.pagoChoferRd ?? d.corporativoPagoChoferEstimadoRd),
  );
  let comisionRd = round2(
    num(desglose.comisionPlataformaRd ?? desglose.cargoCompaniaRd),
  );
  const impuestoRd = round2(
    num(desglose.impuestoTransferenciaRd ?? desglose.recargoTransferenciaRd),
  );
  const facturaRd = round2(
    num(
      desglose.montoTotalFacturaRd ??
        desglose.precioViajeRd ??
        d.precio ??
        d.precioFinal,
    ),
  );

  if (pagoChoferRd <= 0 && baseRd > 0) {
    pagoChoferRd = round2(baseRd * ((100 - comisionPct) / 100));
  }
  if (comisionRd <= 0 && baseRd > 0) {
    comisionRd = round2(baseRd * (comisionPct / 100));
  }

  return {
    desglose,
    baseRd,
    impuestoRd,
    facturaRd,
    comisionRaiRd: comisionRd,
    pagoChoferRd,
    /** Chofer + RAI deben ≈ Precio_Base (el impuesto va aparte en la factura). */
    splitBaseRd: round2(pagoChoferRd + comisionRd),
  };
}

function choferUidDesdeViaje(d) {
  for (const k of [
    "uidTaxista",
    "taxistaId",
    "corporativoChoferAsignadoUid",
    "corporativoChoferPreferidoUid",
  ]) {
    const s = str(d[k]);
    if (s) return s;
  }
  return "";
}

function fmtTs(v) {
  if (!v) return "(sin fecha)";
  if (typeof v.toDate === "function") {
    return v.toDate().toISOString().slice(0, 10);
  }
  return str(v);
}

function comparar(etiqueta, esperado, actual, tolerancia = 0.02) {
  const diff = Math.abs(round2(esperado) - round2(actual));
  const ok = diff <= tolerancia;
  return {
    etiqueta,
    esperado: round2(esperado),
    actual: round2(actual),
    diff: round2(diff),
    ok,
  };
}

function imprimirFila(c) {
  const estado = c.ok ? "OK" : "DESALINEADO";
  console.log(
    `  [${estado}] ${c.etiqueta}: esperado=${c.esperado} actual=${c.actual} Δ=${c.diff}`,
  );
}

initializeApp({ credential: applicationDefault(), projectId });
const db = getFirestore();

if (listMode) {
  console.log(`\n=== Viajes corporativos recientes (${projectId}) ===\n`);
  const snap = await db
    .collection("viajes")
    .where("corporativo", "==", true)
    .limit(listLimit)
    .get();
  if (snap.empty) {
    console.log("No se encontraron viajes corporativos.");
    process.exit(0);
  }
  for (const d of snap.docs) {
    const x = d.data();
    console.log(d.id);
    console.log(`  empresa: ${str(x.corporativoEmpresaNombre) || str(x.corporativoEmpresaId)}`);
    console.log(
      `  estado: ${str(x.estado)} | completado=${x.completado === true} | contab=${x.corporativoContabilizado === true}`,
    );
    console.log(
      `  precio: RD$ ${round2(num(x.precio))} | gananciaTaxista: RD$ ${round2(num(x.gananciaTaxista))}`,
    );
    console.log("");
  }
  console.log("Auditar uno:");
  console.log(`  node functions/scripts/auditar-viaje-corporativo.mjs <ID_ARRIBA> --project ${projectId}\n`);
  process.exit(0);
}

console.log(`\n=== Auditoría corporativo · viaje ${viajeId} ===`);
console.log(`projectId=${projectId}\n`);

const viajeRef = db.collection("viajes").doc(viajeId);
const vSnap = await viajeRef.get();
if (!vSnap.exists) {
  console.error("ERROR: viaje no encontrado.");
  process.exit(2);
}

const v = vSnap.data() ?? {};
if (v.corporativo !== true) {
  console.warn("AVISO: el documento no tiene corporativo=true.");
}

const empresaId = str(v.corporativoEmpresaId);
const choferUid = choferUidDesdeViaje(v);
const esperado = liquidacionEsperadaDesdeViaje(v);

const precioFactura = round2(num(v.precio ?? v.precioFinal ?? v.total));
const gananciaTaxista = round2(num(v.gananciaTaxista));
const comisionViaje = round2(num(v.comision ?? v.comisionFlygo));
const gananciaCents = num(v.ganancia_cents) / 100;
const comisionCents = num(v.comision_cents) / 100;

console.log("--- Viaje ---");
console.log(`  empresaId: ${empresaId || "(vacío)"}`);
console.log(`  plantilla: ${str(v.corporativoPlantillaNombre) || "(sin nombre)"}`);
console.log(`  choferUid: ${choferUid || "(vacío)"}`);
console.log(`  estado: ${str(v.estado)} · completado=${v.completado === true}`);
console.log(
  `  contabilizado=${v.corporativoContabilizado === true} · omitidoSinCodigo=${v.corporativoOmitidoSinCodigo === true}`,
);
console.log(`  codigoVerificado=${v.codigoVerificado === true}`);

console.log("\n--- Desglose tarifario (fuente de verdad al publicar) ---");
console.log(`  Precio_Base:        RD$ ${esperado.baseRd}`);
console.log(`  Impuesto transfer.: RD$ ${esperado.impuestoRd}`);
console.log(`  Monto factura:      RD$ ${esperado.facturaRd || precioFactura}`);
console.log(`  Comisión RAI (10% base): RD$ ${esperado.comisionRaiRd}`);
console.log(`  Pago chofer (90% base): RD$ ${esperado.pagoChoferRd}`);
const facturaCalc = round2(esperado.baseRd + esperado.impuestoRd);
const splitOk = Math.abs(esperado.splitBaseRd - esperado.baseRd) <= 1.01;
const facturaOk =
  Math.abs(facturaCalc - (esperado.facturaRd || precioFactura)) <= 0.02;
console.log(
  `  Chofer+RAI (= base):  RD$ ${esperado.splitBaseRd} vs base ${esperado.baseRd} ${splitOk ? "✓" : "⚠"}`,
);
console.log(
  `  Base+impuesto:        RD$ ${facturaCalc} vs factura ${esperado.facturaRd || precioFactura} ${facturaOk ? "✓" : "⚠"}`,
);

const formulaViejaChofer = round2(precioFactura * 0.9);
const formulaViejaRai = round2(precioFactura * 0.1);
const pareceFormulaVieja =
  precioFactura > 0 &&
  Math.abs(gananciaTaxista - formulaViejaChofer) <= 0.05 &&
  Math.abs(comisionViaje - formulaViejaRai) <= 0.05;
if (pareceFormulaVieja && esperado.pagoChoferRd > 0) {
  console.log(
    `\n  ⚠ Fórmula ANTIGUA detectada: 90%/10% sobre factura (${formulaViejaChofer} / ${formulaViejaRai})`,
  );
  console.log(
    `    Correcto (Ley 30-26): chofer ${esperado.pagoChoferRd} · RAI ${esperado.comisionRaiRd} sobre Precio_Base`,
  );
}

console.log("\n--- Cierre del viaje (finalizarViajeSeguro) ---");
console.log(`  precio (factura):     RD$ ${precioFactura}`);
console.log(`  gananciaTaxista:      RD$ ${gananciaTaxista}`);
console.log(`  comision RAI:         RD$ ${comisionViaje}`);
console.log(`  ganancia_cents/100:   RD$ ${round2(gananciaCents)}`);
console.log(`  comision_cents/100:   RD$ ${round2(comisionCents)}`);
console.log(
  `  corporativoPagoChoferEstimadoRd: RD$ ${round2(num(v.corporativoPagoChoferEstimadoRd))}`,
);

const checks = [];
if (esperado.pagoChoferRd > 0) {
  checks.push(
    comparar("gananciaTaxista vs pagoChoferRd", esperado.pagoChoferRd, gananciaTaxista || gananciaCents),
  );
  checks.push(
    comparar("comision vs comisionPlataformaRd", esperado.comisionRaiRd, comisionViaje || comisionCents),
  );
}
if (esperado.facturaRd > 0) {
  checks.push(comparar("precio vs montoTotalFactura", esperado.facturaRd, precioFactura));
}

console.log("\n--- Validación matemática ---");
if (checks.length === 0) {
  console.log("  (sin desglose tarifario — no se puede validar neto/comisión)");
} else {
  for (const c of checks) imprimirFila(c);
}

const desalineados = checks.filter((c) => !c.ok);
if (desalineados.length > 0) {
  console.log(
    "\n  → Viaje cerrado con fórmula antigua o sin desglose. Los cierres nuevos (post-deploy) deben cuadrar.",
  );
}

console.log("\n--- Acumulado en viaje (snapshot chofer) ---");
console.log(
  `  corporativoChoferAcumuladoPeriodoRd: RD$ ${round2(num(v.corporativoChoferAcumuladoPeriodoRd))}`,
);
console.log(
  `  corporativoChoferViajesPeriodo: ${Math.trunc(num(v.corporativoChoferViajesPeriodo))}`,
);

if (empresaId) {
  const empRef = db.collection("empresas_corporativas").doc(empresaId);
  const [empSnap, histSnap] = await Promise.all([
    empRef.get(),
    empRef.collection("historial").doc(viajeId).get(),
  ]);

  if (empSnap.exists) {
    const ed = empSnap.data() ?? {};
    const periodo = ed.periodoActual ?? {};
    const porChofer = periodo.porChofer ?? {};
    const row = choferUid && porChofer[choferUid] ? porChofer[choferUid] : null;

    console.log("\n--- Empresa · periodoActual ---");
    console.log(`  empresa: ${str(ed.nombre) || empresaId}`);
    console.log(`  viajesCount período: ${Math.trunc(num(periodo.viajesCount))}`);
    console.log(`  montoTotalRd período: RD$ ${round2(num(periodo.montoTotalRd))}`);
    console.log(
      `  período: ${fmtTs(periodo.inicio)} → ${fmtTs(periodo.fin)} (${Math.trunc(num(ed.facturacionCicloDias) || 15)} días)`,
    );

    if (row) {
      console.log(`\n  Chofer ${choferUid} en porChofer:`);
      console.log(`    viajes: ${Math.trunc(num(row.viajes))}`);
      console.log(`    montoRd (neto acumulado): RD$ ${round2(num(row.montoRd))}`);
    } else if (choferUid) {
      console.log(`\n  Chofer ${choferUid}: sin fila en porChofer (aún no contabilizado o uid distinto).`);
    }
  }

  if (histSnap.exists) {
    const h = histSnap.data() ?? {};
    console.log("\n--- Historial empresa (este viaje) ---");
    console.log(`  estado: ${str(h.estado)}`);
    console.log(`  monto facturado: RD$ ${round2(num(h.monto))}`);
    console.log(`  motivoNoCobro: ${str(h.motivoNoCobro) || "(ninguno)"}`);
  }
}

if (choferUid) {
  const opSnap = await db.collection("chofer_operacion").doc(choferUid).get();
  if (opSnap.exists && empresaId) {
    const op = opSnap.data() ?? {};
    const resumen = (op.resumenPagoEmpresas ?? {})[empresaId] ?? null;
    console.log("\n--- Chofer operación (tiempo real) ---");
    if (resumen) {
      console.log(`  acumuladoRd: RD$ ${round2(num(resumen.acumuladoRd))}`);
      console.log(`  viajesCount: ${Math.trunc(num(resumen.viajesCount))}`);
    } else {
      console.log("  resumenPagoEmpresas: sin entrada para esta empresa.");
    }
  }
}

console.log("\n--- Resumen ---");
if (v.corporativoContabilizado === true && desalineados.length === 0) {
  console.log("  ESTADO: CONTABILIZADO Y CUADRADO ✓");
} else if (v.corporativoOmitidoSinCodigo === true) {
  console.log("  ESTADO: NO CONTABILIZADO (sin código / anulado)");
} else if (v.completado !== true) {
  console.log("  ESTADO: viaje aún no completado — acumulados pueden ser estimados.");
} else if (desalineados.length > 0) {
  console.log("  ESTADO: COMPLETADO PERO DESALINEADO — revisar cierre o migrar manualmente.");
} else {
  console.log("  ESTADO: completado; validar contabilizado=true en Firestore.");
}

console.log("");
