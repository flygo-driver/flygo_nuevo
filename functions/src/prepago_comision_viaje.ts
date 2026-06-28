/**
 * Prepago disponible vs comisión estimada al aceptar un viaje en efectivo.
 * Paridad con PagosTaxistaRepo (Dart).
 */

import type { AnyMap } from "./turismo_asignacion_logic.js";
import { comisionCentsDesdePrecioCents } from "./comision_viaje_pct.js";

function comisionPendienteRdFromBilletera(data: AnyMap | undefined): number {
  if (!data) return 0;
  const v = data.comisionPendiente;
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
}

function saldoPrepagoRdFromBilletera(data: AnyMap | undefined): number {
  if (!data) return 0;
  const v = data.saldoPrepagoComisionRd;
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
}

function saldoReservadoGirasRdFromBilletera(data: AnyMap | undefined): number {
  if (!data) return 0;
  const v = data.saldoReservadoParaGiras;
  if (typeof v === "number" && Number.isFinite(v)) return Math.max(0, v);
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? Math.max(0, n) : 0;
  }
  return 0;
}

function saldoDisponiblePrepagoRdFromBilletera(data: AnyMap | undefined): number {
  const prep = saldoPrepagoRdFromBilletera(data);
  const res = saldoReservadoGirasRdFromBilletera(data);
  return Math.max(0, prep - res);
}

function toCents(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return Math.max(0, Math.round(v * 100));
  if (typeof v === "string") {
    const n = Number.parseFloat(v.replace(",", "."));
    if (Number.isFinite(n)) return Math.max(0, Math.round(n * 100));
  }
  return 0;
}

export function viajeEsEfectivoParaComisionPrepago(viaje: AnyMap): boolean {
  const metodo = String(viaje.metodoPago ?? "").toLowerCase().trim();
  if (!metodo) return false;
  if (metodo.includes("transfer") || metodo.includes("tarjeta") || metodo.includes("card")) {
    return false;
  }
  return metodo.includes("efectivo") || metodo === "cash";
}

export function precioCentsDesdeViaje(viaje: AnyMap): number {
  const precioCentsDb =
    typeof viaje.precio_cents === "number" ? Math.trunc(viaje.precio_cents) : null;
  if (precioCentsDb !== null && precioCentsDb > 0) return precioCentsDb;
  return toCents(viaje.precioFinal ?? viaje.precio ?? viaje.total ?? 0);
}

export function pctComisionDesdeViaje(viaje: AnyMap, globalPct: number): number {
  const raw = viaje.comisionPorcentaje;
  if (typeof raw === "number" && Number.isFinite(raw) && raw > 0) {
    return raw <= 1 ? raw * 100 : raw;
  }
  return globalPct;
}

export function comisionEstimadaRdDesdeViaje(viaje: AnyMap, globalPct: number): number {
  const precioCents = precioCentsDesdeViaje(viaje);
  if (precioCents <= 0) return 0;
  const pct = pctComisionDesdeViaje(viaje, globalPct);
  return comisionCentsDesdePrecioCents(precioCents, pct) / 100;
}

/** true si el taxista no tiene prepago libre suficiente para la comisión de este viaje en efectivo. */
export function prepagoInsuficienteParaViajeEfectivo(args: {
  billeData: AnyMap | undefined;
  viajeData: AnyMap;
  globalComisionPct: number;
}): boolean {
  if (!viajeEsEfectivoParaComisionPrepago(args.viajeData)) return false;

  const bData = args.billeData ?? {};
  const pend = comisionPendienteRdFromBilletera(bData);
  const primerGratis = bData.primerViajeComisionGratisConsumido === true;
  if (!primerGratis && pend < 1e-6) return false;

  const comisionRd = comisionEstimadaRdDesdeViaje(args.viajeData, args.globalComisionPct);
  if (comisionRd <= 1e-6) return false;

  const disp = saldoDisponiblePrepagoRdFromBilletera(bData);
  return disp + 1e-9 < comisionRd;
}

export const PREPAGO_INSUFICIENTE_COMISION_VIAJE = "prepago-insuficiente-comision-viaje";
