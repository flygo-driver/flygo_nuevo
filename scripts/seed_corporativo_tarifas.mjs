/**
 * Tarifas corporativas RD: combustible + 5% empresa + 90% chofer.
 *
 * Uso: cd functions && node ../scripts/seed_corporativo_tarifas.mjs
 */
import { createRequire } from "module";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(join(__dirname, "../functions/package.json"));
const admin = require("firebase-admin");

const data = {
  modeloTarifa: "dinamica",
  minimoViajeRd: 550,
  factorKmCarretera: 1.15,
  recargoZonaDificilPorcentaje: 0,
  tasa_impuesto_transferencia: 0.002,
  tasaImpuestoTransferencia: 0.002,
  recargoTransferenciaPorcentaje: 0.2,
  retencionIsrPorcentaje: 2,
  itbisPorcentaje: 18,
  incluirItbisEnPrecioViaje: false,
  usarComisionGlobalViaje: false,
  comisionPlataformaPorcentaje: 10,
  dinamicaBaseRd: 200,
  dinamicaPorKmCortoRd: 18,
  dinamicaPorKmLargoRd: 24,
  dinamicaUmbralKmLargo: 12,
  dinamicaPorMinutoRd: 7,
  dinamicaMinutosPorKm: 1.4,
  dinamicaMinutosPorParada: 4,
  dinamicaMinutosMinimo: 10,
  precioCombustibleLitroRd: 330,
  rendimientoVehiculoKmPorLitro: 11,
  factorOperativoSobreCombustible: 1.35,
  recargoEmpresaServicioPorcentaje: 5,
  uberBaseRd: 200,
  uberPorKmCortoRd: 18,
  uberPorKmLargoRd: 24,
  uberUmbralKmLargo: 12,
  uberPorMinutoRd: 7,
  uberMinutosPorKm: 1.4,
  uberMinutosPorParada: 4,
  uberMinutosMinimo: 10,
  motivoAjuste:
    "RD 2026: combustible ref. + 5% B2B + comisión 10% / chofer 90%",
};

if (!admin.apps.length) {
  admin.initializeApp({ projectId: "flygo-rd" });
}

await admin.firestore().doc("config/corporativo").set(
  {
    ...data,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  },
  { merge: true },
);

console.log("OK config/corporativo actualizado:");
console.log(JSON.stringify(data, null, 2));
process.exit(0);
