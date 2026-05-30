import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { persistirCalificacionClienteEnViaje } from "./trip_feedback.js";

const db = () => getFirestore();

const MAX_COMENTARIO = 280;

/**
 * Calificación del viaje (cliente → taxista). Admin SDK + colección `calificaciones`.
 */
export const submitTripRating = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  const raw = request.data ?? {};
  const viajeId = typeof raw.viajeId === "string" ? raw.viajeId.trim() : "";
  if (!viajeId) {
    throw new HttpsError("invalid-argument", "Falta viajeId.");
  }

  const calRaw = raw.calificacion;
  const calNum = typeof calRaw === "number" ? calRaw : Number(calRaw);
  if (!Number.isFinite(calNum)) {
    throw new HttpsError("invalid-argument", "Calificación inválida.");
  }
  const cal = Math.round(calNum);
  if (cal < 1 || cal > 5) {
    throw new HttpsError("invalid-argument", "La calificación debe ser entre 1 y 5.");
  }

  let comentario = "";
  if (raw.comentario != null && String(raw.comentario).trim()) {
    comentario = String(raw.comentario).trim().slice(0, MAX_COMENTARIO);
  }

  const tripRef = db().collection("viajes").doc(viajeId);

  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(tripRef);
    if (!snap.exists) {
      throw new HttpsError("not-found", "El viaje no existe.");
    }
    const d = snap.data()! as Record<string, unknown>;

    const inner = persistirCalificacionClienteEnViaje(tx, {
      viajeId,
      uidCliente: uid,
      cal,
      comentario,
      tripData: d,
    });
    return { ok: true as const, alreadyRated: inner.alreadyRated };
  });

  return result;
});
