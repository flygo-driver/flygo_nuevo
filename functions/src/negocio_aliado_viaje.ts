import { FieldValue, getFirestore, type DocumentSnapshot, type Transaction } from "firebase-admin/firestore";

import { ledgerNegocioAliadoViajeGratisCreditoCf } from "./taxista_prepago_ledger.js";

export const NEGOCIO_ALIADO_PCT_TAXISTA = 15;
export const NEGOCIO_ALIADO_PCT_NEGOCIO = 3;
export const NEGOCIO_ALIADO_TOPE_GRATIS_CENTS = 60_000;

type AnyMap = Record<string, unknown>;

export function codigoNegocioAliadoDesdeViaje(d: AnyMap): string {
  return String(d.negocioAliadoCodigo ?? "").trim().toUpperCase();
}

export function viajeEsNegocioAliadoReferido(d: AnyMap): boolean {
  return codigoNegocioAliadoDesdeViaje(d).length > 0;
}

/** Viajes QR negocio: 15% siempre, incluso 1.er efectivo del taxista. */
export function negocioAliadoEximePrimerEfectivoGratis(d: AnyMap): boolean {
  return viajeEsNegocioAliadoReferido(d);
}

export function precioNominalCentsDesdeViaje(d: AnyMap): number {
  const nominal = d.precioNominalCents;
  if (typeof nominal === "number" && Number.isFinite(nominal) && nominal > 0) {
    return Math.trunc(nominal);
  }
  const pc = d.precio_cents;
  if (typeof pc === "number" && Number.isFinite(pc) && pc > 0) {
    return Math.trunc(pc);
  }
  const p = Number(d.precioFinal ?? d.precio ?? d.total ?? 0);
  return Math.max(0, Math.round(p * 100));
}

export function comisionNegocioAliadoCentsDesdeNominal(precioNominalCents: number): number {
  const rd = precioNominalCents / 100;
  const com = Number((rd * (NEGOCIO_ALIADO_PCT_NEGOCIO / 100)).toFixed(2));
  return Math.round(com * 100);
}

export function resolverComisionPctNegocioAliado(
  viajeData: AnyMap,
  pctGlobal: number,
): { pct: number; usarIncentivos: boolean } {
  if (!viajeEsNegocioAliadoReferido(viajeData)) {
    return { pct: pctGlobal, usarIncentivos: true };
  }
  const stored = Number(viajeData.comisionPorcentaje ?? 0);
  if (Number.isFinite(stored) && stored > 0 && stored <= 100) {
    return { pct: stored, usarIncentivos: false };
  }
  return { pct: NEGOCIO_ALIADO_PCT_TAXISTA, usarIncentivos: false };
}

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

export function promoNegocioAliadoVigente(clienteData: AnyMap): boolean {
  const codigo = String(clienteData.negocioReferidoCodigo ?? "").trim();
  if (!codigo) return false;
  if (clienteData.negocioReferidoAt == null) return false;
  const vence = leerFechaPromo(clienteData.negocioPromoVenceAt);
  if (vence && Date.now() > vence.getTime()) return false;
  return true;
}

function saldoPrepagoRdFromBilletera(data: AnyMap): number {
  const raw = data.saldoPrepagoComisionRd;
  if (typeof raw === "number" && Number.isFinite(raw)) return raw;
  if (typeof raw === "string") return Number.parseFloat(raw) || 0;
  return 0;
}

/**
 * 6.º viaje gratis QR: acredita prepago al taxista (RAI paga la ganancia neta).
 * Idempotente vía ledger `negocio_aliado_gratis_{viajeId}` y flag en viaje.
 * Solo aplica si la promo del cliente sigue vigente (90 días).
 */
