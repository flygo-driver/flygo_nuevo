import type { AnyMap } from "./taxista_cola_promote_logic.js";

function nn(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  const n = Number(String(v ?? ""));
  return Number.isFinite(n) ? n : Number.NaN;
}

export function coordsValidas(lat: number, lon: number): boolean {
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return false;
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return false;
  if (Math.abs(lat) < 1e-6 && Math.abs(lon) < 1e-6) return false;
  return true;
}

export function coordsPickupClienteViaje(m: AnyMap | undefined): { lat: number; lon: number } | null {
  if (!m) return null;
  const lat = nn(m.latCliente);
  const lon = nn(m.lonCliente);
  if (!coordsValidas(lat, lon)) return null;
  return { lat, lon };
}

export function coordsDestinoFinalViaje(m: AnyMap | undefined): { lat: number; lon: number } | null {
  if (!m) return null;
  const lat = nn(m.latDestino);
  const lon = nn(m.lonDestino);
  if (!coordsValidas(lat, lon)) return null;
  return { lat, lon };
}

function waypointCoords(w: unknown): { lat: number; lon: number } | null {
  if (!w || typeof w !== "object") return null;
  const m = w as AnyMap;
  const lat = nn(m.lat);
  const lon = nn(m.lon);
  if (!coordsValidas(lat, lon)) return null;
  return { lat, lon };
}

function waypointsOrdenados(v: AnyMap): AnyMap[] {
  const raw = v.waypoints;
  if (!Array.isArray(raw) || raw.length === 0) return [];
  const copy = raw
    .filter((w) => w && typeof w === "object")
    .map((w) => w as AnyMap);
  copy.sort((a, b) => {
    const oa = typeof a.orden === "number" ? Math.trunc(a.orden) : 0;
    const ob = typeof b.orden === "number" ? Math.trunc(b.orden) : 0;
    if (oa !== ob) return oa - ob;
    return 0;
  });
  return copy;
}

function multiparadaRutaCompleta(v: AnyMap): boolean {
  if (v.multiparadaCompleta === true) return true;
  const wps = waypointsOrdenados(v);
  if (wps.length === 0) return true;
  const total =
    typeof v.multiparadaLegsTotal === "number" && Number.isFinite(v.multiparadaLegsTotal)
      ? Math.max(1, Math.trunc(v.multiparadaLegsTotal as number))
      : wps.length + 1;
  const hechas =
    typeof v.multiparadaLegCompletadas === "number" && Number.isFinite(v.multiparadaLegCompletadas)
      ? Math.max(0, Math.trunc(v.multiparadaLegCompletadas as number))
      : 0;
  return hechas >= total;
}

/**
 * Punto de referencia para encadenar: parada actual en multiparada o destino final.
 * Paridad con `_coordsLegMultiActual` / `_coordsDestinoParaFinalizar` (taxista en curso).
 */
export function coordsReferenciaEncadenamientoViajeActivo(
  v: AnyMap | undefined,
): { lat: number; lon: number } | null {
  if (!v) return null;
  const wps = waypointsOrdenados(v);
  if (wps.length > 0 && !multiparadaRutaCompleta(v)) {
    const hechas =
      typeof v.multiparadaLegCompletadas === "number" && Number.isFinite(v.multiparadaLegCompletadas)
        ? Math.max(0, Math.trunc(v.multiparadaLegCompletadas as number))
        : 0;
    if (hechas < wps.length) {
      const leg = waypointCoords(wps[hechas]);
      if (leg) return leg;
    }
  }
  return coordsDestinoFinalViaje(v);
}

export function distanciaMetros(
  a: { lat: number; lon: number },
  b: { lat: number; lon: number },
): number {
  const R = 6371000;
  const φ1 = (a.lat * Math.PI) / 180;
  const φ2 = (b.lat * Math.PI) / 180;
  const Δφ = ((b.lat - a.lat) * Math.PI) / 180;
  const Δλ = ((b.lon - a.lon) * Math.PI) / 180;
  const sinΔφ = Math.sin(Δφ / 2);
  const sinΔλ = Math.sin(Δλ / 2);
  const h = sinΔφ * sinΔφ + Math.cos(φ1) * Math.cos(φ2) * sinΔλ * sinΔλ;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}
