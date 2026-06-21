/**
 * Publica cuenta empresa RAI en Firestore app_config/pagos (flygo-rd).
 *
 * Autenticación (elige UNA):
 *   gcloud auth application-default login
 *   — o —
 *   gcloud auth login && gcloud config set project flygo-rd
 *
 * Uso:
 *   node scripts/seed_app_config_pagos.mjs
 */
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { authHelpText, seedFirestoreDoc } from "./firestore_seed_auth.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(
  path.join(__dirname, "..", "functions", "package.json"),
);
const admin = require("firebase-admin");

const projectId = process.env.FIREBASE_PROJECT_ID || "flygo-rd";

const data = {
  banco_nombre: "Banco Popular",
  tipo_cuenta: "Cuenta Corriente",
  numero_cuenta: "787726249",
  titular: "Open ASK Service SRL",
  rnc: "1320-11767",
  alias: "",
  nota:
    "Depósito a Open ASK Service SRL (RAI). En concepto indique su nombre de conductor o la referencia que aparece en Mis pagos.",
  qr_url: "",
  whatsapp_soporte: "",
};

function printManualFallback() {
  console.error("\n--- Alternativa manual (Firebase Console) ---");
  console.error("Firestore → app_config/pagos → merge (no borrar otros campos):");
  console.error(JSON.stringify(data, null, 2));
}

async function main() {
  await seedFirestoreDoc({
    projectId,
    admin,
    docPath: "app_config/pagos",
    patch: data,
  });
  console.log(`OK app_config/pagos (${projectId})`, data);
}

main().catch((e) => {
  console.error(e?.message ?? e);
  console.error("\n" + authHelpText());
  printManualFallback();
  process.exit(1);
});
