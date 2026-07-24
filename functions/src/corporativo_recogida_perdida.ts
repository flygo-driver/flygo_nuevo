/**
 * Recogida corporativa no realizada: detección, cierre del día y avisos.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  enviarPushUid,
  registrarHistorialNotificacionCorp,
} from "./corporativo_notificaciones.js";

type AnyMap = Record<string, unknown>;

const TZ_RD = "America/Santo_Domingo";
const GRACE_CON_VIAJE_MIN = 25;
const GRACE_SIN_VIAJE_MIN = 45;
const VENTANA_PUBLICACION_MIN = 90;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

export function diaCalendarioRdCorp(ref = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ_RD,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(ref);
}

export function recogidaPerdidaKeyDia(keyDia: string): string {
  return `recogidaPerdida_${keyDia}`;
}

export function camposLimpiarRecogidaPerdida(keyDia: string): AnyMap {
  return {
    [recogidaPerdidaKeyDia(keyDia)]: FieldValue.delete(),
    recogidaPerdidaEn: FieldValue.delete(),
    recogidaPerdidaChoferUid: FieldValue.delete(),
  };
}

function esMismoDiaCalendarioRd(dt: Date, ref: Date): boolean {
  return diaCalendarioRdCorp(dt) === diaCalendarioRdCorp(ref);
}

function viajeCorpReutilizableHoy(v: AnyMap): boolean {
  if (v.completado === true) return false;
  if (str(v.corporativoSupersedidoPor).length > 0) return false;
  const e = str(v.estado).toLowerCase();
  return (
    e !== "cancelado" &&
    e !== "rechazado" &&
    e !== "completado" &&
    e !== "cancelado_por_tiempo"
  );
}

export function viajeCorporativoChoferEnServicio(estado: string): boolean {
  const e = estado.toLowerCase();
  return (
    e === "en_camino_pickup" ||
    e === "a_bordo" ||
    e === "en_curso" ||
    e === "en_origen_esperando_codigo" ||
    e === "pendiente_codigo" ||
    e === "esperando_codigo_encargado"
  );
}

export function yaMarcadaRecogidaPerdidaHoy(
  plantilla: AnyMap,
  keyDia: string,
): boolean {
  return str(plantilla[recogidaPerdidaKeyDia(keyDia)]) === "1";
}

/** ¿La recogida de hoy ya se perdió? (solo lectura; no escribe Firestore). */
export function evaluarRecogidaPerdidaCorporativa(args: {
  plantilla: AnyMap;
  vData: AnyMap | null;
  recogida: Date | null;
  ahora: Date;
  keyDia: string;
}): boolean {
  if (args.plantilla.pausaTotal === true) return false;
  const feriados = Array.isArray(args.plantilla.diasPausaFeriado)
    ? (args.plantilla.diasPausaFeriado as string[]).map(str)
    : [];
  if (feriados.includes(args.keyDia)) return false;

  if (yaMarcadaRecogidaPerdidaHoy(args.plantilla, args.keyDia)) return true;

  if (!args.recogida) return false;
  if (!esMismoDiaCalendarioRd(args.recogida, args.ahora)) return false;

  const chofer = str(args.plantilla.choferPreferidoUid);
  if (!chofer) return false;

  const diffMin = (args.recogida.getTime() - args.ahora.getTime()) / 60000;
  const v = args.vData;
  if (v?.completado === true) return false;

  const estado = str(v?.estado).toLowerCase();
  if (viajeCorporativoChoferEnServicio(estado)) return false;
  if (estado === "completado" || estado === "finalizado") return false;

  const tieneViajeHoy = v != null && viajeCorpReutilizableHoy(v);
  const grace = tieneViajeHoy ? GRACE_CON_VIAJE_MIN : GRACE_SIN_VIAJE_MIN;
  if (diffMin > -grace) return false;

  if (tieneViajeHoy) return true;

  // Sin viaje publicado: solo si la ventana de publicación ya estuvo abierta.
  const minDesdeApertura =
    (args.ahora.getTime() -
      (args.recogida.getTime() - VENTANA_PUBLICACION_MIN * 60000)) /
    60000;
  return minDesdeApertura >= grace;
}

