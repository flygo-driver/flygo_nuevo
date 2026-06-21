/**
 * Crear viaje pendiente del pasajero (Admin SDK).
 * Evita permission-denied por reglas estrictas en `viajes` / `usuarios`.
 */
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

const MSG_YA_ACTIVO =
  "Ya tienes un viaje activo. Abre tu viaje en curso o espera a que termine antes de pedir otro.";

const TERMINAL = new Set(["completado", "finalizado", "cancelado", "rechazado"]);
const ACTIVOS = new Set([
  "aceptado",
  "en_camino_pickup",
  "encamino_pickup",
  "a_bordo",
  "abordo",
  "en_curso",
  "encurso",
]);

function trimOrEmpty(v: unknown): string {
  return (v ?? "").toString().trim();
}

function esTerminal(estado: string): boolean {
  return TERMINAL.has(estado.trim().toLowerCase());
}

function tsToMs(v: unknown): number | null {
  if (v instanceof Timestamp) return v.toMillis();
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const ms = Date.parse(v);
    return Number.isNaN(ms) ? null : ms;
  }
  return null;
}

function ventanaPublicacionYAceptacionOk(vd: AnyMap): boolean {
  const now = Date.now();
  const acceptMs = tsToMs(vd.acceptAfter);
  const publishMs = tsToMs(vd.publishAt);
  if (acceptMs != null && now < acceptMs) return false;
  if (publishMs != null && now < publishMs) return false;
  return true;
}

function esReservaProgramadaLejana(vd: AnyMap): boolean {
  if (vd.programado !== true) return false;
  if (vd.esAhora === true) return false;
  if (vd.activo === true) return false;
  return !ventanaPublicacionYAceptacionOk(vd);
}

function viajeOperativoCliente(vd: AnyMap): boolean {
  const st = trimOrEmpty(vd.estado).toLowerCase();
  if (vd.completado === true || esTerminal(st)) return false;
  if (ACTIVOS.has(st)) return true;
  if (vd.activo === true) return true;
  if (
    (st === "pendiente" || st === "pendiente_pago" || st === "pendiente_admin") &&
    (vd.esAhora === true || ventanaPublicacionYAceptacionOk(vd))
  ) {
    return true;
  }
  return false;
}

function clienteViajeExistenteBloqueaNuevoPedido(
  vd: AnyMap,
  uid: string,
  nuevoEsAhora: boolean,
): boolean {
  const cid = trimOrEmpty(vd.uidCliente) || trimOrEmpty(vd.clienteId);
  if (cid !== uid) return false;
  if (esReservaProgramadaLejana(vd)) return !nuevoEsAhora;
  const st = trimOrEmpty(vd.estado).toLowerCase();
  if (vd.completado === true || esTerminal(st)) return false;
  return true;
}

function patchUsuarioTrasCrearViajeCliente(args: {
  uid: string;
  nuevoViajeId: string;
  nuevoEsAhora: boolean;
  userData: AnyMap | undefined;
  viajeActivoDoc: AnyMap | null;
}): { viajeActivoId: string; siguienteViajeId: string } {
  const sigPrev = trimOrEmpty(args.userData?.siguienteViajeId);
  const vidPrev = trimOrEmpty(args.userData?.viajeActivoId);
  let viajeActivoId = args.nuevoViajeId;
  let siguienteViajeId = sigPrev;

  if (vidPrev && args.viajeActivoDoc) {
    const vd = args.viajeActivoDoc;
    if (esReservaProgramadaLejana(vd)) {
      if (args.nuevoEsAhora) {
        if (!sigPrev) siguienteViajeId = vidPrev;
        viajeActivoId = args.nuevoViajeId;
      } else {
        viajeActivoId = args.nuevoViajeId;
      }
    } else if (!args.nuevoEsAhora && viajeOperativoCliente(vd)) {
      viajeActivoId = vidPrev;
      siguienteViajeId = args.nuevoViajeId;
    }
  }

  return { viajeActivoId, siguienteViajeId };
}

