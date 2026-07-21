/**
 * Abordaje por pasajero y notificaciones de destino / viaje completado.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import {
  enviarPushUid,
  registrarHistorialNotificacionCorp,
} from "./corporativo_notificaciones.js";

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function esCorporativo(d: AnyMap): boolean {
  return (
    d.corporativo === true ||
    str(d.categoria).toLowerCase() === "corporativo" ||
    str(d.canalAsignacion) === "corporativo_fijo"
  );
}

function pasajerosRaw(d: AnyMap): AnyMap[] {
  const raw = d.corporativoPasajeros ?? d.pasajeros;
  if (!Array.isArray(raw)) return [];
  return raw.filter((p): p is AnyMap => typeof p === "object" && p !== null);
}

function encargadoUids(ed: AnyMap): string[] {
  const raw = ed.encargadoUids;
  if (!Array.isArray(raw)) return [];
  return raw.map(str).filter(Boolean);
}

async function notificarEncargados(args: {
  empresaId: string;
  viajeId: string;
  plantillaId?: string;
  tipo: string;
  titulo: string;
  cuerpo: string;
}): Promise<void> {
  const empSnap = await getFirestore()
    .collection("empresas_corporativas")
    .doc(args.empresaId)
    .get();
  if (!empSnap.exists) return;
  const ed = empSnap.data() as AnyMap;
  for (const uid of encargadoUids(ed)) {
    const ok = await enviarPushUid(uid, args.titulo, args.cuerpo, {
      type: args.tipo,
      empresaId: args.empresaId,
      viajeId: args.viajeId,
      plantillaId: args.plantillaId ?? "",
      rol: "encargado",
    });
    await registrarHistorialNotificacionCorp({
      empresaId: args.empresaId,
      plantillaId: args.plantillaId,
      viajeId: args.viajeId,
      uidDestino: uid,
      canal: "fcm",
      tipo: args.tipo,
      titulo: args.titulo,
      cuerpo: args.cuerpo,
      enviado: ok,
    });
  }
}

/** Chofer confirma que un pasajero abordó el vehículo. */
export const choferConfirmarAbordajePasajeroCorp = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const uid = request.auth.uid;
  const viajeId = str(request.data?.viajeId);
  const pasajeroId = str(request.data?.pasajeroId);
  if (!viajeId || !pasajeroId) {
    throw new HttpsError("invalid-argument", "Faltan viajeId o pasajeroId");
  }

  const db = getFirestore();
  const viajeRef = db.collection("viajes").doc(viajeId);

  const nombrePasajero = await db.runTransaction(async (tx) => {
    const snap = await tx.get(viajeRef);
    if (!snap.exists) throw new HttpsError("not-found", "Viaje no encontrado");
    const d = snap.data() as AnyMap;
    if (!esCorporativo(d)) {
      throw new HttpsError("failed-precondition", "No es un viaje corporativo");
    }
    const uidTx = str(d.uidTaxista ?? d.taxistaId);
    if (uidTx !== uid) {
      throw new HttpsError("permission-denied", "No eres el chofer del viaje");
    }

    const lista = pasajerosRaw(d);
    let nombre = "Pasajero";
    let encontrado = false;
    const actualizada = lista.map((p) => {
      if (str(p.id) !== pasajeroId) return p;
      encontrado = true;
      nombre = str(p.nombre) || nombre;
      return {
        ...p,
        abordado: true,
        abordadoEn: new Date().toISOString(),
        abordadoPor: uid,
      };
    });
    if (!encontrado) {
      throw new HttpsError("not-found", "Pasajero no encontrado en la ruta");
    }

    tx.update(viajeRef, {
      corporativoPasajeros: actualizada,
      actualizadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return nombre;
  });

  const viajeSnap = await viajeRef.get();
  const vd = (viajeSnap.data() ?? {}) as AnyMap;
  const empresaId = str(vd.corporativoEmpresaId);
  if (empresaId) {
    await notificarEncargados({
      empresaId,
      viajeId,
      plantillaId: str(vd.corporativoPlantillaId),
      tipo: "abordaje_pasajero",
      titulo: "Pasajero abordó",
      cuerpo: `${nombrePasajero} confirmó abordo en el vehículo.`,
    });
  }

  return { ok: true, viajeId, pasajeroId, nombre: nombrePasajero };
});

/** Tras registrar parada multiparada: notifica destino alcanzado. */
export async function notificarDestinoPasajeroCorporativo(args: {
  viajeId: string;
  legIndex: number;
  legLabel: string;
}): Promise<void> {
  const snap = await getFirestore().collection("viajes").doc(args.viajeId).get();
  if (!snap.exists) return;
  const d = snap.data() as AnyMap;
  if (!esCorporativo(d)) return;

  const empresaId = str(d.corporativoEmpresaId);
  if (!empresaId) return;

  const lista = pasajerosRaw(d);
  const pasajero = lista[args.legIndex];
  const nombre = str(pasajero?.nombre) || args.legLabel || "Pasajero";

  if (pasajero && str(pasajero.id)) {
    await snap.ref.update({
      corporativoPasajeros: lista.map((p, i) =>
        i === args.legIndex
          ? {
              ...p,
              dejadoEn: new Date().toISOString(),
              dejadoConfirmado: true,
            }
          : p,
      ),
      actualizadoEn: FieldValue.serverTimestamp(),
    });
  }

  await notificarEncargados({
    empresaId,
    viajeId: args.viajeId,
    plantillaId: str(d.corporativoPlantillaId),
    tipo: "destino_pasajero",
    titulo: "Empleado dejado en destino",
    cuerpo: `${nombre} fue dejado en su destino (${args.legLabel}).`,
  });
}

/** Al completar viaje corporativo: aviso al encargado. */
export async function notificarViajeCorporativoCompletado(
  viajeId: string,
  d: AnyMap,
): Promise<void> {
  if (!esCorporativo(d)) return;
  const empresaId = str(d.corporativoEmpresaId);
  if (!empresaId) return;
  const ruta = str(d.corporativoPlantillaNombre) || "Ruta corporativa";
  await notificarEncargados({
    empresaId,
    viajeId,
    plantillaId: str(d.corporativoPlantillaId),
    tipo: "viaje_completado",
    titulo: "Ruta completada",
    cuerpo: `El chofer finalizó «${ruta}». Revisá el registro de abordaje en el panel.`,
  });
  logger.info("notificarViajeCorporativoCompletado", { viajeId, empresaId });
}
