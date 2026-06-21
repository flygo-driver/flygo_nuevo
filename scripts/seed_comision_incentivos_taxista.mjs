/**
 * Config por defecto de incentivos comisión taxista (config/comision_incentivos_taxista).
 * Merge: no borra otros docs ni activa el programa hasta que admin lo encienda.
 *
 * Requiere firebase-admin (doc con array `escalones`):
 *   gcloud auth application-default login
 *   — o —
 *   set GOOGLE_APPLICATION_CREDENTIALS=ruta\\service-account.json
 *
 * Uso:
 *   node scripts/seed_comision_incentivos_taxista.mjs
 *
 * Para activar en producción: admin → Incentivos comisión taxista → Programa activo.
 */
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { authHelpText, isCredentialError } from "./firestore_seed_auth.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(
  path.join(__dirname, "..", "functions", "package.json"),
);
const admin = require("firebase-admin");

const projectId = process.env.FIREBASE_PROJECT_ID || "flygo-rd";

/** Inactivo por defecto: no cambia facturación hasta que admin active el programa. */
const patch = {
  activo: false,
  ventana: "semana",
  escalones: [
    { viajesMinimos: 20, comisionPct: 15, etiqueta: "Conductor activo" },
    { viajesMinimos: 40, comisionPct: 12, etiqueta: "Conductor estrella" },
  ],
};

function printManualFallback() {
  console.error("\n--- Alternativa manual (Firebase Console) ---");
  console.error("Firestore → config/comision_incentivos_taxista → merge:");
  console.error(JSON.stringify(patch, null, 2));
}

async function main() {
  try {
    if (!admin.apps.length) {
      admin.initializeApp({ projectId });
    }
    const db = admin.firestore();
    await db.doc("config/comision_incentivos_taxista").set(
      {
        ...patch,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    console.log(`OK config/comision_incentivos_taxista (${projectId})`);
    console.log(JSON.stringify(patch, null, 2));
    console.log(
      "\nNota: activo=false — la comisión sigue siendo la global hasta activar en admin.",
    );
  } catch (e) {
    if (isCredentialError(e)) {
      throw new Error(
        `${authHelpText()}\n\nEste seed usa firebase-admin (array escalones). ` +
          "OAuth gcloud no escribe arrays; usa application-default login.",
      );
    }
    throw e;
  }
}

main().catch((e) => {
  console.error(e?.message ?? e);
  printManualFallback();
  process.exit(1);
});
