import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

function normalizeRole(raw: unknown): string {
  const r = String(raw ?? "").trim().toLowerCase();
  if (r === "administrador") return "admin";
  if (r === "driver") return "taxista";
  return r;
}

async function getRole(uid: string): Promise<string> {
  const u = await db().collection("usuarios").doc(uid).get();
  const r1 = normalizeRole((u.data() as AnyMap | undefined)?.rol);
  if (r1) return r1;
  const r = await db().collection("roles").doc(uid).get();
  return normalizeRole((r.data() as AnyMap | undefined)?.rol);
}

async function assertTaxiOrAdmin(uid: string): Promise<string> {
  const role = await getRole(uid);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }
  return role;
}

function onlyDigits(value: unknown): string {
  return String(value ?? "").replace(/\D/g, "").trim();
}

function isValidTransitionToEnCurso(estado: string): boolean {
  return [
    "a_bordo",
    "abordo",
    "aceptado",
    "asignado",
    "en_espera",
    "en_camino_pickup",
    "encamino_pickup",
  ].includes(estado);
}

// Genera un PIN de abordaje (taxista/admin) en viaje asignado.
export const issueBoardingPin = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  const role = await assertTaxiOrAdmin(actorUid);
  const viajeId = String(request.data?.viajeId ?? "").trim();
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const viajeRef = db().collection("viajes").doc(viajeId);
  const viajeSnap = await viajeRef.get();
  if (!viajeSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
  const data = (viajeSnap.data() ?? {}) as AnyMap;
  const uidTaxista = String(data.uidTaxista ?? data.taxistaId ?? "").trim();
  if (role !== "admin" && uidTaxista !== actorUid) {
    throw new HttpsError("permission-denied", "No autorizado para este viaje");
  }

  const pin = Math.floor(1000 + Math.random() * 9000).toString();
  await viajeRef.update({
    boardingPin: pin,
    boardingPinExpira: Date.now() + 10 * 60 * 1000,
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { ok: true, pin };
});

// Confirma el PIN al abordar (cliente/taxista/admin).
export const confirmBoarding = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  const role = await getRole(actorUid);
  if (!["cliente", "taxista", "admin"].includes(role)) {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const viajeId = String(request.data?.viajeId ?? request.data?.tripId ?? "").trim();
  const pinIngresado = onlyDigits(request.data?.pin);
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");
  if (!pinIngresado) throw new HttpsError("invalid-argument", "Falta pin");

  const ref = db().collection("viajes").doc(viajeId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Viaje no existe");

  const data = (snap.data() ?? {}) as AnyMap;
  const uidTaxista = String(data.uidTaxista ?? data.taxistaId ?? "").trim();
  const uidCliente = String(data.uidCliente ?? data.clienteId ?? "").trim();
  if (
    role !== "admin" &&
    actorUid !== uidTaxista &&
    actorUid !== uidCliente
  ) {
    throw new HttpsError("permission-denied", "No autorizado para este viaje");
  }

  const pinDoc = onlyDigits(data.boardingPin);
  if (!pinDoc || pinDoc !== pinIngresado) {
    throw new HttpsError("permission-denied", "PIN incorrecto");
  }
  const expira = Number(data.boardingPinExpira ?? 0);
  if (Number.isFinite(expira) && expira > 0 && Date.now() > expira) {
    throw new HttpsError("failed-precondition", "PIN expirado");
  }

  await ref.update({
    estado: "a_bordo",
    codigoVerificado: true,
    codigoVerificadoEn: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true, estado: "a_bordo" };
});

// Inicio de viaje autoritativo: exige código verificado por backend o PIN válido.
export const iniciarViajeSeguro = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  const role = await assertTaxiOrAdmin(actorUid);
  const viajeId = String(request.data?.viajeId ?? "").trim();
  const pinIngresado = onlyDigits(request.data?.pin);
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const viajeRef = db().collection("viajes").doc(viajeId);
  return await db().runTransaction(async (tx) => {
    const snap = await tx.get(viajeRef);
    if (!snap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const data = (snap.data() ?? {}) as AnyMap;
    const uidTaxista = String(data.uidTaxista ?? data.taxistaId ?? "").trim();
    const estado = String(data.estado ?? "").trim().toLowerCase();

    if (role !== "admin" && uidTaxista !== actorUid) {
      throw new HttpsError("permission-denied", "No autorizado para este viaje");
    }
    if (estado === "en_curso") {
      return { ok: true, viajeId, alreadyStarted: true };
    }
    if (!isValidTransitionToEnCurso(estado)) {
      throw new HttpsError("failed-precondition", "Estado no válido para iniciar viaje");
    }

    const codigoVerificado = data.codigoVerificado === true;
    if (!codigoVerificado) {
      const pinDocA = onlyDigits(data.codigoVerificacion);
      const pinDocB = onlyDigits(data.boardingPin);
      const pinDoc = pinDocA || pinDocB;
      if (!pinDoc || pinIngresado.length == 0 || pinIngresado !== pinDoc) {
        throw new HttpsError("failed-precondition", "Código de verificación inválido");
      }
    }

    tx.update(viajeRef, {
      estado: "en_curso",
      codigoVerificado: true,
      codigoVerificadoEn: FieldValue.serverTimestamp(),
      inicioViaje: FieldValue.serverTimestamp(),
      viajeIniciadoEn: FieldValue.serverTimestamp(),
      inicioEnRutaEn: FieldValue.serverTimestamp(),
      activo: true,
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    });
    return { ok: true, viajeId, alreadyStarted: false };
  });
});
