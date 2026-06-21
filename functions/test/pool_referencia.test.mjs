import assert from "node:assert/strict";
import test from "node:test";

import {
  esReferenciaRecaudoPoolValida,
  generarReferenciaRecaudoPool,
} from "../lib/pool_referencia.js";

test("generarReferenciaRecaudoPool formato estable", () => {
  const ref = generarReferenciaRecaudoPool("pool123abc", "res456def");
  assert.match(ref, /^RAI-P-[A-Z0-9]{1,8}-[A-Z0-9]{1,8}-[0-9A-F]{2}$/);
  assert.equal(ref, generarReferenciaRecaudoPool("pool123abc", "res456def"));
  assert.ok(esReferenciaRecaudoPoolValida(ref));
});

test("generarReferenciaRecaudoPool distintas reservas", () => {
  const a = generarReferenciaRecaudoPool("samePool", "resA");
  const b = generarReferenciaRecaudoPool("samePool", "resB");
  assert.notEqual(a, b);
});
