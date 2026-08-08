/**
 * Libro auxiliar paralelo a `billeteras_taxista` (Cloud Functions). No cambia saldos ni bloqueos.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import type { DocumentReference, DocumentSnapshot, Transaction } from "firebase-admin/firestore";

const db = () => getFirestore();

function safeId(raw: string): string {
  return raw.trim().replace(/\//g, "_");
}

function movColl(uid: string) {
  return db().collection("billeteras_taxista").doc(uid).collection("movimientos_prepago");
}

/** Ref del movimiento ledger de comisión por viaje en efectivo (misma ruta que [ledgerComisionViajeEfectivoCf]). */
export function comisionViajeEfectivoLedgerRef(
  uidTaxista: string,
  viajeId: string,
): DocumentReference {
  const uid = uidTaxista.trim();
  const vid = viajeId.trim();
  return movColl(uid).doc(safeId(`comision_viaje_${vid}`));
}

export async function ledgerComisionViajeEfectivoCf(
  tx: Transaction,
  params: {
    uidTaxista: string;
    viajeId: string;
    fuente: string;
    comisionTotalRd: number;
    pendienteAntes: number;
    saldoPrepagoAntes: number;
    pendienteDespues: number;
    saldoPrepagoDespues: number;
    primerEfectivoSinDescuento: boolean;
    /** Si ya leíste este doc en la misma transacción (antes de cualquier write), pasalo aquí. */
    existingMovSnap?: DocumentSnapshot;
  },
): Promise<void> {
  const uid = params.uidTaxista.trim();
  const vid = params.viajeId.trim();
  if (!uid || !vid) return;

  const ref = movColl(uid).doc(safeId(`comision_viaje_${vid}`));
  const snap = params.existingMovSnap ?? await tx.get(ref);
  if (snap.exists) return;

  const desdeLegacy = Math.max(0, params.pendienteAntes - params.pendienteDespues);
  const desdePrepago = Math.max(0, params.saldoPrepagoAntes - params.saldoPrepagoDespues);

  tx.set(ref, {
    schemaVersion: 1,
    createdAt: FieldValue.serverTimestamp(),
    tipo: params.primerEfectivoSinDescuento ? "primer_efectivo_sin_descuento" : "comision_viaje_efectivo",
    fuente: params.fuente,
    uidTaxista: uid,
    viajeId: vid,
    comisionTotalRd: Number(params.comisionTotalRd.toFixed(2)),
    comisionPendienteAntes: Number(params.pendienteAntes.toFixed(2)),
    saldoPrepagoAntes: Number(params.saldoPrepagoAntes.toFixed(2)),
    comisionPendienteDespues: Number(params.pendienteDespues.toFixed(2)),
    saldoPrepagoDespues: Number(params.saldoPrepagoDespues.toFixed(2)),
    desdeLegacyRd: Number(desdeLegacy.toFixed(2)),
    desdePrepagoRd: Number(desdePrepago.toFixed(2)),
  });
}

export async function ledgerComisionBolaPuebloCf(
  tx: Transaction,
  params: {
    uidTaxista: string;
    bolaId: string;
    fuente: string;
    comisionTotalRd: number;
    pendienteAntes: number;
    saldoPrepagoAntes: number;
    pendienteDespues: number;
    saldoPrepagoDespues: number;
    primerEfectivoSinDescuento: boolean;
    /** Si ya leíste este doc en la misma transacción (antes de cualquier write), pasalo aquí. */
    existingMovSnap?: DocumentSnapshot;
  },
): Promise<void> {
  const uid = params.uidTaxista.trim();
  const bid = params.bolaId.trim();
  if (!uid || !bid) return;

  const ref = movColl(uid).doc(safeId(`comision_bola_${bid}`));
  const snap = params.existingMovSnap ?? (await tx.get(ref));
  if (snap.exists) return;

  const desdeLegacy = Math.max(0, params.pendienteAntes - params.pendienteDespues);
  const desdePrepago = Math.max(0, params.saldoPrepagoAntes - params.saldoPrepagoDespues);

  tx.set(ref, {
    schemaVersion: 1,
    createdAt: FieldValue.serverTimestamp(),
    tipo: params.primerEfectivoSinDescuento ? "primer_efectivo_sin_descuento" : "comision_bola_pueblo",
    fuente: params.fuente,
    uidTaxista: uid,
    bolaId: bid,
    comisionTotalRd: Number(params.comisionTotalRd.toFixed(2)),
    comisionPendienteAntes: Number(params.pendienteAntes.toFixed(2)),
    saldoPrepagoAntes: Number(params.saldoPrepagoAntes.toFixed(2)),
    comisionPendienteDespues: Number(params.pendienteDespues.toFixed(2)),
    saldoPrepagoDespues: Number(params.saldoPrepagoDespues.toFixed(2)),
    desdeLegacyRd: Number(desdeLegacy.toFixed(2)),
    desdePrepagoRd: Number(desdePrepago.toFixed(2)),
  });
}

