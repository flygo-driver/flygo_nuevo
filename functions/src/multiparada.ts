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

function destinoCoordsMultiparada(
  d: AnyMap,
): { lat: number; lon: number } | null {
  let lat = numCoord(d.latDestino);
  let lon = numCoord(d.lonDestino ?? d.lngDestino);
  if (lat != null && lon != null && !(lat === 0 && lon === 0)) {
    return { lat, lon };
  }

  const readRuta = (raw: unknown): { lat: number; lon: number } | null => {
    if (!Array.isArray(raw)) return null;
    for (let i = raw.length - 1; i >= 0; i--) {
      const item = raw[i];
      if (!item || typeof item !== "object") continue;
      const m = item as AnyMap;
      const rol = String(m.rol ?? "").trim().toLowerCase();
      if (rol !== "destino" && rol !== "destino_final") continue;
      const la = numCoord(m.lat);
      const lo = numCoord(m.lon ?? m.lng);
      if (la != null && lo != null) return { lat: la, lon: lo };
    }
    return null;
  };

  const extras = d.extras;
  if (extras && typeof extras === "object") {
    const fromExtras = readRuta((extras as AnyMap).rutaPuntos);
    if (fromExtras) return fromExtras;
  }
  return readRuta(d.rutaPuntos);
}

/** Paradas intermedias + destino final. */
export function totalLegsMultiparada(d: AnyMap): number {
  const wps = d.waypoints;
  if (!Array.isArray(wps) || wps.length === 0) return 0;
  return destinoCoordsMultiparada(d) != null ? wps.length + 1 : wps.length;
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
  const dest = destinoCoordsMultiparada(d);
  if (dest == null) return null;
  const label = String(d.destino ?? "Destino final").trim() || "Destino final";
  return { label, lat: dest.lat, lon: dest.lon, esFinal: true };
}

export function esCorporativoModoInformativo(d: AnyMap): boolean {
  if (d.corporativoModoInformativo === true) return true;
  if (d.corporativoModoInformativo === false) return false;
  if (typeof d.extras === "object" && d.extras !== null) {
    const ex = d.extras as AnyMap;
    if (ex.corporativoModoInformativo === true) return true;
    if (ex.corporativoModoInformativo === false) return false;
  }
  if (d.corporativo === true) return true;
  const canal = String(d.canalAsignacion ?? "").trim();
  if (canal === "corporativo_fijo") return true;
  const cat = String(d.categoria ?? "").trim().toLowerCase();
  if (cat === "corporativo") return true;
  const recaudo = String(d.recaudoDestino ?? "").trim().toLowerCase();
  return recaudo === "empresa_corporativa";
}

