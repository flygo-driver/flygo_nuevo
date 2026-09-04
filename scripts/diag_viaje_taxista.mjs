/**
 * Diagnóstico + limpieza viaje taxista atascado.
 * node scripts/diag_viaje_taxista.mjs cintnen@hotmail.com
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

async function resolveUid(arg) {
  if (arg.includes("@")) {
    const user = await admin.auth().getUserByEmail(arg.trim());
    return user.uid;
  }
  return arg.trim();
}

function pickFields(d) {
  return {
    estado: d.estado,
    activo: d.activo,
    completado: d.completado,
    taxistaLiberado: d.taxistaLiberado,
    uidTaxista: d.uidTaxista ?? d.taxistaId,
    uidCliente: d.uidCliente ?? d.clienteId,
    codigoVerificacion: d.codigoVerificacion,
    clienteAbordo: d.clienteAbordo,
    tipoServicio: d.tipoServicio,
    updatedAt: d.updatedAt?.toDate?.()?.toISOString?.() ?? d.updatedAt,
  };
}

try {
  const email = process.argv[2] || "cintnen@hotmail.com";
  if (!admin.apps.length) admin.initializeApp({ projectId });
  const db = admin.firestore();
  const uid = await resolveUid(email);
  console.log("uid:", uid);

  const uSnap = await db.collection("usuarios").doc(uid).get();
  console.log("\n=== usuarios/" + uid + " ===");
  if (uSnap.exists) {
    const u = uSnap.data();
    console.log({
      viajeActivoId: u.viajeActivoId ?? "",
      siguienteViajeId: u.siguienteViajeId ?? "",
      email: u.email,
      nombre: u.nombre ?? u.displayName,
    });
  } else {
    console.log("(doc no existe)");
  }

  const queries = [
    ["uidTaxista", uid],
    ["taxistaId", uid],
  ];
  const seen = new Set();
  const viajes = [];

  for (const [field, val] of queries) {
    const snap = await db
      .collection("viajes")
      .where(field, "==", val)
      .orderBy("updatedAt", "desc")
      .limit(15)
      .get()
      .catch(async () => {
        return db.collection("viajes").where(field, "==", val).limit(15).get();
      });
    for (const doc of snap.docs) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      viajes.push({ id: doc.id, ...pickFields(doc.data()) });
    }
  }

  console.log("\n=== viajes recientes del taxista (" + viajes.length + ") ===");
  for (const v of viajes) {
    console.log(JSON.stringify(v, null, 2));
  }

  const activos = viajes.filter(
    (v) =>
      v.activo === true &&
      v.completado !== true &&
      v.taxistaLiberado !== true &&
      !["completado", "cancelado", "cancelado_cliente", "cancelado_taxista", "finalizado", "expirado"].includes(
        String(v.estado ?? "").toLowerCase(),
      ),
  );
  console.log("\n=== candidatos activos (" + activos.length + ") ===");
  for (const v of activos) {
    console.log(
      `ID=${v.id} estado=${v.estado} PIN=${v.codigoVerificacion ?? "(sin código)"}`,
    );
  }

  const limpiar = process.argv.includes("--limpiar");
  if (limpiar && activos.length > 0) {
    const ts = admin.firestore.FieldValue.serverTimestamp();
    for (const v of activos) {
      await db.collection("viajes").doc(v.id).set(
        {
          activo: false,
          completado: true,
          taxistaLiberado: true,
          estado: "cancelado_sistema",
          canceladoPor: "admin_script",
          motivoCancelacion: "viaje_fantasma_limpieza",
          updatedAt: ts,
        },
        { merge: true },
      );
      console.log("[limpiar] viaje cancelado:", v.id);
    }
    await db.collection("usuarios").doc(uid).set(
      {
        viajeActivoId: "",
        updatedAt: ts,
        actualizadoEn: ts,
      },
      { merge: true },
    );
    console.log("[limpiar] viajeActivoId borrado en usuario");
  } else if (limpiar) {
    await db.collection("usuarios").doc(uid).set(
      {
        viajeActivoId: "",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    console.log("[limpiar] solo viajeActivoId borrado (sin viajes activos en query)");
  }
} catch (e) {
  console.error("error:", e?.message ?? e);
  console.error(authHelpText());
  process.exit(1);
}
