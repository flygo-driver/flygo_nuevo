/**
 * Config producción soportable (flygo-rd): finance seguro + núcleo taxi/motor.
 *
 * Autenticación:
 *   gcloud auth application-default login
 *   node scripts/seed_config_lanzamiento_produccion.mjs
 *
 * (firebase login solo NO funciona para escribir Firestore vía REST)
 */
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import path from "node:path";

import { authHelpText, seedConfigDocs } from "./firestore_seed_auth.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(
  path.join(__dirname, "..", "functions", "package.json"),
);
const admin = require("firebase-admin");

const projectId = process.env.FIREBASE_PROJECT_ID || "flygo-rd";

const financePatch = {
  pagosConTarjetaAzulHabilitados: false,
  poolRecaudoCentralHabilitado: true,
  poolRecaudoSoloNuevasGiras: true,
  poolLiquidacionAlFinalizar: true,
  poolRecaudoAutoVerificarConciliacion: true,
  transferenciaRecaudoEnCuentaRai: true,
  transferenciaExigeVerificadoParaFinalizar: false,
  conciliacionAutomaticaHabilitada: true,
};

const productosPatch = {
  modoLanzamientoNucleo: false,
  clienteBolaHabilitado: true,
  clienteMultiparadaHabilitado: true,
  clienteMotorHabilitado: true,
  clienteGirasHabilitado: true,
  clienteTurismoHabilitado: true,
};

function printManualFallback() {
  console.error("\n--- Alternativa manual (Firebase Console) ---");
  console.error("Firestore → config/finance → merge:");
  console.error(JSON.stringify(financePatch, null, 2));
  console.error("\nFirestore → config/productos → merge (crear doc si no existe):");
  console.error(JSON.stringify(productosPatch, null, 2));
}

async function main() {
  await seedConfigDocs({
    projectId,
    admin,
    patches: {
      finance: financePatch,
      productos: productosPatch,
    },
  });

  console.log("OK config/finance", financePatch);
  console.log("OK config/productos", productosPatch);
  console.log(
    "\nHome cliente: todas las secciones visibles (modoLanzamientoNucleo: false).",
  );
}

main().catch((e) => {
  console.error(e?.message ?? e);
  console.error("\n" + authHelpText());
  printManualFallback();
  process.exit(1);
});
