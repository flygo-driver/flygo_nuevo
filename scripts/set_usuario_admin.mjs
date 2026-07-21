/**
 * Pone rol admin coherente en usuarios/{uid} + roles/{uid}.
 *
 * Uso (PowerShell), desde la raíz del repo:
 *   gcloud auth application-default login
 *   node scripts/set_usuario_admin.mjs HHzQ3bdtP9M5JA1ziJDV216Q0dd2
 */
import admin from "firebase-admin";

const projectId = "flygo-rd";
const uid = (process.argv[2] || "").trim();
if (!uid) {
  console.error("Falta uid. Ejemplo: node scripts/set_usuario_admin.mjs HHzQ3bdtP9M5JA1ziJDV216Q0dd2");
  process.exit(1);
}

admin.initializeApp({ projectId });
const db = admin.firestore();
const now = admin.firestore.FieldValue.serverTimestamp();

const uRef = db.collection("usuarios").doc(uid);
const rRef = db.collection("roles").doc(uid);

const beforeU = await uRef.get();
const beforeR = await rRef.get();
console.log("ANTES usuarios.rol =", beforeU.exists ? beforeU.data()?.rol : "(no existe)");
console.log("ANTES roles.rol    =", beforeR.exists ? beforeR.data()?.rol : "(no existe)");

await uRef.set(
  {
    rol: "admin",
    isAdmin: true,
    admin: true,
    updatedAt: now,
    actualizadoEn: now,
  },
  { merge: true },
);
await rRef.set(
  {
    rol: "admin",
    updatedAt: now,
    actualizadoEn: now,
  },
  { merge: true },
);

const afterU = await uRef.get();
const afterR = await rRef.get();
console.log("DESPUÉS usuarios.rol =", afterU.data()?.rol, "isAdmin =", afterU.data()?.isAdmin);
console.log("DESPUÉS roles.rol    =", afterR.data()?.rol);
console.log("OK uid", uid);
process.exit(0);
