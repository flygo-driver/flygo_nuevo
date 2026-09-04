import type { AnyMap } from "./turismo_asignacion_logic.js";
import {
  NEGOCIO_ALIADO_PCT_NEGOCIO,
  NEGOCIO_ALIADO_PCT_TAXISTA,
  NEGOCIO_ALIADO_TOPE_GRATIS_CENTS,
} from "./negocio_aliado_viaje.js";

export const NEGOCIO_ALIADO_PROMO_M = 5;
export const NEGOCIO_ALIADO_PROMO_K = 1;
export const NEGOCIO_ALIADO_VIGENCIA_DIAS = 90;

const NEGOCIO_ALIADO_TRIP_KEYS = [
  "negocioAliadoCodigo",
  "negocioAliadoNombre",
  "negocioAliadoPromoGratis",
  "negocioAliadoViajeLocalPueblo",
  "negocioAliadoDescuentoRd",
  "precioNominalCents",
  "negocioAliadoPromoContadorAlCrear",
  "negocioAliadoExigeComision15",
  "negocioAliadoPctComisionNegocio",
  "negocioAliadoCiudadPueblo",
] as const;

function leerFechaPromo(v: unknown): Date | null {
  if (v == null) return null;
  if (v instanceof Date) return v;
  if (typeof v === "object" && v !== null && "toDate" in v) {
    try {
      return (v as { toDate: () => Date }).toDate();
    } catch {
      return null;
    }
  }
  return null;
}

export function normalizarCiudadNegocio(raw: string): string {
  let t = String(raw ?? "").trim().toUpperCase();
  t = t.replace(/[ÁÀÂÄ]/g, "A");
  t = t.replace(/[ÉÈÊË]/g, "E");
  t = t.replace(/[ÍÌÎÏ]/g, "I");
  t = t.replace(/[ÓÒÔÖ]/g, "O");
  t = t.replace(/[ÚÙÛÜ]/g, "U");
  t = t.replace(/[^A-Z0-9\s]/g, " ");
  t = t.replace(/\s+/g, " ").trim();
  return t;
}

function variantesCiudadNegocio(ciudadNegocio: string): string[] {
  const out: string[] = [];
  for (const parte of String(ciudadNegocio ?? "").split(/[,/|;]/)) {
    const c = normalizarCiudadNegocio(parte);
    if (c && !out.includes(c)) out.push(c);
  }
  return out;
}

/** Origen y destino deben contener el pueblo del negocio (misma ciudad). */
export function viajeEsLocalEnPuebloNegocio(params: {
  ciudadNegocio: string;
  origen: string;
  destino: string;
  origenGeoExtra?: string;
  destinoGeoExtra?: string;
}): boolean {
  const variantes = variantesCiudadNegocio(params.ciudadNegocio);
  if (!variantes.length) return false;
  const o = normalizarCiudadNegocio(
    `${params.origen} ${params.origenGeoExtra ?? ""}`,
  );
  const d = normalizarCiudadNegocio(
    `${params.destino} ${params.destinoGeoExtra ?? ""}`,
  );
  if (!o || !d) return false;
  return variantes.some((c) => o.includes(c) && d.includes(c));
}

function stripNegocioAliadoTripFields(trip: AnyMap): void {
  for (const k of NEGOCIO_ALIADO_TRIP_KEYS) {
    delete trip[k];
  }
}