/** Ref ledger comisión Bola Ahorro (idempotente por bolaId). */
export function comisionBolaPuebloLedgerRef(
  uidTaxista: string,
  bolaId: string,
): DocumentReference {
  const uid = uidTaxista.trim();
  const bid = bolaId.trim();
  return movColl(uid).doc(safeId(`comision_bola_${bid}`));
}

function numBilletera(raw: unknown): number {
  if (typeof raw === "number" && Number.isFinite(raw)) return raw;
  if (typeof raw === "string") return Number.parseFloat(raw) || 0;
  return 0;
}

/**
 * Debita comisión de Bola Ahorro en billetera + ledger (misma regla que finalizarBolaPueblo).
 * Idempotente vía movimientos_prepago/comision_bola_{bolaId}.
 */
export async function debitarComisionBolaPuebloEnTx(
  tx: Transaction,
  params: {
    uidTaxista: string;
    bolaId: string;
    comisionRd: number;
    fuente: string;
    billeData: Record<string, unknown>;
    existingMovSnap?: DocumentSnapshot;
  },
): Promise<{
  appliedNow: boolean;
  alreadyHadLedger: boolean;
  saldoPrepagoDespues: number;
  primerGratis: boolean;
}> {
  const uid = params.uidTaxista.trim();
  const bid = params.bolaId.trim();
  const comision = Number(params.comisionRd);
  if (!uid || !bid || !Number.isFinite(comision) || comision < 0) {
    return {
      appliedNow: false,
      alreadyHadLedger: false,
      saldoPrepagoDespues: 0,
      primerGratis: false,
    };
  }

  const ledgerRef = comisionBolaPuebloLedgerRef(uid, bid);
  const movSnap = params.existingMovSnap ?? (await tx.get(ledgerRef));
  if (movSnap.exists) {
    const saldo = numBilletera(params.billeData.saldoPrepagoComisionRd);
    return {
      appliedNow: false,
      alreadyHadLedger: true,
      saldoPrepagoDespues: saldo,
      primerGratis: false,
    };
  }

  const billeRef = db().collection("billeteras_taxista").doc(uid);
  const pendAntes = numBilletera(params.billeData.comisionPendiente);
  let saldo = numBilletera(params.billeData.saldoPrepagoComisionRd);
  const flag = params.billeData.primerViajeComisionGratisConsumido === true;
  const saldoIni = saldo;
  const baseUpd = {
    updatedAt: FieldValue.serverTimestamp(),
    ultimaBolaFinalizadaId: bid,
    ultimaComisionBolaRd: comision,
  };

  if (!flag && pendAntes < 1e-6) {
    await ledgerComisionBolaPuebloCf(tx, {
      uidTaxista: uid,
      bolaId: bid,
      fuente: params.fuente,
      comisionTotalRd: comision,
      pendienteAntes: pendAntes,
      saldoPrepagoAntes: saldoIni,
      pendienteDespues: pendAntes,
      saldoPrepagoDespues: saldoIni,
      primerEfectivoSinDescuento: true,
      existingMovSnap: movSnap,
    });
    tx.set(
      billeRef,
      { ...baseUpd, primerViajeComisionGratisConsumido: true },
      { merge: true },
    );
    return {
      appliedNow: true,
      alreadyHadLedger: false,
      saldoPrepagoDespues: saldoIni,
      primerGratis: true,
    };
  }

  let p = pendAntes;
  const fromPend = Math.min(p, comision);
  p = Number.parseFloat((p - fromPend).toFixed(2));
  const rem = Number.parseFloat((comision - fromPend).toFixed(2));
  const rawRes = params.billeData.saldoReservadoParaGiras;
  const reserv =
    typeof rawRes === "number" && Number.isFinite(rawRes)
      ? Math.max(0, rawRes)
      : typeof rawRes === "string"
        ? Math.max(0, Number.parseFloat(rawRes) || 0)
        : 0;
  const prepagoLibreIni = Math.max(
    0,
    Number.parseFloat((saldoIni - reserv).toFixed(2)),
  );
  const cubiertoPrepago = rem <= prepagoLibreIni ? rem : prepagoLibreIni;
  const faltantePrepago = Number.parseFloat((rem - cubiertoPrepago).toFixed(2));
  saldo = Number.parseFloat((saldo - cubiertoPrepago).toFixed(2));
  p = Number.parseFloat((p + faltantePrepago).toFixed(2));

  await ledgerComisionBolaPuebloCf(tx, {
    uidTaxista: uid,
    bolaId: bid,
    fuente: params.fuente,
    comisionTotalRd: comision,
    pendienteAntes: pendAntes,
    saldoPrepagoAntes: saldoIni,
    pendienteDespues: p,
    saldoPrepagoDespues: saldo,
    primerEfectivoSinDescuento: false,
    existingMovSnap: movSnap,
  });
  tx.set(
    billeRef,
    {
      ...baseUpd,
      comisionPendiente: p,
      saldoPrepagoComisionRd: saldo,
      primerViajeComisionGratisConsumido: true,
    },
    { merge: true },
  );
  return {
    appliedNow: true,
    alreadyHadLedger: false,
    saldoPrepagoDespues: saldo,
    primerGratis: false,
  };
}

