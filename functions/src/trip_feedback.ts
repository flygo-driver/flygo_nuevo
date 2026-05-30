import {
  FieldValue,
  getFirestore,
  type Transaction,
} from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = () => getFirestore();

const MAX_COMENTARIO = 280;
const MAX_MOTIVO = 120;
const MAX_REPORTE_COMENTARIO = 500;

type RolViaje = "cliente" | "taxista";

function esClienteDelViaje(data: Record<string, unknown>, uid: string): boolean {
  const u = String(data.uidCliente ?? "").trim();
  const c = String(data.clienteId ?? "").trim();
  if (u && u === uid) return true;
  if (c && c === uid) return true;
  return false;
}

function esTaxistaDelViaje(data: Record<string, unknown>, uid: string): boolean {
  const t = String(data.uidTaxista ?? data.taxistaId ?? "").trim();
  return t.length > 0 && t === uid;
}

function viajeCerrado(d: Record<string, unknown>): boolean {
  const estNorm = String(d.estado ?? "").trim().toLowerCase();
  return (
    d.completado === true ||
    estNorm === "completado" ||
    estNorm === "finalizado"
  );
}

function uidClienteDeViaje(d: Record<string, unknown>): string {
  return String(d.uidCliente ?? d.clienteId ?? "").trim();
}

function uidTaxistaDeViaje(d: Record<string, unknown>): string {
  return String(d.uidTaxista ?? d.taxistaId ?? "").trim();
}

