/**
 * Viajes taxi: transferencia al taxista (no cuenta RAI).
 * Giras recaudo central no usan este flag (tienen recaudoModelo: central).
 *
 *   gcloud auth application-default login
 *   node scripts/patch_transferencia_taxista.mjs
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
  transferenciaRecaudoEnCuentaRai: false,
};

function printManualFallback() {
  console.error("\n--- Alternativa manual (Firebase Console) ---");
  console.error("Firestore → config/finance → merge:");
  console.error(JSON.stringify(patch, null, 2));
}

try {
  await seedConfigDocs({
    admin,
    projectId,
    docs: [{ collection: "config", id: "finance", patch }],
  });
  console.log(`[patch_transferencia_taxista] OK ${projectId} config/finance`, patch);
} catch (e) {
  console.error("[patch_transferencia_taxista] error:", e?.message ?? e);
  console.error(authHelpText);
  printManualFallback();
  process.exit(1);
}
