import { getFirestore } from "firebase-admin/firestore";

const COMISION_DOC = "comision";
const TTL_MS = 60_000;

/** Giras por cupos: % fijo del prepago (no sigue `config/comision` del admin). */
export const COMISION_GIRA_POR_CUPOS_PCT = 10;

let _cache: { loadedAt: number; pct: number } | null = null;

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

function clampPct(v: number): number {
  if (!Number.isFinite(v)) return 20;
  return Math.min(100, Math.max(0, v));
}

/** Invalida caché (p. ej. tras `setComisionPorcentaje`). */
export function invalidateComisionViajePctCache(): void {
  _cache = null;
}

/**
 * Porcentaje global de comisión en viajes en efectivo (doc `config/comision`, campo `porcentaje`).
 * Default 20. TTL 60s en memoria.
 */
export async function getComisionViajePorcentajeCached(): Promise<number> {
  const now = Date.now();
  if (_cache && now - _cache.loadedAt < TTL_MS) {
    return _cache.pct;
  }
  try {
    const snap = await db().collection("config").doc(COMISION_DOC).get();
    const raw = (snap.data() ?? {}) as AnyMap;
    const p = typeof raw.porcentaje === "number" && Number.isFinite(raw.porcentaje)
      ? raw.porcentaje
      : 20;
    const pct = clampPct(p);
    _cache = { loadedAt: now, pct };
    return pct;
  } catch (e) {
    console.error("[getComisionViajePorcentajeCached]", e);
    _cache = { loadedAt: now, pct: 20 };
    return 20;
  }
}

/** % de comisión en prepago para giras por cupos (`viajes_pool`). */
export function getComisionGiraPorcientoFijo(): number {
  return COMISION_GIRA_POR_CUPOS_PCT;
}

/** Comisión en centavos: round2(totalRd * pct/100) → centavos enteros. */
export function comisionCentsDesdePrecioCents(precioCents: number, pct: number): number {
  const totalRd = precioCents / 100;
  const comisionRd = Number((totalRd * (pct / 100)).toFixed(2));
  return Math.round(comisionRd * 100);
}
