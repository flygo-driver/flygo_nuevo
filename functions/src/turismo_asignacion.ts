/**
 * Auto-asignación turismo y liberación al pool turístico (Admin SDK).
 * Paridad con AsignacionTurismoRepo (Dart); evita permission-denied del cliente.
 */
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import type { Transaction } from "firebase-admin/firestore";

import { getComisionPrepagoConfig } from "./finance.js";
import { taxistaSinBloqueoPrepagoOperativo } from "./taxista_cola_promote_logic.js";
import {
  CANAL_TURISMO_POOL,
  type AnyMap,
  choferEstadoOperativo,
  distanciaKmHastaOrigen,
  estadoPermiteAutoAsignacionTurismo,
  estadoPermiteLiberarAlPool,
  filtrarCandidatoTurismo,
  ordenarCandidatosPorDistancia,
  pasajerosRequeridos,
  toDateFromUnknown,
  vehiculoQueCoincide,
  ventanaPublicacionYAceptacionOk,
  capacidadDesdeVehiculoMap,
} from "./turismo_asignacion_logic.js";

const db = () => getFirestore();

async function getRole(uid: string): Promise<string> {
  const snap = await db().collection("usuarios").doc(uid).get();
  const rol = snap.data()?.rol;
  return typeof rol === "string" ? rol.trim().toLowerCase() : "";
}

function assertPuedeOperarTurismoAsignacion(args: {
  uidActor: string;
  role: string;
  vData: AnyMap;
}): void {
  if (args.role === "admin") return;
  const uidCliente = String(args.vData.uidCliente ?? args.vData.clienteId ?? "").trim();
  if (uidCliente === args.uidActor) return;
  if (args.role === "taxista") return;
  throw new HttpsError(
    "permission-denied",
    "No autorizado para asignar este viaje turístico",
  );
}

async function liberarViajeAlPoolTurismoSiAplica(args: {
  viajeId: string;
  omitirVentanaPublicacion?: boolean;
}): Promise<boolean> {
  const vRef = db().collection("viajes").doc(args.viajeId);
  let liberado = false;
  await db().runTransaction(async (tx: Transaction) => {
    liberado = false;
    const snap = await tx.get(vRef);
    if (!snap.exists) return;
    const v = (snap.data() ?? {}) as AnyMap;

    if (String(v.tipoServicio ?? "").trim() !== "turismo") return;

    const uidTx = String(v.uidTaxista ?? v.taxistaId ?? "").trim();
    if (uidTx) return;

    const canal = String(v.canalAsignacion ?? "admin").trim();
    if (canal !== "admin") return;

    if (!estadoPermiteLiberarAlPool(v)) return;

    const now = new Date();
    if (!ventanaPublicacionYAceptacionOk(v, now, args.omitirVentanaPublicacion === true)) {
      return;
    }

    tx.update(vRef, {
      canalAsignacion: CANAL_TURISMO_POOL,
      liberadoPoolTurismoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    });
    liberado = true;
  });
  return liberado;
}

