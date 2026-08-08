/**
 * Semilla `config/comision` con % de apertura (efectivo 10, transferencia 15, tarjeta 15).
 * Uso: node scripts/seed_comision_metodos.mjs
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
  porcentaje: 10,
  porcentajeTransferencia: 15,
  porcentajeTarjeta: 15,
  nota: "Apertura RAI: efectivo 10%, transferencia 15%, tarjeta 15%",
};

async function main() {
  await seedConfigDocs({
    projectId,
    admin,
    patches: { comision: patch },
  });
  console.log("OK config/comision", patch);
}

main().catch((e) => {
  console.error(e?.message ?? e);
  console.error("\n" + authHelpText());
  console.error("\n--- Alternativa manual (Firebase Console) ---");
  console.error("Firestore → config/comision → merge:");
  console.error(JSON.stringify(patch, null, 2));
  process.exit(1);
});
