// Promo negocio aliado (QR): 5 viajes pagados → el 6.º gratis.
// RAI repone el gratis acreditando recargas al taxista, así que la elegibilidad
// debe salir del contador del perfil (backend) y nunca de lo que escriba la app.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

import {
  NEGOCIO_ALIADO_GRATIS_RECHAZO,
  NEGOCIO_ALIADO_PCT_TAXISTA,
  NEGOCIO_ALIADO_PROMO_M_DEFAULT,
  contadorPromoTrasCierreNegocioAliado,
  creditoViajeGratisNegocioAliadoCents,
  elegibilidadViajeGratisNegocioAliado,
} from "../lib/negocio_aliado_viaje.js";
import { viajeEsLocalEnPuebloNegocio } from "../lib/negocio_aliado_promo.js";
import { comisionCentsDesdePrecioCents } from "../lib/comision_viaje_pct.js";

const aquí = path.dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(path.join(aquí, "..", "..", "firestore.rules"), "utf8");

const CODIGO = "LA-CENA-SDN";

function clientePromo(over = {}) {
  return {
    negocioReferidoCodigo: CODIGO,
    negocioReferidoAt: new Date("2026-06-01T00:00:00Z"),
    negocioPromoVenceAt: new Date(Date.now() + 30 * 24 * 3600 * 1000),
    negocioPromoMxKM: 5,
    negocioPromoMxKK: 1,
    negocioPromoContador: 5,
    ...over,
  };
}

const viajeGratis = { negocioAliadoCodigo: CODIGO, negocioAliadoPromoGratis: true };

test("con 5 viajes pagados el 6.º es elegible", () => {
  const r = elegibilidadViajeGratisNegocioAliado({
    viajeData: viajeGratis,
    clienteData: clientePromo(),
  });
  assert.equal(r.elegible, true);
  assert.equal(r.motivo, null);
  assert.equal(r.contador, 5);
  assert.equal(r.m, 5);
});

test("app que marca gratis sin haberlo ganado no cobra el crédito", () => {
  for (const contador of [0, 1, 4]) {
    const r = elegibilidadViajeGratisNegocioAliado({
      viajeData: viajeGratis,
      clienteData: clientePromo({ negocioPromoContador: contador }),
    });
    assert.equal(r.elegible, false, `contador ${contador} no debe ser elegible`);
    assert.equal(r.motivo, NEGOCIO_ALIADO_GRATIS_RECHAZO.contadorInsuficiente);
  }
});

test("no se puede cobrar el gratis con el código de otro negocio", () => {
  const r = elegibilidadViajeGratisNegocioAliado({
    viajeData: { negocioAliadoCodigo: "OTRO-NEGOCIO", negocioAliadoPromoGratis: true },
    clienteData: clientePromo(),
  });
  assert.equal(r.elegible, false);
  assert.equal(r.motivo, NEGOCIO_ALIADO_GRATIS_RECHAZO.codigoDistinto);
});

test("promo vencida o sin registro QR no da gratis", () => {
  const vencida = elegibilidadViajeGratisNegocioAliado({
    viajeData: viajeGratis,
    clienteData: clientePromo({
      negocioPromoVenceAt: new Date(Date.now() - 1000),
    }),
  });
  assert.equal(vencida.elegible, false);
  assert.equal(vencida.motivo, NEGOCIO_ALIADO_GRATIS_RECHAZO.sinPromoVigente);

  const sinRegistro = elegibilidadViajeGratisNegocioAliado({
    viajeData: viajeGratis,
    clienteData: clientePromo({ negocioReferidoAt: null }),
  });
  assert.equal(sinRegistro.elegible, false);
  assert.equal(sinRegistro.motivo, NEGOCIO_ALIADO_GRATIS_RECHAZO.sinPromoVigente);
});

test("si el perfil no trae meta se exigen 5 viajes", () => {
  const r = elegibilidadViajeGratisNegocioAliado({
    viajeData: viajeGratis,
    clienteData: clientePromo({ negocioPromoMxKM: undefined, negocioPromoContador: 4 }),
  });
  assert.equal(r.m, NEGOCIO_ALIADO_PROMO_M_DEFAULT);
  assert.equal(r.elegible, false);
});

test("contador: suma al pagar, reinicia al usar el gratis y conserva el premio fuera del pueblo", () => {
  assert.equal(
    contadorPromoTrasCierreNegocioAliado({ contadorActual: 0, m: 5, esGratis: false }),
    1,
  );
  assert.equal(
    contadorPromoTrasCierreNegocioAliado({ contadorActual: 4, m: 5, esGratis: false }),
    5,
  );
  // Ya ganó el gratis pero viajó fuera del pueblo: paga completo y no pierde el premio.
  assert.equal(
    contadorPromoTrasCierreNegocioAliado({ contadorActual: 5, m: 5, esGratis: false }),
    5,
  );
  assert.equal(
    contadorPromoTrasCierreNegocioAliado({ contadorActual: 5, m: 5, esGratis: true }),
    0,
  );
});

