/**
 * Baja el tramo 40–80 km (~RD$5/km) para rutas interurbanas vs InDriver.
 * Solo toca config/tarifas_tramos — la app ya lee Firestore.
 *
 * Antes (Carro): [22, 40, 53, 63]
 * Después (Carro): [22, 35, 53, 63]
 *
 * Uso:
 *   gcloud auth application-default login
 *   node scripts/seed_tarifas_tramo_40_80_competitivo.mjs
 */
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { authHelpText, seedConfigDocs } from "./firestore_seed_auth.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(__dirname, "..", "functions", "package.json"));
const admin = require("firebase-admin");

const projectId = process.env.FIREBASE_PROJECT_ID || "flygo-rd";

/** Segundo tramo (índice 1 = km 40–80) −5 RD$/km en cada vehículo. */
const porVehiculo = {
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
};

const patch = {
  activo: true,
  porVehiculo,
  version: 3,
  nota: "Tramo 40–80 km más competitivo (Carro 35 RD$/km) — mar 2026",
};

async function main() {
  await seedConfigDocs({
    projectId,
    admin,
    patches: { tarifas_tramos: patch },
  });
  console.log("OK config/tarifas_tramos — tramo 40–80 actualizado");
  console.log("Carro porKmPorTramo:", porVehiculo.Carro.porKmPorTramo.join(", "));
  console.log("");
  console.log("Ejemplo SD → La Romana (~120 km Carro):");
  console.log("  Antes ~RD$4,650 → Ahora ~RD$4,450 (−RD$200)");
}

main().catch((e) => {
  console.error(e?.message ?? e);
  console.error("\n" + authHelpText());
  process.exit(1);
});
