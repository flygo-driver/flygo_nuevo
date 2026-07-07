import test from "node:test";
import assert from "node:assert/strict";

/** Réplica de cierreRecaudoCentralDesdePool para tests unitarios. */
function cierreRecaudoCentralDesdePool(pool) {
  const numOr0 = (v) => {
    const n = Number(v);
    return Number.isFinite(n) ? n : 0;
  };
  const round2 = (v) => Math.round(Math.max(0, v) * 100) / 100;
  const bruto = Math.max(0, numOr0(pool.montoRecaudadoRaiRd));
  const comisionVentas = Math.max(0, numOr0(pool.montoComisionRaiRd));
  const prepagoRaw = Math.max(
    0,
    numOr0(pool.comisionGiraRealRd) ||
      numOr0(pool.montoComisionCobradaPrepago) ||
      numOr0(pool.prepagoComisionAplicadaRd),
  );
  const prepagoAplicado = round2(Math.min(prepagoRaw, comisionVentas));
  const comisionRetenidaRecaudo = round2(Math.max(0, comisionVentas - prepagoAplicado));
  const netoOrganizadorFinal = round2(Math.max(0, bruto - comisionRetenidaRecaudo));
  return {
    brutoRecaudadoRd: round2(bruto),
    comisionVentasRd: round2(comisionVentas),
    prepagoAplicadoRd: prepagoAplicado,
    comisionRetenidaRecaudoRd: comisionRetenidaRecaudo,
    netoOrganizadorFinalRd: netoOrganizadorFinal,
  };
}

test("10 asientos × 1000, prepago 200 → retener 800, pagar 9200", () => {
  const c = cierreRecaudoCentralDesdePool({
    montoRecaudadoRaiRd: 10000,
    montoComisionRaiRd: 1000,
    prepagoComisionAplicadaRd: 200,
  });
  assert.equal(c.comisionVentasRd, 1000);
  assert.equal(c.prepagoAplicadoRd, 200);
  assert.equal(c.comisionRetenidaRecaudoRd, 800);
  assert.equal(c.netoOrganizadorFinalRd, 9200);
});

test("prepago no supera comisión ventas", () => {
  const c = cierreRecaudoCentralDesdePool({
    montoRecaudadoRaiRd: 500,
    montoComisionRaiRd: 50,
    comisionGiraRealRd: 200,
  });
  assert.equal(c.prepagoAplicadoRd, 50);
  assert.equal(c.comisionRetenidaRecaudoRd, 0);
  assert.equal(c.netoOrganizadorFinalRd, 500);
});
