/**
 * Auditoría del modelo prepago/comisión taxista (primer viaje gratis → recarga → aceptar → PIN → finalizar → bloqueo).
 *
 * Requiere ADC:
 *   gcloud auth application-default login
 *
 * Uso:
 *   node functions/scripts/auditar-prepago-comision-taxista.mjs <uidTaxista> [--project flygo-rd]
 *   node functions/scripts/auditar-prepago-comision-taxista.mjs <uidTaxista> --viaje <viajeId>
 *   node functions/scripts/auditar-prepago-comision-taxista.mjs --list [--limit 15]
 *   node functions/scripts/auditar-prepago-comision-taxista.mjs --config
 *
 * Tests unitarios (lógica pura, sin Firestore):
 *   cd functions && npm test
 */
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import {
  comisionEstimadaRdDesdeViaje,
  prepagoInsuficienteParaViajeEfectivo,
  viajeAplicaComisionPrepago,
} from "../lib/prepago_comision_viaje.js";

const MIN_SALDO_PREPAGO_RD = 200;
const UMBRAL_DEUDA_POOL_RD = 500;
const UMBRAL_COMISION_LEGACY_RD = 500;

const args = process.argv.slice(2);
const listMode = args.includes("--list");
const configOnly = args.includes("--config");
const viajeIdx = args.indexOf("--viaje");
const viajeIdArg = viajeIdx >= 0 ? args[viajeIdx + 1] : null;
const limitIdx = args.indexOf("--limit");
const listLimit = limitIdx >= 0 ? Math.max(1, parseInt(args[limitIdx + 1] ?? "15", 10)) : 15;
const projectIdx = args.indexOf("--project");
const projectId =
  (projectIdx >= 0 ? args[projectIdx + 1] : null) ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "flygo-rd";
const uidTaxista = args.find(
  (a) => !a.startsWith("--") && a !== viajeIdArg && a !== projectId,
);

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

/** Paridad finance.ts bloqueoOperativoPrepago */
function bloqueoOperativoPrepago(bille, cfg) {
  const pend = comisionPendienteRd(bille);
  if (pend > 1e-6) return { bloqueado: true, motivo: `comisionPendiente RD$ ${pend}` };
  if (!primerViajeGratisConsumido(bille)) {
    return { bloqueado: false, motivo: "primer viaje gratis aún disponible" };
  }
  const disp = saldoDisponibleRd(bille);
  if (cfg.permitirViajeConPrepagoParcial) {
    if (disp <= 1e-9) {
      return { bloqueado: true, motivo: "saldo prepago disponible = 0 (modo parcial)" };
    }
    return { bloqueado: false, motivo: `saldo disponible RD$ ${disp} (modo parcial activo)` };
  }
  if (disp + 1e-9 < cfg.minimoOperativoRd) {
    return {
      bloqueado: true,
      motivo: `saldo RD$ ${disp} < mínimo RD$ ${cfg.minimoOperativoRd}`,
    };
  }
  return { bloqueado: false, motivo: `saldo RD$ ${disp} >= mínimo` };
}

function comparar(etiqueta, esperado, actual, tolerancia = 0.02) {
  const e = typeof esperado === "boolean" ? esperado : round2(esperado);
  const a = typeof actual === "boolean" ? actual : round2(actual);
  const ok =
    typeof esperado === "boolean"
      ? esperado === actual
      : Math.abs(num(e) - num(a)) <= tolerancia;
  return { etiqueta, esperado: e, actual: a, ok };
}

function imprimirFila(c) {
  const estado = c.ok ? "OK" : "FALLO";
  console.log(`  [${estado}] ${c.etiqueta}: esperado=${c.esperado} actual=${c.actual}`);
}

async function cargarConfig(db) {
  const [prepSnap, comSnap, finSnap] = await Promise.all([
    db.collection("config").doc("comision_prepago").get(),
    db.collection("config").doc("comision").get(),
    db.collection("config").doc("finance").get(),
  ]);
  const prep = prepSnap.data() ?? {};
  const com = comSnap.data() ?? {};
  let pct = num(com.porcentaje);
  if (pct > 0 && pct <= 1.001) pct *= 100;
  if (pct <= 0) pct = 20;
  return {
    minimoOperativoRd: num(prep.minimoOperativoRd) || MIN_SALDO_PREPAGO_RD,
    umbralPreventivoRd: num(prep.umbralPreventivoRd) || 250,
    permitirViajeConPrepagoParcial: prep.permitirViajeConPrepagoParcial !== false,
    comisionPct: pct,
    financeExists: finSnap.exists,
  };
}

