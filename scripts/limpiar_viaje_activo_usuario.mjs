/**
 * Limpia viajeActivoId huérfano (viaje inexistente o ya terminal) en usuarios.
 *
 *   gcloud auth application-default login
 *   node scripts/limpiar_viaje_activo_usuario.mjs cintnen@hotmail.com
 *   node scripts/limpiar_viaje_activo_usuario.mjs --uid ABC123
 */
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { authHelpText } from "./firestore_seed_auth.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(
  path.join(__dirname, "..", "functions", "package.json"),
);
const admin = require("firebase-admin");

const projectId = process.env.FIREBASE_PROJECT_ID || "flygo-rd";

const TERMINALES = new Set([
  "completado",
  "cancelado",
  "cancelado_cliente",
  "cancelado_taxista",
  "cancelado_sistema",
  "no_show",
  "expirado",
  "rechazado",
  "finalizado",
]);

function normEstado(raw) {
  return String(raw ?? "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "_");
}

function viajeOperativo(d, uid) {
  if (!d || typeof d !== "object") return false;
  if (d.completado === true) return false;
  const st = normEstado(d.estado);
  if (TERMINALES.has(st)) return false;
  const t1 = String(d.uidTaxista ?? d.taxistaId ?? "").trim();
  if (t1 && t1 !== uid) return false;
  return true;
}

async function resolveUid(arg) {
  if (arg.startsWith("--uid=")) return arg.slice("--uid=".length).trim();
  if (arg === "--uid") return "";
  if (arg.includes("@")) {
    const user = await admin.auth().getUserByEmail(arg.trim());
    return user.uid;
  }
  return arg.trim();
}

async function limpiarUsuario(db, uid) {
  const uRef = db.collection("usuarios").doc(uid);
  const uSnap = await uRef.get();
  if (!uSnap.exists) {
    console.log(`[limpiar] usuarios/${uid} no existe`);
    return;
  }
  const u = uSnap.data() ?? {};
  const activo = String(u.viajeActivoId ?? "").trim();
  const siguiente = String(u.siguienteViajeId ?? "").trim();
  console.log(`[limpiar] uid=${uid} viajeActivoId=${activo || "(vacío)"} siguienteViajeId=${siguiente || "(vacío)"}`);

  const patch = {};
  const ts = admin.firestore.FieldValue.serverTimestamp();

  if (activo) {
    const vSnap = await db.collection("viajes").doc(activo).get();
    if (!vSnap.exists || !viajeOperativo(vSnap.data(), uid)) {
      patch.viajeActivoId = "";
      console.log(
        `[limpiar] → borrar viajeActivoId (${!vSnap.exists ? "viaje no existe" : "no operativo"})`,
      );
    } else {
      console.log(`[limpiar] viajeActivoId OK (viaje operativo ${activo})`);
    }
  }

  if (siguiente) {
    const sSnap = await db.collection("viajes").doc(siguiente).get();
    if (!sSnap.exists) {
      patch.siguienteViajeId = "";
      console.log("[limpiar] → borrar siguienteViajeId (viaje no existe)");
    }
  }

  if (Object.keys(patch).length === 0) {
    console.log("[limpiar] nada que limpiar");
    return;
  }

  patch.updatedAt = ts;
  patch.actualizadoEn = ts;
  await uRef.set(patch, { merge: true });
  console.log("[limpiar] OK", patch);
}

const rawArg = process.argv[2];
if (!rawArg) {
  console.error("Uso: node scripts/limpiar_viaje_activo_usuario.mjs EMAIL|UID");
  console.error(authHelpText());
  process.exit(1);
}

try {
  if (!admin.apps.length) {
    admin.initializeApp({ projectId });
  }
  const db = admin.firestore();
  const uid = await resolveUid(rawArg);
  if (!uid) {
    console.error("UID inválido");
    process.exit(1);
  }
  await limpiarUsuario(db, uid);
} catch (e) {
  console.error("[limpiar] error:", e?.message ?? e);
  console.error(authHelpText());
  process.exit(1);
}