// El taxista no debe salir perdiendo por hacer el viaje gratis. Clave: en el gratis
// la comisión NO se debita del prepago, así que la reposición es la ganancia neta
// (tarifa menos comisión). Reponer la tarifa completa le regalaría la comisión.
function gananciaCents(nominalCents) {
  const comision = comisionCentsDesdePrecioCents(nominalCents, NEGOCIO_ALIADO_PCT_TAXISTA);
  return Math.max(0, nominalCents - comision);
}

/** Viaje pagado: cobra la tarifa en mano y el prepago le debita la comisión. */
function netoViajeCobradoCents(nominalCents) {
  return nominalCents - comisionCentsDesdePrecioCents(nominalCents, NEGOCIO_ALIADO_PCT_TAXISTA);
}

/** Viaje gratis: lo poco que haya cobrado más lo que RAI le repone, sin débito. */
function netoViajeGratisCents({ nominalCents, cobradoCents }) {
  return (
    cobradoCents +
    creditoViajeGratisNegocioAliadoCents({
      gananciaCents: gananciaCents(nominalCents),
      precioCents: cobradoCents,
    })
  );
}

test("el viaje gratis le deja al taxista lo mismo que uno cobrado", () => {
  const nominalCents = 50000; // RD$500
  assert.equal(comisionCentsDesdePrecioCents(nominalCents, NEGOCIO_ALIADO_PCT_TAXISTA), 7500);

  const netoCobrado = netoViajeCobradoCents(nominalCents);
  const netoGratis = netoViajeGratisCents({ nominalCents, cobradoCents: 0 });

  assert.equal(netoGratis, netoCobrado, "gratis y cobrado deben dejar el mismo neto");
  assert.equal(netoGratis, 42500, "RD$425 sobre RD$500 al 15%");
});

test("la reposición nunca incluye la comisión del viaje", () => {
  const nominalCents = 50000;
  const credito = creditoViajeGratisNegocioAliadoCents({
    gananciaCents: gananciaCents(nominalCents),
    precioCents: 0,
  });
  assert.equal(credito, 42500, "se repone la ganancia, no la tarifa");
  assert.notEqual(credito, nominalCents, "reponer la tarifa completa regala la comisión");
});

test("si la tarifa pasa el tope solo se repone lo que faltó", () => {
  // Nominal RD$800 con tope de descuento RD$600: el pasajero paga RD$200.
  const nominalCents = 80000;
  const cobradoCents = 20000;
  const credito = creditoViajeGratisNegocioAliadoCents({
    gananciaCents: gananciaCents(nominalCents),
    precioCents: cobradoCents,
  });
  assert.equal(credito, 48000, "ganancia RD$680 menos los RD$200 que sí cobró");
  assert.equal(
    netoViajeGratisCents({ nominalCents, cobradoCents }),
    netoViajeCobradoCents(nominalCents),
  );
});

test("nunca se acredita de más ni en negativo", () => {
  assert.equal(
    creditoViajeGratisNegocioAliadoCents({ gananciaCents: 10000, precioCents: 15000 }),
    0,
    "si cobró más que su ganancia no hay reposición",
  );
  assert.equal(creditoViajeGratisNegocioAliadoCents({ gananciaCents: 0, precioCents: 0 }), 0);
  assert.equal(
    creditoViajeGratisNegocioAliadoCents({ gananciaCents: 30000, precioCents: -5 }),
    30000,
  );
});

test("viaje local acepta variantes de ciudad del negocio", () => {
  assert.equal(
    viajeEsLocalEnPuebloNegocio({
      ciudadNegocio: "Higüey, La Altagracia",
      origen: "Centro, Higuey",
      destino: "Terminal, Higüey",
    }),
    true,
  );
  assert.equal(
    viajeEsLocalEnPuebloNegocio({
      ciudadNegocio: "Bonao",
      origen: "Bonao centro",
      destino: "Santiago",
    }),
    false,
  );
});

test("las reglas exigen que el perfil respalde el viaje marcado gratis", () => {
  assert.ok(
    rules.includes("viajeCreateNegocioAliadoOk()"),
    "el create de viajes debe validar la promo del QR",
  );
  const helper = rules.slice(rules.indexOf("function negocioAliadoViajePerfilRespalda"));
  assert.ok(
    helper.includes("u.negocioPromoContador >= u.negocioPromoMxKM"),
    "el gratis exige contador del perfil >= meta",
  );
  assert.ok(
    helper.includes("u.negocioReferidoCodigo == d.negocioAliadoCodigo"),
    "el viaje solo puede usar el código del propio perfil",
  );
  assert.ok(
    helper.includes("u.negocioPromoVenceAt > request.time"),
    "el gratis exige promo vigente",
  );
});