function imprimirConfig(cfg) {
  console.log("\n--- Config global (ADM) ---");
  console.log(`  comision % viaje: ${cfg.comisionPct}%`);
  console.log(`  minimoOperativoRd: RD$ ${cfg.minimoOperativoRd}`);
  console.log(`  umbralPreventivoRd: RD$ ${cfg.umbralPreventivoRd}`);
  console.log(
    `  permitirViajeConPrepagoParcial: ${cfg.permitirViajeConPrepagoParcial}`,
  );
}

initializeApp({ credential: applicationDefault(), projectId });
const db = getFirestore();

if (configOnly) {
  const cfg = await cargarConfig(db);
  console.log(`\n=== Config prepago/comisión (${projectId}) ===`);
  imprimirConfig(cfg);
  console.log("\nEjecutá tests: cd functions && npm test\n");
  process.exit(0);
}

if (listMode) {
  console.log(`\n=== Taxistas con billetera (${projectId}) ===\n`);
  const snap = await db.collection("billeteras_taxista").limit(listLimit).get();
  const cfg = await cargarConfig(db);
  if (snap.empty) {
    console.log("Sin documentos en billeteras_taxista.");
    process.exit(0);
  }
  for (const d of snap.docs) {
    const b = d.data();
    const bloq = bloqueoOperativoPrepago(b, cfg);
    const uSnap = await db.collection("usuarios").doc(d.id).get();
    const u = uSnap.data() ?? {};
    console.log(d.id);
    console.log(
      `  nombre: ${str(u.nombre) || str(u.displayName) || "(sin nombre)"} | tienePagoPendiente=${u.tienePagoPendiente === true}`,
    );
    console.log(
      `  prepago: RD$ ${saldoPrepagoRd(b)} (disp RD$ ${saldoDisponibleRd(b)}) | pendiente RD$ ${comisionPendienteRd(b)}`,
    );
    console.log(
      `  primerViajeGratis: ${!primerViajeGratisConsumido(b) ? "SÍ (pendiente)" : "ya consumido"} | bloqueo calc: ${bloq.bloqueado ? "SÍ" : "no"} — ${bloq.motivo}`,
    );
    console.log("");
  }
  console.log("Auditar uno:");
  console.log(
    `  node functions/scripts/auditar-prepago-comision-taxista.mjs <uid> --project ${projectId}\n`,
  );
  process.exit(0);
}

if (!uidTaxista) {
  console.error(
    "Uso:\n" +
      "  node functions/scripts/auditar-prepago-comision-taxista.mjs <uidTaxista> [--viaje <id>] [--project flygo-rd]\n" +
      "  node functions/scripts/auditar-prepago-comision-taxista.mjs --list\n" +
      "  node functions/scripts/auditar-prepago-comision-taxista.mjs --config",
  );
  process.exit(1);
}

console.log(`\n=== Auditoría prepago/comisión · taxista ${uidTaxista} ===`);
console.log(`projectId=${projectId}`);

const cfg = await cargarConfig(db);
imprimirConfig(cfg);

const [billeSnap, userSnap] = await Promise.all([
  db.collection("billeteras_taxista").doc(uidTaxista).get(),
  db.collection("usuarios").doc(uidTaxista).get(),
]);

if (!userSnap.exists) {
  console.error("\nERROR: usuario no encontrado en usuarios/{uid}.");
  process.exit(2);
}

const u = userSnap.data() ?? {};
const bille = billeSnap.exists ? billeSnap.data() ?? {} : {};

console.log("\n--- Usuario taxista ---");
console.log(`  nombre: ${str(u.nombre) || str(u.displayName) || "(sin nombre)"}`);
console.log(`  rol: ${str(u.rol)} | bloqueado admin: ${u.bloqueado === true}`);
console.log(`  viajeActivoId: ${str(u.viajeActivoId) || "(ninguno)"}`);
console.log(`  tienePagoPendiente (Firestore): ${u.tienePagoPendiente === true}`);
console.log(`  deudaPoolPendienteRd: RD$ ${round2(num(u.deudaPoolPendienteRd))}`);

console.log("\n--- Billetera prepago ---");
if (!billeSnap.exists) {
  console.log("  (sin documento billeteras_taxista — se tratará como saldo 0)");
}
console.log(`  saldoPrepagoComisionRd: RD$ ${saldoPrepagoRd(bille)}`);
console.log(`  saldoReservadoParaGiras: RD$ ${saldoReservadoRd(bille)}`);
console.log(`  saldo DISPONIBLE: RD$ ${saldoDisponibleRd(bille)}`);
console.log(`  comisionPendiente: RD$ ${comisionPendienteRd(bille)}`);
console.log(
  `  primerViajeComisionGratisConsumido: ${primerViajeGratisConsumido(bille)}`,
);
console.log(`  ultimoViajeId: ${str(bille.ultimoViajeId) || "(ninguno)"}`);

