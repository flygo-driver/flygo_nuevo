/**
 * Validación de conflictos de horario entre rutas corporativas (chofer / empresa).
 */
import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

export function parseHoraMinutos(raw: unknown): number {
  const s = str(raw) || "07:00";
  const parts = s.split(":");
  const h = Number(parts[0] ?? 7);
  const m = Number(parts[1] ?? 0);
  if (!Number.isFinite(h) || !Number.isFinite(m)) return 7 * 60;
  return (
    Math.max(0, Math.min(23, Math.trunc(h))) * 60 +
    Math.max(0, Math.min(59, Math.trunc(m)))
  );
}

export function diasEfectivosPlantilla(d: AnyMap): number[] {
  const patron = str(d.patronRecurrencia) || "lun_vie";
  const raw = Array.isArray(d.diasSemana)
    ? (d.diasSemana as unknown[])
        .map((x) => Number(x))
        .filter((n) => n >= 1 && n <= 7)
    : [];
  if (patron === "lun_vie") return [1, 2, 3, 4, 5];
  if (patron === "diario") return [1, 2, 3, 4, 5, 6, 7];
  if (raw.length > 0) return raw;
  return [1, 2, 3, 4, 5];
}

/** Duración estimada de la ruta (min). */
export function tiempoEstimadoMinPlantilla(d: AnyMap): number {
  const explicito = num(d.tiempoEstimadoMin);
  if (explicito >= 30) return Math.trunc(explicito);
  const pasajeros = Array.isArray(d.pasajeros)
    ? (d.pasajeros as AnyMap[]).filter((p) => p.activo !== false).length
    : 3;
  return Math.max(60, 40 + pasajeros * 20);
}

export function tiempoTrasladoMinPlantilla(d: AnyMap): number {
  const t = num(d.tiempoTrasladoMin);
  return t >= 15 ? Math.trunc(t) : 30;
}

export function bufferOperacionMin(d: AnyMap): number {
  return Math.max(
    tiempoEstimadoMinPlantilla(d) + tiempoTrasladoMinPlantilla(d),
    90,
  );
}

function diasSeSolapan(a: number[], b: number[]): boolean {
  const setB = new Set(b);
  return a.some((d) => setB.has(d));
}

async function snapPlantillasPorChoferUid(choferUid: string) {
  try {
    return await getFirestore()
      .collectionGroup("plantillas_ruta")
      .where("choferPreferidoUid", "==", choferUid)
      .get();
  } catch (e) {
    logger.error("snapPlantillasPorChoferUid", { choferUid, e });
    throw new HttpsError(
      "failed-precondition",
      "No se pudo validar horarios del conductor. Desplegá el índice "
        + "collectionGroup plantillas_ruta + choferPreferidoUid.",
    );
  }
}

async function nombreEmpresa(empresaId: string): Promise<string> {
  const snap = await getFirestore()
    .collection("empresas_corporativas")
    .doc(empresaId)
    .get();
  return str(snap.data()?.nombre) || empresaId;
}

function intervalosSeSolapan(
  inicioA: number,
  finA: number,
  inicioB: number,
  finB: number,
): boolean {
  return inicioA < finB && inicioB < finA;
}

/** Mínimo entre recogidas del mismo chofer en días que se solapan (3 h). */
export const SEPARACION_MINIMA_RECogida_CHOFER_MIN = 180;

/**
 * Chofer con dos rutas en días que coinciden: conflicto si
 * - las recogidas están a menos de 3 h, o
 * - los intervalos operativos [hora, hora+duración+traslado] se solapan.
 */
export function hayConflictoHorarioEntrePlantillas(
  nueva: AnyMap,
  existente: AnyMap,
): boolean {
  const diasN = diasEfectivosPlantilla(nueva);
  const diasE = diasEfectivosPlantilla(existente);
  if (!diasSeSolapan(diasN, diasE)) return false;

  const tN = parseHoraMinutos(nueva.horaRecogidaGrupo ?? nueva.horaRecogida);
  const tE = parseHoraMinutos(
    existente.horaRecogidaGrupo ?? existente.horaRecogida,
  );
  const diff = Math.abs(tN - tE);
  if (diff < SEPARACION_MINIMA_RECogida_CHOFER_MIN) return true;

  const finN = tN + tiempoEstimadoMinPlantilla(nueva) + tiempoTrasladoMinPlantilla(nueva);
  const finE = tE + tiempoEstimadoMinPlantilla(existente) + tiempoTrasladoMinPlantilla(existente);

  return intervalosSeSolapan(tN, finN, tE, finE);
}

