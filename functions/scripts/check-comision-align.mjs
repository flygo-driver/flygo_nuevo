/**
 * Lee config/comision vs configuracion_globals/app (flygo-rd).
 *
 *   gcloud auth application-default login
 *   node functions/scripts/check-comision-align.mjs
 *
 * Opcional: GOOGLE_CLOUD_PROJECT=flygo-rd
 */
import { initializeApp, applicationDefault } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

const projectId = process.env.GOOGLE_CLOUD_PROJECT || "flygo-rd";

function normPct(raw) {
  if (typeof raw !== "number" || !Number.isFinite(raw)) return null;
  let n = raw;
  if (n > 0 && n <= 1.001) n *= 100;
  return Math.min(100, Math.max(0, n));
}

initializeApp({ credential: applicationDefault(), projectId });
const db = getFirestore();

const [comSnap, appSnap, prepSnap] = await Promise.all([
  db.collection("config").doc("comision").get(),
  db.collection("configuracion_globals").doc("app").get(),
  db.collection("config").doc("comision_prepago").get(),
]);

const viaje = normPct(comSnap.data()?.porcentaje);
const gira = normPct(appSnap.data()?.comision_gira_porcentaje);

console.log(`projectId=${projectId}`);
console.log("config/comision:", comSnap.data() ?? "(no existe)");
console.log(
  "configuracion_globals/app.comision_gira_porcentaje:",
  appSnap.data()?.comision_gira_porcentaje ?? "(no existe)",
);
console.log("config/comision_prepago:", prepSnap.data() ?? "(no existe)");
console.log(`normalizado → viaje=${viaje}% gira=${gira}%`);

if (viaje != null && gira != null) {
  const diff = Math.abs(viaje - gira);
  if (diff < 0.05) {
    console.log("ALINEACION: OK");
  } else {
    console.log(`ALINEACION: DESALINEADO (Δ ${diff.toFixed(2)} pp)`);
    console.log("\nMigración recomendada (espejo legacy → fuente de verdad):");
    console.log(
      `  configuracion_globals/app  →  comision_gira_porcentaje: ${viaje}`,
    );
    console.log(
      "\nO desde ADM (tras deploy setComisionPorcentaje): guardar el mismo % en «Comisión viaje».",
    );
  }
} else if (viaje != null && gira == null) {
  console.log("ALINEACION: OK en runtime (solo config/comision); espejo legacy opcional.");
  console.log(`  configuracion_globals/app  →  comision_gira_porcentaje: ${viaje}`);
} else if (viaje == null && gira != null) {
  console.log("ALINEACION: falta config/comision; crear con el % deseado.");
  console.log(`  config/comision  →  porcentaje: ${gira}`);
} else {
  console.log("ALINEACION: sin docs; código usa default 20%.");
}
