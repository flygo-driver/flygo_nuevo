/**
 * Confirmación del chofer y política de sustituto por ruta.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  choferCorporativoElegible,
  resolverChoferPublicacionCorporativo,
} from "./corporativo_auto_asignacion.js";
import { asignarChoferCorporativoFijo } from "./corporativo_assign.js";
import { registrarHistorialNotificacionCorp } from "./corporativo_notificaciones.js";
import {
  detectarConflictosHorarioChofer,
  mensajeCompromisoChoferDesdeConflictos,
} from "./corporativo_validacion.js";

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function diaCalendarioRd(ref = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Santo_Domingo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(ref);
}

async function enviarPushUid(
  uid: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  const { getMessaging } = await import("firebase-admin/messaging");
  const tokSnap = await getFirestore().collection("push_tokens").doc(uid).get();
  const raw = tokSnap.data()?.tokens;
  const tokens = Array.isArray(raw)
    ? raw.filter((t): t is string => typeof t === "string" && t.length > 10)
    : [];
  if (tokens.length === 0) return;
  await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { ...data, click_action: "FLUTTER_NOTIFICATION_CLICK" },
  });
}

function esEncargado(ed: AnyMap, uid: string): boolean {
  const uids = Array.isArray(ed.encargadoUids)
    ? (ed.encargadoUids as string[]).map(String)
    : [];
  return uids.includes(uid);
}

/** Chofer confirma que hará la ruta de hoy. */
export const choferConfirmarRutaCorporativa = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const uid = request.auth.uid;
  const empresaId = str(request.data?.empresaId);
  const plantillaId = str(request.data?.plantillaId);
  if (!empresaId || !plantillaId) {
    throw new HttpsError("invalid-argument", "Faltan empresaId o plantillaId");
  }

  const plRef = getFirestore()
    .collection("empresas_corporativas")
    .doc(empresaId)
    .collection("plantillas_ruta")
    .doc(plantillaId);
  const plSnap = await plRef.get();
  if (!plSnap.exists) {
    throw new HttpsError("not-found", "Ruta no encontrada");
  }
  const d = plSnap.data() as AnyMap;
  const preferido = str(d.choferPreferidoUid);
  if (preferido && preferido !== uid) {
    throw new HttpsError("permission-denied", "No eres el chofer asignado");
  }

  const keyHoy = diaCalendarioRd();
  await plRef.set(
    {
      [`choferConfirmado_${keyHoy}`]: uid,
      choferConfirmadoEn: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { ok: true, keyHoy };
});

/** Si el chofer no confirmó a tiempo, aplica política de sustituto. */
export const scheduledCorporativoSustitutoChofer = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "America/Santo_Domingo",
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const keyHoy = diaCalendarioRd(now);
    let acciones = 0;

    const empresas = await db
      .collection("empresas_corporativas")
      .where("activa", "==", true)
      .limit(30)
      .get();

    for (const emp of empresas.docs) {
      const empresaId = emp.id;
      const empresaNombre = str(emp.data().nombre);
      const encargados = Array.isArray(emp.data().encargadoUids)
        ? (emp.data().encargadoUids as string[]).map(String)
        : [];

      const plantillas = await db
        .collection("empresas_corporativas")
        .doc(empresaId)
        .collection("plantillas_ruta")
        .where("activa", "==", true)
        .limit(20)
        .get();

      for (const pl of plantillas.docs) {
        const d = pl.data() as AnyMap;
        const politica = str(d.politicaSustituto).toLowerCase() || "auto";
        if (politica === "pausar" || politica === "manual") continue;

        const tiempoConf = Math.max(
          15,
          Math.trunc(Number(d.tiempoConfirmacionMin) || 30),
        );
        const horaStr = str(d.horaRecogidaGrupo) || str(d.horaRecogida) || "07:00";
        const parts = horaStr.split(":");
        const h = parseInt(parts[0] ?? "7", 10);
        const m = parseInt(parts[1] ?? "0", 10);
        const fmt = new Intl.DateTimeFormat("en-CA", {
          timeZone: "America/Santo_Domingo",
          year: "numeric",
          month: "2-digit",
          day: "2-digit",
        });
        const [y, mo, day] = fmt.format(now).split("-").map(Number);
        const recogida = new Date(Date.UTC(y, mo - 1, day, h + 4, m, 0));
        const diffMin = (recogida.getTime() - now.getTime()) / 60000;
        if (diffMin > tiempoConf || diffMin < tiempoConf - 20) continue;

        const choferUid = str(d.choferPreferidoUid);
        if (!choferUid) continue;
        if (str(d[`choferConfirmado_${keyHoy}`]) === choferUid) continue;
        if (str(d[`sustitutoAplicado_${keyHoy}`]) === "1") continue;

        const respaldoUid = str(d.choferRespaldoUid);
        let nuevoUid = respaldoUid;
        if (!nuevoUid) {
          const resuelto = await resolverChoferPublicacionCorporativo({
            empresaId,
            plantillaId: pl.id,
            plantilla: { ...d, choferPreferidoUid: "" },
          });
          nuevoUid = resuelto?.uid ?? "";
        }
        if (!nuevoUid || nuevoUid === choferUid) continue;

        await pl.ref.set(
          {
            choferPreferidoUid: nuevoUid,
            [`sustitutoAplicado_${keyHoy}`]: "1",
            choferSustitutoDeUid: choferUid,
            actualizadoEn: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        const viajes = await db
          .collection("viajes")
          .where("corporativoPlantillaId", "==", pl.id)
          .where("corporativoEmpresaId", "==", empresaId)
          .limit(5)
          .get();
        for (const v of viajes.docs) {
          const vd = v.data();
          if (vd.completado === true) continue;
          const estado = str(vd.estado).toLowerCase();
          if (["cancelado", "anulado", "completado"].includes(estado)) continue;
          await asignarChoferCorporativoFijo({
            viajeRef: v.ref,
            choferUid: nuevoUid,
            esAhora: false,
          });
        }

        const msgEnc =
          `El chofer asignado no confirmó a tiempo. Se aplicó sustituto para la ruta de hoy.`;
        for (const uidEnc of encargados) {
          await enviarPushUid(uidEnc, "⚠️ Sustituto de chofer", msgEnc, {
            type: "corporativo_sustituto",
            empresaId,
            plantillaId: pl.id,
            rol: "encargado",
          });
          await registrarHistorialNotificacionCorp({
            empresaId,
            plantillaId: pl.id,
            uidDestino: uidEnc,
            canal: "fcm",
            tipo: "sustituto_encargado",
            titulo: "Sustituto de chofer",
            cuerpo: msgEnc,
            enviado: true,
          });
        }

        await enviarPushUid(
          nuevoUid,
          "🚕 Ruta corporativa asignada (sustituto)",
          `${empresaNombre}: te asignaron la ruta de hoy por sustitución.`,
          { type: "corporativo_sustituto", empresaId, plantillaId: pl.id },
        );

        acciones += 1;
        logger.info("scheduledCorporativoSustitutoChofer", {
          empresaId,
          plantillaId: pl.id,
          choferAnterior: choferUid,
          choferNuevo: nuevoUid,
        });
      }
    }

    logger.info("scheduledCorporativoSustitutoChofer done", { acciones });
  },
);