export async function acreditarPrepagoViajeGratisNegocioAliadoEnTx(params: {
  tx: Transaction;
  uidTaxista: string;
  viajeId: string;
  viajeData: AnyMap;
  clienteSnap: DocumentSnapshot | null;
  gananciaCents: number;
  precioCents: number;
  billeData: AnyMap;
  fuente: string;
  existingLedgerSnap?: DocumentSnapshot;
}): Promise<{
  applied: boolean;
  alreadyCredited: boolean;
  saldoPrepagoDespues: number;
  creditoRd: number;
  patchViaje: AnyMap;
}> {
  const saldoActual = saldoPrepagoRdFromBilletera(params.billeData);
  const noop = {
    applied: false,
    alreadyCredited: false,
    saldoPrepagoDespues: saldoActual,
    creditoRd: 0,
    patchViaje: {} as AnyMap,
  };

  if (params.viajeData.negocioAliadoPromoGratis !== true) return noop;
  if (!viajeEsNegocioAliadoReferido(params.viajeData)) return noop;
  if (!params.clienteSnap?.exists) return noop;

  const clienteData = (params.clienteSnap.data() ?? {}) as AnyMap;
  if (!promoNegocioAliadoVigente(clienteData)) return noop;

  if (params.viajeData.negocioAliadoPrepagoAcreditado === true) {
    const creditoPrev = Number(params.viajeData.negocioAliadoPrepagoCreditoRd ?? 0);
    return {
      applied: false,
      alreadyCredited: true,
      saldoPrepagoDespues: saldoActual,
      creditoRd: Number.isFinite(creditoPrev) ? creditoPrev : 0,
      patchViaje: {},
    };
  }

  const creditoCents = Math.max(0, params.gananciaCents - params.precioCents);
  if (creditoCents < 1) return noop;

  const creditoRd = Number((creditoCents / 100).toFixed(2));
  const saldoAntes = saldoActual;
  const saldoDespues = Number((saldoAntes + creditoRd).toFixed(2));
  const gananciaRd = Number((params.gananciaCents / 100).toFixed(2));
  const precioCobradoRd = Number((params.precioCents / 100).toFixed(2));

  const ledgerWrote = await ledgerNegocioAliadoViajeGratisCreditoCf(params.tx, {
    uidTaxista: params.uidTaxista,
    viajeId: params.viajeId,
    fuente: params.fuente,
    creditoRd,
    gananciaRd,
    precioCobradoRd,
    saldoPrepagoAntes: saldoAntes,
    saldoPrepagoDespues: saldoDespues,
    existingMovSnap: params.existingLedgerSnap,
  });

  if (!ledgerWrote) {
    if (!params.existingLedgerSnap?.exists) return noop;
    const ledgerData = (params.existingLedgerSnap.data() ?? {}) as AnyMap;
    const saldoLedger = Number(ledgerData.saldoPrepagoDespues ?? saldoActual);
    const creditoLedger = Number(ledgerData.creditoRd ?? 0);
    const creditoOk = Number.isFinite(creditoLedger) ? creditoLedger : 0;
    const saldoOk = Number.isFinite(saldoLedger) ? saldoLedger : saldoActual;
    return {
      applied: false,
      alreadyCredited: true,
      saldoPrepagoDespues: saldoOk,
      creditoRd: creditoOk,
      patchViaje:
        params.viajeData.negocioAliadoPrepagoAcreditado === true
          ? {}
          : {
              negocioAliadoPrepagoAcreditado: true,
              negocioAliadoPrepagoCreditoRd: creditoOk,
              negocioAliadoPrepagoAcreditadoEn: FieldValue.serverTimestamp(),
            },
    };
  }

  const billeRef = getFirestore().collection("billeteras_taxista").doc(params.uidTaxista.trim());
  params.tx.set(
    billeRef,
    {
      saldoPrepagoComisionRd: saldoDespues,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return {
    applied: true,
    alreadyCredited: false,
    saldoPrepagoDespues: saldoDespues,
    creditoRd,
    patchViaje: {
      negocioAliadoPrepagoAcreditado: true,
      negocioAliadoPrepagoCreditoRd: creditoRd,
      negocioAliadoPrepagoAcreditadoEn: FieldValue.serverTimestamp(),
    },
  };
}

/**
 * Tras finalizar viaje referido: contador cliente 5+1, viajesReferidos negocio, comisión 3%.
 * Idempotente con flag `negocioAliadoPromoContabilizado` en el viaje.
 */
export function aplicarCierreNegocioAliadoEnTx(params: {
  tx: Transaction;
  viajeData: AnyMap;
  uidCliente: string;
  clienteSnap: DocumentSnapshot;
  precioNominalCents: number;
}): AnyMap {
  const { tx, viajeData, uidCliente, clienteSnap, precioNominalCents } = params;
  const patch: AnyMap = {};

  if (!viajeEsNegocioAliadoReferido(viajeData)) return patch;
  if (viajeData.negocioAliadoPromoContabilizado === true) return patch;
  if (!uidCliente) return patch;

  const clienteData = (clienteSnap.data() ?? {}) as AnyMap;
  if (!promoNegocioAliadoVigente(clienteData)) return patch;

  const m = Math.max(
    1,
    Math.trunc(Number(clienteData.negocioPromoMxKM ?? 5)),
  );
  const contadorActual = Math.max(
    0,
    Math.trunc(Number(clienteData.negocioPromoContador ?? 0)),
  );
  const esGratis = viajeData.negocioAliadoPromoGratis === true;
  const contadorAlCrear = Math.trunc(Number(viajeData.negocioAliadoPromoContadorAlCrear ?? contadorActual));
  const eraElegibleGratis = contadorAlCrear >= m;
  // 6.º viaje inter-pueblo: paga completo y conserva contador en M.
  let nuevoContador = contadorActual;
  if (esGratis) {
    nuevoContador = 0;
  } else if (eraElegibleGratis && !esGratis) {
    nuevoContador = contadorActual;
  } else {
    nuevoContador = contadorActual + 1;
  }

  tx.set(
    clienteSnap.ref,
    {
      negocioPromoContador: nuevoContador,
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const codigo = codigoNegocioAliadoDesdeViaje(viajeData);
  if (codigo) {
    tx.set(
      getFirestore().collection("negocios_aliados").doc(codigo),
      {
        viajesReferidos: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  const comisionNegocioCents = esGratis
    ? 0
    : comisionNegocioAliadoCentsDesdeNominal(precioNominalCents);

  patch.negocioAliadoPromoContabilizado = true;
  patch.negocioAliadoComisionNegocioCents = comisionNegocioCents;
  patch.negocioAliadoComisionNegocioRd = comisionNegocioCents / 100;
  patch.negocioAliadoPctComisionTaxista = NEGOCIO_ALIADO_PCT_TAXISTA;
  patch.negocioAliadoPctComisionNegocio = NEGOCIO_ALIADO_PCT_NEGOCIO;

  return patch;
}
