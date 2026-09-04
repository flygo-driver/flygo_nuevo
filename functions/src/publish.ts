// functions/src/publish.ts
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

import {
  AHORA_THRESHOLD_MINUTES,
  poolOpensAtMsForScheduledPickup,
  startWindowAtMsForScheduledPickup,
} from "./trip_publish_windows.js";

// initializeApp() ya se hace en src/index.ts
const db = () => getFirestore();

const COLL = "viajes";

// Utilidades pequeñas
const tsNow = () => Timestamp.now();
const svNow = () => FieldValue.serverTimestamp();

// Convierte fechaHora a Date (acepta Timestamp, Date o string ISO)
function toDateSafe(v: any, fallback: Date): Date {
  if (!v) return fallback;
  if (v instanceof Timestamp) return v.toDate();
  if (v instanceof Date) return v;
  if (typeof v === "string") {
    const t = Date.parse(v);
    if (!Number.isNaN(t)) return new Date(t);
  }
  return fallback;
}

function fromDate(d: Date): Timestamp {
  return Timestamp.fromDate(d);
}

function computeFieldsOnCreate(data: FirebaseFirestore.DocumentData, now: Date) {
  // fecha del viaje
  const fechaViaje = toDateSafe(data.fechaHora, now);

  const pickupMs = fechaViaje.getTime();
  const nowMs = now.getTime();

  const clientSetWindows =
    data.publishAt instanceof Timestamp && data.acceptAfter instanceof Timestamp;

  // Si la app ya fijó ventanas (programar / forzarEsAhora), no recalcular esAhora con umbral 15 min.
  let esAhora: boolean;
  let programado: boolean;
  if (clientSetWindows && (data.esAhora === true || data.esAhora === false)) {
    esAhora = data.esAhora === true;
    programado = data.programado === true ? true : !esAhora;
  } else {
    esAhora =
      pickupMs <= nowMs + AHORA_THRESHOLD_MINUTES * 60_000;
    programado = !esAhora;
  }

  // Respetar si ya vienen set, si no, calcular (misma política que TripPublishWindows en la app)
  const publishAt: Date = (data.publishAt instanceof Timestamp)
    ? data.publishAt.toDate()
    : esAhora
      ? now
      : new Date(poolOpensAtMsForScheduledPickup(pickupMs, nowMs));

  const acceptAfter: Date = (data.acceptAfter instanceof Timestamp)
    ? data.acceptAfter.toDate()
    : esAhora
      ? now
      : new Date(poolOpensAtMsForScheduledPickup(pickupMs, nowMs));

  const startWindowAt: Date = (data.startWindowAt instanceof Timestamp)
    ? data.startWindowAt.toDate()
    : esAhora
      ? now
      : new Date(startWindowAtMsForScheduledPickup(pickupMs, nowMs));

  // Publicado si ya estamos dentro de publishAt
  const publicado = (publishAt.getTime() <= now.getTime()) || !!data.publicado;

  // Estado por defecto si no vino
  const estado = typeof data.estado === "string" && data.estado.length > 0
    ? data.estado
    : (String(data.metodoPago ?? "").toLowerCase().trim() === "tarjeta" ? "pendiente_pago" : "pendiente");

  // Asegurar campos de asignación
  const uidTaxista = (typeof data.uidTaxista === "string") ? data.uidTaxista : "";
  const taxistaId  = (typeof data.taxistaId  === "string") ? data.taxistaId  : "";

  return {
    // ventanas
    publishAt: fromDate(publishAt),
    acceptAfter: fromDate(acceptAfter),
    startWindowAt: fromDate(startWindowAt),

    // flags
    esAhora,
    programado,
    publicado,

    // estado base seguro
    estado,
    uidTaxista,
    taxistaId,

    // timestamps de auditoría
    createdAt: data.createdAt ?? svNow(),
    actualizadoEn: svNow(),
    updatedAt: svNow(),
  };
}

