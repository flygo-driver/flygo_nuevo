/**
 * Idempotencia movimientos_banco — bancoTransaccionId como clave preferida.
 */
import { createHash } from "node:crypto";

/** Sanitiza ID de transacción del banco para usarlo como doc id. */
export function sanitizeBancoTransaccionId(raw: unknown): string {
  const s = String(raw ?? "").trim();
  if (!s) return "";
  return s.replace(/[^a-zA-Z0-9._-]/g, "").slice(0, 120);
}

/** ID hash legacy (re-import CSV sin txn id del banco). */
export function movimientoBancoDocIdHash(input: {
  fechaValor: Date;
  referenciaNormalizada: string;
  montoCents: number;
  tipo: string;
}): string {
  const day = input.fechaValor.toISOString().slice(0, 10);
  const ref = input.referenciaNormalizada || "SINREF";
  const payload = `${day}|${input.tipo}|${ref}|${input.montoCents}`;
  const hash = createHash("sha256").update(payload).digest("hex").slice(0, 24);
  return `pop_${hash}`;
}

/** Resuelve doc id: bancoTransaccionId > hash extracto. */
export function resolveMovimientoBancoDocId(input: {
  bancoTransaccionId?: unknown;
  fechaValor: Date;
  referenciaNormalizada: string;
  montoCents: number;
  tipo: string;
}): { docId: string; bancoTransaccionId: string; idSource: "banco_txn" | "hash" } {
  const txn = sanitizeBancoTransaccionId(input.bancoTransaccionId);
  if (txn) {
    return { docId: `btxn_${txn}`, bancoTransaccionId: txn, idSource: "banco_txn" };
  }
  return {
    docId: movimientoBancoDocIdHash(input),
    bancoTransaccionId: "",
    idSource: "hash",
  };
}

export function extraerBancoTransaccionIdDeFila(row: Record<string, unknown>): string {
  const pick = (...keys: string[]) => {
    for (const k of keys) {
      if (row[k] !== undefined && row[k] !== null && String(row[k]).trim() !== "") {
        return row[k];
      }
    }
    return undefined;
  };
  return sanitizeBancoTransaccionId(
    pick(
      "bancoTransaccionId",
      "bancotransaccionid",
      "transaccionId",
      "transaccion_id",
      "idTransaccion",
      "txnId",
      "txn_id",
      "id_movimiento",
      "numeroReferencia",
      "referenciaUnica",
    ),
  );
}