const bloq = bloqueoOperativoPrepago(bille, cfg);
console.log(`\n  Bloqueo operativo (recalculado): ${bloq.bloqueado ? "SÍ" : "NO"} — ${bloq.motivo}`);

let deudaPoolRd = 0;
let poolsPendientes = 0;
try {
  const poolSnap = await db
    .collection("viajes_pool")
    .where("ownerTaxistaId", "==", uidTaxista)
    .where("comisionPendientePagoAdmin", "==", true)
    .limit(100)
    .get();
  poolsPendientes = poolSnap.size;
  for (const p of poolSnap.docs) {
    const d = p.data();
    deudaPoolRd += num(d.montoComisionPendienteAdmin ?? d.montoComision);
  }
  deudaPoolRd = round2(deudaPoolRd);
} catch (e) {
  console.log(`\n  AVISO pool query: ${e.message}`);
}

const bloqueoPool = deudaPoolRd + 1e-9 >= UMBRAL_DEUDA_POOL_RD;
const tienePagoEsperado = bloq.bloqueado || bloqueoPool;

console.log("\n--- Deuda pool (admin) ---");
console.log(`  pools con comisionPendientePagoAdmin: ${poolsPendientes}`);
console.log(`  deudaPool calculada: RD$ ${deudaPoolRd} (tope RD$ ${UMBRAL_DEUDA_POOL_RD})`);
console.log(`  bloqueo por pool: ${bloqueoPool ? "SÍ" : "no"}`);

const checks = [];
checks.push(
  comparar(
    "usuarios.tienePagoPendiente vs regla servidor",
    tienePagoEsperado,
    u.tienePagoPendiente === true,
  ),
);
checks.push(
  comparar(
    "usuarios.deudaPoolPendienteRd vs suma pools",
    deudaPoolRd,
    num(u.deudaPoolPendienteRd),
  ),
);

console.log("\n--- Paridad bloqueo (cliente/servidor) ---");
for (const c of checks) imprimirFila(c);

const viajeActivoId = str(u.viajeActivoId) || str(bille.ultimoViajeId);
const viajeId = viajeIdArg || viajeActivoId;

if (viajeId) {
  console.log(`\n--- Viaje ${viajeId} ---`);
  const vSnap = await db.collection("viajes").doc(viajeId).get();
  if (!vSnap.exists) {
    console.log("  Viaje no encontrado.");
  } else {
    const v = vSnap.data() ?? {};
    const aplicaPrepago = viajeAplicaComisionPrepago(v);
    const estado = str(v.estado);
    const comisionRd = comisionEstimadaRdDesdeViaje(v, cfg.comisionPct);
    const comisionCents = num(v.comision_cents);
    const gananciaCents = num(v.ganancia_cents);
    const precioCents = num(v.precio_cents) || round2(num(v.precio) * 100);

    console.log(`  estado: ${estado} | completado: ${v.completado === true}`);
    console.log(`  metodoPago: ${str(v.metodoPago)} | corporativo: ${v.corporativo === true}`);
    console.log(`  aplicaComisionPrepago: ${aplicaPrepago}`);
    console.log(`  codigoVerificado: ${v.codigoVerificado === true}`);
    console.log(`  pagoRegistrado: ${v.pagoRegistrado === true}`);
    console.log(`  precio: RD$ ${round2(precioCents / 100)}`);
    console.log(
      `  comision: RD$ ${round2(comisionCents / 100)} (estimada RD$ ${comisionRd})`,
    );
    console.log(`  gananciaTaxista: RD$ ${round2(gananciaCents / 100)}`);
    console.log(
      `  facturaSaldoPrepagoComisionRd: RD$ ${round2(num(v.facturaSaldoPrepagoComisionRd))}`,
    );

    const insuficiente = prepagoInsuficienteParaViajeEfectivo({
      billeData: bille,
      viajeData: v,
      globalComisionPct: cfg.comisionPct,
      permitirViajeConPrepagoParcial: cfg.permitirViajeConPrepagoParcial,
    });
    console.log(
      `  prepagoInsuficienteParaAceptar (estricto): ${insuficiente ? "SÍ rechazaría" : "no"}`,
    );

    const viajeChecks = [];
    if (aplicaPrepago && v.pagoRegistrado === true && comisionRd > 0) {
      viajeChecks.push(
        comparar(
          "comision_cents vs estimada",
          round2(comisionRd * 100),
          comisionCents,
          1,
        ),
      );
    }
    if (estado === "completado" && aplicaPrepago && !v.corporativo) {
      viajeChecks.push(
        comparar(
          "codigoVerificado antes de completar",
          true,
          v.codigoVerificado === true,
        ),
      );
    }

    const ledgerRef = db
      .collection("billeteras_taxista")
      .doc(uidTaxista)
      .collection("movimientos_prepago")
      .doc(`comision_viaje_${viajeId}`);
    const ledgerSnap = await ledgerRef.get();
    if (aplicaPrepago && v.pagoRegistrado === true) {
      viajeChecks.push(
        comparar(
          "ledger comision_viaje existe",
          true,
          ledgerSnap.exists,
        ),
      );
      if (ledgerSnap.exists) {
        const lg = ledgerSnap.data() ?? {};
        const total = round2(num(lg.comisionTotalRd));
        const desdeLegacy = round2(num(lg.desdeLegacyRd));
        const desdePrepago = round2(num(lg.desdePrepagoRd));
        console.log(`\n  Ledger movimiento:`);
        console.log(`    tipo: ${str(lg.tipo)}`);
        console.log(
          `    comisionTotal: RD$ ${total} | desdeLegacy: RD$ ${desdeLegacy} | desdePrepago: RD$ ${desdePrepago}`,
        );
        viajeChecks.push(
          comparar(
            "ledger suma = comisionTotal",
            total,
            desdeLegacy + desdePrepago,
            0.05,
          ),
        );
        if (lg.tipo === "primer_efectivo_sin_descuento") {
          viajeChecks.push(
            comparar("primer viaje gratis sin debito prepago", 0, desdePrepago),
          );
        }
      }
    }

    console.log("\n--- Validación viaje ---");
    if (viajeChecks.length === 0) {
      console.log("  (viaje no aplica prepago o aún no finalizado)");
    } else {
      for (const c of viajeChecks) imprimirFila(c);
    }
  }
}

