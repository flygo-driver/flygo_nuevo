/**
 * Activa liquidaciones semanales PR2 en config/finance (flygo-rd).
 *
 * Autenticación (elige UNA):
 *   gcloud auth application-default login
 *   — o —
 *   gcloud auth login && gcloud config set project flygo-rd
 *
 * Uso:
 *   node scripts/seed_finance_pr2_liquidaciones.mjs
 *
 * Rollback:
 *   node scripts/seed_finance_pr2_liquidaciones.mjs --rollback
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
const rollback = process.argv.includes("--rollback");

const patch = rollback
  ? {
      useLiquidacionesSemanales: false,
      escrituraPagosTaxistasLegacy: true,
      notaPr2: "Rollback PR2 manual",
    }
  : {
      useLiquidacionesSemanales: true,
      escrituraPagosTaxistasLegacy: false,
      notaPr2:
        "PR2 activo: liquidaciones_semanales + panel ADM Verificar pagos",
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
  console.log(rollback ? "ROLLBACK OK" : "ACTIVACIÓN OK", "config/finance", patch);
  if (!rollback) {
    console.log(
      "\nSiguiente: ADM → Verificar pagos → Comisiones semanales → pestaña «A liquidar».",
    );
  }
}

main().catch((e) => {
  console.error(e?.message ?? e);
  console.error("\n" + authHelpText());
  printManualFallback();
  process.exit(1);
});
