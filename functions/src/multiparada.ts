import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

const db = () => getFirestore();
type AnyMap = Record<string, unknown>;

function numCoord(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number.parseFloat(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

/** Paradas intermedias + destino final. */
export function totalLegsMultiparada(d: AnyMap): number {
  const wps = d.waypoints;
  if (!Array.isArray(wps) || wps.length === 0) return 0;
  const latD = numCoord(d.latDestino);
  const lonD = numCoord(d.lonDestino ?? d.lngDestino);
  if (latD == null || lonD == null || (latD === 0 && lonD === 0)) {
    return wps.length;
  }
  return wps.length + 1;
}

export function esViajeMultiparada(d: AnyMap): boolean {
  if (totalLegsMultiparada(d) > 0) return true;
  return String(d.categoria ?? "").trim().toLowerCase() === "multi" &&
    Array.isArray(d.waypoints) &&
    (d.waypoints as unknown[]).length > 0;
}

function legEsperada(
  d: AnyMap,
  legIndex: number,
): { label: string; lat: number; lon: number; esFinal: boolean } | null {
  const total = totalLegsMultiparada(d);
  if (legIndex < 0 || legIndex >= total) return null;
  const wps = d.waypoints as AnyMap[];
  if (legIndex < wps.length) {
    const w = wps[legIndex] ?? {};
    const lat = numCoord(w.lat);
    const lon = numCoord(w.lon ?? w.lng);
    if (lat == null || lon == null) return null;
    const label = String(w.label ?? `Parada ${legIndex + 1}`).trim() || `Parada ${legIndex + 1}`;
    return { label, lat, lon, esFinal: false };
  }
  const lat = numCoord(d.latDestino);
  const lon = numCoord(d.lonDestino ?? d.lngDestino);
  if (lat == null || lon == null) return null;
  const label = String(d.destino ?? "Destino final").trim() || "Destino final";
  return { label, lat, lon, esFinal: true };
}

export function assertMultiparadaCompletaParaFinalizar(d: AnyMap): void {
  if (!esViajeMultiparada(d)) return;
  const total =
    typeof d.multiparadaLegsTotal === "number" && (d.multiparadaLegsTotal as number) > 0
      ? Math.trunc(d.multiparadaLegsTotal as number)
      : totalLegsMultiparada(d);
  if (total <= 0) return;
  const done =
    typeof d.multiparadaLegCompletadas === "number"
      ? Math.trunc(d.multiparadaLegCompletadas as number)
      : 0;
  if (d.multiparadaCompleta === true || done >= total) return;
  throw new HttpsError(
    "failed-precondition",
    `Viaje multiparada: confirmá cada parada con «Llegué — siguiente destino» antes de finalizar (${done}/${total}).`,
  );
}

/** Al iniciar ruta (`iniciarViajeSeguro`) inicializa contadores en el doc. */
export function multiparadaInitPatch(d: AnyMap): Record<string, unknown> | null {
  const total = totalLegsMultiparada(d);
  if (total <= 0) return null;
  return {
    multiparadaLegsTotal: total,
    multiparadaLegCompletadas: 0,
    multiparadaParadasVisitadas: [],
    multiparadaCompleta: false,
    multiparadaCompletaEn: FieldValue.delete(),
  };
}

async function rolTaxistaOAdmin(uid: string): Promise<string> {
  const snap = await db().collection("usuarios").doc(uid).get();
  let rol = String((snap.data() as AnyMap | undefined)?.rol ?? "").trim().toLowerCase();
  if (rol === "driver") rol = "taxista";
  if (rol === "administrador") rol = "admin";
  return rol;
}

/**
 * Conductor registra llegada al destino actual de una ruta multiparada.
 * Secuencial e idempotente por índice de leg.
 */
export const registrarLegMultiparadaSeguro = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  const viajeId = String(request.data?.viajeId ?? "").trim();
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId.");

  const rol = await rolTaxistaOAdmin(uid);
  if (rol !== "taxista" && rol !== "admin") {
    throw new HttpsError("permission-denied", "Solo el conductor asignado puede registrar paradas.");
  }

  const viajeRef = db().collection("viajes").doc(viajeId);

  return db().runTransaction(async (tx) => {
    const snap = await tx.get(viajeRef);
    if (!snap.exists) throw new HttpsError("not-found", "Viaje no encontrado.");
    const d = (snap.data() ?? {}) as AnyMap;

    const uidTx = String(d.uidTaxista ?? d.taxistaId ?? "").trim();
    if (rol !== "admin" && uidTx !== uid) {
      throw new HttpsError("permission-denied", "No autorizado para este viaje.");
    }

    if (!esViajeMultiparada(d)) {
      throw new HttpsError("failed-precondition", "Este viaje no tiene paradas múltiples.");
    }

    const estado = String(d.estado ?? "").trim().toLowerCase().replace(/\s+/g, "_");
    if (estado !== "en_curso") {
      throw new HttpsError(
        "failed-precondition",
        "Solo podés registrar paradas con el viaje en curso (ruta iniciada).",
      );
    }
    if (d.codigoVerificado !== true) {
      throw new HttpsError(
        "failed-precondition",
        "El código PIN del cliente debe estar verificado antes de registrar paradas.",
      );
    }

    const total =
      typeof d.multiparadaLegsTotal === "number" && (d.multiparadaLegsTotal as number) > 0
        ? Math.trunc(d.multiparadaLegsTotal as number)
        : totalLegsMultiparada(d);
    const done =
      typeof d.multiparadaLegCompletadas === "number"
        ? Math.trunc(d.multiparadaLegCompletadas as number)
        : 0;

    if (d.multiparadaCompleta === true || done >= total) {
      return { ok: true, viajeId, alreadyComplete: true, legCompletadas: done, legsTotal: total };
    }

    const legIndex = done;
    const leg = legEsperada(d, legIndex);
    if (!leg) {
      throw new HttpsError("failed-precondition", "Destino de parada inválido o sin coordenadas.");
    }

    const visitadas = Array.isArray(d.multiparadaParadasVisitadas)
      ? [...(d.multiparadaParadasVisitadas as AnyMap[])]
      : [];
    visitadas.push({
      legIndex,
      label: leg.label,
      lat: leg.lat,
      lon: leg.lon,
      esFinal: leg.esFinal,
      visitadoEn: new Date().toISOString(),
      registradoPor: uid,
    });

    const newDone = legIndex + 1;
    const completa = newDone >= total;

    const patch: Record<string, unknown> = {
      multiparadaLegsTotal: total,
      multiparadaLegCompletadas: newDone,
      multiparadaParadasVisitadas: visitadas,
      multiparadaCompleta: completa,
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    };
    if (completa) {
      patch.multiparadaCompletaEn = FieldValue.serverTimestamp();
    }

    tx.update(viajeRef, patch);

    logger.info("[MULTIPARADA] leg registrada", {
      viajeId,
      legIndex,
      newDone,
      total,
      completa,
    });

    return {
      ok: true,
      viajeId,
      alreadyComplete: false,
      legCompletadas: newDone,
      legsTotal: total,
      multiparadaCompleta: completa,
    };
  });
});