function parseTimestamp(v: unknown, label: string): Timestamp {
  if (v instanceof Timestamp) return v;
  if (typeof v === "string") {
    const ms = Date.parse(v);
    if (!Number.isNaN(ms)) return Timestamp.fromDate(new Date(ms));
  }
  if (typeof v === "number" && Number.isFinite(v)) {
    return Timestamp.fromMillis(v);
  }
  if (v && typeof v === "object") {
    const o = v as AnyMap;
    if (typeof o._seconds === "number") {
      return new Timestamp(o._seconds as number, (o._nanoseconds as number) ?? 0);
    }
    if (typeof o.seconds === "number") {
      return new Timestamp(o.seconds as number, (o.nanoseconds as number) ?? 0);
    }
  }
  throw new HttpsError("invalid-argument", `Timestamp inválido: ${label}`);
}

function sanitizeTrip(raw: AnyMap, viajeId: string, uid: string): AnyMap {
  const uidCliente = trimOrEmpty(raw.uidCliente) || trimOrEmpty(raw.clienteId);
  if (uidCliente !== uid) {
    throw new HttpsError("permission-denied", "Solo podés crear viajes para tu cuenta.");
  }
  if (trimOrEmpty(raw.uidTaxista) !== "" || trimOrEmpty(raw.taxistaId) !== "") {
    throw new HttpsError("invalid-argument", "El viaje no debe tener taxista al crear.");
  }

  const tsFields = ["fechaHora", "acceptAfter", "publishAt", "startWindowAt"] as const;
  const out: AnyMap = { ...raw };
  out.id = viajeId;
  out.uidCliente = uid;
  out.clienteId = uid;
  out.uidTaxista = "";
  out.taxistaId = "";

  for (const key of tsFields) {
    if (out[key] != null) {
      out[key] = parseTimestamp(out[key], key);
    }
  }

  const forbidden = [
    "referenciaRecaudo",
    "recaudoDestino",
    "qrRecaudoPayload",
    "qrRecaudoTipo",
    "qrRecaudoVersion",
    "qrRecaudoGeneradoEn",
    "qrRecaudoEstado",
    "pagoAzulId",
    "payment",
    "pagoRegistrado",
    "liquidado",
    "pagoDetalle",
    "settlement",
    "comision_cents",
    "ganancia_cents",
    "comision",
    "comisionFlygo",
    "gananciaTaxista",
    "comisionCalculada",
    "comisionCalculadaEn",
    "confirmacionTransferencia",
  ];
  for (const k of forbidden) {
    delete out[k];
  }

  out.creadoEn = FieldValue.serverTimestamp();
  out.createdAt = FieldValue.serverTimestamp();
  out.updatedAt = FieldValue.serverTimestamp();
  out.actualizadoEn = FieldValue.serverTimestamp();

  return out;
}

export const crearViajePendienteCliente = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }
  const uid = request.auth.uid;
  const payload = (request.data ?? {}) as AnyMap;
  const viajeId = trimOrEmpty(payload.viajeId);
  const tripRaw = payload.trip;
  if (!viajeId || !tripRaw || typeof tripRaw !== "object") {
    throw new HttpsError("invalid-argument", "Faltan datos del viaje.");
  }

  const trip = sanitizeTrip(tripRaw as AnyMap, viajeId, uid);
  const nuevoEsAhora = trip.esAhora === true;
  const viajeRef = db().collection("viajes").doc(viajeId);
  const userRef = db().collection("usuarios").doc(uid);

  await db().runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const userData = (userSnap.data() ?? {}) as AnyMap;
    const vid = trimOrEmpty(userData.viajeActivoId);
    let viajeActivoDoc: AnyMap | null = null;
    if (vid) {
      const vSnap = await tx.get(db().collection("viajes").doc(vid));
      if (vSnap.exists) {
        viajeActivoDoc = (vSnap.data() ?? {}) as AnyMap;
        if (
          clienteViajeExistenteBloqueaNuevoPedido(viajeActivoDoc, uid, nuevoEsAhora)
        ) {
          throw new HttpsError("failed-precondition", MSG_YA_ACTIVO);
        }
      }
    }

    tx.set(viajeRef, trip);
    const userPatch = patchUsuarioTrasCrearViajeCliente({
      uid,
      nuevoViajeId: viajeId,
      nuevoEsAhora,
      userData,
      viajeActivoDoc,
    });
    tx.set(
      userRef,
      {
        viajeActivoId: userPatch.viajeActivoId,
        siguienteViajeId: userPatch.siguienteViajeId,
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });

  return { viajeId, ok: true };
});