export async function detectarConflictosHorarioChofer(args: {
  choferUid: string;
  empresaId: string;
  plantillaId: string;
  plantilla: AnyMap;
}): Promise<AnyMap[]> {
  const snap = await snapPlantillasPorChoferUid(args.choferUid);

  const conflictos: AnyMap[] = [];

  for (const doc of snap.docs) {
    const empresaId = doc.ref.parent.parent?.id ?? "";
    if (empresaId === args.empresaId && doc.id === args.plantillaId) continue;
    const d = doc.data() as AnyMap;
    if (d.activa === false) continue;
    if (!hayConflictoHorarioEntrePlantillas(args.plantilla, d)) continue;

    const tNueva = parseHoraMinutos(
      args.plantilla.horaRecogidaGrupo ?? args.plantilla.horaRecogida,
    );
    const tOtra = parseHoraMinutos(d.horaRecogidaGrupo ?? d.horaRecogida);
    const diff = Math.abs(tNueva - tOtra);
    const margen = Math.max(
      SEPARACION_MINIMA_RECogida_CHOFER_MIN,
      bufferOperacionMin(args.plantilla),
      bufferOperacionMin(d),
    );

    const empresaNombre = await nombreEmpresa(empresaId);
    const plantillaNombre = str(d.nombre) || "Ruta";
    const hora = str(d.horaRecogidaGrupo) || str(d.horaRecogida) || "07:00";
    const horasMin = Math.round(SEPARACION_MINIMA_RECogida_CHOFER_MIN / 60);
    conflictos.push({
      empresaId,
      empresaNombre,
      plantillaId: doc.id,
      plantillaNombre,
      hora,
      dias: diasEfectivosPlantilla(d),
      diferenciaMinutos: diff,
      margenMinutos: margen,
      detalle:
        `Comprometido con ${empresaNombre}: ruta «${plantillaNombre}» a las ${hora}. ` +
        `Separación ${diff} min; el mismo chofer necesita ≥ ${horasMin} h entre recogidas.`,
    });
  }
  return conflictos;
}

/** Mensaje estándar: chofer no disponible por compromiso con otra empresa/ruta. */
export function mensajeCompromisoChoferDesdeConflictos(
  conflictos: AnyMap[],
  choferNombre = "El conductor",
): string {
  if (conflictos.length === 0) return "";
  const c = conflictos[0] ?? {};
  const emp = str(c.empresaNombre) || "otra empresa";
  const ruta = str(c.plantillaNombre) || "ruta";
  const hora = str(c.hora);
  const horaTxt = hora ? ` a las ${hora}` : "";
  return (
    `${choferNombre} no puede asignarse: está comprometido con ${emp} ` +
    `(ruta «${ruta}»${horaTxt}). Elegí otro conductor o ajustá el horario.`
  );
}

/** Misma empresa u otra: bloquea chofer con rutas que chocan de horario. */
export async function bloquearMismoChoferMismaHoraEnEmpresa(args: {
  empresaId: string;
  plantillaId: string;
  plantilla: AnyMap;
}): Promise<string | null> {
  const choferUid = str(args.plantilla.choferPreferidoUid);
  if (!choferUid) return null;

  const conflictos = await detectarConflictosHorarioChofer({
    choferUid,
    empresaId: args.empresaId,
    plantillaId: args.plantillaId,
    plantilla: args.plantilla,
  });
  if (conflictos.length > 0) {
    return mensajeCompromisoChoferDesdeConflictos(conflictos, "El conductor");
  }
  return null;
}

export async function listarOtrasRutasChofer(args: {
  choferUid: string;
  excludeEmpresaId: string;
  excludePlantillaId: string;
}): Promise<AnyMap[]> {
  const snap = await snapPlantillasPorChoferUid(args.choferUid);
  const out: AnyMap[] = [];
  for (const doc of snap.docs) {
    const empresaId = doc.ref.parent.parent?.id ?? "";
    if (
      empresaId === args.excludeEmpresaId &&
      doc.id === args.excludePlantillaId
    ) {
      continue;
    }
    const d = doc.data() as AnyMap;
    if (d.activa === false) continue;
    out.push({
      empresaId,
      empresaNombre: await nombreEmpresa(empresaId),
      plantillaId: doc.id,
      plantillaNombre: str(d.nombre) || "Ruta",
      hora: str(d.horaRecogidaGrupo) || str(d.horaRecogida) || "07:00",
      dias: diasEfectivosPlantilla(d),
    });
  }
  return out;
}

