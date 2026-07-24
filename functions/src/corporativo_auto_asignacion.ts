/**
 * Resolución de chofer al publicar ruta corporativa.
 * Solo conductor asignado por ADM (choferPreferidoUid / respaldo explícito).
 * Sin auto-asignación del pool: disponibilidad la valida ADM con choque de horarios.
 */
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import {
  detectarConflictosHorarioChofer,
  mensajeCompromisoChoferDesdeConflictos,
} from "./corporativo_validacion.js";

type AnyMap = Record<string, unknown>;

export type CorporativoChoferResuelto = {
  uid: string;
  nombre: string;
  telefono: string;
  /** preferido = ADM en plantilla; respaldo = choferRespaldoUid explícito */
  modo: "preferido" | "respaldo";
};

function str(v: unknown): string {
  return String(v ?? "").trim();
}

/** ¿Está en pool corporativo aprobado y activo? */
export async function choferCorporativoElegible(uid: string): Promise<{
  ok: boolean;
  nombre: string;
  telefono: string;
}> {
  const id = str(uid);
  if (!id) return { ok: false, nombre: "", telefono: "" };
  const db = getFirestore();
  const [corpSnap, uSnap] = await Promise.all([
    db.collection("choferes_corporativos").doc(id).get(),
    db.collection("usuarios").doc(id).get(),
  ]);
  const corp = (corpSnap.data() ?? {}) as AnyMap;
  const u = (uSnap.data() ?? {}) as AnyMap;
  const estado = str(corp.estado).toLowerCase();
  const ok =
    corpSnap.exists &&
    (estado === "aprobado" || estado === "activo") &&
    corp.activo !== false &&
    uSnap.exists;
  const nombre =
    str(u.nombre ?? u.displayName) ||
    str(corp.nombre) ||
    "Conductor RAI";
  const telefono = str(u.telefono ?? corp.telefono);
  return { ok, nombre, telefono };
}

async function resolverSiElegibleSinChoque(args: {
  choferUid: string;
  empresaId: string;
  plantillaId: string;
  plantilla: AnyMap;
  nombreFallback: string;
  telefonoFallback: string;
  modo: "preferido" | "respaldo";
}): Promise<CorporativoChoferResuelto | null> {
  const uid = str(args.choferUid);
  if (!uid) return null;
  const eleg = await choferCorporativoElegible(uid);
  if (!eleg.ok) return null;
  const conflictos = await detectarConflictosHorarioChofer({
    choferUid: uid,
    empresaId: args.empresaId,
    plantillaId: args.plantillaId,
    plantilla: args.plantilla,
  });
  if (conflictos.length > 0) return null;
  return {
    uid,
    nombre: eleg.nombre || args.nombreFallback || "Conductor RAI",
    telefono: eleg.telefono || args.telefonoFallback,
    modo: args.modo,
  };
}

/**
 * Resuelve chofer para publicar la ruta del día.
 * 1) choferPreferidoUid (ADM) si elegible y sin choque
 * 2) choferRespaldoUid (ADM explícito) si el preferido no sirve
 * 3) sin preferido → null (ADM debe asignar; no hay auto-pool)
 */
export async function resolverChoferPublicacionCorporativo(args: {
  empresaId: string;
  plantillaId: string;
  plantilla: AnyMap;
}): Promise<CorporativoChoferResuelto | null> {
  const preferidoUid = str(args.plantilla.choferPreferidoUid);
  if (!preferidoUid) {
    logger.info("corporativo publicar sin chofer ADM", {
      empresaId: args.empresaId,
      plantillaId: args.plantillaId,
    });
    return null;
  }

  const preferido = await resolverSiElegibleSinChoque({
    choferUid: preferidoUid,
    empresaId: args.empresaId,
    plantillaId: args.plantillaId,
    plantilla: args.plantilla,
    nombreFallback: str(args.plantilla.choferPreferidoNombre),
    telefonoFallback: str(args.plantilla.choferPreferidoTelefono),
    modo: "preferido",
  });
  if (preferido) return preferido;

  const respaldoUid = str(args.plantilla.choferRespaldoUid);
  if (respaldoUid && respaldoUid !== preferidoUid) {
    const respaldo = await resolverSiElegibleSinChoque({
      choferUid: respaldoUid,
      empresaId: args.empresaId,
      plantillaId: args.plantillaId,
      plantilla: args.plantilla,
      nombreFallback: "Conductor respaldo",
      telefonoFallback: "",
      modo: "respaldo",
    });
    if (respaldo) return respaldo;
  }

  return null;
}

/** Motivo legible cuando no se puede publicar por chofer / compromiso. */
export async function mensajeErrorPublicacionChoferCorporativo(args: {
  empresaId: string;
  plantillaId: string;
  plantilla: AnyMap;
}): Promise<string> {
  const preferidoUid = str(args.plantilla.choferPreferidoUid);
  if (!preferidoUid) {
    return (
      "RAI debe asignar un conductor a esta ruta antes de publicar. " +
      "Contactá al administrador RAI."
    );
  }
  const eleg = await choferCorporativoElegible(preferidoUid);
  const nombre =
    eleg.nombre ||
    str(args.plantilla.choferPreferidoNombre) ||
    "El conductor asignado";
  const conflictos = await detectarConflictosHorarioChofer({
    choferUid: preferidoUid,
    empresaId: args.empresaId,
    plantillaId: args.plantillaId,
    plantilla: args.plantilla,
  });
  if (conflictos.length > 0) {
    return mensajeCompromisoChoferDesdeConflictos(conflictos, nombre);
  }
  if (!eleg.ok) {
    return (
      `${nombre} no está habilitado en el pool corporativo RAI. ` +
      "El administrador debe asignar otro conductor."
    );
  }
  const respaldoUid = str(args.plantilla.choferRespaldoUid);
  if (respaldoUid && respaldoUid !== preferidoUid) {
    const conflictosResp = await detectarConflictosHorarioChofer({
      choferUid: respaldoUid,
      empresaId: args.empresaId,
      plantillaId: args.plantillaId,
      plantilla: args.plantilla,
    });
    if (conflictosResp.length > 0) {
      return (
        `${nombre} no está disponible y el conductor de respaldo también ` +
        "tiene compromiso de horario con otra empresa."
      );
    }
  }
  return (
    `${nombre} no está disponible para publicar esta ruta. ` +
    "El administrador RAI debe revisar la asignación."
  );
}

/** Ya no persiste auto-pool (solo ADM asigna). Mantenido por compat de imports. */
export async function persistirChoferPreferidoPlantilla(_args: {
  empresaId: string;
  plantillaId: string;
  chofer: CorporativoChoferResuelto;
}): Promise<void> {
  return;
}