/** Encargado: política manual → asignar sustituto explícito. */
export const encargadoAsignarSustitutoCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const uid = request.auth.uid;
  const empresaId = str(request.data?.empresaId);
  const plantillaId = str(request.data?.plantillaId);
  const choferUid = str(request.data?.choferUid);
  if (!empresaId || !plantillaId || !choferUid) {
    throw new HttpsError("invalid-argument", "Faltan datos");
  }

  const empRef = getFirestore().collection("empresas_corporativas").doc(empresaId);
  const empSnap = await empRef.get();
  if (!empSnap.exists) {
    throw new HttpsError("not-found", "Empresa no encontrada");
  }
  if (!esEncargado(empSnap.data() as AnyMap, uid)) {
    throw new HttpsError("permission-denied", "Solo encargado");
  }

  const keyHoy = diaCalendarioRd();
  await empRef.collection("plantillas_ruta").doc(plantillaId).set(
    {
      choferPreferidoUid: choferUid,
      [`sustitutoAplicado_${keyHoy}`]: "1",
      politicaSustituto: "manual",
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { ok: true };
});

/** Admin: asigna sustituto urgente desde el pool (sin esperar scheduler). */
export const adminAsignarSustitutoUrgenteCorp = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const adminSnap = await getFirestore()
    .collection("roles")
    .doc(request.auth.uid)
    .get();
  if (str(adminSnap.data()?.rol).toLowerCase() !== "admin") {
    throw new HttpsError("permission-denied", "Solo administradores");
  }

  const empresaId = str(request.data?.empresaId);
  const plantillaId = str(request.data?.plantillaId);
  if (!empresaId || !plantillaId) {
    throw new HttpsError("invalid-argument", "Faltan empresaId o plantillaId");
  }

  const plRef = getFirestore()
    .collection("empresas_corporativas")
    .doc(empresaId)
    .collection("plantillas_ruta")
    .doc(plantillaId);
  const plSnap = await plRef.get();
  if (!plSnap.exists) {
    throw new HttpsError("not-found", "Ruta no encontrada");
  }
  const d = plSnap.data() as AnyMap;
  const sustitutoUid = str(request.data?.choferUid);
  if (!sustitutoUid) {
    throw new HttpsError(
      "invalid-argument",
      "Indicá el conductor sustituto (choferUid). RAI asigna manualmente; no hay auto-pool.",
    );
  }
  const excluir = str(d.choferPreferidoUid);
  if (sustitutoUid === excluir) {
    throw new HttpsError(
      "failed-precondition",
      "El sustituto no puede ser el mismo conductor titular.",
    );
  }

  const eleg = await choferCorporativoElegible(sustitutoUid);
  if (!eleg.ok) {
    throw new HttpsError(
      "failed-precondition",
      "El conductor no está habilitado en el pool corporativo RAI.",
    );
  }
  const conflictos = await detectarConflictosHorarioChofer({
    choferUid: sustitutoUid,
    empresaId,
    plantillaId,
    plantilla: d,
  });
  if (conflictos.length > 0) {
    throw new HttpsError(
      "failed-precondition",
      mensajeCompromisoChoferDesdeConflictos(conflictos, eleg.nombre),
    );
  }

  const resuelto = {
    uid: sustitutoUid,
    nombre: eleg.nombre,
    telefono: eleg.telefono,
  };

  const keyHoy = diaCalendarioRd();
  await plRef.set(
    {
      choferPreferidoUid: resuelto.uid,
      choferPreferidoNombre: resuelto.nombre,
      choferPreferidoTelefono: resuelto.telefono,
      [`sustitutoAplicado_${keyHoy}`]: "1",
      politicaSustituto: "manual",
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  await enviarPushUid(
    resuelto.uid,
    "Sustituto urgente asignado",
    `RAI te asignó como sustituto en ${str(d.nombre) || "ruta corporativa"}.`,
    { type: "corporativo_sustituto_urgente", empresaId, plantillaId },
  );

  return {
    ok: true,
    choferUid: resuelto.uid,
    choferNombre: resuelto.nombre,
  };
});