/**
 * 1) Normaliza un viaje nuevo: completa ventanas, flags y publicado.
 */
export const viajeOnCreate = onDocumentCreated(`/${COLL}/{id}`, async (event) => {
  const snap = event.data;
  if (!snap) return;

  const now = new Date();
  const data = snap.data();

  const patch = computeFieldsOnCreate(data, now);

  const tipoTurismo = String(data.tipoServicio ?? "").trim() === "turismo";
  if (tipoTurismo && patch.esAhora === true) {
    (patch as Record<string, unknown>).canalAsignacion = "turismo_pool";
    (patch as Record<string, unknown>).liberadoPoolTurismoEn = svNow();
    const estadoRaw = String(data.estado ?? patch.estado ?? "").trim();
    if (estadoRaw === "pendiente_admin" || estadoRaw === "pendienteAdmin") {
      (patch as Record<string, unknown>).estado = "pendiente";
    }
  }

  await snap.ref.set(patch, { merge: true });
  logger.info("publish: viaje normalizado en onCreate", {
    id: snap.id,
    esAhora: patch.esAhora,
    programado: patch.programado,
    publicado: patch.publicado,
  });
});

/**
 * 2) Cron cada 1 minuto:
 *    - Marca como 'publicado: true' los viajes pendientes con publishAt <= now.
 *    - Libera reservas vencidas (reservadoHasta <= now) en viajes pendientes.
 *    - Sincroniza esAhora (<= 15 min) por si fechaHora cambió.
 */