async function transaccionAsignarTurismoAutomatico(args: {
  viajeId: string;
  uidChofer: string;
  choferData: AnyMap;
  vehiculo: AnyMap;
  subtipoTurismo: string;
  minimoPrepagoRd: number;
}): Promise<boolean> {
  const vRef = db().collection("viajes").doc(args.viajeId);
  const cRef = db().collection("choferes_turismo").doc(args.uidChofer);
  const uRef = db().collection("usuarios").doc(args.uidChofer);

  let asignado = false;
  try {
    await db().runTransaction(async (tx: Transaction) => {
      asignado = false;
      const vSnap = await tx.get(vRef);
      if (!vSnap.exists) return;
      const d = (vSnap.data() ?? {}) as AnyMap;

      if (!estadoPermiteAutoAsignacionTurismo(d)) return;

      const now = new Date();
      if (!ventanaPublicacionYAceptacionOk(d, now, false)) return;

      const reservadoPor = String(d.reservadoPor ?? "");
      let reservadoHasta: Date | null = null;
      const rh = d.reservadoHasta;
      if (rh) reservadoHasta = toDateFromUnknown(rh);
      const reservaVigente =
        reservadoPor.length > 0 &&
        (reservadoHasta == null || reservadoHasta > now);
      if (reservaVigente && reservadoPor !== args.uidChofer) return;

      const cSnap = await tx.get(cRef);
      if (!cSnap.exists) return;
      const cLive = (cSnap.data() ?? {}) as AnyMap;
      if (!choferEstadoOperativo(cLive.estado)) return;
      if (cLive.disponible !== true) return;

      const pax = pasajerosRequeridos(d);
      const vMatch = vehiculoQueCoincide(cLive.vehiculos, args.subtipoTurismo);
      if (!vMatch) return;
      if (capacidadDesdeVehiculoMap(vMatch, args.subtipoTurismo) < pax) return;

      const uSnap = await tx.get(uRef);
      const uData = (uSnap.data() ?? {}) as AnyMap;
      if (String(uData.viajeActivoId ?? "").trim()) return;

      const bSnap = await tx.get(db().collection("billeteras_taxista").doc(args.uidChofer));
      if (!taxistaSinBloqueoPrepagoOperativo(uData, bSnap.data() as AnyMap | undefined, args.minimoPrepagoRd)) {
        return;
      }

      const nombreChofer = String(
        args.choferData.nombre ?? cLive.nombre ?? "",
      ).trim();
      const telChofer = String(
        args.choferData.telefono ?? cLive.telefono ?? "",
      ).trim();
      const placa = String(args.vehiculo.placa ?? vMatch.placa ?? "").trim();
      const marca = String(
        args.vehiculo.marca ?? uData.marca ?? uData.vehiculoMarca ?? "",
      );
      const modelo = String(
        args.vehiculo.modelo ?? uData.modelo ?? uData.vehiculoModelo ?? "",
      );
      const color = String(
        args.vehiculo.color ?? uData.color ?? uData.vehiculoColor ?? "",
      );
      const uidCliente = String(d.uidCliente ?? d.clienteId ?? "").trim();

      tx.update(vRef, {
        uidTaxista: args.uidChofer,
        taxistaId: args.uidChofer,
        nombreTaxista: nombreChofer,
        telefono: telChofer,
        telefonoTaxista: telChofer,
        placa,
        tipoVehiculo: "🏝️ TURISMO 🏝️",
        tipoVehiculoOriginal: args.subtipoTurismo,
        marca,
        modelo,
        color,
        latTaxista: 0.0,
        lonTaxista: 0.0,
        driverLat: 0.0,
        driverLon: 0.0,
        estado: "aceptado",
        aceptado: true,
        rechazado: false,
        activo: true,
        aceptadoEn: FieldValue.serverTimestamp(),
        asignacionAutomatica: true,
        asignadoPor: "auto",
        asignadoEn: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
        reservadoPor: "",
        reservadoHasta: null,
        ignoradosPor: FieldValue.delete(),
      });

      tx.update(cRef, {
        disponible: false,
        viajeActualId: args.viajeId,
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      });

      tx.set(
        uRef,
        {
          viajeActivoId: args.viajeId,
          updatedAt: FieldValue.serverTimestamp(),
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      if (uidCliente) {
        tx.set(
          db().collection("usuarios").doc(uidCliente),
          {
            viajeActivoId: args.viajeId,
            updatedAt: FieldValue.serverTimestamp(),
            actualizadoEn: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      asignado = true;
    });
  } catch {
    return false;
  }
  return asignado;
}

export async function intentarAsignacionTurismoInterno(args: {
  viajeId: string;
  radioKm?: number;
  maxCandidatos?: number;
  omitirVentanaPublicacion?: boolean;
}): Promise<{
  uidChofer: string | null;
  liberadoPool: boolean;
  canalAsignacion: string;
}> {
  const viajeId = args.viajeId.trim();
  if (!viajeId) {
    return { uidChofer: null, liberadoPool: false, canalAsignacion: "admin" };
  }

  const radioKm = typeof args.radioKm === "number" && args.radioKm > 0 ? args.radioKm : 55;
  const maxCandidatos =
    typeof args.maxCandidatos === "number" && args.maxCandidatos > 0
      ? args.maxCandidatos
      : 18;

  const vRef = db().collection("viajes").doc(viajeId);
  const vSnap = await vRef.get();
  if (!vSnap.exists) {
    return { uidChofer: null, liberadoPool: false, canalAsignacion: "admin" };
  }
  const v0 = (vSnap.data() ?? {}) as AnyMap;

  if (!estadoPermiteAutoAsignacionTurismo(v0)) {
    const canal = String(v0.canalAsignacion ?? "admin").trim();
    return { uidChofer: null, liberadoPool: false, canalAsignacion: canal };
  }

  const now = new Date();
  if (!ventanaPublicacionYAceptacionOk(v0, now, args.omitirVentanaPublicacion === true)) {
    return { uidChofer: null, liberadoPool: false, canalAsignacion: "admin" };
  }

  const rawLat = v0.latOrigen ?? v0.latCliente;
  const rawLon = v0.lonOrigen ?? v0.lonCliente;
  const latO = typeof rawLat === "number" ? rawLat : Number(rawLat);
  const lonO = typeof rawLon === "number" ? rawLon : Number(rawLon);
  if (!Number.isFinite(latO) || !Number.isFinite(lonO)) {
    const liberadoPool = await liberarViajeAlPoolTurismoSiAplica({
      viajeId,
      omitirVentanaPublicacion: args.omitirVentanaPublicacion,
    });
    const canalAfter = liberadoPool ? CANAL_TURISMO_POOL : "admin";
    return { uidChofer: null, liberadoPool, canalAsignacion: canalAfter };
  }

  const subtipo = String(v0.subtipoTurismo ?? "carro").trim() || "carro";
  const pax = pasajerosRequeridos(v0);
  const prepagoCfg = await getComisionPrepagoConfig();

  const q = await db()
    .collection("choferes_turismo")
    .where("estado", "in", ["aprobado", "activo"])
    .where("disponible", "==", true)
    .limit(40)
    .get();

  const candidatos = ordenarCandidatosPorDistancia(
    q.docs.map((doc) => ({
      id: doc.id,
      data: (doc.data() ?? {}) as AnyMap,
      distanciaKm: distanciaKmHastaOrigen(doc.data() as AnyMap, latO, lonO),
    })),
  );

  let intentos = 0;
  for (const cand of candidatos) {
    if (intentos >= maxCandidatos) break;
    const filtro = filtrarCandidatoTurismo({
      choferData: cand.data,
      subtipoTurismo: subtipo,
      pasajeros: pax,
      latO,
      lonO,
      radioKm,
    });
    if (!filtro.ok || !filtro.vehiculo) continue;

    intentos += 1;
    const ok = await transaccionAsignarTurismoAutomatico({
      viajeId,
      uidChofer: cand.id,
      choferData: cand.data,
      vehiculo: filtro.vehiculo,
      subtipoTurismo: subtipo,
      minimoPrepagoRd: prepagoCfg.minimoOperativoRd,
    });
    if (ok) {
      return {
        uidChofer: cand.id,
        liberadoPool: false,
        canalAsignacion: "admin",
      };
    }
  }

  const liberadoPool = await liberarViajeAlPoolTurismoSiAplica({
    viajeId,
    omitirVentanaPublicacion: args.omitirVentanaPublicacion,
  });
  return {
    uidChofer: null,
    liberadoPool,
    canalAsignacion: liberadoPool ? CANAL_TURISMO_POOL : "admin",
  };
}

/** Cliente / taxista / admin: auto-asignar chofer turismo aprobado o liberar al pool. */
export const intentarAsignacionTurismoSeguro = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }

  const viajeId =
    typeof request.data?.viajeId === "string" ? request.data.viajeId.trim() : "";
  if (!viajeId) {
    throw new HttpsError("invalid-argument", "Falta viajeId");
  }

  const radioKm =
    typeof request.data?.radioKm === "number" && request.data.radioKm > 0
      ? request.data.radioKm
      : 55;

  const omitirVentanaPublicacion = request.data?.omitirVentanaPublicacion === true;

  const uidActor = request.auth.uid;
  const role = await getRole(uidActor);

  const vSnap = await db().collection("viajes").doc(viajeId).get();
  if (!vSnap.exists) {
    throw new HttpsError("not-found", "Viaje no existe");
  }
  const vData = (vSnap.data() ?? {}) as AnyMap;
  if (String(vData.tipoServicio ?? "").trim() !== "turismo") {
    throw new HttpsError("failed-precondition", "no-turismo");
  }

  assertPuedeOperarTurismoAsignacion({ uidActor, role, vData });

  const result = await intentarAsignacionTurismoInterno({
    viajeId,
    radioKm,
    omitirVentanaPublicacion,
  });

  return {
    ok: true,
    uidChofer: result.uidChofer,
    liberadoPool: result.liberadoPool,
    canalAsignacion: result.canalAsignacion,
  };
});

/** Admin: liberar manualmente al pool turístico (sin ventana publish/accept). */
export const liberarViajeTurismoPoolSeguro = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const role = await getRole(request.auth.uid);
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Solo administración");
  }

  const viajeId =
    typeof request.data?.viajeId === "string" ? request.data.viajeId.trim() : "";
  if (!viajeId) {
    throw new HttpsError("invalid-argument", "Falta viajeId");
  }

  const liberadoPool = await liberarViajeAlPoolTurismoSiAplica({
    viajeId,
    omitirVentanaPublicacion: true,
  });

  return { ok: true, liberadoPool };
});