export function assertMultiparadaCompletaParaFinalizar(d: AnyMap): void {
  const corpModoInformativo = esCorporativoModoInformativo(d);
  if (corpModoInformativo) {
    const pas = d.corporativoPasajeros;
    if (!Array.isArray(pas) || pas.length === 0) return;
    const total = pas.length;
    const hechas = Array.isArray(d.corporativoParadasHechas)
      ? (d.corporativoParadasHechas as unknown[]).length
      : typeof d.multiparadaLegCompletadas === "number"
        ? Math.trunc(d.multiparadaLegCompletadas as number)
        : 0;
    if (d.multiparadaCompleta === true || hechas >= total) return;
    throw new HttpsError(
      "failed-precondition",
      `Ruta corporativa: marcá todas las entregas antes de finalizar (${hechas}/${total}).`,
    );
  }
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

function visitadosMultiparadaSet(d: AnyMap): Set<number> {
  const visitadas = Array.isArray(d.multiparadaParadasVisitadas)
    ? (d.multiparadaParadasVisitadas as AnyMap[])
    : [];
  const visitados = new Set<number>();
  for (const item of visitadas) {
    const idx = Math.trunc(Number(item.legIndex));
    if (Number.isFinite(idx) && idx >= 0) visitados.add(idx);
  }
  return visitados;
}

/** Paradas donde el chofer ya abrió Waze/Maps (incluye confirmadas). */
export function multiparadaParadasAbiertasSet(
  d: AnyMap,
  total: number,
): Set<number> {
  const raw = d.multiparadaParadasAbiertas;
  const abiertas = Array.isArray(raw)
    ? new Set(
        raw
          .filter((x): x is number => typeof x === "number" && Number.isFinite(x))
          .map((x) => Math.trunc(x))
          .filter((i) => i >= 0 && i < total),
      )
    : new Set<number>();
  for (const i of visitadosMultiparadaSet(d)) {
    if (i >= 0 && i < total) abiertas.add(i);
  }
  return abiertas;
}

export function multiparadaRecogidaAbierta(d: AnyMap): boolean {
  if (d.multiparadaRecogidaAbierta === true) return true;
  return (
    d.clienteAbordo === true ||
    d.pickupConfirmadoEn != null ||
    d.corporativoRecogidaAbierta === true
  );
}

/** Al iniciar ruta (`iniciarViajeSeguro`) inicializa contadores en el doc. */
export function multiparadaInitPatch(d: AnyMap): Record<string, unknown> | null {
  const total = totalLegsMultiparada(d);
  if (total <= 0) return null;
  const done =
    typeof d.multiparadaLegCompletadas === "number"
      ? Math.trunc(d.multiparadaLegCompletadas as number)
      : 0;
  const visitadas = Array.isArray(d.multiparadaParadasVisitadas)
    ? d.multiparadaParadasVisitadas
    : [];
  const abiertas = Array.isArray(d.multiparadaParadasAbiertas)
    ? d.multiparadaParadasAbiertas
    : [];
  // No borrar paradas ya confirmadas al pasar a `en_curso`.
  if (done > 0 || visitadas.length > 0) {
    return {
      multiparadaLegsTotal: total,
      multiparadaLegCompletadas: done,
      multiparadaParadasVisitadas: visitadas,
      multiparadaParadasAbiertas: abiertas,
      multiparadaRecogidaAbierta: multiparadaRecogidaAbierta(d),
      multiparadaCompleta: d.multiparadaCompleta === true || done >= total,
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    };
  }
  return {
    multiparadaLegsTotal: total,
    multiparadaLegCompletadas: 0,
    multiparadaParadasVisitadas: [],
    multiparadaParadasAbiertas: [],
    multiparadaRecogidaAbierta: false,
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
 * Conductor registra llegada a una parada de ruta multiparada.
 * Con `legIndex` opcional: orden libre (estilo corporativo compartido).
 * Sin `legIndex`: primera parada pendiente (apps anteriores).
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

  const result = await db().runTransaction(async (tx) => {
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
    const codigoOk = d.codigoVerificado === true;
    const estadoOk = estado === "en_curso" || (estado === "a_bordo" && codigoOk);
    if (!estadoOk) {
      throw new HttpsError(
        "failed-precondition",
        "Solo podés registrar paradas con el viaje en curso (ruta iniciada).",
      );
    }
    if (!codigoOk) {
      throw new HttpsError(
        "failed-precondition",
        "El código PIN del cliente debe estar verificado antes de registrar paradas.",
      );
    }

    const total =
      typeof d.multiparadaLegsTotal === "number" && (d.multiparadaLegsTotal as number) > 0
        ? Math.trunc(d.multiparadaLegsTotal as number)
        : totalLegsMultiparada(d);
    const visitadas = Array.isArray(d.multiparadaParadasVisitadas)
      ? [...(d.multiparadaParadasVisitadas as AnyMap[])]
      : [];
    const visitados = new Set<number>();
    for (const item of visitadas) {
      const idx = Math.trunc(Number((item as AnyMap).legIndex));
      if (Number.isFinite(idx) && idx >= 0) visitados.add(idx);
    }
    const done = visitados.size > 0
      ? visitados.size
      : typeof d.multiparadaLegCompletadas === "number"
        ? Math.trunc(d.multiparadaLegCompletadas as number)
        : 0;

    if (d.multiparadaCompleta === true || done >= total) {
      return { ok: true, viajeId, alreadyComplete: true, legCompletadas: done, legsTotal: total };
    }

    const legIndexRaw = request.data?.legIndex;
    let legIndex: number;
    if (legIndexRaw !== undefined && legIndexRaw !== null && legIndexRaw !== "") {
      legIndex = Math.trunc(Number(legIndexRaw));
      if (!Number.isFinite(legIndex)) {
        throw new HttpsError("invalid-argument", "legIndex inválido.");
      }
      if (legIndex < 0 || legIndex >= total) {
        throw new HttpsError("failed-precondition", "Índice de parada fuera de rango.");
      }
      if (visitados.has(legIndex)) {
        return {
          ok: true,
          viajeId,
          alreadyVisited: true,
          legIndex,
          legCompletadas: done,
          legsTotal: total,
        };
      }
    } else {
      legIndex = -1;
      for (let i = 0; i < total; i++) {
        if (!visitados.has(i)) {
          legIndex = i;
          break;
        }
      }
      if (legIndex < 0) {
        return { ok: true, viajeId, alreadyComplete: true, legCompletadas: done, legsTotal: total };
      }
    }

    const leg = legEsperada(d, legIndex);
    if (!leg) {
      throw new HttpsError("failed-precondition", "Destino de parada inválido o sin coordenadas.");
    }

    const abiertas = multiparadaParadasAbiertasSet(d, total);
    if (!abiertas.has(legIndex)) {
      throw new HttpsError(
        "failed-precondition",
        "Abrí Waze o Maps a esta parada antes de marcar la llegada.",
      );
    }

    const latGps = numCoord(request.data?.lat);
    const lonGps = numCoord(request.data?.lon);
    visitadas.push({
      legIndex,
      label: leg.label,
      lat: leg.lat,
      lon: leg.lon,
      esFinal: leg.esFinal,
      visitadoEn: new Date().toISOString(),
      registradoPor: uid,
      ...(latGps != null && lonGps != null
        ? { gpsLat: latGps, gpsLon: lonGps }
        : {}),
    });

    const newDone = visitadas.length;
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
      corpNotify:
        d.corporativo === true ||
        String(d.categoria ?? "").trim() === "corporativo"
          ? { legIndex, legLabel: leg.label }
          : null,
    };
  });

  const corp = (result as AnyMap).corpNotify as
    | { legIndex: number; legLabel: string }
    | null
    | undefined;
  if (corp) {
    const { notificarDestinoPasajeroCorporativo } = await import(
      "./corporativo_abordaje.js"
    );
    void notificarDestinoPasajeroCorporativo({
      viajeId,
      legIndex: corp.legIndex,
      legLabel: corp.legLabel,
    }).catch((e) =>
      logger.warn("notificarDestinoPasajeroCorporativo", { viajeId, e }),
    );
  }

  return result;
});