export const publishDueTrips = onSchedule("every 1 minutes", async () => {
  const nowTs = tsNow();
  const now = new Date();

  // ---- A) Publicar viajes cuyo publishAt ya venció ----
  {
    const q = db().collection(COLL)
      .where("estado", "in", ["pendiente", "pendiente_pago"])
      .where("uidTaxista", "==", "")
      .where("publishAt", "<=", nowTs)
      .limit(400);

    const snaps = await q.get();
    if (!snaps.empty) {
      let batch = db().batch();
      let writes = 0;

      for (const doc of snaps.docs) {
        const d = doc.data();

        // Si ya está publicado, sigue
        if (d.publicado === true) continue;

        // esAhora si faltan <= 15 min
        const fecha = toDateSafe(d.fechaHora, now);
        const esAhora =
          fecha.getTime() <= now.getTime() + AHORA_THRESHOLD_MINUTES * 60_000;

        batch.update(doc.ref, {
          publicado: true,
          esAhora,
          updatedAt: svNow(),
          actualizadoEn: svNow(),
          ...(String(d.tipoServicio ?? "").trim() === "turismo" &&
          String(d.canalAsignacion ?? "admin").trim() === "admin"
            ? {
                canalAsignacion: "turismo_pool",
                liberadoPoolTurismoEn: svNow(),
              }
            : {}),
        });
        writes++;

        if (writes >= 450) {
          await batch.commit();
          batch = db().batch();
          writes = 0;
        }
      }
      if (writes > 0) await batch.commit();
      logger.info(`publish: publicados ${snaps.size} viajes (publishAt <= now).`);
    }
  }

  // ---- A2) Turismo programado (pendiente_admin): liberar al pool turístico ----
  {
    const q = db().collection(COLL)
      .where("tipoServicio", "==", "turismo")
      .where("canalAsignacion", "==", "admin")
      .where("estado", "in", ["pendiente_admin", "pendienteAdmin"])
      .where("uidTaxista", "==", "")
      .where("publishAt", "<=", nowTs)
      .limit(200);

    const snaps = await q.get();
    if (!snaps.empty) {
      let batch = db().batch();
      let writes = 0;

      for (const doc of snaps.docs) {
        const d = doc.data();
        const acceptAfter = d.acceptAfter;
        if (acceptAfter instanceof Timestamp && acceptAfter.toDate() > now) {
          continue;
        }
        batch.update(doc.ref, {
          canalAsignacion: "turismo_pool",
          estado: "pendiente",
          publicado: true,
          liberadoPoolTurismoEn: svNow(),
          updatedAt: svNow(),
          actualizadoEn: svNow(),
        });
        writes++;

        if (writes >= 450) {
          await batch.commit();
          batch = db().batch();
          writes = 0;
        }
      }
      if (writes > 0) await batch.commit();
      logger.info(`publish: turismo liberado al pool ${writes} viajes.`);
    }
  }

  // ---- B) Liberar reservas vencidas ----
  {
    const q = db().collection(COLL)
      .where("estado", "in", ["pendiente", "pendiente_pago"])
      .where("uidTaxista", "==", "")
      .where("reservadoHasta", "<=", nowTs) // solo los que tienen fecha de vencimiento menor/igual a ahora
      .limit(400);

    const snaps = await q.get();
    const liberadas: Array<{ viajeId: string; taxistaUid: string }> = [];
    if (!snaps.empty) {
      let batch = db().batch();
      let writes = 0;

      for (const doc of snaps.docs) {
        const d = doc.data();

        const reservadoPor = (typeof d.reservadoPor === "string") ? d.reservadoPor : "";
        if (!reservadoPor) continue; // si no hay reserva, nada que liberar

        batch.update(doc.ref, {
          reservadoPor: "",
          reservadoHasta: null,
          updatedAt: svNow(),
          actualizadoEn: svNow(),
        });
        liberadas.push({ viajeId: doc.id, taxistaUid: reservadoPor });
        writes++;

        if (writes >= 450) {
          await batch.commit();
          batch = db().batch();
          writes = 0;
        }
      }
      if (writes > 0) await batch.commit();
      logger.info(`publish: liberadas ${liberadas.length} reservas vencidas.`);

      for (const item of liberadas) {
        try {
          const uRef = db().collection("usuarios").doc(item.taxistaUid);
          const uSnap = await uRef.get();
          const u = uSnap.data() ?? {};
          const patch: Record<string, unknown> = {};
          if (String(u.siguienteViajeId ?? "").trim() === item.viajeId) {
            patch.siguienteViajeId = "";
          }
          if (String(u.viajeEncoladoId ?? "").trim() === item.viajeId) {
            patch.viajeEncoladoId = "";
          }
          if (Object.keys(patch).length > 0) {
            patch.updatedAt = svNow();
            patch.actualizadoEn = svNow();
            await uRef.set(patch, { merge: true });
          }
          await uRef.collection("cola_viajes").doc(item.viajeId).set(
            {
              estado: "invalidado",
              invalidadoEn: svNow(),
              motivo: "reserva_vencida",
              updatedAt: svNow(),
            },
            { merge: true },
          );
        } catch (e) {
          logger.warn("publish: limpiar cola tras reserva vencida", { item, e });
        }
      }
    }
  }

  // ---- C) Sincronizar 'esAhora' por si alguien reprogramó fechaHora ----
  {
    const q = db().collection(COLL)
      .where("estado", "in", ["pendiente", "pendiente_pago"])
      .where("uidTaxista", "==", "")
      .limit(400);

    const snaps = await q.get();
    if (!snaps.empty) {
      let batch = db().batch();
      let writes = 0;

      for (const doc of snaps.docs) {
        const d = doc.data();
        const fecha = toDateSafe(d.fechaHora, now);
        const shouldBeAhora =
          fecha.getTime() <= now.getTime() + AHORA_THRESHOLD_MINUTES * 60_000;

        if (d.esAhora !== shouldBeAhora) {
          batch.update(doc.ref, {
            esAhora: shouldBeAhora,
            updatedAt: svNow(),
            actualizadoEn: svNow(),
          });
          writes++;
        }

        if (writes >= 450) {
          await batch.commit();
          batch = db().batch();
          writes = 0;
        }
      }
      if (writes > 0) await batch.commit();
      logger.info(`publish: sincronizado esAhora en viajes pendientes.`);
    }
  }
});
