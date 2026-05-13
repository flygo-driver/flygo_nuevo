/**
 * Lógica pura compartida entre la callable de promoción y tests (sin Firestore).
 */

export type AnyMap = Record<string, unknown>;

export const UMBRAL_COMISION_LEGACY_RD = 500;

export function comisionPendienteRdFromBilletera(data: AnyMap | undefined): number {
  if (!data) return 0;
  const v = data.comisionPendiente;
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
}

export function saldoPrepagoRdFromBilletera(data: AnyMap | undefined): number {
  if (!data) return 0;
  const v = data.saldoPrepagoComisionRd;
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
}

export function saldoReservadoGirasRdFromBilletera(data: AnyMap | undefined): number {
  if (!data) return 0;
  const v = data.saldoReservadoParaGiras;
  if (typeof v === "number" && Number.isFinite(v)) return Math.max(0, v);
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? Math.max(0, n) : 0;
  }
  return 0;
}

export function saldoDisponiblePrepagoRdFromBilletera(data: AnyMap | undefined): number {
  const prep = saldoPrepagoRdFromBilletera(data);
  const res = saldoReservadoGirasRdFromBilletera(data);
  return Math.max(0, prep - res);
}

/** Igual que `PagosTaxistaRepo.bloqueoOperativoPorComisionEfectivo` / `bloqueoOperativoPrepago` en finance.ts */
export function bloqueoOperativoPorComisionEfectivo(billeData: AnyMap | undefined): boolean {
  const pend = comisionPendienteRdFromBilletera(billeData);
  if (pend + 1e-9 >= UMBRAL_COMISION_LEGACY_RD) return true;
  if (pend > 1e-6) return false;
  if (billeData?.primerViajeComisionGratisConsumido !== true) return false;
  return saldoDisponiblePrepagoRdFromBilletera(billeData) <= 1e-6;
}

export function taxistaSinBloqueoPrepagoOperativo(
  uData: AnyMap | undefined,
  billeData: AnyMap | undefined,
): boolean {
  if (uData?.tienePagoPendiente === true) return false;
  if (bloqueoOperativoPorComisionEfectivo(billeData)) return false;
  return true;
}

export function mensajeBloqueoOperativo(): string {
  return "No puedes recibir el siguiente viaje: revisa saldo prepago de comisión o deuda legacy en Mis pagos.";
}

export type ColaSortKey = { id: string; slot: number; createdAtMs: number };

export function sortColaCandidates(a: ColaSortKey, b: ColaSortKey): number {
  if (a.slot !== b.slot) return a.slot - b.slot;
  return a.createdAtMs - b.createdAtMs;
}