function escribirCalificacion(
  tx: Transaction,
  params: {
    viajeId: string;
    taxistaId: string;
    clienteId: string;
    calificacion: number;
    comentario: string;
    tipoServicio: string;
    rolOrigen: RolViaje;
    rolDestino: RolViaje;
  },
): void {
  const ref = db().collection("calificaciones").doc();
  tx.set(ref, {
    viajeId: params.viajeId,
    taxistaId: params.taxistaId,
    clienteId: params.clienteId,
    calificacion: params.calificacion,
    comentario: params.comentario,
    fecha: FieldValue.serverTimestamp(),
    tipoServicio: params.tipoServicio,
    rolOrigen: params.rolOrigen,
    rolDestino: params.rolDestino,
    creadoEn: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Cliente → taxista (extiende submitTripRating con colección unificada).
 */
export function persistirCalificacionClienteEnViaje(
  tx: Transaction,
  params: {
    viajeId: string;
    uidCliente: string;
    cal: number;
    comentario: string;
    tripData: Record<string, unknown>;
  },
): { alreadyRated: boolean } {
  const { viajeId, uidCliente, cal, comentario, tripData: d } = params;
  const tripRef = db().collection("viajes").doc(viajeId);

  if (!esClienteDelViaje(d, uidCliente)) {
    throw new HttpsError("permission-denied", "No puedes calificar este viaje.");
  }
  if (!viajeCerrado(d)) {
    throw new HttpsError(
      "failed-precondition",
      "Solo puedes calificar viajes completados.",
    );
  }
  if (d.calificado === true) {
    return { alreadyRated: true };
  }

  const uidTaxista = uidTaxistaDeViaje(d);
  const uidClienteViaje = uidClienteDeViaje(d);
  const patch: Record<string, unknown> = {
    calificado: true,
    calificacion: cal,
    calificadoEn: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    actualizadoEn: FieldValue.serverTimestamp(),
  };
  if (comentario) patch.comentario = comentario;
  tx.update(tripRef, patch);

  if (uidTaxista) {
    tx.set(
      db().collection("usuarios").doc(uidTaxista),
      {
        ratingSuma: FieldValue.increment(cal),
        ratingConteo: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  escribirCalificacion(tx, {
    viajeId,
    taxistaId: uidTaxista,
    clienteId: uidClienteViaje,
    calificacion: cal,
    comentario,
    tipoServicio: String(d.tipoServicio ?? ""),
    rolOrigen: "cliente",
    rolDestino: "taxista",
  });

  return { alreadyRated: false };
}

/**
 * Taxista → cliente.
 */
export const calificarCliente = onCall(async (request) => {
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
    throw new HttpsError(
      "invalid-argument",
      "La calificación debe ser entre 1 y 5.",
    );
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

    if (!esTaxistaDelViaje(d, uid)) {
      throw new HttpsError(
        "permission-denied",
        "No puedes calificar al cliente de este viaje.",
      );
    }
    if (!viajeCerrado(d)) {
      throw new HttpsError(
        "failed-precondition",
        "Solo puedes calificar viajes completados.",
      );
    }
    if (d.clienteCalificado === true) {
      return { ok: true as const, alreadyRated: true as const };
    }

    const uidCliente = uidClienteDeViaje(d);
    const uidTaxista = uidTaxistaDeViaje(d);

    const patch: Record<string, unknown> = {
      clienteCalificado: true,
      calificacionCliente: cal,
      clienteCalificadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    };
    if (comentario) {
      patch.comentarioTaxistaCliente = comentario;
    }
    tx.update(tripRef, patch);

    if (uidCliente) {
      tx.set(
        db().collection("usuarios").doc(uidCliente),
        {
          ratingSuma: FieldValue.increment(cal),
          ratingConteo: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    escribirCalificacion(tx, {
      viajeId,
      taxistaId: uidTaxista,
      clienteId: uidCliente,
      calificacion: cal,
      comentario,
      tipoServicio: String(d.tipoServicio ?? ""),
      rolOrigen: "taxista",
      rolDestino: "cliente",
    });

    return { ok: true as const, alreadyRated: false as const };
  });

  return result;
});

const MOTIVOS_CLIENTE_REPORTA = new Set([
  "Mal servicio",
  "Conduccion peligrosa",
  "Conducta inapropiada",
  "Cobro incorrecto",
  "Vehiculo en mal estado",
  "Otro",
]);

const MOTIVOS_TAXISTA_REPORTA = new Set([
  "Cliente agresivo",
  "No pago",
  "Destrozo del vehiculo",
  "Conducta inapropiada",
  "Otro",
]);

/**
 * Reporte simétrico cliente↔taxista → colección reportes_viaje.
 */
export const reportarProblema = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  const raw = request.data ?? {};
  const viajeId = typeof raw.viajeId === "string" ? raw.viajeId.trim() : "";
  if (!viajeId) {
    throw new HttpsError("invalid-argument", "Falta viajeId.");
  }

  let motivo = typeof raw.motivo === "string" ? raw.motivo.trim() : "";
  if (!motivo || motivo.length > MAX_MOTIVO) {
    throw new HttpsError("invalid-argument", "Motivo inválido.");
  }

  let comentario =
    typeof raw.comentario === "string" ? raw.comentario.trim() : "";
  if (!comentario || comentario.length > MAX_REPORTE_COMENTARIO) {
    throw new HttpsError(
      "invalid-argument",
      "El comentario es obligatorio (máx. 500 caracteres).",
    );
  }

  const tripRef = db().collection("viajes").doc(viajeId);
  const tripSnap = await tripRef.get();
  if (!tripSnap.exists) {
    throw new HttpsError("not-found", "El viaje no existe.");
  }
  const d = tripSnap.data()! as Record<string, unknown>;

  const uidCliente = uidClienteDeViaje(d);
  const uidTaxista = uidTaxistaDeViaje(d);

  let rolReportante: RolViaje;
  let rolReportado: RolViaje;

  if (esClienteDelViaje(d, uid)) {
    rolReportante = "cliente";
    rolReportado = "taxista";
    if (!MOTIVOS_CLIENTE_REPORTA.has(motivo)) {
      throw new HttpsError("invalid-argument", "Motivo no permitido.");
    }
  } else if (esTaxistaDelViaje(d, uid)) {
    rolReportante = "taxista";
    rolReportado = "cliente";
    if (!MOTIVOS_TAXISTA_REPORTA.has(motivo)) {
      throw new HttpsError("invalid-argument", "Motivo no permitido.");
    }
  } else {
    throw new HttpsError(
      "permission-denied",
      "No puedes reportar este viaje.",
    );
  }

  if (!viajeCerrado(d)) {
    throw new HttpsError(
      "failed-precondition",
      "Solo puedes reportar viajes completados.",
    );
  }

  const uidReportante = uid;
  const uidReportado =
    rolReportado === "cliente" ? uidCliente : uidTaxista;

  if (!uidReportado) {
    throw new HttpsError(
      "failed-precondition",
      "No hay usuario reportado en este viaje.",
    );
  }

  const repRef = db().collection("reportes_viaje").doc();
  await repRef.set({
    id: repRef.id,
    viajeId,
    uidCliente,
    uidTaxista,
    uidReportante,
    uidReportado,
    rolReportante,
    rolReportado,
    /** @deprecated alias legible: quién recibe el reporte */
    rolAfectado: rolReportado,
    motivo,
    comentario,
    estado: "pendiente",
    tipoServicio: String(d.tipoServicio ?? ""),
    creadoEn: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    actualizadoEn: FieldValue.serverTimestamp(),
  });

  await tripRef.set(
    {
      reportado: true,
      ultimoReporteEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return { ok: true, reporteId: repRef.id };
});
