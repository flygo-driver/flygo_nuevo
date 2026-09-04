// El cliente cambia entre efectivo y transferencia durante el viaje. Si el
// servidor rechaza un estado que la app sí muestra, la elección "vuelve atrás"
// sola en pantalla: por eso el gate de estados tiene que ser el mismo.
import test from "node:test";
import assert from "node:assert/strict";

import {
  estadoPermiteCambioMetodoPago,
  normalizeEstadoViajeDoc,
} from "../lib/viaje_metodo_pago.js";

test("acepta los estados activos que la app ofrece", () => {
  for (const estado of [
    "aceptado",
    "asignado",
    "en_camino_pickup",
    "en camino",
    "a_bordo",
    "abordo",
    "en_curso",
    "encurso",
  ]) {
    const norm = normalizeEstadoViajeDoc(estado);
    assert.ok(
      estadoPermiteCambioMetodoPago(norm, false),
      `${estado} debería permitir cambiar el pago`,
    );
  }
});

test("viaje asignado por administración (pendiente_admin + aceptado) también", () => {
  const norm = normalizeEstadoViajeDoc("pendiente_admin");
  assert.equal(estadoPermiteCambioMetodoPago(norm, false, false), false);
  assert.equal(estadoPermiteCambioMetodoPago(norm, false, true), true);
});

test("viaje cerrado o cancelado no cambia de método", () => {
  for (const estado of ["completado", "finalizado", "cancelado", "rechazado"]) {
    assert.equal(
      estadoPermiteCambioMetodoPago(normalizeEstadoViajeDoc(estado), false, true),
      false,
      `${estado} no debería permitir cambios`,
    );
  }
  assert.equal(estadoPermiteCambioMetodoPago("en_curso", true, true), false);
});
