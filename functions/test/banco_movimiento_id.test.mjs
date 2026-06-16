import assert from "node:assert/strict";
import test from "node:test";
import {
  extraerBancoTransaccionIdDeFila,
  movimientoBancoDocIdHash,
  resolveMovimientoBancoDocId,
  sanitizeBancoTransaccionId,
} from "../lib/banco_movimiento_id.js";

test("sanitizeBancoTransaccionId limpia caracteres inválidos", () => {
  assert.equal(sanitizeBancoTransaccionId("  TXN-123/abc  "), "TXN-123abc");
});

test("resolveMovimientoBancoDocId usa bancoTransaccionId como clave", () => {
  const r = resolveMovimientoBancoDocId({
    bancoTransaccionId: "POP-998877",
    fechaValor: new Date("2026-06-11"),
    referenciaNormalizada: "RAI-V-ABC",
    montoCents: 50000,
    tipo: "entrada",
  });
  assert.equal(r.docId, "btxn_POP-998877");
  assert.equal(r.idSource, "banco_txn");
});

test("resolveMovimientoBancoDocId cae a hash sin txn id", () => {
  const d = new Date("2026-06-11T12:00:00.000Z");
  const r = resolveMovimientoBancoDocId({
    fechaValor: d,
    referenciaNormalizada: "RAI-V-ABCD1234-7F",
    montoCents: 125000,
    tipo: "entrada",
  });
  assert.equal(r.idSource, "hash");
  assert.equal(r.docId, movimientoBancoDocIdHash({
    fechaValor: d,
    referenciaNormalizada: "RAI-V-ABCD1234-7F",
    montoCents: 125000,
    tipo: "entrada",
  }));
});

test("extraerBancoTransaccionIdDeFila lee alias comunes", () => {
  assert.equal(
    extraerBancoTransaccionIdDeFila({ transaccion_id: "ABC-001" }),
    "ABC-001",
  );
});