async function esAdminUid(uid: string): Promise<boolean> {
  const snap = await getFirestore().collection("usuarios").doc(uid).get();
  const data = (snap.data() ?? {}) as AnyMap;
  const rol = str(data.rol).toLowerCase();
  if (rol === "admin" || rol === "administrador") return true;
  if (data.isAdmin === true || data.admin === true) return true;
  const rSnap = await getFirestore().collection("roles").doc(uid).get();
  const rRol = str(rSnap.data()?.rol).toLowerCase();
  return rRol === "admin" || rRol === "administrador";
}

function esEncargadoEmpresa(ed: AnyMap, uid: string): boolean {
  const uids = Array.isArray(ed.encargadoUids)
    ? (ed.encargadoUids as string[]).map(String)
    : [];
  return uids.includes(uid);
}

async function assertAdmin(uid: string): Promise<void> {
  if (!(await esAdminUid(uid))) {
    throw new HttpsError("permission-denied", "Solo administradores");
  }
}

/** Admin: calendario semanal de rutas de un chofer (todas las empresas). */
export const adminCalendarioChoferCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const choferUid = str(request.data?.choferUid);
  if (!choferUid) {
    throw new HttpsError("invalid-argument", "Falta choferUid");
  }

  const snap = await snapPlantillasPorChoferUid(choferUid);
  const rutas: AnyMap[] = [];
  for (const doc of snap.docs) {
    const empresaId = doc.ref.parent.parent?.id ?? "";
    const d = doc.data() as AnyMap;
    if (d.activa === false) continue;
    rutas.push({
      empresaId,
      empresaNombre: await nombreEmpresa(empresaId),
      plantillaId: doc.id,
      nombre: str(d.nombre) || "Ruta",
      hora: str(d.horaRecogidaGrupo) || str(d.horaRecogida) || "07:00",
      dias: diasEfectivosPlantilla(d),
      tiempoEstimadoMin: tiempoEstimadoMinPlantilla(d),
      estadoPublicacion: str(d.estadoPublicacion) || "activa",
    });
  }
  rutas.sort((a, b) => parseHoraMinutos(a.hora) - parseHoraMinutos(b.hora));
  return { ok: true, choferUid, rutas };
});

/** Admin / encargado: validar conflictos antes de asignar o publicar. */
export const validarConflictosChoferCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");

  const empresaId = str(request.data?.empresaId);
  const plantillaId = str(request.data?.plantillaId);
  const choferUid = str(request.data?.choferUid);
  if (!empresaId || !plantillaId || !choferUid) {
    throw new HttpsError("invalid-argument", "Faltan empresaId, plantillaId o choferUid");
  }

  const callerUid = request.auth.uid;
  if (!(await esAdminUid(callerUid))) {
    const empSnap = await getFirestore()
      .collection("empresas_corporativas")
      .doc(empresaId)
      .get();
    if (!empSnap.exists) {
      throw new HttpsError("not-found", "Empresa no encontrada");
    }
    if (!esEncargadoEmpresa((empSnap.data() ?? {}) as AnyMap, callerUid)) {
      throw new HttpsError("permission-denied", "Sin permiso para esta empresa");
    }
  }

  const plSnap = await getFirestore()
    .collection("empresas_corporativas")
    .doc(empresaId)
    .collection("plantillas_ruta")
    .doc(plantillaId)
    .get();
  if (!plSnap.exists) throw new HttpsError("not-found", "Ruta no encontrada");
  const plantilla = { ...(plSnap.data() as AnyMap), choferPreferidoUid: choferUid };

  const bloqueo = await bloquearMismoChoferMismaHoraEnEmpresa({
    empresaId,
    plantillaId,
    plantilla,
  });
  if (bloqueo) {
    return { ok: true, bloqueado: true, conflictos: [], mensaje: bloqueo };
  }

  const conflictos = await detectarConflictosHorarioChofer({
    choferUid,
    empresaId,
    plantillaId,
    plantilla,
  });
  const otrasRutas = await listarOtrasRutasChofer({
    choferUid,
    excludeEmpresaId: empresaId,
    excludePlantillaId: plantillaId,
  });

  return {
    ok: true,
    bloqueado: false,
    conflictos,
    otrasRutas,
    requiereConfirmacion: conflictos.length > 0,
  };
});