/** Turismo programado: cuando llega publishAt, auto-asignar o liberar al pool (app cerrada). */
export const scheduledTurismoProgramadoAlPool = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "America/Santo_Domingo",
    memory: "256MiB",
    timeoutSeconds: 120,
  },
  async () => {
    const now = Timestamp.now();
    let q: FirebaseFirestore.QuerySnapshot;
    try {
      q = await db()
        .collection("viajes")
        .where("tipoServicio", "==", "turismo")
        .where("programado", "==", true)
        .where("publishAt", "<=", now)
        .limit(30)
        .get();
    } catch (e) {
      logger.error("scheduledTurismoProgramadoAlPool query failed", e);
      return;
    }

    for (const doc of q.docs) {
      const d = (doc.data() ?? {}) as AnyMap;
      const uidTx = String(d.uidTaxista ?? d.taxistaId ?? "").trim();
      if (uidTx) continue;

      const canal = String(d.canalAsignacion ?? "admin").trim();
      if (canal !== "admin") continue;

      if (!estadoPermiteLiberarAlPool(d)) continue;
      if (!ventanaPublicacionYAceptacionOk(d, new Date())) continue;

      try {
        await intentarAsignacionTurismoInterno({ viajeId: doc.id });
      } catch (e) {
        logger.warn("scheduledTurismoProgramadoAlPool fallo", {
          viajeId: doc.id,
          error: String(e),
        });
      }
    }
  },
);
