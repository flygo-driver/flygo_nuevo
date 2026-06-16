import assert from "node:assert/strict";
import test from "node:test";
import {
  movimientoBancoDocId,
  normalizarReferenciaExtracto,
  montoCentsDesdeExtracto,
  parseCsvExtractoPopular,
  resolveMovimientoBancoDocId,
} from "../lib/banco_movimientos.js";

test("normalizarReferenciaExtracto extrae RAI-V embebido", () => {
  const ref = normalizarReferenciaExtracto("Pago servicio RAI-V-ABC12345-7F ref");
  assert.equal(ref, "RAI-V-ABC12345-7F");
});

test("montoCentsDesdeExtracto parsea RD", () => {
  assert.equal(montoCentsDesdeExtracto("1,250.50"), 125050);
  assert.equal(montoCentsDesdeExtracto(500), 50000);
});

test("movimientoBancoDocId es estable", () => {
  const d = new Date("2026-06-11T12:00:00.000Z");
  const a = movimientoBancoDocId({
    fechaValor: d,
    referenciaNormalizada: "RAI-V-ABCD1234-7F",
    montoCents: 125000,
    tipo: "entrada",
  });
  const b = movimientoBancoDocId({
    fechaValor: d,
    referenciaNormalizada: "RAI-V-ABCD1234-7F",
    montoCents: 125000,
    tipo: "entrada",
  });
  assert.equal(a, b);
  assert.match(a, /^pop_[a-f0-9]{24}$/);
});

test("resolveMovimientoBancoDocId prioriza bancoTransaccionId", () => {
  const r = resolveMovimientoBancoDocId({
    bancoTransaccionId: "TXN-001",
    fechaValor: new Date("2026-06-11"),
    referenciaNormalizada: "RAI-V-X",
    montoCents: 100,
    tipo: "entrada",
  });
  assert.equal(r.docId, "btxn_TXN-001");
});

test("parseCsvExtractoPopular lee encabezados", () => {
  const csv = "fecha,monto,referencia,descripcion\n11/06/2026,500.00,RAI-V-TEST1234-A1,Pago viaje";
  const filas = parseCsvExtractoPopular(csv);
  assert.equal(filas.length, 1);
  assert.equal(String(filas[0].referencia), "RAI-V-TEST1234-A1");
  assert.equal(montoCentsDesdeExtracto(filas[0].monto), 50000);
});