/**
 * Chofer multiparada: registra que abrió Waze/Maps en origen o parada (estilo corp.).
 * Obligatorio antes de `registrarLegMultiparadaSeguro`.
 */
export const marcarMultiparadaNavAbiertaSeguro = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  const viajeId = String(request.data?.viajeId ?? "").trim();
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId.");

  const accion = String(request.data?.accion ?? "marcar_abierta")
    .trim()
    .toLowerCase();
  if (accion !== "marcar_abierta" && accion !== "marcar_recogida_abierta") {
    throw new HttpsError("invalid-argument", "Acción no válida.");
  }

  const rol = await rolTaxistaOAdmin(uid);
  if (rol !== "taxista" && rol !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Solo el conductor asignado puede registrar navegación.",
    );
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

    if (d.completado === true || d.multiparadaCompleta === true) {
      return { ok: true, viajeId, yaCompleto: true };
    }

    const estado = String(d.estado ?? "").trim().toLowerCase().replace(/\s+/g, "_");
    const codigoOk = d.codigoVerificado === true;
    const estadoOk = estado === "en_curso" || (estado === "a_bordo" && codigoOk);
    if (!estadoOk) {
      throw new HttpsError(
        "failed-precondition",
        "Solo podés registrar navegación con el viaje en curso.",
      );
    }

    const now = FieldValue.serverTimestamp();
    const patch: Record<string, unknown> = {
      updatedAt: now,
      actualizadoEn: now,
    };

    if (accion === "marcar_recogida_abierta") {
      if (multiparadaRecogidaAbierta(d)) {
        return { ok: true, viajeId, recogidaAbierta: true };
      }
      patch.multiparadaRecogidaAbierta = true;
      patch.multiparadaRecogidaAbiertaEn = now;
      if (estado !== "en_curso") {
        patch.estado = "en_curso";
      }
      tx.update(viajeRef, patch);
      return { ok: true, viajeId, recogidaAbierta: true };
    }

    const total =
      typeof d.multiparadaLegsTotal === "number" && (d.multiparadaLegsTotal as number) > 0
        ? Math.trunc(d.multiparadaLegsTotal as number)
        : totalLegsMultiparada(d);
    const legIndex = Math.trunc(Number(request.data?.legIndex ?? -1));
    if (!Number.isFinite(legIndex) || legIndex < 0 || legIndex >= total) {
      throw new HttpsError("invalid-argument", "Parada inválida.");
    }

    const abiertas = multiparadaParadasAbiertasSet(d, total);
    if (abiertas.has(legIndex)) {
      return { ok: true, viajeId, legIndex, yaAbierta: true };
    }
    abiertas.add(legIndex);
    patch.multiparadaParadasAbiertas = [...abiertas]
      .filter((i) => i >= 0 && i < total)
      .sort((a, b) => a - b);
    patch.multiparadaParadaAbiertaEn = now;
    if (estado !== "en_curso") {
      patch.estado = "en_curso";
    }
    tx.update(viajeRef, patch);
    return { ok: true, viajeId, legIndex, yaAbierta: false };
  });
});
