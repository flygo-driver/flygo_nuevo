/**
 * Limpia estado operativo sucio del piloto corporativo (pruebas de hora/viajes viejos).
 *
 * Uso (PowerShell, desde raíz del repo):
 *   gcloud auth application-default login
 *   node scripts/reset_piloto_corporativo.mjs
 *   node scripts/reset_piloto_corporativo.mjs --empresa=zdTBOgWjOfrl5q243tRV --chofer=4CyXCaseJwPkiIj9snV8ABVkcJ92
 *   node scripts/reset_piloto_corporativo.mjs --dry-run
 */
import admin from "./lib/firebase_admin.mjs";

const projectId = "flygo-rd";
const DEFAULT_EMPRESA = "zdTBOgWjOfrl5q243tRV";
const DEFAULT_CHOFER = "4CyXCaseJwPkiIj9snV8ABVkcJ92";

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const empresaId =
  args.find((a) => a.startsWith("--empresa="))?.split("=")[1]?.trim() ||
  DEFAULT_EMPRESA;
const choferUid =
  args.find((a) => a.startsWith("--chofer="))?.split("=")[1]?.trim() ||
  DEFAULT_CHOFER;

admin.initializeApp({ projectId });
const db = admin.firestore();
const now = admin.firestore.FieldValue.serverTimestamp();

function hoyRd() {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Santo_Domingo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function esHoyRd(ts) {
  if (!ts) return false;
  const d = ts.toDate ? ts.toDate() : new Date(ts);
  const key = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Santo_Domingo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
  return key === hoyRd();
}

async function cancelarViaje(id, data) {
  const estado = String(data.estado ?? "").toLowerCase();
  if (data.completado === true) return false;
  if (
    estado === "cancelado" ||
    estado === "rechazado" ||
    estado === "cancelado_por_tiempo"
  ) {
    console.log(`  cerrar viaje ${id} (${estado}, completado=false)`);
    if (!dryRun) {
      await db.collection("viajes").doc(id).set(
        {
          estado: "cancelado",
          completado: true,
          aceptado: false,
          rechazado: true,
          activo: false,
          corporativoSupersedidoPor: "reset_piloto",
          corporativoSupersedidoEn: now,
          canceladoMotivo: "reset_piloto_laboratorio",
          updatedAt: now,
          actualizadoEn: now,
        },
        { merge: true },
      );
    }
    return true;
  }
  if (estado === "en_curso" || estado === "a_bordo" || estado === "abordo") {
    console.log(`  SKIP en curso: ${id} (${estado})`);
    return false;
  }
  console.log(`  cancelar viaje ${id} (${estado || "?"})`);
  if (!dryRun) {
    await db.collection("viajes").doc(id).set(
      {
        estado: "cancelado",
        completado: true,
        aceptado: false,
        rechazado: true,
        activo: false,
        corporativoSupersedidoPor: "reset_piloto",
        corporativoSupersedidoEn: now,
        canceladoMotivo: "reset_piloto_laboratorio",
        updatedAt: now,
        actualizadoEn: now,
      },
      { merge: true },
    );
  }
  return true;
}

async function main() {
  console.log(`Proyecto: ${projectId}`);
  console.log(`Empresa:  ${empresaId}`);
  console.log(`Chofer:   ${choferUid}`);
  console.log(`Modo:     ${dryRun ? "DRY-RUN" : "EJECUTAR"}`);
  console.log("");

  let cancelados = 0;

  const q = await db
    .collection("viajes")
    .where("corporativoEmpresaId", "==", empresaId)
    .limit(80)
    .get();

  for (const doc of q.docs) {
    const d = doc.data();
    const esCorp =
      d.corporativo === true ||
      String(d.corporativoEmpresaId ?? "") === empresaId;
    if (!esCorp) continue;
    if (await cancelarViaje(doc.id, d)) cancelados++;
  }

  // Viajes huérfanos por nombre (empresa borrada fuera del flujo normal).
  const corp = await db.collection("viajes").where("corporativo", "==", true).limit(120).get();
  for (const doc of corp.docs) {
    const d = doc.data();
    const name = String(d.corporativoEmpresaNombre ?? "").toLowerCase();
    if (!name.includes("bravo") && !name.includes("supermercado bravo")) continue;
    if (String(d.corporativoEmpresaId ?? "") === empresaId) continue;
    if (await cancelarViaje(doc.id, d)) cancelados++;
  }

  const uRef = db.collection("usuarios").doc(choferUid);
  const uSnap = await uRef.get();
  if (uSnap.exists) {
    const u = uSnap.data() ?? {};
    const patch = {};
    if (String(u.viajeActivoId ?? "").trim()) patch.viajeActivoId = "";
    if (String(u.siguienteViajeId ?? "").trim()) patch.siguienteViajeId = "";
    if (Object.keys(patch).length > 0) {
      console.log(`Limpiar usuario chofer: ${JSON.stringify(patch)}`);
      if (!dryRun) {
        await uRef.set(
          { ...patch, updatedAt: now, actualizadoEn: now },
          { merge: true },
        );
      }
    }
  }

  const opRef = db.collection("chofer_operacion").doc(choferUid);
  const opSnap = await opRef.get();
  if (opSnap.exists) {
    console.log("Reset chofer_operacion (panel chofer se regenera al guardar ruta o refresh).");
    if (!dryRun) {
      await opRef.set(
        {
          rutasFijas: [],
          viajesHoy: [],
          mensajeGeneral: "",
          actualizadoEn: now,
          resetPilotoEn: now,
        },
        { merge: true },
      );
    }
  }

  const plSnap = await db
    .collection("empresas_corporativas")
    .doc(empresaId)
    .collection("plantillas_ruta")
    .get();

  for (const pl of plSnap.docs) {
    const d = pl.data();
    if (String(d.ultimoViajeId ?? "").trim() || String(d.ultimaPublicacionFijaKey ?? "").trim()) {
      console.log(`Limpiar plantilla ${pl.id}: ultimoViajeId / ultimaPublicacionFijaKey`);
      if (!dryRun) {
        await pl.ref.set(
          {
            ultimoViajeId: "",
            ultimaPublicacionFijaKey: "",
            actualizadoEn: now,
          },
          { merge: true },
        );
      }
    }
  }

  console.log("");
  console.log(`Viajes cancelados hoy: ${cancelados}`);
  console.log("Siguiente paso:");
  console.log("  1. Encargado: abrir ruta → Guardar (o Enviar ahora)");
  console.log("  2. Chofer: Mis rutas corporativas → pull refresh");
  console.log("  3. node scripts/smoke_corporativo_piloto.mjs");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
