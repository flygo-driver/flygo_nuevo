import test from "node:test";
import assert from "node:assert/strict";
import {
  bloqueoOperativoPorComisionEfectivo,
  sortColaCandidates,
  taxistaSinBloqueoPrepagoOperativo,
  UMBRAL_COMISION_LEGACY_RD,
} from "../lib/taxista_cola_promote_logic.js";

test("sortColaCandidates: slot 0 antes que slot 1", () => {
  const a = { id: "late", slot: 1, createdAtMs: 0 };
  const b = { id: "early", slot: 0, createdAtMs: 9_999_999 };
  assert.deepEqual([a, b].sort(sortColaCandidates), [b, a]);
});

test("sortColaCandidates: mismo slot ordena por createdAtMs", () => {
  const a = { id: "second", slot: 0, createdAtMs: 200 };
  const b = { id: "first", slot: 0, createdAtMs: 100 };
  assert.deepEqual([a, b].sort(sortColaCandidates), [b, a]);
});

test("taxistaSinBloqueoPrepagoOperativo: tienePagoPendiente bloquea", () => {
  assert.equal(
    taxistaSinBloqueoPrepagoOperativo({ tienePagoPendiente: true }, {}),
    false,
  );
});

test("bloqueoOperativoPorComisionEfectivo: comisión legacy >= umbral", () => {
  assert.equal(
    bloqueoOperativoPorComisionEfectivo({
      comisionPendiente: UMBRAL_COMISION_LEGACY_RD,
    }),
    true,
  );
});

test("taxistaSinBloqueoPrepagoOperativo: libre con billetera vacía", () => {
  assert.equal(taxistaSinBloqueoPrepagoOperativo({}, undefined), true);
});
