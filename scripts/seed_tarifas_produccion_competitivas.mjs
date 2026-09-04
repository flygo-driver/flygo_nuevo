/**
 * Publica tarifas competitivas en producción (flygo-rd):
 *   - tarifas/general → Carro porKm 22, mínimo 150
 *   - config/tarifas_tramos → tramo urbano Carro 22 RD$/km
 *
 * El mínimo RD$175 desde 2 km y recargos hora pico/lluvia/tráfico viven en la app.
 *
 * Uso:
 *   gcloud auth application-default login
 *   node scripts/seed_tarifas_produccion_competitivas.mjs
 *
 * Alternativa:
 *   gcloud auth login && gcloud config set project flygo-rd
 */
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { authHelpText, seedConfigDocs, seedFirestoreDoc } from "./firestore_seed_auth.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(__dirname, "..", "functions", "package.json"));
const admin = require("firebase-admin");

const projectId = process.env.FIREBASE_PROJECT_ID || "flygo-rd";

const tarifasTramos = {
  activo: true,
  tramosKm: [40, 80, 140],
  minimoLargaDistanciaRd: 1200,
  promoAplicaSoloTramoLocal: true,
  distanciaMaximaCotizableKm: 800,
  version: 2,
  nota: "Tarifa competitiva urbano Carro RD$22/km; tramo 40–80 = RD$35/km — mar 2026",
  porVehiculo: {
    Carro: { porKmPorTramo: [22, 35, 53, 63] },
    Jeepeta: { porKmPorTramo: [30, 45, 65, 80] },
    Minivan: { porKmPorTramo: [32, 47, 68, 82] },
    "Minibús": { porKmPorTramo: [35, 50, 70, 85] },
    AutobusGuagua: { porKmPorTramo: [45, 60, 80, 95] },
    motor: { porKmPorTramo: [12, 20, 35, 42] },
    carro: { porKmPorTramo: [22, 35, 53, 63] },
    jeepeta: { porKmPorTramo: [30, 45, 65, 80] },
    minivan: { porKmPorTramo: [32, 47, 68, 82] },
    bus: { porKmPorTramo: [45, 60, 80, 95] },
  },
};

const carroUrbano = {
  base: 50,
  porKm: 22,
  minimo: 150,
};

async function main() {
  await seedFirestoreDoc({
    projectId,
    admin,
    docPath: "tarifas/general",
    patch: {
      Carro: carroUrbano,
      carro: carroUrbano,
    },
  });
  console.log("OK tarifas/general Carro", carroUrbano);

  await seedConfigDocs({
    projectId,
    admin,
    patches: { tarifas_tramos: tarifasTramos },
  });
  console.log("OK config/tarifas_tramos activo=true Carro tramo1=22");
}

main().catch((e) => {
  console.error(e?.message ?? e);
  console.error("\n" + authHelpText());
  process.exit(1);
});
