/**
 * Libro auxiliar paralelo a `billeteras_taxista` (Cloud Functions). No cambia saldos ni bloqueos.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import type { Transaction } from "firebase-admin/firestore";

const db = () => getFirestore();

function safeId(raw: string): string {
  return raw.trim().replace(/\//g, "_");
}

function movColl(uid: string) {
  return db().collection("billeteras_taxista").doc(uid).collection("movimientos_prepago");
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
  },
): Promise<void> {
  const uid = params.uidTaxista.trim();
  const vid = params.viajeId.trim();
  if (!uid || !vid) return;

  const ref = movColl(uid).doc(safeId(`comision_viaje_${vid}`));
  const snap = await tx.get(ref);
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
  },
): Promise<void> {
  const uid = params.uidTaxista.trim();
  const bid = params.bolaId.trim();
  if (!uid || !bid) return;

  const ref = movColl(uid).doc(safeId(`comision_bola_${bid}`));
  const snap = await tx.get(ref);
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
