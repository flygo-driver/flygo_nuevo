import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = () => getFirestore();

const MAX_COMENTARIO = 280;

function esClienteDelViaje(data: Record<string, unknown>, uid: string): boolean {
  const u = String(data.uidCliente ?? "").trim();
  const c = String(data.clienteId ?? "").trim();
  if (u && u === uid) return true;
  if (c && c === uid) return true;
  return false;
}

/**
 * Calificación del viaje (cliente → taxista). Admin SDK: no depende de reglas cliente en viajes/usuarios.
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
    const d = snap.data()!;

    if (!esClienteDelViaje(d, uid)) {
      throw new HttpsError("permission-denied", "No puedes calificar este viaje.");
    }

    if (d.completado !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Solo puedes calificar viajes completados.",
      );
    }

    if (d.calificado === true) {
      return { ok: true as const, alreadyRated: true as const };
    }

    const uidTaxista = String(d.uidTaxista ?? d.taxistaId ?? "").trim();
    const taxRef = uidTaxista
      ? db().collection("usuarios").doc(uidTaxista)
      : null;
    if (taxRef) {
      await tx.get(taxRef);
    }

    const patch: Record<string, unknown> = {
      calificado: true,
      calificacion: cal,
      calificadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    };
    if (comentario) {
      patch.comentario = comentario;
    }

    tx.update(tripRef, patch);

    if (taxRef) {
      tx.set(
        taxRef,
        {
          ratingSuma: FieldValue.increment(cal),
          ratingConteo: FieldValue.increment(1),
        },
        { merge: true },
      );
    }

    return { ok: true as const, alreadyRated: false as const };
  });

  return result;
});
