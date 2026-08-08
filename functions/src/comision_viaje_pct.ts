import { getFirestore } from "firebase-admin/firestore";

const COMISION_DOC = "comision";
const TTL_MS = 60_000;

/** Giras por cupos: % fijo del prepago (no sigue `config/comision` del admin). */
export const COMISION_GIRA_POR_CUPOS_PCT = 10;

/** Defaults de apertura si admin no configuró aún. */
export const COMISION_EFECTIVO_PCT_DEFAULT = 10;
export const COMISION_TRANSFERENCIA_PCT_DEFAULT = 15;
export const COMISION_TARJETA_PCT_DEFAULT = 15;

export type MetodoComisionViaje = "efectivo" | "transferencia" | "tarjeta";

export type ComisionConfigParsed = {
  porcentaje: number;
  porcentajeTransferencia: number;
  porcentajeTarjeta: number;
};

type ComisionConfigCache = ComisionConfigParsed & { loadedAt: number };

let _cache: ComisionConfigCache | null = null;

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

function clampPct(v: number, fallback: number): number {
  if (!Number.isFinite(v)) return fallback;
  return Math.min(100, Math.max(0, v));
}

/** Parsea `config/comision` con defaults seguros por método. */
export function parseComisionConfig(data: AnyMap): ComisionConfigParsed {
  const porcentaje = clampPct(
    typeof data.porcentaje === "number" ? data.porcentaje : NaN,
    COMISION_EFECTIVO_PCT_DEFAULT,
  );
  const porcentajeTransferencia = clampPct(
    typeof data.porcentajeTransferencia === "number"
      ? data.porcentajeTransferencia
      : NaN,
    COMISION_TRANSFERENCIA_PCT_DEFAULT,
  );
  const porcentajeTarjeta = clampPct(
    typeof data.porcentajeTarjeta === "number" ? data.porcentajeTarjeta : NaN,
    COMISION_TARJETA_PCT_DEFAULT,
  );
  return { porcentaje, porcentajeTransferencia, porcentajeTarjeta };
}

async function loadComisionConfigCached(): Promise<ComisionConfigCache> {
  const now = Date.now();
  if (_cache && now - _cache.loadedAt < TTL_MS) {
    return _cache;
  }
  try {
    const snap = await db().collection("config").doc(COMISION_DOC).get();
    const parsed = parseComisionConfig((snap.data() ?? {}) as AnyMap);
    _cache = { loadedAt: now, ...parsed };
    return _cache;
  } catch (e) {
    console.error("[loadComisionConfigCached]", e);
    _cache = {
      loadedAt: now,
      porcentaje: COMISION_EFECTIVO_PCT_DEFAULT,
      porcentajeTransferencia: COMISION_TRANSFERENCIA_PCT_DEFAULT,
      porcentajeTarjeta: COMISION_TARJETA_PCT_DEFAULT,
    };
    return _cache;
  }
}

/** Invalida caché (p. ej. tras `setComisionPorcentaje`). */
export function invalidateComisionViajePctCache(): void {
  _cache = null;
}

/**
 * Porcentaje efectivo / prepago (`config/comision.porcentaje`).
 * Default 10. TTL 60s en memoria.
 */
export async function getComisionViajePorcentajeCached(): Promise<number> {
  const cfg = await loadComisionConfigCached();
  return cfg.porcentaje;
}

/** Config completa en caché (admin / diagnóstico). */
export async function getComisionConfigCached(): Promise<ComisionConfigParsed> {
  const cfg = await loadComisionConfigCached();
  return {
    porcentaje: cfg.porcentaje,
    porcentajeTransferencia: cfg.porcentajeTransferencia,
    porcentajeTarjeta: cfg.porcentajeTarjeta,
  };
}

/**
 * Comisión RAI según método de pago del viaje.
 * - efectivo → `porcentaje` (default 10)
 * - transferencia → `porcentajeTransferencia` (default 15)
 * - tarjeta → `porcentajeTarjeta` (default 15)
 */
export async function getComisionPorMetodoCached(
  metodo: MetodoComisionViaje,
): Promise<number> {
  const cfg = await loadComisionConfigCached();
  if (metodo === "tarjeta") return cfg.porcentajeTarjeta;
  if (metodo === "transferencia") return cfg.porcentajeTransferencia;
  return cfg.porcentaje;
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
