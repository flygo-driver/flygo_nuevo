import test from "node:test";
import assert from "node:assert/strict";
import {
  CANAL_TURISMO_POOL,
  choferEstadoOperativo,
  estadoPermiteAutoAsignacionTurismo,
  estadoPermiteLiberarAlPool,
  filtrarCandidatoTurismo,
  pasajerosRequeridos,
  subtipoTurismoRequeridoDesdeViaje,
  ventanaPublicacionYAceptacionOk,
} from "../lib/turismo_asignacion_logic.js";

test("choferEstadoOperativo: aprobado y activo", () => {
  assert.equal(choferEstadoOperativo("aprobado"), true);
  assert.equal(choferEstadoOperativo("activo"), true);
  assert.equal(choferEstadoOperativo("pendiente"), false);
});

test("estadoPermiteAutoAsignacionTurismo: admin sin chofer", () => {
  assert.equal(
    estadoPermiteAutoAsignacionTurismo({
      tipoServicio: "turismo",
      canalAsignacion: "admin",
      estado: "pendiente_admin",
      uidTaxista: "",
    }),
    true,
  );
  assert.equal(
    estadoPermiteAutoAsignacionTurismo({
      tipoServicio: "turismo",
      canalAsignacion: CANAL_TURISMO_POOL,
      estado: "pendiente_admin",
      uidTaxista: "",
    }),
    false,
  );
});

test("estadoPermiteLiberarAlPool: pendiente_admin ok", () => {
  assert.equal(
    estadoPermiteLiberarAlPool({ estado: "pendiente_admin" }),
    true,
  );
});

test("ventanaPublicacionYAceptacionOk: acceptAfter futuro bloquea", () => {
  const future = new Date(Date.now() + 60_000);
  assert.equal(
    ventanaPublicacionYAceptacionOk({ acceptAfter: future }, new Date(), false),
    false,
  );
  assert.equal(
    ventanaPublicacionYAceptacionOk({ acceptAfter: future }, new Date(), true),
    true,
  );
});

test("pasajerosRequeridos desde extras", () => {
  assert.equal(
    pasajerosRequeridos({ extras: { pasajeros: 5 } }),
    5,
  );
  assert.equal(pasajerosRequeridos({}), 1);
});

test("filtrarCandidatoTurismo: vehículo y capacidad", () => {
  const chofer = {
    estado: "aprobado",
    disponible: true,
    vehiculos: [{ tipo: "carro", placa: "ABC123", capacidad: 4 }],
    ultimaUbicacion: { latitude: 18.5, longitude: -69.9 },
  };
  const ok = filtrarCandidatoTurismo({
    choferData: chofer,
    subtipoTurismo: "carro",
    pasajeros: 2,
    latO: 18.4861,
    lonO: -69.9312,
    radioKm: 55,
  });
  assert.equal(ok.ok, true);
});

test("filtrarCandidatoTurismo: subtipo catalogo CIUDAD -> carro", () => {
  const chofer = {
    estado: "aprobado",
    disponible: true,
    vehiculos: [{ tipo: "carro", placa: "ABC123", capacidad: 4 }],
    ultimaUbicacion: { latitude: 18.5, longitude: -69.9 },
  };
  const ok = filtrarCandidatoTurismo({
    choferData: chofer,
    subtipoTurismo: "CIUDAD",
    pasajeros: 2,
    latO: 18.4861,
    lonO: -69.9312,
    radioKm: 55,
  });
  assert.equal(ok.ok, true);
});

test("subtipoTurismoRequeridoDesdeViaje: PLAYA + Carro Turismo -> carro", () => {
  assert.equal(
    subtipoTurismoRequeridoDesdeViaje({
      subtipoTurismo: "PLAYA",
      tipoVehiculo: "🏝️ TURISMO 🏝️",
      tipoVehiculoOriginal: "Carro Turismo",
    }),
    "carro",
  );
});

test("subtipoTurismoRequeridoDesdeViaje: codigo vehiculo en subtipoTurismo", () => {
  assert.equal(
    subtipoTurismoRequeridoDesdeViaje({
      subtipoTurismo: "jeepeta",
      tipoVehiculoOriginal: "Carro Turismo",
    }),
    "jeepeta",
  );
});