export function mensajeChoferRecogidaPerdida(hora: string): string {
  return (
    `Recogida de las ${hora} no realizada. ` +
    `RAI y la empresa fueron notificados. ` +
    `Mañana se publica la ruta ~90 min antes de la hora habitual.`
  );
}

export async function aplicarRecogidaPerdidaCorporativa(args: {
  empresaId: string;
  plantillaId: string;
  plantilla: AnyMap;
  viajeId: string;
  vData: AnyMap | null;
  choferUid: string;
  horaTxt: string;
  keyDia: string;
  empresaNombre: string;
  plantillaNombre: string;
}): Promise<boolean> {
  if (yaMarcadaRecogidaPerdidaHoy(args.plantilla, args.keyDia)) return false;

  const db = getFirestore();
  const plRef = db
    .collection("empresas_corporativas")
    .doc(args.empresaId)
    .collection("plantillas_ruta")
    .doc(args.plantillaId);

  await plRef.set(
    {
      [recogidaPerdidaKeyDia(args.keyDia)]: "1",
      recogidaPerdidaEn: FieldValue.serverTimestamp(),
      recogidaPerdidaChoferUid: args.choferUid,
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const viajeId = str(args.viajeId);
  if (viajeId && args.vData) {
    const e = str(args.vData.estado).toLowerCase();
    if (
      !viajeCorporativoChoferEnServicio(e) &&
      args.vData.completado !== true &&
      viajeCorpReutilizableHoy(args.vData)
    ) {
      await db.collection("viajes").doc(viajeId).set(
        {
          estado: "cancelado_por_tiempo",
          canceladoEn: FieldValue.serverTimestamp(),
          canceladoMotivo: "recogida_perdida_chofer",
          corporativoRecogidaPerdida: true,
          activo: false,
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
  }

  await db.collection("alertas_admin").add({
    tipo: "corporativo_recogida_perdida",
    empresaId: args.empresaId,
    plantillaId: args.plantillaId,
    viajeId: viajeId || null,
    uidTaxista: args.choferUid,
    titulo: "Recogida corporativa no realizada",
    mensaje:
      `${args.empresaNombre} · ${args.plantillaNombre}: ` +
      `el chofer no fue a la recogida de las ${args.horaTxt}.`,
    leida: false,
    creadoEn: FieldValue.serverTimestamp(),
  });

  const empSnap = await db
    .collection("empresas_corporativas")
    .doc(args.empresaId)
    .get();
  const encargados = Array.isArray(empSnap.data()?.encargadoUids)
    ? (empSnap.data()!.encargadoUids as string[]).map(String)
    : [];

  const msgChofer = mensajeChoferRecogidaPerdida(args.horaTxt);
  const msgEnc =
    `El chofer no fue a la recogida de las ${args.horaTxt} ` +
    `(${args.plantillaNombre}). Coordiná sustituto o transporte alternativo.`;

  await enviarPushUid(
    args.choferUid,
    "⚠️ Recogida no realizada",
    msgChofer,
    {
      type: "corporativo_recogida_perdida",
      empresaId: args.empresaId,
      plantillaId: args.plantillaId,
      rol: "taxista",
    },
  );
  await registrarHistorialNotificacionCorp({
    empresaId: args.empresaId,
    plantillaId: args.plantillaId,
    viajeId: viajeId || undefined,
    uidDestino: args.choferUid,
    canal: "fcm",
    tipo: "recogida_perdida_chofer",
    titulo: "Recogida no realizada",
    cuerpo: msgChofer,
    enviado: true,
  });

  for (const uidEnc of encargados) {
    await enviarPushUid(uidEnc, "⚠️ Chofer no fue a recoger", msgEnc, {
      type: "corporativo_recogida_perdida",
      empresaId: args.empresaId,
      plantillaId: args.plantillaId,
      rol: "encargado",
    });
    await registrarHistorialNotificacionCorp({
      empresaId: args.empresaId,
      plantillaId: args.plantillaId,
      viajeId: viajeId || undefined,
      uidDestino: uidEnc,
      canal: "fcm",
      tipo: "recogida_perdida_encargado",
      titulo: "Chofer no fue a recoger",
      cuerpo: msgEnc,
      enviado: true,
    });
  }

  const { refrescarChoferOperacionCorporativa } = await import(
    "./corporativo_rutas.js"
  );
  await refrescarChoferOperacionCorporativa(args.choferUid);

  logger.info("aplicarRecogidaPerdidaCorporativa", {
    empresaId: args.empresaId,
    plantillaId: args.plantillaId,
    choferUid: args.choferUid,
    viajeId,
  });
  return true;
}

/** Cada 10 min: detecta recogidas no realizadas y cierra el día operativo. */
export const scheduledCorporativoRecogidaPerdida = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: TZ_RD,
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    const db = getFirestore();
    const ahora = new Date();
    const keyDia = diaCalendarioRdCorp(ahora);
    let aplicadas = 0;

    const empresas = await db
      .collection("empresas_corporativas")
      .where("activa", "==", true)
      .limit(40)
      .get();

    for (const emp of empresas.docs) {
      const empresaId = emp.id;
      const empresaNombre = str(emp.data().nombre) || "Empresa";
      const plantillas = await db
        .collection("empresas_corporativas")
        .doc(empresaId)
        .collection("plantillas_ruta")
        .where("activa", "==", true)
        .where("esFijo", "==", true)
        .limit(25)
        .get();

      for (const pl of plantillas.docs) {
        const d = pl.data() as AnyMap;
        const choferUid = str(d.choferPreferidoUid);
        if (!choferUid) continue;
        if (yaMarcadaRecogidaPerdidaHoy(d, keyDia)) continue;

        const horaStr =
          str(d.horaRecogidaGrupo) || str(d.horaRecogida) || "07:00";
        const parts = horaStr.split(":");
        const h = parseInt(parts[0] ?? "7", 10);
        const m = parseInt(parts[1] ?? "0", 10);
        const [y, mo, day] = keyDia.split("-").map(Number);
        const recogida = new Date(Date.UTC(y, mo - 1, day, h + 4, m, 0));

        let viajeId = str(d.ultimoViajeId);
        let vData: AnyMap | null = null;
        if (viajeId) {
          try {
            const vSnap = await db.collection("viajes").doc(viajeId).get();
            if (vSnap.exists) {
              vData = (vSnap.data() ?? {}) as AnyMap;
              const fh = vData.fechaHora;
              const fhDate =
                fh && typeof (fh as { toDate?: () => Date }).toDate === "function"
                  ? (fh as { toDate: () => Date }).toDate()
                  : null;
              if (fhDate && diaCalendarioRdCorp(fhDate) !== keyDia) {
                viajeId = "";
                vData = null;
              }
            } else {
              viajeId = "";
            }
          } catch {
            viajeId = "";
            vData = null;
          }
        }

        if (
          !evaluarRecogidaPerdidaCorporativa({
            plantilla: d,
            vData,
            recogida,
            ahora,
            keyDia,
          })
        ) {
          continue;
        }

        const horaTxt = `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
        const ok = await aplicarRecogidaPerdidaCorporativa({
          empresaId,
          plantillaId: pl.id,
          plantilla: d,
          viajeId,
          vData,
          choferUid,
          horaTxt,
          keyDia,
          empresaNombre,
          plantillaNombre: str(d.nombre) || "Ruta corporativa",
        });
        if (ok) aplicadas += 1;
      }
    }

    logger.info("scheduledCorporativoRecogidaPerdida", { aplicadas, keyDia });
  },
);