/** Ref ledger crédito prepago por 6.º viaje gratis negocio aliado (idempotente por viajeId). */
export function negocioAliadoViajeGratisLedgerRef(
  uidTaxista: string,
  viajeId: string,
): DocumentReference {
  const uid = uidTaxista.trim();
  const vid = viajeId.trim();
  return movColl(uid).doc(safeId(`negocio_aliado_gratis_${vid}`));
}

export async function ledgerNegocioAliadoViajeGratisCreditoCf(
  tx: Transaction,
  params: {
    uidTaxista: string;
    viajeId: string;
    fuente: string;
    creditoRd: number;
    gananciaRd: number;
    precioCobradoRd: number;
    saldoPrepagoAntes: number;
    saldoPrepagoDespues: number;
    existingMovSnap?: DocumentSnapshot;
  },
): Promise<boolean> {
  const uid = params.uidTaxista.trim();
  const vid = params.viajeId.trim();
  if (!uid || !vid) return false;

  const ref = negocioAliadoViajeGratisLedgerRef(uid, vid);
  const snap = params.existingMovSnap ?? (await tx.get(ref));
  if (snap.exists) return false;

  tx.set(ref, {
    schemaVersion: 1,
    createdAt: FieldValue.serverTimestamp(),
    tipo: "negocio_aliado_viaje_gratis_credito",
    fuente: params.fuente,
    uidTaxista: uid,
    viajeId: vid,
    creditoRd: Number(params.creditoRd.toFixed(2)),
    gananciaRd: Number(params.gananciaRd.toFixed(2)),
    precioCobradoRd: Number(params.precioCobradoRd.toFixed(2)),
    saldoPrepagoAntes: Number(params.saldoPrepagoAntes.toFixed(2)),
    saldoPrepagoDespues: Number(params.saldoPrepagoDespues.toFixed(2)),
  });
  return true;
}

export async function ledgerRecargaPrepagoVerificadaCf(
  tx: Transaction,
  params: {
    uidTaxista: string;
    recargaId: string;
    saldoPrepagoAntes: number;
    saldoPrepagoDespues: number;
    comisionPendienteAntes: number;
    comisionPendienteDespues: number;
    montoAcreditadoRd: number;
    referencia?: string;
  },
): Promise<void> {
  const uid = params.uidTaxista.trim();
  const rid = params.recargaId.trim();
  if (!uid || !rid) return;

  const ref = movColl(uid).doc(safeId(`recarga_prepago_${rid}`));
  const snap = await tx.get(ref);
  if (snap.exists) return;

  tx.set(ref, {
    schemaVersion: 1,
    createdAt: FieldValue.serverTimestamp(),
    tipo: "recarga_prepago",
    fuente: "admin_verificar_recarga_comision_cf",
    uidTaxista: uid,
    recargaId: rid,
    montoAcreditadoRd: Number(params.montoAcreditadoRd.toFixed(2)),
    saldoPrepagoAntes: Number(params.saldoPrepagoAntes.toFixed(2)),
    saldoPrepagoDespues: Number(params.saldoPrepagoDespues.toFixed(2)),
    comisionPendienteAntes: Number(params.comisionPendienteAntes.toFixed(2)),
    comisionPendienteDespues: Number(params.comisionPendienteDespues.toFixed(2)),
    ...(params.referencia && params.referencia.trim()
      ? { referencia: params.referencia.trim() }
      : {}),
  });
}
