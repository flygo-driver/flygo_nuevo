import { FieldValue, getFirestore, type DocumentSnapshot, type Transaction } from "firebase-admin/firestore";

import { ledgerNegocioAliadoViajeGratisCreditoCf } from "./taxista_prepago_ledger.js";

export const NEGOCIO_ALIADO_PCT_TAXISTA = 15;
export const NEGOCIO_ALIADO_PCT_NEGOCIO = 3;
export const NEGOCIO_ALIADO_TOPE_GRATIS_CENTS = 60_000;
/** Viajes pagados exigidos antes del gratis cuando el perfil no trae `negocioPromoMxKM`. */
export const NEGOCIO_ALIADO_PROMO_M_DEFAULT = 5;

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

export const NEGOCIO_ALIADO_GRATIS_RECHAZO = {
  sinPromoVigente: "promo_no_vigente",
  codigoDistinto: "codigo_distinto_al_registrado",
  contadorInsuficiente: "contador_insuficiente",
} as const;

export type NegocioAliadoGratisRechazo =
  (typeof NEGOCIO_ALIADO_GRATIS_RECHAZO)[keyof typeof NEGOCIO_ALIADO_GRATIS_RECHAZO];

/**
 * ¿El cliente ganó de verdad el viaje gratis? Se mide contra el contador que
 * vive en su perfil (solo el backend lo sube al finalizar cada viaje pagado),
 * nunca contra los campos que la app escribió en el viaje.
 */
export function elegibilidadViajeGratisNegocioAliado(params: {
  viajeData: AnyMap;
  clienteData: AnyMap;
}): { elegible: boolean; motivo: NegocioAliadoGratisRechazo | null; contador: number; m: number } {
  const { viajeData, clienteData } = params;
  const m = Math.max(1, Math.trunc(Number(clienteData.negocioPromoMxKM ?? NEGOCIO_ALIADO_PROMO_M_DEFAULT)));
  const contador = Math.max(0, Math.trunc(Number(clienteData.negocioPromoContador ?? 0)));

  if (!promoNegocioAliadoVigente(clienteData)) {
    return { elegible: false, motivo: NEGOCIO_ALIADO_GRATIS_RECHAZO.sinPromoVigente, contador, m };
  }

  const codigoViaje = codigoNegocioAliadoDesdeViaje(viajeData);
  const codigoCliente = String(clienteData.negocioReferidoCodigo ?? "").trim().toUpperCase();
  if (!codigoViaje || codigoViaje !== codigoCliente) {
    return { elegible: false, motivo: NEGOCIO_ALIADO_GRATIS_RECHAZO.codigoDistinto, contador, m };
  }

  if (contador < m) {
    return { elegible: false, motivo: NEGOCIO_ALIADO_GRATIS_RECHAZO.contadorInsuficiente, contador, m };
  }

  return { elegible: true, motivo: null, contador, m };
}

function saldoPrepagoRdFromBilletera(data: AnyMap): number {
  const raw = data.saldoPrepagoComisionRd;
  if (typeof raw === "number" && Number.isFinite(raw)) return raw;
  if (typeof raw === "string") return Number.parseFloat(raw) || 0;
  return 0;
}

/**
 * 6.º viaje gratis QR: RAI repone en recargas la ganancia neta que el taxista no
 * cobró, para que quede igual que si el pasajero le hubiera pagado.
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

  // RAI solo repone el viaje gratis si el cliente lo ganó según su propio contador.
  const elegibilidad = elegibilidadViajeGratisNegocioAliado({
    viajeData: params.viajeData,
    clienteData,
  });
  if (!elegibilidad.elegible) {
    console.warn(
      "[negocioAliadoGratis] credito rechazado",
      params.viajeId,
      elegibilidad.motivo,
      `contador=${elegibilidad.contador}/${elegibilidad.m}`,
    );
    return {
      ...noop,
      patchViaje: {
        negocioAliadoGratisCreditoRechazado: true,
        negocioAliadoGratisCreditoRechazoMotivo: elegibilidad.motivo,
        negocioAliadoGratisCreditoRechazoContador: elegibilidad.contador,
        negocioAliadoGratisCreditoRechazadoEn: FieldValue.serverTimestamp(),
      },
    };
  }

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

  const creditoCents = creditoViajeGratisNegocioAliadoCents({
    gananciaCents: params.gananciaCents,
    precioCents: params.precioCents,
  });
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
 * Lo que RAI repone en recargas por el viaje gratis: la ganancia neta que el
 * taxista dejó de cobrar. En estos viajes la comisión NO se debita del prepago
 * (ver `aplicaCreditoPrepagoGratis` en finance.ts), así que reponer la tarifa
 * completa le regalaría también la comisión.
 */
export function creditoViajeGratisNegocioAliadoCents(params: {
  gananciaCents: number;
  precioCents: number;
}): number {
  const ganancia = Number.isFinite(params.gananciaCents)
    ? Math.max(0, Math.trunc(params.gananciaCents))
    : 0;
  const cobrado = Number.isFinite(params.precioCents)
    ? Math.max(0, Math.trunc(params.precioCents))
    : 0;
  return Math.max(0, ganancia - cobrado);
}

/**
 * Contador tras cerrar un viaje referido: el gratis lo reinicia, y quien ya llegó
 * a la meta pero viajó fuera del pueblo conserva su premio (paga completo sin subir).
 */
export function contadorPromoTrasCierreNegocioAliado(params: {
  contadorActual: number;
  m: number;
  esGratis: boolean;
}): number {
  if (params.esGratis) return 0;
  if (params.contadorActual >= params.m) return params.contadorActual;
  return params.contadorActual + 1;
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
    Math.trunc(Number(clienteData.negocioPromoMxKM ?? NEGOCIO_ALIADO_PROMO_M_DEFAULT)),
  );
  const contadorActual = Math.max(
    0,
    Math.trunc(Number(clienteData.negocioPromoContador ?? 0)),
  );
  // Solo cuenta como gratis si el contador del perfil lo respalda; si la app lo
  // marcó sin haberlo ganado, el viaje se contabiliza como pagado normal.
  const esGratis =
    viajeData.negocioAliadoPromoGratis === true &&
    elegibilidadViajeGratisNegocioAliado({ viajeData, clienteData }).elegible;
  const nuevoContador = contadorPromoTrasCierreNegocioAliado({
    contadorActual,
    m,
    esGratis,
  });

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