function numRd(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number.parseFloat(v.replace(",", "."));
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

export type PromoNegocioAliadoEval = {
  codigo: string;
  nombre: string;
  ciudadPueblo: string;
  contador: number;
  m: number;
  k: number;
  esGratis: boolean;
  viajeLocalEnPueblo: boolean;
  precioNominalRd: number;
  precioClienteRd: number;
  descuentoRd: number;
};

export function evaluarPromoNegocioAliado(params: {
  clienteData: AnyMap;
  precioNominalRd: number;
  origen: string;
  destino: string;
  ciudadNegocioOverride?: string;
}): PromoNegocioAliadoEval | null {
  const { clienteData, precioNominalRd, origen, destino } = params;
  if (!Number.isFinite(precioNominalRd) || precioNominalRd <= 0) return null;

  const codigo = String(clienteData.negocioReferidoCodigo ?? "").trim().toUpperCase();
  if (!codigo) return null;
  if (clienteData.negocioReferidoAt == null) return null;

  const vence = leerFechaPromo(clienteData.negocioPromoVenceAt);
  if (vence && Date.now() > vence.getTime()) return null;

  const m = Math.max(
    1,
    Math.trunc(Number(clienteData.negocioPromoMxKM ?? NEGOCIO_ALIADO_PROMO_M)),
  );
  const k = Math.max(
    0,
    Math.trunc(Number(clienteData.negocioPromoMxKK ?? NEGOCIO_ALIADO_PROMO_K)),
  );
  const contador = Math.max(0, Math.trunc(Number(clienteData.negocioPromoContador ?? 0)));
  const nombre = String(clienteData.negocioReferidoNombre ?? "").trim();
  const ciudadNegocio = String(
    params.ciudadNegocioOverride ??
      clienteData.negocioReferidoCiudad ??
      "",
  ).trim();

  const elegibleGratis = contador >= m && k > 0;
  const viajeLocalEnPueblo = viajeEsLocalEnPuebloNegocio({
    ciudadNegocio,
    origen,
    destino,
  });
  const esGratis = elegibleGratis && viajeLocalEnPueblo;
  const topeGratisRd = NEGOCIO_ALIADO_TOPE_GRATIS_CENTS / 100;
  const descuentoRd = esGratis
    ? Math.min(precioNominalRd, topeGratisRd)
    : 0;
  const precioClienteRd = Number(
    Math.max(0, precioNominalRd - descuentoRd).toFixed(2),
  );

  return {
    codigo,
    nombre,
    ciudadPueblo: ciudadNegocio,
    contador,
    m,
    k,
    esGratis,
    viajeLocalEnPueblo,
    precioNominalRd,
    precioClienteRd,
    descuentoRd,
  };
}

/** Revalida promo QR en servidor (no confiar en campos del cliente). */
export function aplicarPromoNegocioAliadoEnTrip(params: {
  trip: AnyMap;
  clienteData: AnyMap;
  negocioCiudad?: string;
  negocioActivo?: boolean;
}): AnyMap {
  const precioEnviado = numRd(params.trip.precio) ?? 0;
  const nominalCentsRaw = params.trip.precioNominalCents;
  let precioNominalRd = precioEnviado;
  if (typeof nominalCentsRaw === "number" && Number.isFinite(nominalCentsRaw) && nominalCentsRaw > 0) {
    precioNominalRd = nominalCentsRaw / 100;
  } else if (precioEnviado > 0) {
    precioNominalRd = precioEnviado;
  }

  const trip = { ...params.trip };
  stripNegocioAliadoTripFields(trip);

  const origen = String(trip.origen ?? "");
  const destino = String(trip.destino ?? "");

  if (params.negocioActivo === false) {
    trip.precio = precioNominalRd;
    trip.precio_cents = Math.max(0, Math.round(precioNominalRd * 100));
    return trip;
  }

  const evaluado = evaluarPromoNegocioAliado({
    clienteData: params.clienteData,
    precioNominalRd,
    origen,
    destino,
    ciudadNegocioOverride: params.negocioCiudad,
  });

  if (!evaluado) {
    trip.precio = precioNominalRd;
    trip.precio_cents = Math.max(0, Math.round(precioNominalRd * 100));
    return trip;
  }

  trip.negocioAliadoCodigo = evaluado.codigo;
  if (evaluado.nombre) trip.negocioAliadoNombre = evaluado.nombre;
  trip.negocioAliadoCiudadPueblo = evaluado.ciudadPueblo;
  trip.negocioAliadoPromoGratis = evaluado.esGratis;
  trip.negocioAliadoViajeLocalPueblo = evaluado.viajeLocalEnPueblo;
  trip.negocioAliadoDescuentoRd = evaluado.descuentoRd;
  trip.precioNominalCents = Math.round(evaluado.precioNominalRd * 100);
  trip.negocioAliadoPromoContadorAlCrear = evaluado.contador;
  trip.negocioAliadoExigeComision15 = true;
  trip.negocioAliadoPctComisionNegocio = NEGOCIO_ALIADO_PCT_NEGOCIO;
  trip.comisionPorcentaje = NEGOCIO_ALIADO_PCT_TAXISTA;
  trip.precio = evaluado.precioClienteRd;
  trip.precio_cents = Math.max(0, Math.round(evaluado.precioClienteRd * 100));

  return trip;
}