console.log("\n--- Recargas recientes ---");
const recSnap = await db
  .collection("recargas_comision_taxista")
  .where("uidTaxista", "==", uidTaxista)
  .limit(5)
  .get();
if (recSnap.empty) {
  console.log("  Sin recargas registradas.");
} else {
  for (const r of recSnap.docs) {
    const d = r.data();
    console.log(
      `  ${r.id}: RD$ ${round2(num(d.montoDeclaradoRd ?? d.montoElegidoRd))} | estado=${str(d.estado)} | ${str(d.creadoEn) || ""}`,
    );
  }
}

console.log("\n--- Checklist flujo de negocio ---");
const pasos = [
  {
    paso: "1. Primer viaje gratis",
    ok: !primerViajeGratisConsumido(bille),
    detalle: primerViajeGratisConsumido(bille)
      ? "Ya consumido — exige prepago/deuda cero"
      : "Disponible — puede aceptar sin recarga",
  },
  {
    paso: "2. Puede operar (no bloqueado)",
    ok: !tienePagoEsperado && u.bloqueado !== true,
    detalle: tienePagoEsperado
      ? `Bloqueado: ${bloq.motivo}${bloqueoPool ? " + deuda pool" : ""}`
      : "Puede aceptar viajes / estar disponible",
  },
  {
    paso: "3. Saldo para comisión (modo actual)",
    ok:
      !primerViajeGratisConsumido(bille) ||
      saldoDisponibleRd(bille) > 0 ||
      comisionPendienteRd(bille) === 0,
    detalle: `Disp RD$ ${saldoDisponibleRd(bille)} | pendiente RD$ ${comisionPendienteRd(bille)}`,
  },
  {
    paso: "4. Viaje activo / PIN / navegación",
    ok: !str(u.viajeActivoId) || true,
    detalle: str(u.viajeActivoId)
      ? `Viaje activo: ${u.viajeActivoId} — verificar codigoVerificado en auditoría viaje`
      : "Sin viaje activo ahora",
  },
  {
    paso: "5. Recarga ADM",
    ok: !tienePagoEsperado || recSnap.docs.some((d) => d.data().estado === "pendiente_verificacion"),
    detalle: tienePagoEsperado
      ? "Depositar y enviar comprobante en Mis pagos → ADM aprueba"
      : "No requiere recarga urgente",
  },
];

for (const p of pasos) {
  console.log(`  ${p.ok ? "✓" : "○"} ${p.paso}: ${p.detalle}`);
}

const fallos = checks.filter((c) => !c.ok);
console.log("\n--- Resumen ---");
if (fallos.length === 0) {
  console.log("  ESTADO: billetera y flags de bloqueo CUADRADOS con servidor ✓");
} else {
  console.log(
    `  ESTADO: ${fallos.length} desalineación(es) en flags — ejecutá sincronizarBloqueoOperativoTaxista o revisá ADM.`,
  );
}
if (comisionPendienteRd(bille) >= UMBRAL_COMISION_LEGACY_RD) {
  console.log(
    `  AVISO: comisionPendiente >= RD$ ${UMBRAL_COMISION_LEGACY_RD} (tope legacy).`,
  );
}
console.log("\nTests unitarios: cd functions && npm test\n");
