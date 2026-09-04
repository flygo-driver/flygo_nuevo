/**
 * Activa recaudo central giras por cupos en config/finance (flygo-rd).
 *
 * Autenticación (elige UNA):
 *   gcloud auth application-default login
 *   — o —
 *   gcloud auth login && gcloud config set project flygo-rd
 *
 * Uso:
 *   node scripts/seed_finance_pool_central.mjs
 */
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { authHelpText, seedConfigDocs } from "./firestore_seed_auth.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(
  path.join(__dirname, "..", "functions", "package.json"),
);
const admin = require("firebase-admin");

const projectId = process.env.FIREBASE_PROJECT_ID || "flygo-rd";

const patch = {
  poolRecaudoCentralHabilitado: true,
  poolRecaudoSoloNuevasGiras: true,
  poolLiquidacionAlFinalizar: true,
  poolRecaudoAutoVerificarConciliacion: true,
  transferenciaRecaudoEnCuentaRai: false,
  conciliacionAutomaticaHabilitada: true,
};

function printManualFallback() {
  console.error("\n--- Alternativa manual (Firebase Console) ---");
  console.error("Firestore → config/finance → merge (no borrar otros campos):");
  console.error(JSON.stringify(patch, null, 2));
}

async function main() {
  await seedConfigDocs({
    projectId,
    admin,
    patches: { finance: patch },
  });
  console.log("OK config/finance", patch);
}

main().catch((e) => {
  console.error(e?.message ?? e);
  console.error("\n" + authHelpText());
  printManualFallback();
  process.exit(1);
});
