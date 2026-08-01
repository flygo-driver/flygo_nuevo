/**
 * Acreditación prepago taxista — compartida entre admin (transferencia) y AZUL (tarjeta).
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import type { DocumentReference, Transaction } from "firebase-admin/firestore";

import { ledgerRecargaPrepagoVerificadaCf } from "./taxista_prepago_ledger.js";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();

export type AcreditarRecargaPrepagoInput = {
  recargaId: string;
  actorUid: string;
  notaAdmin?: string;
  estadosPermitidos: string[];
  metodoVerificacion: "admin" | "azul_tarjeta";
  pagoAzulId?: string;
  azulOrderId?: string;
};

export type AcreditarRecargaPrepagoResult = {
  uidTaxista: string;
  yaEstabaPagada: boolean;
  montoAcreditado: number;
  abonoComisionLegacyRd: number;
  saldoPrepagoIncrementoRd: number;
};

function parseMontoRecargaRd(m: AnyMap): number {
  const montoRaw = m.montoDeclaradoRd;
  let monto = typeof montoRaw === "number" ? montoRaw : Number(montoRaw ?? 0);
  if (!Number.isFinite(monto) || monto <= 0) {
    const altRaw = m.montoElegidoRd;
    const alt = typeof altRaw === "number" ? altRaw : Number(altRaw ?? 0);
    if (Number.isFinite(alt) && alt > 0) monto = alt;
  }
  return monto;
}

/** Acredita billetera y marca recarga pagada (idempotente si ya pagado). */
export async function acreditarRecargaPrepagoEnTx(
  tx: Transaction,
  input: AcreditarRecargaPrepagoInput,
): Promise<AcreditarRecargaPrepagoResult> {
  const recRef = db().collection("recargas_comision_taxista").doc(input.recargaId);
  const recSnap = await tx.get(recRef);
  if (!recSnap.exists) {
    throw new Error("Recarga no encontrada");
  }
  const m = (recSnap.data() ?? {}) as AnyMap;
  const estado = String(m.estado ?? "").trim().toLowerCase();
  const uidTaxista = String(m.uidTaxista ?? "").trim();
  if (!uidTaxista) throw new Error("Recarga sin taxista");

  if (estado === "pagado") {
    return {
      uidTaxista,
      yaEstabaPagada: true,
      montoAcreditado: 0,
      abonoComisionLegacyRd: 0,
      saldoPrepagoIncrementoRd: 0,
    };
  }

  const permitidos = input.estadosPermitidos.map((e) => e.trim().toLowerCase());
  if (!permitidos.includes(estado)) {
    throw new Error(`Recarga en estado no acreditable: ${estado}`);
  }

  const montoAcreditado = parseMontoRecargaRd(m);
  if (!Number.isFinite(montoAcreditado) || montoAcreditado <= 0) {
    throw new Error("Monto inválido en recarga");
  }

  const bRef = db().collection("billeteras_taxista").doc(uidTaxista);
  const bSnap = await tx.get(bRef);
  const bData = (bSnap.data() ?? {}) as AnyMap;
  const saldoAntes = Number(bData.saldoPrepagoComisionRd ?? 0) || 0;
  const pendAntes = Number(bData.comisionPendiente ?? 0) || 0;

  const abonoLegacy = Math.min(Math.max(0, montoAcreditado), Math.max(0, pendAntes));
  const restoPrepago = Math.max(0, Number((montoAcreditado - abonoLegacy).toFixed(2)));
  const pendDespues = Math.max(0, Number((pendAntes - abonoLegacy).toFixed(2)));
  const saldoDespues = Number((saldoAntes + restoPrepago).toFixed(2));

  await ledgerRecargaPrepagoVerificadaCf(tx, {
    uidTaxista,
    recargaId: input.recargaId,
    saldoPrepagoAntes: saldoAntes,
    saldoPrepagoDespues: saldoDespues,
    comisionPendienteAntes: pendAntes,
    comisionPendienteDespues: pendDespues,
    montoAcreditadoRd: montoAcreditado,
    referencia:
      input.metodoVerificacion === "azul_tarjeta"
        ? `azul_recarga:${input.recargaId}`
        : `recarga:${input.recargaId}`,
  });

  const billePatch: Record<string, unknown> = {
    saldoPrepagoComisionRd: saldoDespues,
    comisionPendiente: pendDespues,
    ultimaRecargaPrepagoComisionEn: FieldValue.serverTimestamp(),
    ultimaRecargaPrepagoComisionMonto: Number(montoAcreditado.toFixed(2)),
    ultimaRecargaPrepagoComisionRef:
      input.metodoVerificacion === "azul_tarjeta"
        ? `azul_recarga:${input.recargaId}`
        : `recarga:${input.recargaId}`,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (abonoLegacy + 1e-9 > 0) {
    billePatch.ultimaRecargaAbonoLegacyRd = Number(abonoLegacy.toFixed(2));
    billePatch.ultimaRecargaAbonoLegacyEn = FieldValue.serverTimestamp();
  }

  tx.set(bRef, billePatch, { merge: true });

  const recPatch: AnyMap = {
    estado: "pagado",
    metodoPago: input.metodoVerificacion === "azul_tarjeta" ? "tarjeta" : String(m.metodoPago ?? "transferencia"),
    verificadoEn: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    verificadoPor: input.actorUid,
    metodoVerificacion: input.metodoVerificacion,
  };
  if (input.notaAdmin) recPatch.notaAdmin = input.notaAdmin;
  if (input.pagoAzulId) recPatch.pagoAzulId = input.pagoAzulId;
  if (input.azulOrderId) recPatch.azulOrderId = input.azulOrderId;

  tx.update(recRef, recPatch);

  return {
    uidTaxista,
    yaEstabaPagada: false,
    montoAcreditado,
    abonoComisionLegacyRd: abonoLegacy,
    saldoPrepagoIncrementoRd: restoPrepago,
  };
}

export function recargaRefById(recargaId: string): DocumentReference {
  return db().collection("recargas_comision_taxista").doc(recargaId);
}
