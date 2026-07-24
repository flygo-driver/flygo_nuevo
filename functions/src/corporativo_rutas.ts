/**
 * Rutas corporativas fijas: publicación automática + alarma al chofer.
 */
import { randomUUID } from "node:crypto";

import { FieldValue, GeoPoint, Timestamp, getFirestore, type DocumentReference } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  asignarChoferCorporativoFijo,
  CANAL_CORPORATIVO_FIJO,
  ejecutarPromoverViajeCorporativoEnCurso,
  repararChoferViajeCorporativoSiHaceFalta,
} from "./corporativo_assign.js";
import {
  mensajeErrorPublicacionChoferCorporativo,
  resolverChoferPublicacionCorporativo,
} from "./corporativo_auto_asignacion.js";
import {
  calcularPrecioCorporativoDesdeKm,
  construirDesgloseTarifaCorporativoViaje,
  distanciaKmLineaRectaRuta,
  getCorporativoTarifaConfigCached,
} from "./corporativo_tarifa_config.js";
import {
  codigoAccesoDesdePeriodo,
  generarCodigoAccesoPeriodo,
} from "./corporativo_codigo.js";
import {
  obtenerDiasPausaEmpresa,
  repararPeriodoSinRotarCodigo,
  evaluarVigenciaCodigoCorporativo,
} from "./corporativo_periodo.js";
import {
  bloquearMismoChoferMismaHoraEnEmpresa,
  detectarConflictosHorarioChofer,
  mensajeCompromisoChoferDesdeConflictos,
} from "./corporativo_validacion.js";
import { esDiaNoLaborableCorporativo } from "./corporativo_feriados_rd.js";
import {
  camposLimpiarRecogidaPerdida,
  diaCalendarioRdCorp,
  evaluarRecogidaPerdidaCorporativa,
  mensajeChoferRecogidaPerdida,
  yaMarcadaRecogidaPerdidaHoy,
} from "./corporativo_recogida_perdida.js";
import {
  CORP_CONTRATO_VERSION,
  CORP_ENVIAR_AHORA_OFFSET_MIN,
  CORP_MINUTOS_PUBLICAR_ANTES_DEFAULT,
  CORP_VENTANA_TOLERANCIA_MIN,
  corporativoPoolOpensAtMs,
  minutosPublicarAntesCorporativo,
} from "./corporativo_constants.js";

const db = () => getFirestore();
const messaging = () => getMessaging();
const ANDROID_CHANNEL = "rai_driver_notifications";

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function round2(n: number): number {
  if (!Number.isFinite(n)) return 0;
  return Math.round(n * 100) / 100;
}

function roundCoord6(n: number): number {
  if (!Number.isFinite(n)) return 0;
  return Math.round(n * 1e6) / 1e6;
}

function mergeExtrasCorporativo(base: unknown, patch: AnyMap): AnyMap {
  const b = base && typeof base === "object" ? (base as AnyMap) : {};
  return { ...b, ...patch };
}

/** Ventana corporativa (~90 min antes de la recogida, configurable por plantilla). */
function ventanasPublicacionCorporativo(
  fechaRecogida: Date,
  minPub = CORP_MINUTOS_PUBLICAR_ANTES_DEFAULT,
): {
  publishAt: Timestamp;
  acceptAfter: Timestamp;
  startWindowAt: Timestamp;
  publicado: boolean;
} {
  const pickupMs = fechaRecogida.getTime();
  const nowMs = Date.now();
  const publishAtMs = corporativoPoolOpensAtMs(pickupMs, nowMs, minPub);
  return {
    publishAt: Timestamp.fromMillis(publishAtMs),
    acceptAfter: Timestamp.fromMillis(publishAtMs),
    startWindowAt: Timestamp.fromMillis(publishAtMs),
    publicado: publishAtMs <= nowMs,
  };
}

/** Campos multiparada + extras corporativos (misma forma que programar_viaje_multi). */
function aplicarCamposMultiparadaCorporativo(
  trip: AnyMap,
  args: {
    waypoints: AnyMap[];
    activos: AnyMap[];
    rutaPuntos: AnyMap[];
    mapsUrl: string;
    wazeUrl: string;
    desglose: AnyMap;
    kmCotizados: number;
  },
  opts?: { preservarProgreso?: boolean },
): void {
  const baseExtras = (trip.extras as AnyMap) ?? {};
  const extrasPatch: AnyMap = {
    corporativo: true,
    corporativoPasajeros: args.activos,
    rutaPuntos: args.rutaPuntos,
    corporativoGoogleMapsRutaUrl: args.mapsUrl,
    corporativoWazeOrigenUrl: args.wazeUrl,
    distancia_km: args.kmCotizados,
    corporativoTarifaDesglose: args.desglose,
  };
  if (args.waypoints.length > 0) {
    trip.waypoints = args.waypoints;
    trip.multiparadaLegsTotal = args.waypoints.length + 1;
    extrasPatch.paradas_count = args.waypoints.length;
    trip.categoria = "multi";
  } else {
    trip.multiparadaLegsTotal = Math.max(1, args.activos.length);
  }
  trip.rutaPuntos = args.rutaPuntos;
  if (opts?.preservarProgreso !== true) {
    trip.multiparadaLegCompletadas = 0;
    trip.multiparadaParadasVisitadas = [];
    trip.multiparadaCompleta = false;
  }
  trip.extras = mergeExtrasCorporativo(baseExtras, extrasPatch);
}

function firmaPasajerosPlantilla(d: AnyMap): string {
  const raw = Array.isArray(d.pasajeros) ? (d.pasajeros as AnyMap[]) : [];
  return raw
    .filter((p) => p?.activo !== false)
    .map(
      (p) =>
        `${str(p.id)}|${Number(p.lat)}|${Number(p.lon)}|${str(p.nombre)}|${str(p.destinoLabel || p.destino)}`,
    )
    .join(";");
}

function pagoChoferEstimadoDesdeDesgloseCorporativo(
  desglose: AnyMap,
  precioFactura: number,
  cfg: { comisionPlataformaPorcentaje?: number },
): number {
  const comisionPct = Number(cfg.comisionPlataformaPorcentaje ?? 10);
  const baseChofer = Math.round(
    Number(desglose.precioBaseServicioRd ?? desglose.subtotalFacturaRd ?? 0),
  );
  return Math.max(
    0,
    Math.round(
      Number(desglose.pagoChoferRd ?? 0) > 0
        ? Number(desglose.pagoChoferRd)
        : baseChofer > 0
          ? baseChofer * ((100 - comisionPct) / 100)
          : precioFactura * ((100 - comisionPct) / 100),
    ),
  );
}

/** Cuenta pasajeros activos del viaje publicado (tiempo real) o plantilla. */
function pasajerosActivosOperativos(
  vData: AnyMap | null,
  plantillaCount: number,
): number {
  if (!vData) return plantillaCount;
  const fromRoot = Array.isArray(vData.corporativoPasajeros)
    ? (vData.corporativoPasajeros as AnyMap[])
    : [];
  const ex =
    vData.extras && typeof vData.extras === "object"
      ? (vData.extras as AnyMap)
      : {};
  const fromEx = Array.isArray(ex.corporativoPasajeros)
    ? (ex.corporativoPasajeros as AnyMap[])
    : [];
  const list = fromRoot.length >= fromEx.length ? fromRoot : fromEx;
  if (list.length === 0) return plantillaCount;
  return list.filter((p) => p?.activo !== false).length;
}

function diaSemanaIso(d: Date): number {
  const js = d.getDay();
  return js === 0 ? 7 : js;
}

function soloFecha(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function diasEntre(a: Date, b: Date): number {
  return Math.round((soloFecha(b).getTime() - soloFecha(a).getTime()) / 86400000);
}

function servicioIniciado(d: AnyMap, hoy: Date): boolean {
  const iniStr = str(d.fechaInicioServicio);
  if (!iniStr) return true;
  const ini = new Date(iniStr);
  if (!Number.isFinite(ini.getTime())) return true;
  return diasEntre(soloFecha(ini), soloFecha(hoy)) >= 0;
}

function coincidePatronHoy(d: AnyMap, hoy: Date): boolean {
  const patron = str(d.patronRecurrencia) || "lun_vie";
  const dias = Array.isArray(d.diasSemana) ? (d.diasSemana as number[]) : [1, 2, 3, 4, 5];
  const dia = diaSemanaIso(hoy);
  switch (patron) {
    case "lun_vie":
      return dia >= 1 && dia <= 5;
    case "diario":
      return true;
    case "interdiaria": {
      const anclaStr = str(d.fechaAnclaInterdiaria);
      const ancla = anclaStr ? new Date(anclaStr) : hoy;
      const diff = diasEntre(soloFecha(ancla), soloFecha(hoy));
      return diff >= 0 && diff % 2 === 0;
    }
    case "personalizado":
    default:
      return dias.includes(dia);
  }
}

/** Normaliza a HH:mm 24h. Acepta 7:00, 07:00, 07:00:00, 7:00 AM/PM. */
function normalizarHoraHHmm(raw: string): string | null {
  let s = String(raw ?? "").trim();
  if (!s) return null;
  const upper = s.toUpperCase();
  let esPm = false;
  let esAm = false;
  if (/\bPM\b/.test(upper) || upper.endsWith("PM")) {
    esPm = true;
    s = s.replace(/\s*[AaPp][Mm]\s*/g, "").trim();
  } else if (/\bAM\b/.test(upper) || upper.endsWith("AM")) {
    esAm = true;
    s = s.replace(/\s*[AaPp][Mm]\s*/g, "").trim();
  }
  const parts = s.split(/[:.]/);
  if (parts.length < 2) return null;
  let h = parseInt(parts[0], 10);
  const mMatch = String(parts[1]).trim().match(/^(\d{1,2})/);
  const m = mMatch ? parseInt(mMatch[1], 10) : NaN;
  if (!Number.isFinite(h) || !Number.isFinite(m)) return null;
  if (m < 0 || m > 59) return null;
  if (esPm || esAm) {
    if (h < 1 || h > 12) return null;
    if (esPm && h < 12) h += 12;
    if (esAm && h === 12) h = 0;
  } else if (h < 0 || h > 23) {
    return null;
  }
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

function parseHora(hora: string): { h: number; m: number } | null {
  const norm = normalizarHoraHHmm(hora);
  if (!norm) return null;
  const [hs, ms] = norm.split(":");
  return { h: parseInt(hs, 10), m: parseInt(ms, 10) };
}

/** Hora HH:mm en calendario RD (para mostrar al chofer). */
function horaHmEnZonaRd(d: Date): string {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: TZ_RD,
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(d);
  const h = parts.find((p) => p.type === "hour")?.value ?? "00";
  const m = parts.find((p) => p.type === "minute")?.value ?? "00";
  return `${h.padStart(2, "0")}:${m.padStart(2, "0")}`;
}

function fechaHoraViajeCorporativo(v: AnyMap | null): Date | null {
  if (!v) return null;
  const fh = v.fechaHora;
  if (fh instanceof Timestamp) return fh.toDate();
  if (fh instanceof Date) return fh;
  return null;
}

/** Hora contractual del encargado en plantilla (fuente sagrada). */
function horaEncargadoDesdePlantilla(plantilla: AnyMap): string {
  return (
    normalizarHoraHHmm(
      str(plantilla.horaRecogidaGrupo) || str(plantilla.horaRecogida) || "",
    ) || "07:00"
  );
}

/** Hora contractual del encargado: siempre la plantilla (fuente sagrada). */
function horaContratoEncargadoCorporativo(
  _vData: AnyMap | null,
  plantilla: AnyMap,
): string {
  return horaEncargadoDesdePlantilla(plantilla);
}

/** Hora almacenada en el viaje (para reconciliar sync). */
function horaAlmacenadaEnViaje(vData: AnyMap): string {
  const corp = normalizarHoraHHmm(str(vData.corporativoHoraRecogidaGrupo));
  if (corp) return corp;
  const desdeViaje = fechaHoraViajeCorporativo(vData);
  if (desdeViaje) return horaHmEnZonaRd(desdeViaje);
  return "";
}

/**
 * Recogida operativa: la hora mostrada al chofer es siempre la del encargado;
 * `fechaHora` del viaje solo se usa si coincide (~2 min) con la contractual.
 */
function recogidaOperativaDesdeViajeOPlantilla(args: {
  vData: AnyMap | null;
  plantilla: AnyMap;
  ahora: Date;
}): { recogida: Date | null; hora: string } {
  const hora = horaContratoEncargadoCorporativo(args.vData, args.plantilla);
  const recogidaContrato = recogidaConHoraZonaRd(hora, args.ahora);
  const desdeViaje = fechaHoraViajeCorporativo(args.vData);
  if (desdeViaje && recogidaContrato) {
    const diffMin = Math.abs(
      (recogidaContrato.getTime() - desdeViaje.getTime()) / 60000,
    );
    if (diffMin < 2) {
      return { recogida: desdeViaje, hora };
    }
  }
  if (recogidaContrato) {
    return { recogida: recogidaContrato, hora };
  }
  if (desdeViaje) {
    return { recogida: desdeViaje, hora: horaHmEnZonaRd(desdeViaje) };
  }
  return { recogida: null, hora };
}

function rutaKeySegura(empresaId: string, plantillaId: string): string {
  return `${empresaId}__${plantillaId}`.replace(/\./g, "_");
}

async function assertEncargadoOAdminCorporativo(
  uid: string,
  empresaId: string,
): Promise<void> {
  const uSnap = await db().collection("usuarios").doc(uid).get();
  if (String(uSnap.data()?.rol ?? "").toLowerCase() === "admin") return;
  const empSnap = await db().collection("empresas_corporativas").doc(empresaId).get();
  if (!empSnap.exists) {
    throw new HttpsError("not-found", "Empresa no encontrada");
  }
  const encargados = Array.isArray(empSnap.data()?.encargadoUids)
    ? (empSnap.data()!.encargadoUids as string[]).map(String)
    : [];
  if (!encargados.includes(uid)) {
    throw new HttpsError("permission-denied", "Solo encargado o administración RAI");
  }
}

const TZ_RD = "America/Santo_Domingo";
const TZ_RD_OFFSET = "-04:00";

function diaCalendarioRd(ref: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ_RD,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(ref);
}

/** Hora HH:mm en calendario de RD (evita desfase UTC del servidor). */
function recogidaConHoraZonaRd(
  horaStr: string,
  ref: Date = new Date(),
): Date | null {
  const p = parseHora(horaStr);
  if (!p) return null;
  const day = diaCalendarioRd(ref);
  const hh = String(p.h).padStart(2, "0");
  const mm = String(p.m).padStart(2, "0");
  const d = new Date(`${day}T${hh}:${mm}:00${TZ_RD_OFFSET}`);
  return Number.isFinite(d.getTime()) ? d : null;
}

function fechaRecogidaConHora(base: Date, horaStr: string): Date | null {
  return recogidaConHoraZonaRd(horaStr, base);
}

/** Si la recogida de hoy ya pasó (>5 min), empujar al futuro cercano (prueba / «Enviar ahora»). */
function ajustarRecogidaHoySiYaPaso(
  recogida: Date,
  ref: Date = new Date(),
  minutosFuturo = CORP_ENVIAR_AHORA_OFFSET_MIN,
): Date {
  const diffMin = (recogida.getTime() - ref.getTime()) / 60000;
  if (diffMin < -5) {
    return new Date(ref.getTime() + minutosFuturo * 60000);
  }
  return recogida;
}

/** Minutos de diferencia para cancelar viaje del día y crear otro al cambiar hora. */
const CORPORATIVO_CAMBIO_HORA_MATERIAL_MIN = 5;

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

function viajeCorporativoEnRutaOperativa(v: AnyMap): boolean {
  const e = str(v.estado).toLowerCase();
  return (
    e === "en_curso" ||
    e === "encurso" ||
    e === "a_bordo" ||
    e === "abordo"
  );
}

/** Diferencia en minutos entre dos HH:mm (0–720; cruza medianoche). */
function minutosEntreHorasContrato(a: string, b: string): number {
  const pa = parseHora(a);
  const pb = parseHora(b);
  if (!pa || !pb) return 0;
  const ma = pa.h * 60 + pa.m;
  const mb = pb.h * 60 + pb.m;
  let d = Math.abs(mb - ma);
  if (d > 12 * 60) d = 24 * 60 - d;
  return d;
}

function viajeCorpListoParaAbrirOperacion(
  v: AnyMap | null,
  recogida: Date | null,
  minPub: number,
  ahora: Date,
): boolean {
  if (!v || !recogida) return false;
  if (!viajeCorpReutilizableHoy(v)) return false;
  return viajeListoParaAbrirCorporativo(v, recogida, minPub, ahora);
}

function viajeCorporativoNoIniciado(estado: string): boolean {
  const e = estado.toLowerCase();
  return (
    e === "pendiente" ||
    e === "aceptado" ||
    e === "en_camino_pickup" ||
    e === "pendiente_pago"
  );
}

/** Viaje corporativo activo al que se puede aplicar patch operativo (hora/pasajeros). */
function viajePermitePatchOperativaCorporativa(estado: string): boolean {
  const e = estado.toLowerCase();
  if (
    !e ||
    e === "completado" ||
    e === "finalizado" ||
    e === "cancelado" ||
    e === "rechazado" ||
    e === "cancelado_por_tiempo"
  ) {
    return false;
  }
  return true;
}

function horaOperativaViaje(vData: AnyMap, plantilla: AnyMap): string {
  return horaAlmacenadaEnViaje(vData) || horaContratoEncargadoCorporativo(vData, plantilla);
}

function hoyKey(d: Date): string {
  return diaCalendarioRd(d);
}

function resolverUidEncargadoOperacion(args: {
  empresaData: AnyMap;
  encargadoUid?: string;
  operadorUid?: string;
  choferUid?: string;
}): string {
  const explicit = str(args.encargadoUid);
  if (explicit) return explicit;
  const encargados = Array.isArray(args.empresaData.encargadoUids)
    ? (args.empresaData.encargadoUids as string[]).map(String).filter(Boolean)
    : [];
  if (encargados[0]) return encargados[0];
  const operador = str(args.operadorUid);
  if (operador) return operador;
  return str(args.choferUid);
}

/** Ventana ~90 min antes de la recogida (mismo día calendario RD). */
function ventanaPublicacionCorporativoAbierta(
  plantilla: AnyMap,
  ref: Date = new Date(),
): boolean {
  const horaStr =
    str(plantilla.horaRecogidaGrupo) || str(plantilla.horaRecogida) || "07:00";
  const recogida = recogidaConHoraZonaRd(horaStr, ref);
  if (!recogida || !esMismoDiaCalendarioRd(recogida, ref)) return false;
  const diffMin = (recogida.getTime() - ref.getTime()) / 60000;
  const minPub = minutosPublicarAntesCorporativo(plantilla.minutosPublicarAntes);
  return (
    diffMin <= minPub + CORP_VENTANA_TOLERANCIA_MIN && diffMin >= -120
  );
}

/** ¿Publicar viaje operativo de hoy? (asignación ADM puede forzar recogida hoy). */
function debePublicarHoyOperativa(
  plantilla: AnyMap,
  ref: Date,
  forzarRecogidaHoy: boolean,
): boolean {
  if (plantilla.activa === false) return false;
  const horaStr =
    str(plantilla.horaRecogidaGrupo) || str(plantilla.horaRecogida) || "07:00";
  const recogida = recogidaConHoraZonaRd(horaStr, ref);
  if (!recogida || !esMismoDiaCalendarioRd(recogida, ref)) return false;
  if (forzarRecogidaHoy) return true;
  if (!coincidePatronHoy(plantilla, ref)) return false;
  const feriados = Array.isArray(plantilla.diasPausaFeriado)
    ? (plantilla.diasPausaFeriado as string[]).map(String)
    : [];
  return !feriados.includes(hoyKey(ref));
}

function esMismoDiaCalendarioRd(dt: Date, ref: Date = new Date()): boolean {
  return diaCalendarioRd(dt) === diaCalendarioRd(ref);
}

/** Viaje corporativo operativo de hoy (por fecha del doc o por hora de la plantilla). */
function esViajeCorporativoDelDiaHoy(
  vData: AnyMap,
  plantilla: AnyMap,
  ref: Date = new Date(),
): boolean {
  const fh = vData.fechaHora;
  let dt: Date | null = null;
  if (fh instanceof Timestamp) dt = fh.toDate();
  else if (fh instanceof Date) dt = fh;
  if (dt && esMismoDiaCalendarioRd(dt, ref)) return true;
  const horaStr =
    str(plantilla.horaRecogidaGrupo) || str(plantilla.horaRecogida) || "07:00";
  const recogida = recogidaConHoraZonaRd(horaStr, ref);
  return !!(recogida && esMismoDiaCalendarioRd(recogida, ref));
}

function parseTs(v: unknown): Date | null {
  if (v instanceof Timestamp) return v.toDate();
  if (v instanceof Date) return v;
  if (typeof v === "string") {
    const d = new Date(v);
    return Number.isFinite(d.getTime()) ? d : null;
  }
  return null;
}

/** Servicio contratado con RAI (como giras): sin pool público. */
function empresaContratoVigente(empresaData: AnyMap, now: Date): boolean {
  if (empresaData.activa === false) return false;
  if (empresaData.contratoActivo !== true) return false;
  const hasta = parseTs(empresaData.contratoHasta);
  if (hasta && hasta.getTime() < now.getTime()) return false;
  return true;
}

/** Código único del período de liquidación (mismo todos los días hasta el pago). */
async function resolverCodigoAccesoEmpresa(empresaId: string): Promise<string> {
  const ref = db().collection("empresas_corporativas").doc(empresaId);
  const diasPausa = await obtenerDiasPausaEmpresa(empresaId);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return generarCodigoAccesoPeriodo();
    const ed = snap.data() ?? {};
    const periodo = (ed.periodoActual ?? {}) as AnyMap;
    let codigo = codigoAccesoDesdePeriodo(periodo);
    const cicloDias = Math.max(
      1,
      Math.trunc(Number(ed.facturacionCicloDias) || 15),
    );
    const reparado = repararPeriodoSinRotarCodigo(
      ed,
      cicloDias,
      new Date(),
      diasPausa,
      periodo,
    );
    if (!codigo) {
      codigo = str(reparado.codigoAcceso) || generarCodigoAccesoPeriodo();
      reparado.codigoAcceso = codigo;
    }
    if (
      !codigoAccesoDesdePeriodo(periodo) ||
      str(periodo.modoFin) !== "dias_cobrables"
    ) {
      tx.set(
        ref,
        {
          periodoActual: {
            ...reparado,
            codigoAcceso: codigo,
            actualizadoEn: FieldValue.serverTimestamp(),
          },
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    return codigo;
  });
}

function accionDeepLinkEncargado(type: string): string {
  switch (type) {
    case "corporativo_feriado":
    case "corporativo_feriado_calendario":
    case "corporativo_pausa_total":
      return "gestion";
    case "corporativo_quitar_pasajero":
    case "corporativo_agregar_pasajero":
      return "editor";
    default:
      return "rutas";
  }
}

function deepLinkEncargadoCorporativo(
  empresaId: string,
  plantillaId: string,
  type: string,
): string {
  const params = new URLSearchParams();
  params.set("plantilla", plantillaId);
  params.set("empresa", empresaId);
  const accion = accionDeepLinkEncargado(type);
  if (accion !== "rutas") params.set("accion", accion);
  return `https://flygo-rd.web.app/empresas?${params.toString()}`;
}

async function enviarPushUid(
  uid: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<boolean> {
  const tokSnap = await db().collection("push_tokens").doc(uid).get();
  const raw = tokSnap.data()?.tokens;
  const tokens = Array.isArray(raw)
    ? raw.filter((t): t is string => typeof t === "string" && t.length > 10)
    : [];
  if (tokens.length === 0) return false;

  const payload: Record<string, string> = {
    ...data,
    click_action: "FLUTTER_NOTIFICATION_CLICK",
  };
  if (
    str(data.rol).toLowerCase() === "encargado" &&
    str(data.plantillaId) &&
    str(data.empresaId)
  ) {
    payload.deepLink = deepLinkEncargadoCorporativo(
      str(data.empresaId),
      str(data.plantillaId),
      str(data.type),
    );
  }

  const res = await messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: payload,
    android: { notification: { channelId: ANDROID_CHANNEL, sound: "default" } },
    apns: { payload: { aps: { sound: "default" } } },
  });
  return res.successCount > 0;
}

/** Compat: mismo canal push (chofer o encargado). */
async function enviarPushChofer(
  uid: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<boolean> {
  return enviarPushUid(uid, title, body, data);
}

async function notificarFeriadoSinViaje(args: {
  empresaId: string;
  empresaNombre: string;
  plantillaId: string;
  plantillaNombre: string;
  encargadoUids: string[];
  choferUid: string;
  keyHoy: string;
  nota: string;
  pasajerosActivos?: number;
}): Promise<void> {
  const feriadoKey = `${args.keyHoy}_feriado`;
  const plRef = db()
    .collection("empresas_corporativas")
    .doc(args.empresaId)
    .collection("plantillas_ruta")
    .doc(args.plantillaId);
  const plSnap = await plRef.get();
  if (str(plSnap.data()?.ultimaNotificacionFeriadoKey) === feriadoKey) {
    return;
  }

  const nota = args.nota.trim();
  const causa = nota ? ` (${nota})` : "";
  const n =
    typeof args.pasajerosActivos === "number" ? args.pasajerosActivos : null;
  const titleEnc = "📅 Feriado · no se buscan pasajeros";
  const bodyEnc =
    `${args.empresaNombre} · ${args.plantillaNombre}\n` +
    `Hoy es día feriado/no laborable${causa}. ` +
    `NO se publica el viaje y NO se busca el grupo.`;

  const titleChofer = "📅 Hoy NO hay viaje corporativo";
  const bodyChofer =
    `${args.empresaNombre} · ${args.plantillaNombre}\n` +
    `Hoy no hay ruta (feriado)${causa}. No vayas a buscar pasajeros.` +
    (n != null ? ` Pasajeros en la ruta (otros días): ${n}.` : "");

  const dataBase = {
    type: "corporativo_feriado",
    plantillaId: args.plantillaId,
    empresaId: args.empresaId,
    keyHoy: args.keyHoy,
    seBusca: "no",
  };

  for (const uid of args.encargadoUids) {
    if (!uid) continue;
    try {
      await enviarPushUid(uid, titleEnc, bodyEnc, {
        ...dataBase,
        rol: "encargado",
      });
    } catch (e) {
      logger.warn("push feriado encargado", { uid, e });
    }
  }

  if (args.choferUid) {
    try {
      await enviarPushUid(args.choferUid, titleChofer, bodyChofer, {
        ...dataBase,
        rol: "chofer",
        ...(n != null ? { pasajerosActivos: String(n) } : {}),
      });
    } catch (e) {
      logger.warn("push feriado chofer", { uid: args.choferUid, e });
    }
  }

  await plRef.set(
    {
      ultimaNotificacionFeriadoKey: feriadoKey,
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function fmtCoord(v: number): string {
  return Number(v).toFixed(6);
}

function ordenPasajero(p: AnyMap): number {
  const o = p.orden;
  return typeof o === "number" && o > 0 ? Math.trunc(o) : 999;
}

function coordsValidasCorporativo(lat: unknown, lon: unknown): boolean {
  const la = Number(lat);
  const lo = Number(lon);
  if (!Number.isFinite(la) || !Number.isFinite(lo)) return false;
  if (la < -90 || la > 90 || lo < -180 || lo > 180) return false;
  if (Math.abs(la) < 1e-6 && Math.abs(lo) < 1e-6) return false;
  return true;
}

/** Mismo criterio que `pasajerosActivos` en Dart: activos ordenados por `orden`. */
function pasajerosActivosOrdenados(d: AnyMap): AnyMap[] {
  const raw = Array.isArray(d.pasajeros) ? (d.pasajeros as AnyMap[]) : [];
  return raw
    .filter((p) => p.activo !== false)
    .sort((a, b) => ordenPasajero(a) - ordenPasajero(b));
}

/** Paradas GPS intermedias (todos los pasajeros menos el destino final). */
function armarWaypoints(d: AnyMap): AnyMap[] {
  const activos = pasajerosActivosOrdenados(d).filter((p) =>
    coordsValidasCorporativo(p.lat, p.lon),
  );
  if (activos.length <= 1) return [];
  const wps: AnyMap[] = [];
  for (let i = 0; i < activos.length - 1; i++) {
    const p = activos[i];
    wps.push({
      lat: roundCoord6(Number(p.lat)),
      lon: roundCoord6(Number(p.lon)),
      label: `${str(p.nombre)} · ${str(p.destinoLabel || p.destino)}`,
      orden: i + 1,
      pasajeroId: str(p.id) || null,
    });
  }
  return wps;
}

/** URL Google Maps con origen + waypoints GPS + destino (siempre fresca al publicar). */
function urlGoogleMapsRuta(args: {
  origenLat: number;
  origenLon: number;
  destinoLat: number;
  destinoLon: number;
  paradas: { lat: number; lon: number }[];
}): string {
  const o = `${fmtCoord(args.origenLat)},${fmtCoord(args.origenLon)}`;
  const d = `${fmtCoord(args.destinoLat)},${fmtCoord(args.destinoLon)}`;
  const wp = args.paradas
    .filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon))
    .map((p) => `${fmtCoord(p.lat)},${fmtCoord(p.lon)}`)
    .join("|");
  return (
    "https://www.google.com/maps/dir/?api=1" +
    `&origin=${o}&destination=${d}` +
    (wp ? `&waypoints=${wp}` : "") +
    "&travelmode=driving"
  );
}

function urlWazeOrigen(lat: number, lon: number): string {
  return `https://waze.com/ul?ll=${fmtCoord(lat)},${fmtCoord(lon)}&navigate=yes`;
}

/** Lista ordenada origen → paradas → destino (navegación / map in-app). */
function armarRutaPuntosGps(args: {
  origenLat: number;
  origenLon: number;
  origenLabel: string;
  activos: AnyMap[];
}): AnyMap[] {
  const pts: AnyMap[] = [
    {
      lat: roundCoord6(args.origenLat),
      lon: roundCoord6(args.origenLon),
      label: args.origenLabel || "Recogida",
      rol: "origen",
      orden: 0,
    },
  ];
  args.activos.forEach((p, i) => {
    const isLast = i === args.activos.length - 1;
    pts.push({
      lat: roundCoord6(Number(p.lat)),
      lon: roundCoord6(Number(p.lon)),
      label: `${str(p.nombre)} · ${str(p.destinoLabel || p.destino)}`,
      rol: isLast ? "destino" : "parada",
      orden: i + 1,
      pasajeroId: str(p.id) || null,
    });
  });
  return pts;
}

async function marcarErrorPlantilla(
  empresaId: string,
  plantillaId: string,
  error: string,
): Promise<void> {
  const msg = error.trim().slice(0, 500);
  if (!msg) return;
  const plRef = db()
    .collection("empresas_corporativas")
    .doc(empresaId)
    .collection("plantillas_ruta")
    .doc(plantillaId);
  await plRef.set(
    {
      ultimoErrorPublicacion: msg,
      ultimoErrorPublicacionEn: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  // Alerta Admin (1 por día/plantilla).
  try {
    const plSnap = await plRef.get();
    const plNombre = str(plSnap.data()?.nombre) || plantillaId;
    const empSnap = await db()
      .collection("empresas_corporativas")
      .doc(empresaId)
      .get();
    const empNombre = str(empSnap.data()?.nombre) || empresaId;
    const now = new Date();
    const keyHoy =
      `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-` +
      `${String(now.getDate()).padStart(2, "0")}`;
    const alertaId = `corp_pub_${empresaId}_${plantillaId}_${keyHoy}`;
    await db()
      .collection("admin_alertas")
      .doc(alertaId)
      .set(
        {
          tipo: "corporativo_publicacion",
          titulo: `Corporativo · no publicó · ${empNombre}`,
          mensaje:
            `${empNombre} · ${plNombre}\n${msg}\n` +
            `Asigná chofer o revisá la plantilla en Admin → Empresas corporativas.`,
          severidad: "warning",
          leida: false,
          metadata: {
            empresaId,
            plantillaId,
            plantillaNombre: plNombre,
            empresaNombre: empNombre,
            error: msg,
          },
          createdAt: FieldValue.serverTimestamp(),
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  } catch (e) {
    logger.warn("admin_alerta corporativo publish", { empresaId, plantillaId, e });
  }
}

function alertaSinChoferDocId(empresaId: string, plantillaId: string): string {
  return `corp_sin_chofer_${empresaId}_${plantillaId}`;
}

/** Alerta ADM: plantilla activa guardada sin conductor asignado. */
export async function alertarPlantillaSinChofer(
  empresaId: string,
  plantillaId: string,
  plantilla: AnyMap,
): Promise<void> {
  try {
    const empSnap = await db()
      .collection("empresas_corporativas")
      .doc(empresaId)
      .get();
    const empNombre = str(empSnap.data()?.nombre) || empresaId;
    const plNombre = str(plantilla.nombre) || plantillaId;
    const hora =
      str(plantilla.horaRecogidaGrupo) || str(plantilla.horaRecogida) || "—";
    const pasajeros = Array.isArray(plantilla.pasajeros)
      ? (plantilla.pasajeros as AnyMap[]).filter((p) => p?.activo !== false).length
      : 0;
    await db()
      .collection("admin_alertas")
      .doc(alertaSinChoferDocId(empresaId, plantillaId))
      .set(
        {
          tipo: "corporativo_sin_chofer",
          titulo: `Corporativo · sin chofer · ${empNombre}`,
          mensaje:
            `${empNombre} · ${plNombre}\n` +
            `Recogida ${hora} · ${pasajeros} pasajero(s) activo(s).\n` +
            `El encargado guardó la ruta sin conductor. Asigná chofer en Admin → Empresas corporativas.`,
          severidad: "warning",
          leida: false,
          metadata: {
            empresaId,
            plantillaId,
            plantillaNombre: plNombre,
            empresaNombre: empNombre,
            horaRecogida: hora,
            pasajerosActivos: pasajeros,
          },
          createdAt: FieldValue.serverTimestamp(),
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  } catch (e) {
    logger.warn("admin_alerta corporativo sin chofer", { empresaId, plantillaId, e });
  }
}

/** Quita alerta pendiente cuando ya hay chofer o la plantilla deja de estar activa. */
export async function limpiarAlertaPlantillaSinChofer(
  empresaId: string,
  plantillaId: string,
): Promise<void> {
  try {
    await db()
      .collection("admin_alertas")
      .doc(alertaSinChoferDocId(empresaId, plantillaId))
      .delete();
  } catch (e) {
    logger.warn("limpiar alerta corporativo sin chofer", { empresaId, plantillaId, e });
  }
}

async function limpiarErrorPlantilla(
  empresaId: string,
  plantillaId: string,
): Promise<void> {
  await db()
    .collection("empresas_corporativas")
    .doc(empresaId)
    .collection("plantillas_ruta")
    .doc(plantillaId)
    .set(
      {
        ultimoErrorPublicacion: FieldValue.delete(),
        ultimoErrorPublicacionEn: FieldValue.delete(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}

async function publicarViajeDesdePlantilla(args: {
  empresaId: string;
  plantillaId: string;
  plantilla: AnyMap;
  empresaNombre: string;
  encargadoUid: string;
  fechaRecogida: Date;
  minutosPublicarAntes: number;
  /** Encargado «Enviar ahora»: ventana y promoción inmediatas. */
  publicacionInmediata?: boolean;
}): Promise<string | null> {
  const d = args.plantilla;
  const choferResuelto = await resolverChoferPublicacionCorporativo({
    empresaId: args.empresaId,
    plantillaId: args.plantillaId,
    plantilla: d,
  });
  if (!choferResuelto) {
    const mensaje = await mensajeErrorPublicacionChoferCorporativo({
      empresaId: args.empresaId,
      plantillaId: args.plantillaId,
      plantilla: d,
    });
    await marcarErrorPlantilla(args.empresaId, args.plantillaId, mensaje);
    logger.warn("corporativo publicar sin chofer ADM o con compromiso", {
      empresaId: args.empresaId,
      plantillaId: args.plantillaId,
      preferido: str(d.choferPreferidoUid),
    });
    return null;
  }
  const choferFijo = choferResuelto.uid;
  const conflictosPub = await detectarConflictosHorarioChofer({
    choferUid: choferFijo,
    empresaId: args.empresaId,
    plantillaId: args.plantillaId,
    plantilla: d,
  });
  if (conflictosPub.length > 0) {
    const mensaje = mensajeCompromisoChoferDesdeConflictos(
      conflictosPub,
      choferResuelto.nombre || "El conductor",
    );
    await marcarErrorPlantilla(args.empresaId, args.plantillaId, mensaje);
    logger.warn("corporativo publicar chofer con compromiso horario", {
      empresaId: args.empresaId,
      plantillaId: args.plantillaId,
      choferUid: choferFijo,
      conflictos: conflictosPub.length,
    });
    return null;
  }
  logger.info("corporativo chofer resuelto", {
    empresaId: args.empresaId,
    plantillaId: args.plantillaId,
    modo: choferResuelto.modo,
    choferUid: choferFijo,
  });

  const activos = pasajerosActivosOrdenados(d);
  if (activos.length === 0) return null;

  const origenLat = Number(d.origenLat);
  const origenLon = Number(d.origenLon);
  if (!coordsValidasCorporativo(origenLat, origenLon)) {
    await marcarErrorPlantilla(
      args.empresaId,
      args.plantillaId,
      "Origen sin GPS válido. El encargado debe editar la ruta.",
    );
    return null;
  }
  for (const p of activos) {
    if (!coordsValidasCorporativo(p.lat, p.lon)) {
      await marcarErrorPlantilla(
        args.empresaId,
        args.plantillaId,
        `Pasajero «${str(p.nombre)}» sin GPS de destino. El encargado debe editar la ruta.`,
      );
      return null;
    }
  }
  const ultimo = activos[activos.length - 1];
  const latD = Number(ultimo.lat);
  const lonD = Number(ultimo.lon);

  const waypoints = armarWaypoints(d);
  const paradasGps = waypoints.map((w) => ({
    lat: Number(w.lat),
    lon: Number(w.lon),
  }));
  const mapsUrl =
    urlGoogleMapsRuta({
      origenLat,
      origenLon,
      destinoLat: latD,
      destinoLon: lonD,
      paradas: paradasGps,
    }) || str(d.googleMapsRutaUrl);
  const wazeUrl =
    urlWazeOrigen(origenLat, origenLon) || str(d.wazeOrigenUrl);
  const rutaPuntos = armarRutaPuntosGps({
    origenLat,
    origenLon,
    origenLabel: str(d.origenLabel),
    activos,
  });
  const cfg = await getCorporativoTarifaConfigCached();
  const kmLinea = distanciaKmLineaRectaRuta({
    origenLat,
    origenLon,
    pasajeros: activos.map((p) => ({
      lat: Number(p.lat),
      lon: Number(p.lon),
    })),
    kmMinimoPorTramo: cfg.kmMinimoPorTramo,
  });
  const empSnap = await db()
    .collection("empresas_corporativas")
    .doc(args.empresaId)
    .get();
  const ed = (empSnap.data() ?? {}) as AnyMap;
  const empresaLogoUrl = str(ed.logoUrl) || str(ed.logo);
  const tarifaContratada = Number(ed.tarifaViajeContratadaRd ?? 0);
  const periodoEmpresa = (ed.periodoActual ?? {}) as AnyMap;
  const cicloDiasEmpresa = Math.max(
    1,
    Math.trunc(Number(ed.facturacionCicloDias) || 15),
  );
  const porChoferEmpresa = (periodoEmpresa.porChofer ?? {}) as AnyMap;
  const choferPeriodoPrev = (porChoferEmpresa[choferFijo] ?? {}) as AnyMap;
  const desglose = construirDesgloseTarifaCorporativoViaje({
    kmLineaRecta: kmLinea,
    cfg,
    numParadas: activos.length,
    tarifaContratadaRd: tarifaContratada,
    precioAcordadoPlantillaRd: Number(d.precioAcordado),
  });
  const precio = Math.max(0, Math.round(desglose.precioViajeRd));
  const desgloseMap = desglose as AnyMap;
  const pagoChoferEstimadoRd = pagoChoferEstimadoDesdeDesgloseCorporativo(
    desgloseMap,
    precio,
    cfg,
  );
  const viajeRef = db().collection("viajes").doc();
  const now = Timestamp.now();
  const fechaTs = Timestamp.fromDate(args.fechaRecogida);
  const minPub = Math.max(3, Math.trunc(args.minutosPublicarAntes));
  const ventanas = args.publicacionInmediata === true
    ? {
        publishAt: now,
        acceptAfter: now,
        startWindowAt: fechaTs,
        publicado: true,
      }
    : ventanasPublicacionCorporativo(args.fechaRecogida, minPub);
  const kmCotizados = Number(desglose.kmCotizados ?? kmLinea * cfg.factorKmCarretera);

  const destinoLabel = `${str(ultimo.nombre)} · ${str(ultimo.destinoLabel || ultimo.destino)}`;
  const codigoVerificacion = await resolverCodigoAccesoEmpresa(args.empresaId);

  const trip: AnyMap = {
    id: viajeRef.id,
    uidCliente: args.encargadoUid,
    clienteId: args.encargadoUid,
    uidTaxista: "",
    taxistaId: "",
    origen: str(d.origenLabel),
    destino: destinoLabel,
    latCliente: roundCoord6(origenLat),
    lonCliente: roundCoord6(origenLon),
    latOrigen: roundCoord6(origenLat),
    lonOrigen: roundCoord6(origenLon),
    origenGeoPoint: new GeoPoint(roundCoord6(origenLat), roundCoord6(origenLon)),
    latDestino: roundCoord6(latD),
    lonDestino: roundCoord6(lonD),
    fechaHora: fechaTs,
    acceptAfter: ventanas.acceptAfter,
    publishAt: ventanas.publishAt,
    startWindowAt: ventanas.startWindowAt,
    publicado: ventanas.publicado,
    programado: true,
    esAhora: false,
    metodoPago: "transferencia",
    estado: "pendiente",
    estadoPago: "pendiente",
    precio: precio,
    precio_cents: Math.round(precio * 100),
    distancia_km: kmCotizados,
    extras: {
      distancia_km: kmCotizados,
      distancia_km_linea_recta: kmLinea,
      corporativoTarifaDesglose: desglose,
      corporativo: true,
    },
    tipoServicio: "normal",
    categoria: "corporativo",
    canalAsignacion: CANAL_CORPORATIVO_FIJO,
    corporativo: true,
    recaudoDestino: "empresa_corporativa",
    corporativoEmpresaId: args.empresaId,
    corporativoEmpresaNombre: args.empresaNombre,
    corporativoEmpresaLogoUrl: empresaLogoUrl,
    corporativoClienteNombre: str(d.clienteNombre),
    corporativoReferencia: str(d.referencia),
    corporativoPlantillaId: args.plantillaId,
    corporativoPlantillaNombre: str(d.nombre),
    corporativoPasajeros: activos,
    corporativoEsFijo: d.esFijo === true,
    corporativoOrigenLanzamiento: "automatico_fijo",
    corporativoServicioContratado: true,
    exentoBloqueoPrepago: true,
    corporativoMinutosPublicarAntes: minPub,
    corporativoVentanaPoolMinutos: minPub,
    corporativoPublicadoEn: now,
    codigoVerificacion,
    codigoVerificado: false,
    corporativoCodigoEsPeriodo: true,
    corporativoModoInformativo: d.corporativoModoInformativo !== false,
    corporativoFacturacionCicloDias: cicloDiasEmpresa,
    corporativoPeriodoInicio: periodoEmpresa.inicio ?? null,
    corporativoPeriodoFin: periodoEmpresa.fin ?? null,
    corporativoChoferAcumuladoPeriodoRd: round2(
      Number(choferPeriodoPrev.montoRd ?? 0),
    ),
    corporativoChoferViajesPeriodo: Math.trunc(
      Number(choferPeriodoPrev.viajes ?? 0),
    ),
    corporativoPagoChoferEstimadoRd: pagoChoferEstimadoRd,
    googleMapsRutaUrl: mapsUrl,
    wazeOrigenUrl: wazeUrl,
    corporativoGoogleMapsRutaUrl: mapsUrl,
    corporativoWazeOrigenUrl: wazeUrl,
    rutaPuntos,
    aceptado: false,
    rechazado: false,
    completado: false,
    activo: false,
    ignoradosPor: [],
    reservadoPor: "",
    creadoEn: now,
    createdAt: now,
    updatedAt: now,
    actualizadoEn: now,
  };

  trip.corporativoChoferPreferidoUid =
    str(d.choferPreferidoUid) || choferFijo;
  trip.corporativoChoferAsignacionModo = choferResuelto.modo;
  if (choferResuelto.modo === "respaldo") {
    trip.corporativoChoferRespaldo = true;
    trip.corporativoChoferFijoOriginalUid = str(d.choferPreferidoUid);
  }

  aplicarCamposMultiparadaCorporativo(trip, {
    waypoints,
    activos,
    rutaPuntos,
    mapsUrl,
    wazeUrl,
    desglose,
    kmCotizados,
  });

  await viajeRef.set(trip);

  const asignado = await asignarChoferCorporativoFijo({
    viajeRef,
    choferUid: choferFijo,
    esAhora: args.publicacionInmediata === true || ventanas.publicado,
  });
  if (asignado) {
    try {
      await repararChoferViajeCorporativoSiHaceFalta(viajeRef.id);
    } catch (e) {
      logger.warn("corporativo reparar chofer post-asignar", {
        viajeId: viajeRef.id,
        e,
      });
    }
    try {
      await refrescarChoferOperacionTrasPublicar(
        viajeRef.id,
        str(d.choferPreferidoUid),
      );
    } catch (e) {
      logger.warn("corporativo refrescar chofer_operacion post-publicar", {
        choferUid: choferFijo,
        viajeId: viajeRef.id,
        e,
      });
    }
    if (args.publicacionInmediata === true || ventanas.publicado) {
      try {
        await ejecutarPromoverViajeCorporativoEnCurso({
          choferUid: choferFijo,
          viajeId: viajeRef.id,
        });
      } catch (e) {
        logger.warn("corporativo auto-promover post-publicar", {
          choferUid: choferFijo,
          viajeId: viajeRef.id,
          e,
        });
      }
    }
    const origen = str(d.origenLabel) || "empresa";
    const horaStr = str(d.horaRecogidaGrupo) || str(d.horaRecogida) || "07:00";
    const pasajerosN = activos.length;
    const horaParsed = parseHora(horaStr);
    const turno = !horaParsed
      ? "Ruta"
      : horaParsed.h < 12
        ? "Mañana"
        : horaParsed.h < 17
          ? "Tarde"
          : "Noche";
    const etiquetaModo =
      choferResuelto.modo === "respaldo" ? " (respaldo)" : "";
    await enviarPushChofer(
      choferFijo,
      `🏢 ${turno} ${horaStr} · ruta corporativa${etiquetaModo}`,
      `${args.empresaNombre} · ${str(d.nombre)}\n` +
        `Ve a ${origen} a las ${horaStr} a buscar ${pasajerosN} pasajero(s). ` +
        `Abrí Mis rutas → Waze / Maps.`,
      {
        type: "corporativo_asignado",
        viajeId: viajeRef.id,
        empresaId: args.empresaId,
        plantillaId: args.plantillaId,
        modo: choferResuelto.modo,
      },
    );
  } else {
    await marcarErrorPlantilla(
      args.empresaId,
      args.plantillaId,
      "No se pudo asignar el viaje al chofer corporativo.",
    );
    logger.error("corporativo asignacion chofer fallo", {
      viajeId: viajeRef.id,
      choferFijo,
      modo: choferResuelto.modo,
    });
  }

  await db()
    .collection("usuarios")
    .doc(args.encargadoUid)
    .set(
      {
        siguienteViajeId: viajeRef.id,
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  await db()
    .collection("empresas_corporativas")
    .doc(args.empresaId)
    .collection("historial")
    .doc(viajeRef.id)
    .set({
      viajeId: viajeRef.id,
      plantillaId: args.plantillaId,
      plantillaNombre: str(d.nombre),
      clienteNombre: str(d.clienteNombre),
      referencia: str(d.referencia),
      origenLabel: str(d.origenLabel),
      pasajeros: activos,
      precio,
      fechaRecogida: fechaTs,
      origenLanzamiento: "automatico_fijo",
      estado: "publicado_auto",
      choferUid: choferFijo,
      choferNombre: choferResuelto.nombre,
      choferAsignacionModo: choferResuelto.modo,
      creadoEn: FieldValue.serverTimestamp(),
    });

  await db()
    .collection("empresas_corporativas")
    .doc(args.empresaId)
    .collection("plantillas_ruta")
    .doc(args.plantillaId)
    .set(
      {
        ultimoViajeId: viajeRef.id,
        ultimoErrorPublicacion: FieldValue.delete(),
        ultimoErrorPublicacionEn: FieldValue.delete(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  if (asignado) {
    try {
      await anularViajesObsoletosPlantillaHoy({
        empresaId: args.empresaId,
        plantillaId: args.plantillaId,
        plantilla: d,
        viajeCanonicoId: viajeRef.id,
        operadorUid: args.encargadoUid,
      });
    } catch (e) {
      logger.warn("corporativo anular obsoletos post-publicar", {
        viajeId: viajeRef.id,
        e,
      });
    }
  }

  return asignado ? viajeRef.id : null;
}

export const scheduledCorporativoRutasFijas = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "America/Santo_Domingo",
    memory: "512MiB",
    timeoutSeconds: 180,
  },
  async () => {
    const now = new Date();
    const keyHoy = hoyKey(now);

    let empresasSnap: FirebaseFirestore.QuerySnapshot;
    try {
      empresasSnap = await db()
        .collection("empresas_corporativas")
        .where("activa", "==", true)
        .limit(40)
        .get();
    } catch (e) {
      logger.error("scheduledCorporativoRutasFijas empresas", e);
      return;
    }

    for (const emp of empresasSnap.docs) {
      const empresaId = emp.id;
      const empresaData = emp.data();
      if (!empresaContratoVigente(empresaData, now)) {
        continue;
      }
      const empresaNombre = str(empresaData.nombre) || "Empresa";
      const encargados = Array.isArray(empresaData.encargadoUids)
        ? (empresaData.encargadoUids as string[])
        : [];
      const encargadoUid = encargados[0] ?? "";
      if (!encargadoUid) continue;

      let plantillasSnap: FirebaseFirestore.QuerySnapshot;
      try {
        plantillasSnap = await db()
          .collection("empresas_corporativas")
          .doc(empresaId)
          .collection("plantillas_ruta")
          .where("activa", "==", true)
          .where("esFijo", "==", true)
          .limit(30)
          .get();
      } catch (e) {
        logger.warn("scheduledCorporativoRutasFijas plantillas", { empresaId, e });
        continue;
      }

      for (const plDoc of plantillasSnap.docs) {
        const d = plDoc.data();
        if (!servicioIniciado(d, now)) continue;
        if (!coincidePatronHoy(d, now)) continue;
        const feriados = Array.isArray(d.diasPausaFeriado)
          ? (d.diasPausaFeriado as unknown[]).map((x) => String(x))
          : [];
        const feriadosEmp = Array.isArray(empresaData.diasPausaFeriadoEmpresa)
          ? (empresaData.diasPausaFeriadoEmpresa as string[]).map(String)
          : [];
        const noLabor = esDiaNoLaborableCorporativo({
          keyHoy,
          feriadosPlantilla: feriados,
          feriadosEmpresa: feriadosEmp,
        });
        if (noLabor.pausa && !feriados.includes(keyHoy)) {
          logger.info("scheduledCorporativo skip feriado nacional", {
            plantillaId: plDoc.id,
            keyHoy,
            motivo: noLabor.motivo,
          });
          continue;
        }
        if (feriados.includes(keyHoy)) {
          logger.info("scheduledCorporativo skip feriado", {
            plantillaId: plDoc.id,
            keyHoy,
          });
          const choferUidFeriado = str(d.choferPreferidoUid);
          const nActivosFeriado = Array.isArray(d.pasajeros)
            ? (d.pasajeros as AnyMap[]).filter((p) => p.activo !== false).length
            : 0;
          try {
            await notificarFeriadoSinViaje({
              empresaId,
              empresaNombre,
              plantillaId: plDoc.id,
              plantillaNombre: str(d.nombre) || "Ruta corporativa",
              encargadoUids: encargados.map((u) => String(u)).filter(Boolean),
              choferUid: choferUidFeriado,
              keyHoy,
              nota: str(d.pausaNota),
              pasajerosActivos: nActivosFeriado,
            });
          } catch (e) {
            logger.error("scheduledCorporativo push feriado", {
              plantillaId: plDoc.id,
              e,
            });
          }
          continue;
        }

        const horaStr = str(d.horaRecogidaGrupo) || str(d.horaRecogida) || "07:00";
        const hora = parseHora(horaStr);
        if (!hora) continue;

        const recogida = recogidaConHoraZonaRd(horaStr, now);
        if (!recogida) continue;
        const diffMin = (recogida.getTime() - now.getTime()) / 60000;

        const minPub = typeof d.minutosPublicarAntes === "number"
          ? Math.trunc(d.minutosPublicarAntes as number)
          : 90;
        const minAviso = typeof d.minutosAvisoChofer === "number"
          ? Math.trunc(d.minutosAvisoChofer as number)
          : 40;

        const pubKey = `${keyHoy}_pub`;
        const avisoKey = `${keyHoy}_aviso`;
        // Tras auto-asignación queda en plantilla; si no, el aviso se salta.
        const choferUid = str(d.choferPreferidoUid);

        // Publicación: ventana ±3 min o catch-up hasta ~10 min tras la hora
        // (si el scheduler se atrasó, igual publica una vez al día).
        // Chofer: preferido, auto del pool o respaldo (resolver en publicarViaje).
        if (
          d.publicacionAutomatica !== false &&
          str(d.ultimaPublicacionFijaKey) !== pubKey &&
          diffMin <= minPub + 3 &&
          diffMin >= -10
        ) {
          try {
            const viajeId = await publicarViajeDesdePlantilla({
              empresaId,
              plantillaId: plDoc.id,
              plantilla: d,
              empresaNombre,
              encargadoUid,
              fechaRecogida: recogida,
              minutosPublicarAntes: minPub,
            });
            if (viajeId) {
              await plDoc.ref.set(
                {
                  ultimaPublicacionFijaKey: pubKey,
                  ultimoViajeId: viajeId,
                  ultimoErrorPublicacion: FieldValue.delete(),
                  ultimoErrorPublicacionEn: FieldValue.delete(),
                  ...camposLimpiarRecogidaPerdida(diaCalendarioRdCorp()),
                  actualizadoEn: FieldValue.serverTimestamp(),
                },
                { merge: true },
              );
              try {
                await repararChoferViajeCorporativoSiHaceFalta(viajeId);
              } catch (e) {
                logger.warn("scheduled reparar chofer", { viajeId, e });
              }
              const choferPreferido = str(d.choferPreferidoUid);
              try {
                await refrescarChoferOperacionTrasPublicar(viajeId, choferPreferido);
                const choferOp =
                  (await choferUidDesdeViajeId(viajeId)) || choferPreferido;
                if (choferOp) {
                  await ejecutarPromoverViajeCorporativoEnCurso({
                    choferUid: choferOp,
                    viajeId,
                  });
                }
              } catch (e) {
                logger.warn("scheduled promover chofer corporativo", {
                  viajeId,
                  choferPreferido,
                  e,
                });
              }
              logger.info("scheduledCorporativo publicado", {
                plantillaId: plDoc.id,
                viajeId,
              });
            } else {
              await marcarErrorPlantilla(
                empresaId,
                plDoc.id,
                "No se pudo publicar la ruta automáticamente.",
              );
            }
          } catch (e) {
            const msg = e instanceof Error ? e.message : String(e);
            await marcarErrorPlantilla(empresaId, plDoc.id, msg);
            logger.error("scheduledCorporativo publicar", { plantillaId: plDoc.id, e });
          }
        }

        // Promover cuando abre la ventana corporativa (~90 min antes de recogida).
        const ultimoViajeId = str(d.ultimoViajeId);
        if (
          ultimoViajeId &&
          str(d.ultimaPublicacionFijaKey) === pubKey
        ) {
          try {
            await repararChoferViajeCorporativoSiHaceFalta(ultimoViajeId);
          } catch (e) {
            logger.warn("scheduled reparar ventana corporativo", {
              ultimoViajeId,
              e,
            });
          }
        }

        // Alarma al chofer: ventana ±3 o catch-up hasta la recogida.
        if (
          choferUid &&
          str(d.ultimaNotificacionFijaKey) !== avisoKey &&
          diffMin <= minAviso + 3 &&
          diffMin >= -5
        ) {
          const nombreRuta = str(d.nombre) || "Ruta corporativa";
          const origen = str(d.origenLabel) || "empresa";
          // Preferir URL fresca desde GPS de plantilla (no depender de campo stale).
          let maps = str(d.googleMapsRutaUrl);
          try {
            const activosAviso = Array.isArray(d.pasajeros)
              ? (d.pasajeros as AnyMap[]).filter((p) => p.activo !== false)
              : [];
            if (
              activosAviso.length > 0 &&
              typeof d.origenLat === "number" &&
              typeof d.origenLon === "number"
            ) {
              const ult = activosAviso[activosAviso.length - 1];
              const wpsAviso = armarWaypoints(d);
              maps = urlGoogleMapsRuta({
                origenLat: Number(d.origenLat),
                origenLon: Number(d.origenLon),
                destinoLat: Number(ult.lat),
                destinoLon: Number(ult.lon),
                paradas: wpsAviso.map((w) => ({
                  lat: Number(w.lat),
                  lon: Number(w.lon),
                })),
              });
            }
          } catch {
            /* keep plantilla url */
          }
          const horaTxt =
            `${hora.h.toString().padStart(2, "0")}:${hora.m.toString().padStart(2, "0")}`;
          const turno =
            hora.h < 12 ? "Mañana" : hora.h < 17 ? "Tarde" : "Noche";
          const nPas = Array.isArray(d.pasajeros)
            ? (d.pasajeros as AnyMap[]).filter((p) => p.activo !== false).length
            : 0;
          const title = `⏰ ${turno} ${horaTxt} · ve a buscar el grupo`;
          const body =
            `${empresaNombre} · ${nombreRuta}\n` +
            `Recogida ${horaTxt} en ${origen}` +
            (nPas > 0 ? ` · ${nPas} pasajero(s)` : "") +
            `. Abrí Mis rutas corporativas.`;

          // Viaje ya publicado (~90 min antes): incluir viajeId para deep-link.
          let viajeIdAviso = "";
          try {
            const vSnap = await db()
              .collection("viajes")
              .where("corporativoPlantillaId", "==", plDoc.id)
              .where("uidTaxista", "==", choferUid)
              .limit(8)
              .get();
            for (const vd of vSnap.docs) {
              const vdData = vd.data();
              if (vdData.completado === true) continue;
              const fh = vdData.fechaHora as Timestamp | undefined;
              if (!fh) continue;
              const fhd = fh.toDate();
              const keyV =
                `${fhd.getFullYear()}-${String(fhd.getMonth() + 1).padStart(2, "0")}-${String(fhd.getDate()).padStart(2, "0")}`;
              if (keyV === keyHoy) {
                viajeIdAviso = vd.id;
                break;
              }
            }
          } catch (e) {
            logger.warn("aviso corporativo lookup viaje", { e });
          }

          try {
            const ok = await enviarPushChofer(choferUid, title, body, {
              type: "corporativo_ruta_fija",
              plantillaId: plDoc.id,
              empresaId,
              seBusca: "si",
              ...(viajeIdAviso ? { viajeId: viajeIdAviso } : {}),
              ...(maps ? { mapsUrl: maps } : {}),
            });
            // Encargado: confirmación coherente — hoy SÍ se buscan.
            const titleEnc = "✅ Hoy SÍ se buscan pasajeros";
            const bodyEnc =
              `${empresaNombre} · ${nombreRuta}\n` +
              `Hoy hay viaje. El chofer buscará el grupo a las ${horaTxt}.`;
            for (const uidEnc of encargados) {
              const u = String(uidEnc || "");
              if (!u) continue;
              try {
                await enviarPushUid(u, titleEnc, bodyEnc, {
                  type: "corporativo_ruta_operativa",
                  plantillaId: plDoc.id,
                  empresaId,
                  seBusca: "si",
                  rol: "encargado",
                });
              } catch (e) {
                logger.warn("push operativo encargado", { uid: u, e });
              }
            }
            if (ok) {
              await plDoc.ref.set(
                {
                  ultimaNotificacionFijaKey: avisoKey,
                  actualizadoEn: FieldValue.serverTimestamp(),
                },
                { merge: true },
              );
            }
          } catch (e) {
            logger.error("scheduledCorporativo aviso", { plantillaId: plDoc.id, e });
          }
        }
      }
    }
  },
);

// Compat: nombre anterior exportado
export { scheduledCorporativoRutasFijas as scheduledNotifyCorporativoChoferRutaFija };

async function calcularPrecioOperativaPlantilla(
  empresaId: string,
  d: AnyMap,
  activos: AnyMap[],
  origenLat: number,
  origenLon: number,
): Promise<{ precio: number; desglose: AnyMap; pagoChoferEstimadoRd: number }> {
  const cfg = await getCorporativoTarifaConfigCached();
  const kmLinea = distanciaKmLineaRectaRuta({
    origenLat,
    origenLon,
    pasajeros: activos.map((p) => ({
      lat: Number(p.lat),
      lon: Number(p.lon),
    })),
    kmMinimoPorTramo: cfg.kmMinimoPorTramo,
  });
  const tarifaContratada = Number(
    (await db().collection("empresas_corporativas").doc(empresaId).get()).data()
      ?.tarifaViajeContratadaRd ?? 0,
  );
  const desglose = construirDesgloseTarifaCorporativoViaje({
    kmLineaRecta: kmLinea,
    cfg,
    numParadas: activos.length,
    tarifaContratadaRd: tarifaContratada,
    precioAcordadoPlantillaRd: Number(d.precioAcordado),
  });
  const precio = Math.max(0, Math.round(desglose.precioViajeRd));
  const pagoChoferEstimadoRd = pagoChoferEstimadoDesdeDesgloseCorporativo(
    desglose as AnyMap,
    precio,
    cfg,
  );
  return { precio, desglose, pagoChoferEstimadoRd };
}

async function actualizarAsignacionChoferDesdePlantilla(args: {
  choferUid: string;
  empresaId: string;
  empresaNombre: string;
  plantillaId: string;
  plantilla: AnyMap;
  pasajerosActivos: number;
}): Promise<void> {
  const rutaKey = rutaKeySegura(args.empresaId, args.plantillaId);
  const horaStr = horaEncargadoDesdePlantilla(args.plantilla);
  const choferRef = db()
    .collection("choferes_corporativos")
    .doc(args.choferUid);
  const asignacion = {
    empresaId: args.empresaId,
    empresaNombre: args.empresaNombre,
    plantillaId: args.plantillaId,
    plantillaNombre: str(args.plantilla.nombre) || "Ruta corporativa",
    hora: horaStr,
    pasajerosActivos: args.pasajerosActivos,
    origenLabel: str(args.plantilla.origenLabel),
    precioAcordado: Number(args.plantilla.precioAcordado ?? 0),
    actualizadoEn: FieldValue.serverTimestamp(),
  };
  await choferRef.set(
    {
      [`asignacionesRutas.${rutaKey}`]: asignacion,
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function choferOperativoDesdeViaje(v: AnyMap | null | undefined): string {
  if (!v) return "";
  return (
    str(v.uidTaxista) ||
    str(v.taxistaId) ||
    str(v.corporativoChoferAsignadoUid) ||
    ""
  );
}

function esViajeCorporativoPanel(v: AnyMap): boolean {
  return (
    v.corporativo === true ||
    str(v.canalAsignacion) === CANAL_CORPORATIVO_FIJO ||
    str(v.categoria).toLowerCase() === "corporativo" ||
    str(v.recaudoDestino) === "empresa_corporativa"
  );
}

async function nombreEmpresaCorporativaCached(
  empresaId: string,
  empCache: Map<string, string>,
  empDataCache: Map<string, AnyMap>,
): Promise<string> {
  const cached = empCache.get(empresaId);
  if (cached) return cached;
  let empresaNombre = empresaId;
  try {
    const eSnap = await db()
      .collection("empresas_corporativas")
      .doc(empresaId)
      .get();
    const ed = (eSnap.data() ?? {}) as AnyMap;
    empresaNombre = str(ed.nombre) || empresaId;
    empDataCache.set(empresaId, ed);
  } catch {
    empresaNombre = empresaId;
  }
  empCache.set(empresaId, empresaNombre);
  return empresaNombre;
}

function preferirRutaFijaCorporativa(a: AnyMap, b: AnyMap): AnyMap {
  const score = (r: AnyMap): number => {
    let s = 0;
    if (str(r.hora).length > 0) s += 8;
    if (str(r.viajeHoyId).length > 0) s += 4;
    if (r.listoParaAbrir === true) s += 2;
    return s;
  };
  const sa = score(a);
  const sb = score(b);
  const mejor = sa >= sb ? a : b;
  const otro = sa >= sb ? b : a;
  const merged: AnyMap = { ...otro, ...mejor };
  const hora = str(merged.hora);
  if (hora.length > 0) merged.hora = hora;
  return merged;
}

/** Una fila por plantilla en chofer_operacion (evita duplicados tras cambio de hora). */
function dedupeRutasFijasPorPlantilla(rutas: AnyMap[]): AnyMap[] {
  const byKey = new Map<string, AnyMap>();
  for (const r of rutas) {
    const empresaId = str(r.empresaId);
    const plantillaId = str(r.plantillaId);
    if (!empresaId || !plantillaId) continue;
    const key = rutaKeySegura(empresaId, plantillaId);
    const prev = byKey.get(key);
    byKey.set(key, prev ? preferirRutaFijaCorporativa(prev, r) : r);
  }
  return [...byKey.values()];
}

/** Una fila de rutasFijas + viajesHoy para chofer_operacion/{uid}. */
async function pushEntradaOperacionChofer(args: {
  choferUid: string;
  empresaId: string;
  plantillaId: string;
  plantilla: AnyMap;
  viajeHoyIdInicial: string;
  vDataInicial: AnyMap | null;
  ahora: Date;
  empCache: Map<string, string>;
  empDataCache: Map<string, AnyMap>;
  rutasFijas: AnyMap[];
  viajesHoy: AnyMap[];
  viajeIdsVistos: Set<string>;
  rutasKeysVistas: Set<string>;
}): Promise<void> {
  const uid = str(args.choferUid);
  const empresaId = str(args.empresaId);
  const plantillaId = str(args.plantillaId);
  if (!uid || !empresaId || !plantillaId) return;

  const d = args.plantilla;
  let viajeHoyId = str(args.viajeHoyIdInicial);
  let vData = args.vDataInicial;

  if (vData) {
    const asignado = choferOperativoDesdeViaje(vData);
    if (asignado && asignado !== uid) {
      viajeHoyId = "";
      vData = null;
    }
  }

  const pasajerosRaw = Array.isArray(d.pasajeros) ? (d.pasajeros as AnyMap[]) : [];
  let pasajerosActivos = pasajerosRaw.filter((p) => p?.activo !== false).length;

  const completadoHoy =
    vData?.completado === true &&
    viajeHoyId !== "" &&
    esViajeCorporativoDelDiaHoy(vData!, d, args.ahora);
  let viajeHoyIdActivo =
    completadoHoy || !vData || !viajeCorpReutilizableHoy(vData) ? "" : viajeHoyId;
  pasajerosActivos = pasajerosActivosOperativos(vData, pasajerosActivos);

  const recogidaOp = recogidaOperativaDesdeViajeOPlantilla({
    vData,
    plantilla: d,
    ahora: args.ahora,
  });
  const hora = horaEncargadoDesdePlantilla(d);
  const recogida =
    recogidaOp.recogida ?? recogidaConHoraZonaRd(hora, args.ahora);
  const minPub =
    typeof d.minutosPublicarAntes === "number"
      ? Math.max(3, Math.trunc(d.minutosPublicarAntes as number))
      : 90;
  const ventanas = recogida
    ? ventanasPublicacionCorporativo(recogida, minPub)
    : null;
  let puedeAbrirEn = ventanas?.publishAt ?? null;
  if (vData) {
    const pub = vData.publishAt ?? vData.acceptAfter ?? vData.startWindowAt;
    if (pub instanceof Timestamp && pub.toDate().getTime() <= args.ahora.getTime()) {
      puedeAbrirEn = pub;
    }
    if (vData.publicado === true || vData.corporativoPublicadoEn) {
      puedeAbrirEn = Timestamp.fromDate(args.ahora);
    }
  }

  const empresaNombre = await nombreEmpresaCorporativaCached(
    empresaId,
    args.empCache,
    args.empDataCache,
  );

  const keyDiaOperacion = diaCalendarioRdCorp(args.ahora);
  const recogidaPerdidaHoy =
    !completadoHoy &&
    evaluarRecogidaPerdidaCorporativa({
      plantilla: d,
      vData,
      recogida,
      ahora: args.ahora,
      keyDia: keyDiaOperacion,
    });

  let estadoOperacion = completadoHoy
    ? "completado"
    : estadoOperacionRutaCorporativa(vData, viajeHoyIdActivo);
  let listoParaAbrir = completadoHoy
    ? false
    : viajeCorpListoParaAbrirOperacion(vData, recogida, minPub, args.ahora);
  let mensajeChofer = completadoHoy
    ? "Ruta de hoy cerrada ✓ El viaje quedó en tu historial. " +
      "Mañana se publica el nuevo ~90 min antes de la recogida."
    : mensajeOperacionRutaCorporativa({
        estado: estadoOperacion,
        hora,
        recogida,
        puedeAbrirEn: puedeAbrirEn?.toDate() ?? null,
        listoParaAbrir,
        ahora: args.ahora,
        empresaNombre,
        plantillaNombre: str(d.nombre) || "Ruta",
      });

  if (recogidaPerdidaHoy) {
    estadoOperacion = "recogida_perdida";
    listoParaAbrir = false;
    viajeHoyIdActivo = "";
    mensajeChofer = mensajeChoferRecogidaPerdida(hora);
  }

  const rutaKey = rutaKeySegura(empresaId, plantillaId);
  const rutaEntry: AnyMap = {
    empresaId,
    empresaNombre,
    plantillaId,
    plantillaNombre: str(d.nombre) || "Ruta corporativa",
    hora,
    pasajerosActivos,
    origenLabel: str(d.origenLabel),
    precioAcordado: Number(d.precioAcordado ?? 0),
    precioViaje: vData ? Number(vData.precio ?? 0) : 0,
    viajeHoyId: viajeHoyIdActivo,
    viajeCompletadoId: completadoHoy ? viajeHoyId : "",
    completadoHoy,
    recogidaPerdidaHoy,
    estadoOperacion,
    listoParaAbrir,
    mensajeChofer,
    puedeAbrirEn: puedeAbrirEn ?? null,
    recogidaEn: recogida ? Timestamp.fromDate(recogida) : null,
    _key: rutaKey,
  };

  const idx = args.rutasFijas.findIndex((r) => str(r._key) === rutaKey);
  if (idx >= 0) {
    args.rutasFijas[idx] = {
      ...(args.rutasFijas[idx] as AnyMap),
      ...rutaEntry,
    };
  } else if (!args.rutasKeysVistas.has(rutaKey)) {
    args.rutasKeysVistas.add(rutaKey);
    args.rutasFijas.push(rutaEntry);
  }

  if (viajeHoyIdActivo && vData) {
    const enPoolTrabajo =
      listoParaAbrir || estadoOperacion === "en_curso";
    if (!enPoolTrabajo) {
      return;
    }

    // Una sola fila por plantilla: reemplazar viaje anterior si el encargado actualizó.
    for (let i = args.viajesHoy.length - 1; i >= 0; i--) {
      const row = args.viajesHoy[i] as AnyMap;
      if (
        str(row.empresaId) === empresaId &&
        str(row.plantillaId) === plantillaId &&
        str(row.viajeId) !== viajeHoyIdActivo
      ) {
        const oldId = str(row.viajeId);
        if (oldId) args.viajeIdsVistos.delete(oldId);
        args.viajesHoy.splice(i, 1);
      }
    }

    const entradaViaje: AnyMap = {
      viajeId: viajeHoyIdActivo,
      empresaId,
      empresaNombre,
      plantillaId,
      plantillaNombre: str(d.nombre) || "Ruta corporativa",
      estado: str(vData.estado) || "pendiente",
      estadoOperacion,
      listoParaAbrir,
      fechaHora: vData.fechaHora instanceof Timestamp ? vData.fechaHora : null,
      origen: str(vData.origen),
      precio: Number(vData.precio ?? 0),
      pasajerosActivos,
    };
    const idxViaje = args.viajesHoy.findIndex(
      (v) =>
        str(v.empresaId) === empresaId &&
        str(v.plantillaId) === plantillaId,
    );
    if (idxViaje >= 0) {
      args.viajesHoy[idxViaje] = { ...(args.viajesHoy[idxViaje] as AnyMap), ...entradaViaje };
    } else {
      args.viajeIdsVistos.add(viajeHoyIdActivo);
      args.viajesHoy.push(entradaViaje);
    }
  }
}

/** Viajes corporativos de hoy asignados al chofer (respaldo/auto ≠ choferPreferidoUid). */
async function incorporarViajesCorporativosAsignadosHoy(args: {
  choferUid: string;
  ahora: Date;
  empCache: Map<string, string>;
  empDataCache: Map<string, AnyMap>;
  rutasFijas: AnyMap[];
  viajesHoy: AnyMap[];
  viajeIdsVistos: Set<string>;
  rutasKeysVistas: Set<string>;
}): Promise<void> {
  const uid = str(args.choferUid);
  if (!uid) return;
  let viajesSnap;
  try {
    viajesSnap = await db()
      .collection("viajes")
      .where("uidTaxista", "==", uid)
      .limit(40)
      .get();
  } catch (e) {
    logger.warn("chofer_operacion viajes uidTaxista", { uid, e });
    return;
  }

  for (const vd of viajesSnap.docs) {
    const vData = (vd.data() ?? {}) as AnyMap;
    if (!esViajeCorporativoPanel(vData)) continue;
    if (str(vData.corporativoSupersedidoPor).length > 0) continue;
    if (!choferOperativoDesdeViaje(vData) || choferOperativoDesdeViaje(vData) !== uid) {
      continue;
    }
    const viajeHoyId = vd.id;
    if (args.viajeIdsVistos.has(viajeHoyId)) continue;

    const empresaId = str(vData.corporativoEmpresaId);
    const plantillaId = str(vData.corporativoPlantillaId);
    if (!empresaId || !plantillaId) continue;

    let plantilla: AnyMap = {};
    try {
      const plSnap = await db()
        .collection("empresas_corporativas")
        .doc(empresaId)
        .collection("plantillas_ruta")
        .doc(plantillaId)
        .get();
      if (plSnap.exists) plantilla = (plSnap.data() ?? {}) as AnyMap;
    } catch (e) {
      logger.warn("chofer_operacion plantilla desde viaje", { plantillaId, e });
    }

    if (!esViajeCorporativoDelDiaHoy(vData, plantilla, args.ahora)) continue;
    if (!viajeCorpReutilizableHoy(vData)) continue;

    const ultimoId = str(plantilla.ultimoViajeId);
    if (ultimoId && viajeHoyId !== ultimoId) continue;

    await pushEntradaOperacionChofer({
      choferUid: uid,
      empresaId,
      plantillaId,
      plantilla,
      viajeHoyIdInicial: viajeHoyId,
      vDataInicial: vData,
      ahora: args.ahora,
      empCache: args.empCache,
      empDataCache: args.empDataCache,
      rutasFijas: args.rutasFijas,
      viajesHoy: args.viajesHoy,
      viajeIdsVistos: args.viajeIdsVistos,
      rutasKeysVistas: args.rutasKeysVistas,
    });
  }
}

async function choferUidDesdeViajeId(viajeId: string): Promise<string> {
  const id = str(viajeId);
  if (!id) return "";
  try {
    const vSnap = await db().collection("viajes").doc(id).get();
    if (!vSnap.exists) return "";
    return choferOperativoDesdeViaje((vSnap.data() ?? {}) as AnyMap);
  } catch {
    return "";
  }
}

/** Refresca panel del chofer real y limpia al preferido si cambió (respaldo/auto). */
export async function refrescarChoferOperacionTrasPublicar(
  viajeId: string,
  choferPreferidoUid?: string,
): Promise<void> {
  const asignado = await choferUidDesdeViajeId(viajeId);
  const preferido = str(choferPreferidoUid);
  if (asignado) {
    await refrescarChoferOperacionCorporativa(asignado);
    if (preferido && preferido !== asignado) {
      await refrescarChoferOperacionCorporativa(preferido);
    }
    return;
  }
  if (preferido) {
    await refrescarChoferOperacionCorporativa(preferido);
  }
}

/** Espejo + panel único del chofer (`chofer_operacion/{uid}`). */
export async function refrescarChoferOperacionCorporativa(
  choferUid: string,
): Promise<void> {
  const uid = str(choferUid);
  if (!uid) return;
  try {
    // Solo choferPreferidoUid (índice simple). Filtrar activa en memoria:
    // el compound activa+choferPreferidoUid a veces falta en prod y dejaba
    // chofer_operacion vacío → chofer sin Abrir ruta / auto-abrir.
    const snap = await db()
      .collectionGroup("plantillas_ruta")
      .where("choferPreferidoUid", "==", uid)
      .limit(40)
      .get();
    const ahora = new Date();
    const keyHoy = `${hoyKey(ahora)}_pub`;
    const empCache = new Map<string, string>();
    const empDataCache = new Map<string, AnyMap>();
    const rutasFijas: AnyMap[] = [];
    const viajesHoy: AnyMap[] = [];
    const viajeIdsVistos = new Set<string>();
    const rutasKeysVistas = new Set<string>();

    for (const plDoc of snap.docs) {
      const d = (plDoc.data() ?? {}) as AnyMap;
      if (d.activa === false) continue;
      const empresaId = str(plDoc.ref.parent.parent?.id) || str(d.empresaId);
      const plantillaId = plDoc.id;
      if (!empresaId || !plantillaId) continue;

      let empresaActiva = true;
      try {
        const eSnap = await db()
          .collection("empresas_corporativas")
          .doc(empresaId)
          .get();
        if (!eSnap.exists || eSnap.data()?.activa === false) {
          empresaActiva = false;
        } else {
          empDataCache.set(empresaId, (eSnap.data() ?? {}) as AnyMap);
        }
      } catch (e) {
        logger.warn("chofer_operacion empresa", { empresaId, e });
      }
      if (!empresaActiva) continue;

      let viajeHoyId = "";
      const ultimoId = str(d.ultimoViajeId);
      if (ultimoId) {
        try {
          const vSnap = await db().collection("viajes").doc(ultimoId).get();
          if (vSnap.exists) {
            const v = (vSnap.data() ?? {}) as AnyMap;
            if (
              v.completado === true &&
              esViajeCorporativoDelDiaHoy(v, d, ahora)
            ) {
              viajeHoyId = ultimoId;
            } else if (
              v.completado !== true &&
              esViajeCorporativoDelDiaHoy(v, d, ahora) &&
              viajeCorpReutilizableHoy(v)
            ) {
              viajeHoyId = ultimoId;
            }
          }
        } catch (e) {
          logger.warn("chofer_operacion ultimoViajeId", { plantillaId, e });
        }
      }
      if (!viajeHoyId && str(d.ultimaPublicacionFijaKey) === keyHoy && ultimoId) {
        try {
          const vSnap = await db().collection("viajes").doc(ultimoId).get();
          if (vSnap.exists) {
            const v = (vSnap.data() ?? {}) as AnyMap;
            if (viajeCorpReutilizableHoy(v)) {
              viajeHoyId = ultimoId;
            }
          }
        } catch (e) {
          logger.warn("chofer_operacion ultimaPublicacionFijaKey", {
            plantillaId,
            e,
          });
        }
      }
      if (!viajeHoyId) {
        try {
          const vq = await db()
            .collection("viajes")
            .where("corporativoPlantillaId", "==", plantillaId)
            .where("corporativoEmpresaId", "==", empresaId)
            .limit(6)
            .get();
          for (const vd of vq.docs) {
            const v = (vd.data() ?? {}) as AnyMap;
            if (v.completado === true) continue;
            if (!viajeCorpReutilizableHoy(v)) continue;
            if (!esViajeCorporativoDelDiaHoy(v, d, ahora)) continue;
            viajeHoyId = vd.id;
            break;
          }
        } catch (e) {
          logger.warn("chofer_operacion buscar viaje hoy", { plantillaId, e });
        }
      }

      let vData: AnyMap | null = null;
      if (viajeHoyId) {
        try {
          const vSnap = await db().collection("viajes").doc(viajeHoyId).get();
          if (vSnap.exists) vData = (vSnap.data() ?? {}) as AnyMap;
        } catch (_) {
          vData = null;
        }
      }

      await pushEntradaOperacionChofer({
        choferUid: uid,
        empresaId,
        plantillaId,
        plantilla: d,
        viajeHoyIdInicial: viajeHoyId,
        vDataInicial: vData,
        ahora,
        empCache,
        empDataCache,
        rutasFijas,
        viajesHoy,
        viajeIdsVistos,
        rutasKeysVistas,
      });
    }

    await incorporarViajesCorporativosAsignadosHoy({
      choferUid: uid,
      ahora,
      empCache,
      empDataCache,
      rutasFijas,
      viajesHoy,
      viajeIdsVistos,
      rutasKeysVistas,
    });

    const rutasFijasUnicas = dedupeRutasFijasPorPlantilla(rutasFijas);
    rutasFijasUnicas.sort((a, b) => str(a.hora).localeCompare(str(b.hora)));
    viajesHoy.sort((a, b) => {
      const ta =
        a.fechaHora instanceof Timestamp ? a.fechaHora.toMillis() : 0;
      const tb =
        b.fechaHora instanceof Timestamp ? b.fechaHora.toMillis() : 0;
      return ta - tb;
    });

    const viajesPublicados = viajesHoy.filter(
      (v) => str(v.estadoOperacion) !== "completado",
    ).length;
    const enCurso = viajesHoy.filter(
      (v) => str(v.estadoOperacion) === "en_curso",
    ).length;
    const siguienteHora =
      rutasFijasUnicas.length > 0 ? str(rutasFijasUnicas[0].hora) : "";

    let mensajeGeneral = "Sin rutas corporativas amarradas.";
    if (rutasFijasUnicas.length > 0 && viajesPublicados === 0) {
      mensajeGeneral =
        `Tenés ${rutasFijasUnicas.length} ruta(s) fija(s). ` +
        "El viaje del día se publica ~90 min antes de la recogida.";
    } else if (viajesPublicados > 0) {
      mensajeGeneral =
        enCurso > 0
          ? `${enCurso} ruta(s) en curso · ${viajesPublicados} publicada(s) hoy.`
          : `${viajesPublicados} viaje(s) publicado(s) hoy. Abrí la ruta cuando esté lista.`;
    }

    const resumenPagoEmpresas: AnyMap = {};
    for (const [empresaId, ed] of empDataCache.entries()) {
      const periodo = (ed.periodoActual ?? {}) as AnyMap;
      const porChofer = (periodo.porChofer ?? {}) as AnyMap;
      const choferRow = (porChofer[uid] ?? {}) as AnyMap;
      resumenPagoEmpresas[empresaId] = {
        empresaNombre: str(ed.nombre) || empresaId,
        acumuladoRd: round2(Number(choferRow.montoRd ?? 0)),
        viajesCount: Math.trunc(Number(choferRow.viajes ?? 0)),
        periodoInicio: periodo.inicio ?? null,
        periodoFin: periodo.fin ?? null,
        cicloDias: Math.max(1, Math.trunc(Number(ed.facturacionCicloDias) || 15)),
      };
    }

    const operacionPayload: AnyMap = {
      schemaVersion: 2,
      choferUid: uid,
      rutasFijas: rutasFijasUnicas,
      viajesHoy,
      rutasActivasLista: rutasFijasUnicas,
      resumenPagoEmpresas,
      resumen: {
        totalRutas: rutasFijasUnicas.length,
        viajesPublicadosHoy: viajesPublicados,
        rutasEnCurso: enCurso,
        siguienteHora,
      },
      mensajeGeneral,
      actualizadoEn: FieldValue.serverTimestamp(),
    };

    const batch = db().batch();
    const opRef = db().collection("chofer_operacion").doc(uid);
    const choferRef = db().collection("choferes_corporativos").doc(uid);
    batch.set(opRef, operacionPayload, { merge: true });
    batch.set(
      choferRef,
      {
        rutasActivasLista: rutasFijasUnicas,
        rutasActivasActualizadoEn: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await batch.commit();
  } catch (e) {
    logger.warn("refrescarChoferOperacionCorporativa", { choferUid: uid, e });
  }
}

/** @deprecated alias — usar refrescarChoferOperacionCorporativa */
export async function refrescarEspejoRutasChofer(
  choferUid: string,
): Promise<void> {
  return refrescarChoferOperacionCorporativa(choferUid);
}

function estadoOperacionRutaCorporativa(
  v: AnyMap | null,
  viajeHoyId: string,
): string {
  if (!viajeHoyId || !v) return "amarrado";
  if (v.completado === true) return "completado";
  const e = str(v.estado).toLowerCase();
  if (
    e === "completado" ||
    e === "finalizado" ||
    e === "cancelado" ||
    e === "rechazado" ||
    e === "cancelado_por_tiempo"
  ) {
    return e === "cancelado" ||
      e === "rechazado" ||
      e === "cancelado_por_tiempo"
      ? "cancelado"
      : "completado";
  }
  if (
    e === "en_camino_pickup" ||
    e === "a_bordo" ||
    e === "en_curso" ||
    e === "en_origen_esperando_codigo" ||
    e === "pendiente_codigo" ||
    e === "esperando_codigo_encargado"
  ) {
    return "en_curso";
  }
  return "publicado";
}

function viajeListoParaAbrirCorporativo(
  v: AnyMap | null,
  recogida: Date | null,
  minPub: number,
  ahora: Date,
): boolean {
  if (!v || !recogida) return false;
  const diffMin = (recogida.getTime() - ahora.getTime()) / 60000;
  const ventanaMin = Math.min(Math.max(minPub + 10, 20), 180);
  if (diffMin <= ventanaMin && diffMin >= -90) return true;
  // «Enviar ahora»: viaje ya publicado hoy con recogida del día.
  const publicadoHoy =
    v.publicado === true || v.corporativoPublicadoEn != null;
  if (
    publicadoHoy &&
    esMismoDiaCalendarioRd(recogida, ahora) &&
    diffMin <= 180 &&
    diffMin >= -120
  ) {
    return true;
  }
  const pub = v.publishAt ?? v.acceptAfter ?? v.startWindowAt;
  if (pub instanceof Timestamp && pub.toDate().getTime() <= ahora.getTime()) {
    return true;
  }
  return (
    esMismoDiaCalendarioRd(recogida, ahora) && diffMin <= ventanaMin
  );
}

function mensajeOperacionRutaCorporativa(args: {
  estado: string;
  hora: string;
  recogida: Date | null;
  puedeAbrirEn: Date | null;
  listoParaAbrir: boolean;
  ahora: Date;
  empresaNombre: string;
  plantillaNombre: string;
}): string {
  if (args.estado === "recogida_perdida") {
    return mensajeChoferRecogidaPerdida(args.hora);
  }
  if (args.estado === "en_curso") {
    return "Ruta en curso. Tocá Abrir ruta para continuar.";
  }
  if (args.estado === "completado") {
    return "Ruta de hoy completada.";
  }
  if (args.recogida) {
    const diffMin = (args.recogida.getTime() - args.ahora.getTime()) / 60000;
    if (diffMin < -25 && !args.listoParaAbrir && args.estado === "amarrado") {
      return (
        `La recogida de las ${args.hora} ya pasó y el viaje no se inició. ` +
        `RAI está registrando la incidencia.`
      );
    }
  }
  if (args.listoParaAbrir) {
    return `Listo para abrir · recogida ${args.hora}.`;
  }
  if (args.recogida) {
    const diffMin =
      (args.recogida.getTime() - args.ahora.getTime()) / 60000;
    if (diffMin < -180 && !args.listoParaAbrir && args.estado === "amarrado") {
      return (
        `Ruta amarrada · recogida ${args.hora}. ` +
        `El viaje de hoy aún no está publicado; mañana se abre ~90 min antes.`
      );
    }
  }
  if (args.puedeAbrirEn && args.ahora < args.puedeAbrirEn) {
    const min = Math.max(
      1,
      Math.ceil((args.puedeAbrirEn.getTime() - args.ahora.getTime()) / 60000),
    );
    if (min <= 180) {
      return `Se abre en ~${min} min (recogida ${args.hora}).`;
    }
  }
  if (args.recogida) {
    const diffMin = (args.recogida.getTime() - args.ahora.getTime()) / 60000;
    if (diffMin > 90) {
      return `Ruta amarrada · recogida ${args.hora}. Se publica ~90 min antes.`;
    }
  }
  return `Ruta amarrada · recogida ${args.hora}.`;
}

async function patchViajeOperativaDesdePlantilla(args: {
  viajeId: string;
  vData: AnyMap;
  empresaId: string;
  plantilla: AnyMap;
  empRef: DocumentReference;
}): Promise<boolean> {
  const estado = str(args.vData.estado);
  if (!viajePermitePatchOperativaCorporativa(estado)) {
    return false;
  }

  const d = args.plantilla;
  const activos = pasajerosActivosOrdenados(d);
  if (activos.length === 0) return false;

  const origenLat = Number(d.origenLat);
  const origenLon = Number(d.origenLon);
  const ultimo = activos[activos.length - 1];
  const latD = Number(ultimo.lat);
  const lonD = Number(ultimo.lon);
  if (
    !coordsValidasCorporativo(origenLat, origenLon) ||
    !coordsValidasCorporativo(latD, lonD) ||
    activos.some((p) => !coordsValidasCorporativo(p.lat, p.lon))
  ) {
    return false;
  }

  const horaStr = str(d.horaRecogidaGrupo) || str(d.horaRecogida) || "07:00";
  const rawFecha = recogidaConHoraZonaRd(horaStr, new Date());
  if (!rawFecha) return false;
  const nuevaFecha = ajustarRecogidaHoySiYaPaso(rawFecha);
  const diffMin = (nuevaFecha.getTime() - Date.now()) / 60000;
  const minPubVentana = minutosPublicarAntesCorporativo(d.minutosPublicarAntes);
  const ventanas = ventanasPublicacionCorporativo(nuevaFecha, minPubVentana);
  if (diffMin <= 120) {
    ventanas.publicado = true;
  }
  const waypoints = armarWaypoints(d);
  const paradasGps = waypoints.map((w) => ({
    lat: Number(w.lat),
    lon: Number(w.lon),
  }));
  const mapsUrl =
    urlGoogleMapsRuta({
      origenLat,
      origenLon,
      destinoLat: latD,
      destinoLon: lonD,
      paradas: paradasGps,
    }) || str(d.googleMapsRutaUrl);
  const wazeUrl = urlWazeOrigen(origenLat, origenLon) || str(d.wazeOrigenUrl);
  const rutaPuntos = armarRutaPuntosGps({
    origenLat,
    origenLon,
    origenLabel: str(d.origenLabel),
    activos,
  });
  const { precio, desglose, pagoChoferEstimadoRd } = await calcularPrecioOperativaPlantilla(
    args.empresaId,
    d,
    activos,
    origenLat,
    origenLon,
  );
  const empSnap = await args.empRef.get();
  const empData = (empSnap.data() ?? {}) as AnyMap;
  const empresaNombre =
    str(empData.nombre) || str(empData.nombreComercial) || args.empresaId;
  const minPub =
    typeof args.vData.corporativoMinutosPublicarAntes === "number"
      ? Math.max(3, Math.trunc(args.vData.corporativoMinutosPublicarAntes as number))
      : typeof d.minutosPublicarAntes === "number"
        ? Math.max(3, Math.trunc(d.minutosPublicarAntes as number))
        : 90;
  const destinoLabel = `${str(ultimo.nombre)} · ${str(ultimo.destinoLabel || ultimo.destino)}`;
  const choferUid = str(d.choferPreferidoUid);
  const kmCotizados = Number(desglose.kmCotizados ?? 0);

  const patch: AnyMap = {
    origen: str(d.origenLabel),
    destino: destinoLabel,
    latCliente: roundCoord6(origenLat),
    lonCliente: roundCoord6(origenLon),
    latOrigen: roundCoord6(origenLat),
    lonOrigen: roundCoord6(origenLon),
    origenGeoPoint: new GeoPoint(roundCoord6(origenLat), roundCoord6(origenLon)),
    latDestino: roundCoord6(latD),
    lonDestino: roundCoord6(lonD),
    fechaHora: Timestamp.fromDate(nuevaFecha),
    acceptAfter: ventanas.acceptAfter,
    publishAt: ventanas.publishAt,
    startWindowAt: ventanas.startWindowAt,
    publicado: ventanas.publicado,
    precio,
    precio_cents: Math.round(precio * 100),
    corporativoPagoChoferEstimadoRd: pagoChoferEstimadoRd,
    distancia_km: kmCotizados,
    corporativoPasajeros: activos,
    corporativoPlantillaNombre: str(d.nombre) || "Ruta corporativa",
    corporativoEmpresaId: args.empresaId,
    corporativoEmpresaNombre: empresaNombre,
    corporativoHoraRecogidaGrupo: horaStr,
    corporativoHoraActualizadaEn: FieldValue.serverTimestamp(),
    corporativoModoInformativo: d.corporativoModoInformativo !== false,
    corporativoVentanaPoolMinutos: minPub,
    googleMapsRutaUrl: mapsUrl,
    wazeOrigenUrl: wazeUrl,
    corporativoGoogleMapsRutaUrl: mapsUrl,
    corporativoWazeOrigenUrl: wazeUrl,
    rutaPuntos,
    corporativoPlantillaSincronizadaEn: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    actualizadoEn: FieldValue.serverTimestamp(),
  };
  if (diffMin <= 120 && !args.vData.corporativoPublicadoEn) {
    patch.corporativoPublicadoEn = FieldValue.serverTimestamp();
  }

  if (choferUid) {
    patch.uidTaxista = choferUid;
    patch.taxistaId = choferUid;
    patch.corporativoChoferPreferidoUid = choferUid;
    patch.corporativoChoferAsignadoUid = choferUid;
  }

  const patchTrip = { ...patch };
  const enRuta = estado === "en_curso" || estado === "a_bordo";
  const prevLegs = Math.max(
    0,
    Math.trunc(Number(args.vData.multiparadaLegCompletadas ?? 0)),
  );
  const prevVisitadas = Array.isArray(args.vData.multiparadaParadasVisitadas)
    ? (args.vData.multiparadaParadasVisitadas as AnyMap[])
    : [];
  aplicarCamposMultiparadaCorporativo(
    patchTrip,
    {
      waypoints,
      activos,
      rutaPuntos,
      mapsUrl,
      wazeUrl,
      desglose,
      kmCotizados,
    },
    { preservarProgreso: enRuta },
  );
  if (enRuta) {
    const totalLegs = Math.max(
      1,
      Math.trunc(Number(patchTrip.multiparadaLegsTotal ?? activos.length)),
    );
    const legsOk = Math.min(prevLegs, totalLegs);
    patchTrip.multiparadaLegCompletadas = legsOk;
    patchTrip.multiparadaParadasVisitadas = prevVisitadas.slice(0, legsOk);
    patchTrip.multiparadaCompleta = legsOk >= totalLegs;
    patchTrip.corporativoPasajerosActualizadosEn = FieldValue.serverTimestamp();
  }
  patchTrip.extras = mergeExtrasCorporativo(
    (args.vData.extras as AnyMap) ?? {},
    (patchTrip.extras as AnyMap) ?? {},
  );
  if (minPub > 0) {
    patchTrip.corporativoMinutosPublicarAntes = minPub;
  }

  await db().collection("viajes").doc(args.viajeId).set(patchTrip, { merge: true });
  await args.empRef.collection("historial").doc(args.viajeId).set(
    {
      fechaRecogida: Timestamp.fromDate(nuevaFecha),
      horaRecogidaGrupo: horaStr,
      pasajerosActivos: activos.length,
      horaActualizadaEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  if (choferUid) {
    const fh = patch.fechaHora ?? args.vData.fechaHora;
    let diffMin = 9999;
    if (fh instanceof Timestamp) {
      diffMin = (fh.toDate().getTime() - Date.now()) / 60000;
    }
    try {
      await asignarChoferCorporativoFijo({
        viajeRef: db().collection("viajes").doc(args.viajeId),
        choferUid,
        esAhora: ventanas.publicado || diffMin <= 120,
      });
      await repararChoferViajeCorporativoSiHaceFalta(args.viajeId);
    } catch (e) {
      logger.warn("patchViaje asignarChofer", {
        viajeId: args.viajeId,
        choferUid,
        e,
      });
    }
  }

  return true;
}

/** Actualiza hora/ventanas en viaje activo (fallback si el patch operativo completo falla). */
async function patchHoraEnViajeCorporativo(args: {
  viajeId: string;
  vData: AnyMap;
  plantilla: AnyMap;
  empRef: DocumentReference;
}): Promise<boolean> {
  const estado = str(args.vData.estado).toLowerCase();
  if (
    estado === "completado" ||
    estado === "cancelado" ||
    estado === "rechazado" ||
    estado === "finalizado"
  ) {
    return false;
  }

  const d = args.plantilla;
  const horaStr = horaEncargadoDesdePlantilla(d);
  const rawFecha = recogidaConHoraZonaRd(horaStr, new Date());
  if (!rawFecha) return false;
  // Sync desde encargado: hora exacta, sin empujar al futuro (eso es solo «Enviar ahora»).
  const nuevaFecha = rawFecha;
  const diffMin = (nuevaFecha.getTime() - Date.now()) / 60000;
  const minPubVentana = minutosPublicarAntesCorporativo(d.minutosPublicarAntes);
  const ventanas = ventanasPublicacionCorporativo(nuevaFecha, minPubVentana);
  if (diffMin <= 120) {
    ventanas.publicado = true;
  }

  const patchTrip: AnyMap = {
    fechaHora: Timestamp.fromDate(nuevaFecha),
    acceptAfter: ventanas.acceptAfter,
    publishAt: ventanas.publishAt,
    startWindowAt: ventanas.startWindowAt,
    publicado: ventanas.publicado,
    corporativoHoraRecogidaGrupo: horaStr,
    corporativoPlantillaSincronizadaEn: FieldValue.serverTimestamp(),
    corporativoHoraActualizadaEn: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    actualizadoEn: FieldValue.serverTimestamp(),
    extras: mergeExtrasCorporativo((args.vData.extras as AnyMap) ?? {}, {
      corporativoHoraRecogidaGrupo: horaStr,
    }),
  };
  if (diffMin <= 120 && !args.vData.corporativoPublicadoEn) {
    patchTrip.corporativoPublicadoEn = FieldValue.serverTimestamp();
  }

  await db().collection("viajes").doc(args.viajeId).set(patchTrip, { merge: true });
  await args.empRef.collection("historial").doc(args.viajeId).set(
    {
      fechaRecogida: Timestamp.fromDate(nuevaFecha),
      horaRecogidaGrupo: horaStr,
      horaActualizadaEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  logger.info("patchHora ok", {
    viajeId: args.viajeId,
    hora: horaStr,
    diffMin: Math.round(diffMin),
  });
  return true;
}

/** Actualiza pasajeros/mapas en viaje activo (fallback si el patch operativo completo falla). */
async function patchPasajerosEnViajeCorporativo(args: {
  viajeId: string;
  vData: AnyMap;
  empresaId: string;
  plantilla: AnyMap;
}): Promise<boolean> {
  const estado = str(args.vData.estado).toLowerCase();
  if (estado === "completado" || estado === "cancelado") return false;

  const d = args.plantilla;
  const activos = pasajerosActivosOrdenados(d);
  if (activos.length === 0) return false;

  const origenLat = Number(d.origenLat);
  const origenLon = Number(d.origenLon);
  const ultimo = activos[activos.length - 1];
  const latD = Number(ultimo.lat);
  const lonD = Number(ultimo.lon);
  if (
    !coordsValidasCorporativo(origenLat, origenLon) ||
    !coordsValidasCorporativo(latD, lonD) ||
    activos.some((p) => !coordsValidasCorporativo(p.lat, p.lon))
  ) {
    logger.warn("patchPasajeros: GPS inválido", {
      viajeId: args.viajeId,
      pasajeros: activos.length,
    });
    return false;
  }

  const waypoints = armarWaypoints(d);
  const paradasGps = waypoints.map((w) => ({
    lat: Number(w.lat),
    lon: Number(w.lon),
  }));
  const mapsUrl =
    urlGoogleMapsRuta({
      origenLat,
      origenLon,
      destinoLat: latD,
      destinoLon: lonD,
      paradas: paradasGps,
    }) || str(d.googleMapsRutaUrl);
  const wazeUrl = urlWazeOrigen(origenLat, origenLon) || str(d.wazeOrigenUrl);
  const rutaPuntos = armarRutaPuntosGps({
    origenLat,
    origenLon,
    origenLabel: str(d.origenLabel),
    activos,
  });
  const { precio, desglose, pagoChoferEstimadoRd } = await calcularPrecioOperativaPlantilla(
    args.empresaId,
    d,
    activos,
    origenLat,
    origenLon,
  );
  const kmCotizados = Number(desglose.kmCotizados ?? 0);
  const destinoLabel = `${str(ultimo.nombre)} · ${str(ultimo.destinoLabel || ultimo.destino)}`;
  const enRuta = estado === "en_curso" || estado === "a_bordo";
  const prevLegs = Math.max(
    0,
    Math.trunc(Number(args.vData.multiparadaLegCompletadas ?? 0)),
  );
  const prevVisitadas = Array.isArray(args.vData.multiparadaParadasVisitadas)
    ? (args.vData.multiparadaParadasVisitadas as AnyMap[])
    : [];

  const patchTrip: AnyMap = {
    origen: str(d.origenLabel),
    destino: destinoLabel,
    latCliente: roundCoord6(origenLat),
    lonCliente: roundCoord6(origenLon),
    latDestino: roundCoord6(latD),
    lonDestino: roundCoord6(lonD),
    precio,
    precio_cents: Math.round(precio * 100),
    corporativoPagoChoferEstimadoRd: pagoChoferEstimadoRd,
    distancia_km: kmCotizados,
    corporativoPasajeros: activos,
    corporativoPlantillaNombre: str(d.nombre),
    googleMapsRutaUrl: mapsUrl,
    wazeOrigenUrl: wazeUrl,
    corporativoGoogleMapsRutaUrl: mapsUrl,
    corporativoWazeOrigenUrl: wazeUrl,
    rutaPuntos,
    corporativoPlantillaSincronizadaEn: FieldValue.serverTimestamp(),
    corporativoPasajerosActualizadosEn: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    actualizadoEn: FieldValue.serverTimestamp(),
  };

  aplicarCamposMultiparadaCorporativo(
    patchTrip,
    {
      waypoints,
      activos,
      rutaPuntos,
      mapsUrl,
      wazeUrl,
      desglose,
      kmCotizados,
    },
    { preservarProgreso: enRuta },
  );
  if (enRuta) {
    const totalLegs = Math.max(
      1,
      Math.trunc(Number(patchTrip.multiparadaLegsTotal ?? activos.length)),
    );
    const legsOk = Math.min(prevLegs, totalLegs);
    patchTrip.multiparadaLegCompletadas = legsOk;
    patchTrip.multiparadaParadasVisitadas = prevVisitadas.slice(0, legsOk);
    patchTrip.multiparadaCompleta = legsOk >= totalLegs;
  }
  patchTrip.extras = mergeExtrasCorporativo(
    (args.vData.extras as AnyMap) ?? {},
    (patchTrip.extras as AnyMap) ?? {},
  );

  await db().collection("viajes").doc(args.viajeId).set(patchTrip, { merge: true });
  logger.info("patchPasajeros ok", {
    viajeId: args.viajeId,
    pasajeros: activos.length,
  });
  return true;
}

function viajeActivoDePlantillaHoy(
  v: AnyMap,
  empresaId: string,
  plantillaId: string,
  plantilla: AnyMap,
  ref: Date = new Date(),
): boolean {
  if (v.completado === true || v.activo === false) return false;
  if (!viajeCorpReutilizableHoy(v)) return false;
  if (str(v.corporativoPlantillaId) !== plantillaId) return false;
  if (str(v.corporativoEmpresaId) !== empresaId) return false;
  if (!esViajeCorporativoDelDiaHoy(v, plantilla, ref)) {
    return viajeCorporativoEnRutaOperativa(v);
  }
  const horaEsperada = horaEncargadoDesdePlantilla(plantilla);
  const horaViaje = horaAlmacenadaEnViaje(v);
  if (
    horaViaje &&
    horaEsperada &&
    horaViaje !== horaEsperada &&
    !viajeCorporativoEnRutaOperativa(v)
  ) {
    return false;
  }
  return true;
}

async function buscarYActualizarViajeHoyPlantilla(args: {
  empresaId: string;
  plantillaId: string;
  plantilla: AnyMap;
  ultimoViajeId: string;
  empRef: DocumentReference;
  plRef: DocumentReference;
}): Promise<string> {
  const ahora = new Date();

  async function intentar(viajeId: string): Promise<boolean> {
    const vSnap = await db().collection("viajes").doc(viajeId).get();
    if (!vSnap.exists) return false;
    const v = (vSnap.data() ?? {}) as AnyMap;
    if (!viajeActivoDePlantillaHoy(
      v,
      args.empresaId,
      args.plantillaId,
      args.plantilla,
      ahora,
    )) {
      return false;
    }
    const okFull = await patchViajeOperativaDesdePlantilla({
      viajeId,
      vData: v,
      empresaId: args.empresaId,
      plantilla: args.plantilla,
      empRef: args.empRef,
    });
    if (okFull) return true;
    const okHora = await patchHoraEnViajeCorporativo({
      viajeId,
      vData: v,
      plantilla: args.plantilla,
      empRef: args.empRef,
    });
    const okPas = await patchPasajerosEnViajeCorporativo({
      viajeId,
      vData: v,
      empresaId: args.empresaId,
      plantilla: args.plantilla,
    });
    return okHora || okPas;
  }

  if (args.ultimoViajeId && (await intentar(args.ultimoViajeId))) {
    return args.ultimoViajeId;
  }

  try {
    const q = await db()
      .collection("viajes")
      .where("corporativoPlantillaId", "==", args.plantillaId)
      .where("corporativoEmpresaId", "==", args.empresaId)
      .limit(12)
      .get();
    for (const doc of q.docs) {
      if (await intentar(doc.id)) {
        await args.plRef.set(
          { ultimoViajeId: doc.id, actualizadoEn: FieldValue.serverTimestamp() },
          { merge: true },
        );
        return doc.id;
      }
    }
  } catch (e) {
    logger.warn("sync plantilla: buscar viaje hoy", {
      plantillaId: args.plantillaId,
      e,
    });
  }
  return "";
}

/** Si no hay viaje de hoy, publica uno al guardar/sincronizar (recogida hoy). */
async function asegurarViajeHoyDesdePlantilla(args: {
  empresaId: string;
  plantillaId: string;
  plantilla: AnyMap;
  empresaNombre: string;
  empresaData: AnyMap;
  encargadoUid?: string;
  operadorUid?: string;
  choferUid: string;
  plRef: DocumentReference;
  forzarRecogidaHoy?: boolean;
}): Promise<string> {
  const d = args.plantilla;
  const ahora = new Date();

  if (!empresaContratoVigente(args.empresaData, ahora)) return "";
  if (!servicioIniciado(d, ahora)) return "";
  if (!debePublicarHoyOperativa(d, ahora, args.forzarRecogidaHoy === true)) {
    return "";
  }

  const activos = pasajerosActivosOrdenados(d);
  if (activos.length === 0) return "";
  if (!str(args.choferUid)) return "";

  const pubKey = `${hoyKey(ahora)}_pub`;
  const ultimoId = str(d.ultimoViajeId);
  if (str(d.ultimaPublicacionFijaKey) === pubKey && ultimoId) {
    const vSnap = await db().collection("viajes").doc(ultimoId).get();
    if (vSnap.exists && viajeCorpReutilizableHoy((vSnap.data() ?? {}) as AnyMap)) {
      return ultimoId;
    }
  }

  const horaStr = str(d.horaRecogidaGrupo) || str(d.horaRecogida) || "07:00";
  const rawRecogida = recogidaConHoraZonaRd(horaStr, ahora);
  if (!rawRecogida) return "";
  let recogida = ajustarRecogidaHoySiYaPaso(rawRecogida, ahora, 15);
  let diffMin = (recogida.getTime() - ahora.getTime()) / 60000;
  const ventanaAbierta = ventanaPublicacionCorporativoAbierta(d, ahora);
  // Lejos en el futuro: el scheduler publica ~90 min antes (salvo asignación ADM en ventana).
  if (diffMin > 360 && !ventanaAbierta && args.forzarRecogidaHoy !== true) {
    return "";
  }

  const encargadoUid = resolverUidEncargadoOperacion({
    empresaData: args.empresaData,
    encargadoUid: args.encargadoUid,
    operadorUid: args.operadorUid,
    choferUid: args.choferUid,
  });
  if (!encargadoUid) return "";

  const minPub =
    typeof d.minutosPublicarAntes === "number"
      ? Math.trunc(d.minutosPublicarAntes as number)
      : 90;

  const viajeId = await publicarViajeDesdePlantilla({
    empresaId: args.empresaId,
    plantillaId: args.plantillaId,
    plantilla: d,
    empresaNombre: args.empresaNombre,
    encargadoUid,
    fechaRecogida: recogida,
    minutosPublicarAntes: minPub,
  });
  if (!viajeId) return "";

  await args.plRef.set(
    {
      ultimoViajeId: viajeId,
      ultimaPublicacionFijaKey: pubKey,
      ultimoErrorPublicacion: FieldValue.delete(),
      ultimoErrorPublicacionEn: FieldValue.delete(),
      ...camposLimpiarRecogidaPerdida(diaCalendarioRdCorp()),
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  logger.info("corporativo auto-publicar al sincronizar", {
    empresaId: args.empresaId,
    plantillaId: args.plantillaId,
    viajeId,
    diffMin: Math.round(diffMin),
  });

  return viajeId;
}

/**
 * Sincroniza plantilla → asignación del chofer → viaje de hoy (hora, pasajeros, maps).
 * La plantilla ya debe estar guardada en Firestore.
 */
export async function ejecutarSincronizacionOperativaPlantilla(args: {
  empresaId: string;
  plantillaId: string;
  horaAnterior?: string;
  enviarPushHora?: boolean;
  notificarCambioPasajeros?: boolean;
  notificarActualizacionRuta?: boolean;
  encargadoUid?: string;
  operadorUid?: string;
  forzarRecogidaHoy?: boolean;
  notificarChoferAsignacion?: boolean;
}): Promise<{
  ok: true;
  viajeId: string;
  choferUid: string;
  horaNueva: string;
  pasajerosActivos: number;
  pushEnviado: boolean;
  viajeCreado: boolean;
}> {
  const empresaId = str(args.empresaId);
  const plantillaId = str(args.plantillaId);
  if (!empresaId || !plantillaId) {
    throw new HttpsError("invalid-argument", "Faltan empresaId o plantillaId");
  }

  const empRef = db().collection("empresas_corporativas").doc(empresaId);
  const plRef = empRef.collection("plantillas_ruta").doc(plantillaId);
  const plSnap = await plRef.get();
  if (!plSnap.exists) throw new HttpsError("not-found", "Ruta no encontrada");
  const d = plSnap.data() ?? {};
  const ed = (await empRef.get()).data() ?? {};
  const empresaNombre = str(ed.nombre) || str(ed.nombreComercial) || "Empresa";
  const plantillaNombre = str(d.nombre) || "Ruta corporativa";
  const choferUid = str(d.choferPreferidoUid);
  const origen = str(d.origenLabel) || "empresa";
  const horaNueva = horaEncargadoDesdePlantilla(d);
  const horaAnterior = str(args.horaAnterior);
  const pasajerosRaw = Array.isArray(d.pasajeros) ? (d.pasajeros as AnyMap[]) : [];
  const pasajerosActivos = pasajerosRaw.filter((p) => p.activo !== false).length;

  if (choferUid) {
    await actualizarAsignacionChoferDesdePlantilla({
      choferUid,
      empresaId,
      empresaNombre,
      plantillaId,
      plantilla: d,
      pasajerosActivos,
    });
  }

  if (horaAnterior.length > 0 && horaAnterior !== horaNueva) {
    try {
      await invalidarViajesSiCambioHoraMaterial({
        empresaId,
        plantillaId,
        plantilla: d,
        plRef,
        horaAnterior,
        horaNueva,
        operadorUid:
          str(args.encargadoUid) || str(args.operadorUid) || choferUid,
      });
    } catch (e) {
      logger.warn("sync invalidar por cambio hora", {
        empresaId,
        plantillaId,
        e,
      });
    }
  }

  let viajeIdActualizado = await buscarYActualizarViajeHoyPlantilla({
    empresaId,
    plantillaId,
    plantilla: d,
    ultimoViajeId: str(d.ultimoViajeId),
    empRef,
    plRef,
  });

  let viajeCreado = false;
  const huboCambioOperativo =
    args.notificarCambioPasajeros === true || horaAnterior.length > 0;
  const forzarHoy =
    args.forzarRecogidaHoy === true ||
    horaAnterior.length > 0 ||
    args.notificarCambioPasajeros === true;
  if (!viajeIdActualizado && choferUid && pasajerosActivos > 0) {
    const creado = await asegurarViajeHoyDesdePlantilla({
      empresaId,
      plantillaId,
      plantilla: d,
      empresaNombre,
      empresaData: ed,
      encargadoUid: str(args.encargadoUid),
      operadorUid: str(args.operadorUid),
      choferUid,
      plRef,
      forzarRecogidaHoy: forzarHoy,
    });
    if (creado) {
      viajeIdActualizado = creado;
      viajeCreado = true;
    }
  }

  if (viajeIdActualizado) {
    try {
      await repararChoferViajeCorporativoSiHaceFalta(viajeIdActualizado);
    } catch (e) {
      logger.warn("sync reparar chofer viaje", { viajeIdActualizado, e });
    }
    try {
      const vSnap = await db()
        .collection("viajes")
        .doc(viajeIdActualizado)
        .get();
      const vData = (vSnap.data() ?? {}) as AnyMap;
      const enViaje = pasajerosActivosOperativos(vData, 0);
      if (enViaje !== pasajerosActivos) {
        logger.warn("sync reconciliar pasajeros", {
          viajeId: viajeIdActualizado,
          plantilla: pasajerosActivos,
          viaje: enViaje,
        });
        await patchPasajerosEnViajeCorporativo({
          viajeId: viajeIdActualizado,
          vData,
          empresaId,
          plantilla: d,
        });
      }
      const horaEnViaje = horaAlmacenadaEnViaje(vData);
      const horaEsperada = horaEncargadoDesdePlantilla(d);
      if (horaEsperada.length > 0 && horaEnViaje !== horaEsperada) {
        logger.warn("sync reconciliar hora encargado", {
          viajeId: viajeIdActualizado,
          plantilla: horaEsperada,
          viaje: horaEnViaje,
        });
        await patchHoraEnViajeCorporativo({
          viajeId: viajeIdActualizado,
          vData,
          plantilla: d,
          empRef,
        });
      }
    } catch (e) {
      logger.warn("sync reconciliar operativa", { viajeIdActualizado, e });
    }

    if (huboCambioOperativo) {
      try {
        await reiniciarProgresoRutaCorpInformativa(viajeIdActualizado);
      } catch (e) {
        logger.warn("sync reiniciar progreso informativo", {
          viajeId: viajeIdActualizado,
          e,
        });
      }
    }

    try {
      const operadorUid =
        str(args.encargadoUid) || str(args.operadorUid) || choferUid;
      await anularViajesObsoletosPlantillaHoy({
        empresaId,
        plantillaId,
        plantilla: d,
        viajeCanonicoId: viajeIdActualizado,
        operadorUid,
      });
    } catch (e) {
      logger.warn("sync anular viajes obsoletos", {
        viajeId: viajeIdActualizado,
        plantillaId,
        e,
      });
    }
  } else if (choferUid) {
    try {
      const q = await db()
        .collection("viajes")
        .where("corporativoPlantillaId", "==", plantillaId)
        .where("corporativoEmpresaId", "==", empresaId)
        .limit(8)
        .get();
      for (const doc of q.docs) {
        const v = doc.data() ?? {};
        if (v.completado === true) continue;
        if (!esViajeCorporativoDelDiaHoy(v, d, new Date())) continue;
        const ok = await repararChoferViajeCorporativoSiHaceFalta(doc.id);
        if (ok) {
          viajeIdActualizado = doc.id;
          break;
        }
      }
    } catch (e) {
      logger.warn("sync reparar viajes hoy plantilla", { plantillaId, e });
    }
  }

  const hayViajeHoy =
    d.activa !== false &&
    servicioIniciado(d, new Date()) &&
    coincidePatronHoy(d, new Date()) &&
    !((Array.isArray(d.diasPausaFeriado)
      ? (d.diasPausaFeriado as string[])
      : []
    ).includes(hoyKey(new Date())));

  let pushEnviado = false;
  const debePushHora =
    args.enviarPushHora === true ||
    (horaAnterior.length > 0 && horaAnterior !== horaNueva);
  const debePushAsignacion = args.notificarChoferAsignacion === true;
  const debePushPasajeros = args.notificarCambioPasajeros === true;
  const debePushActualizacion = args.notificarActualizacionRuta === true;
  if (
    debePushHora ||
    viajeCreado ||
    debePushAsignacion ||
    debePushPasajeros ||
    debePushActualizacion
  ) {
    let tituloChofer = viajeCreado
      ? "🏢 Ruta corporativa lista"
      : debePushAsignacion
        ? "🏢 Ruta corporativa asignada"
        : debePushPasajeros
          ? "👤 Pasajeros actualizados"
          : debePushActualizacion
            ? "🏢 Ruta actualizada"
            : "🕐 Nueva hora de recogida";
    let cuerpoChofer = viajeCreado
      ? `${empresaNombre} · ${plantillaNombre}\n` +
        `Recogida a las ${horaNueva}. Abrí Mis rutas corporativas → Abrir ruta.`
      : debePushAsignacion
        ? `${empresaNombre} · ${plantillaNombre}\n` +
          `Recogida a las ${horaNueva}. ` +
          (viajeIdActualizado
            ? "El viaje de hoy ya está en Mis rutas corporativas."
            : `Verás el viaje ~90 min antes de la recogida en Mis rutas.`)
        : debePushPasajeros
          ? `${empresaNombre} · ${plantillaNombre}\n` +
            `Ahora ${pasajerosActivos} pasajero(s) activo(s). ` +
            `Revisá paradas en viaje en curso.`
          : debePushActualizacion
            ? `${empresaNombre} · ${plantillaNombre}\n` +
              `La empresa modificó la ruta (tarifa u operación). ` +
              `Revisá Mis rutas corporativas.`
            : `${empresaNombre} · ${plantillaNombre}\n` +
              (horaAnterior
                ? `Cambió de ${horaAnterior} a ${horaNueva}. `
                : `Recogida a las ${horaNueva}. `) +
              `Ve a ${origen}. Revisá Mis rutas corporativas.`;
    const tituloEnc = viajeCreado
      ? "✅ Viaje publicado al chofer"
      : horaAnterior
        ? "🕐 Hora de ruta actualizada"
        : "🕐 Hora de recogida confirmada";
    const cuerpoEnc = viajeCreado
      ? `${plantillaNombre} · recogida ${horaNueva}\nEl chofer ya ve el viaje en su app.`
      : `${plantillaNombre}: ${horaAnterior ? `${horaAnterior} → ` : ""}${horaNueva}` +
        (viajeIdActualizado
          ? "\nEl chofer ya ve la hora nueva en su app."
          : "");

    const encargados = Array.isArray(ed.encargadoUids)
      ? (ed.encargadoUids as string[]).map(String)
      : [];
    for (const uid of encargados) {
      await enviarPushUid(uid, tituloEnc, cuerpoEnc, {
        type: "corporativo_cambio_hora",
        empresaId,
        plantillaId,
        viajeId: viajeIdActualizado,
        horaNueva,
        seBusca: hayViajeHoy ? "si" : "no",
        rol: "encargado",
      });
    }
    if (choferUid) {
      await enviarPushUid(choferUid, tituloChofer, cuerpoChofer, {
        type: viajeCreado
          ? "corporativo_asignado"
          : debePushAsignacion
            ? "corporativo_chofer_asignado"
            : debePushPasajeros
              ? "corporativo_pasajeros_actualizados"
              : debePushActualizacion
                ? "corporativo_ruta_actualizada"
                : "corporativo_cambio_hora",
        empresaId,
        plantillaId,
        viajeId: viajeIdActualizado,
        horaNueva,
        seBusca: hayViajeHoy ? "si" : "no",
        rol: "chofer",
      });
    }
    pushEnviado = choferUid.length > 0 || encargados.length > 0;
  }

  if (choferUid) {
    try {
      if (viajeIdActualizado) {
        await refrescarChoferOperacionTrasPublicar(
          viajeIdActualizado,
          choferUid,
        );
      } else {
        await refrescarChoferOperacionCorporativa(choferUid);
      }
    } catch (e) {
      logger.warn("sync chofer_operacion", { choferUid, empresaId, plantillaId, e });
    }
  }

  return {
    ok: true,
    viajeId: viajeIdActualizado,
    choferUid,
    horaNueva,
    pasajerosActivos,
    pushEnviado,
    viajeCreado,
  };
}

/** Propaga hora nueva a chofer, viaje de hoy e historial (plantilla ya actualizada). */
export async function ejecutarPropagacionCambioHoraCorporativa(args: {
  empresaId: string;
  plantillaId: string;
  horaNueva: string;
  horaAnterior?: string;
}): Promise<{
  ok: true;
  viajeId: string;
  choferUid: string;
  horaNueva: string;
  pushEnviado: boolean;
}> {
  const empresaId = str(args.empresaId);
  const plantillaId = str(args.plantillaId);
  const horaNueva = str(args.horaNueva);
  if (!empresaId || !plantillaId || !horaNueva) {
    throw new HttpsError(
      "invalid-argument",
      "Faltan empresaId, plantillaId u hora nueva",
    );
  }
  const sync = await ejecutarSincronizacionOperativaPlantilla({
    empresaId,
    plantillaId,
    horaAnterior: str(args.horaAnterior),
    enviarPushHora: true,
  });
  return {
    ok: true,
    viajeId: sync.viajeId,
    choferUid: sync.choferUid,
    horaNueva: sync.horaNueva,
    pushEnviado: sync.pushEnviado,
  };
}

/**
 * Propaga cambio de hora de recogida en tiempo real: plantilla → chofer → viaje de hoy → historial.
 * Lo llama el encargado al guardar la ruta (o admin).
 */
export const propagarCambioHoraCorporativa = onCall(
  { region: "us-central1", memory: "256MiB", timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }
    const empresaId = str(request.data?.empresaId);
    const plantillaId = str(request.data?.plantillaId);
    const horaNueva =
      str(request.data?.horaNueva) ||
      str(request.data?.horaRecogidaGrupo);
    const horaAnterior = str(request.data?.horaAnterior);
    if (!empresaId || !plantillaId || !horaNueva) {
      throw new HttpsError(
        "invalid-argument",
        "Faltan empresaId, plantillaId u hora nueva",
      );
    }
    await assertEncargadoOAdminCorporativo(request.auth.uid, empresaId);
    return ejecutarPropagacionCambioHoraCorporativa({
      empresaId,
      plantillaId,
      horaNueva,
      horaAnterior,
    });
  },
);

/**
 * Sincroniza en tiempo real plantilla → chofer asignado → viaje de hoy (hora, pasajeros, maps).
 * Lo llama el encargado al guardar cualquier cambio operativo en la ruta.
 */
export const sincronizarPlantillaCorporativaEnVivo = onCall(
  { region: "us-central1", memory: "512MiB", timeoutSeconds: 90 },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }
    const empresaId = str(request.data?.empresaId);
    const plantillaId = str(request.data?.plantillaId);
    if (!empresaId || !plantillaId) {
      throw new HttpsError("invalid-argument", "Faltan empresaId o plantillaId");
    }
    await assertEncargadoOAdminCorporativo(request.auth.uid, empresaId);
    const horaAnterior = str(request.data?.horaAnterior);
    const enviarPushHora =
      request.data?.enviarPushHora === true || horaAnterior.length > 0;
    const notificarCambioPasajeros =
      request.data?.notificarCambioPasajeros === true;
    const notificarActualizacionRuta =
      request.data?.notificarActualizacionRuta === true;
    return ejecutarSincronizacionOperativaPlantilla({
      empresaId,
      plantillaId,
      horaAnterior,
      enviarPushHora,
      notificarCambioPasajeros,
      notificarActualizacionRuta,
      encargadoUid: request.auth.uid,
      operadorUid: request.auth.uid,
      forzarRecogidaHoy:
        horaAnterior.length > 0 || notificarCambioPasajeros,
    });
  },
);

/**
 * Aviso inmediato al taxista/encargado al cambiar operación.
 * tipo: feriado | pausa_total | reactivar | quitar_pasajero | agregar_pasajero | lanzar_manual
 */
export const avisarOperacionCorporativa = onCall(
  { region: "us-central1", memory: "256MiB", timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }
    const empresaId = str(request.data?.empresaId);
    const plantillaId = str(request.data?.plantillaId);
    const tipo = str(request.data?.tipo).toLowerCase() || "feriado";
    if (!empresaId || !plantillaId) {
      throw new HttpsError("invalid-argument", "Faltan empresaId o plantillaId");
    }

    const empRef = db().collection("empresas_corporativas").doc(empresaId);
    const empSnap = await empRef.get();
    if (!empSnap.exists) throw new HttpsError("not-found", "Empresa no encontrada");
    const ed = empSnap.data() ?? {};
    const encargados = Array.isArray(ed.encargadoUids)
      ? (ed.encargadoUids as string[]).map(String)
      : [];
    if (!encargados.includes(request.auth.uid)) {
      throw new HttpsError("permission-denied", "Solo el encargado de la empresa");
    }

    const plRef = empRef.collection("plantillas_ruta").doc(plantillaId);
    const plSnap = await plRef.get();
    if (!plSnap.exists) throw new HttpsError("not-found", "Ruta no encontrada");
    const d = plSnap.data() ?? {};
    const empresaNombre = str(ed.nombre) || "Empresa";
    const plantillaNombre = str(d.nombre) || "Ruta corporativa";
    const choferUid = str(d.choferPreferidoUid);
    const nota = str(request.data?.nota) || str(d.pausaNota);
    const keyHoy = hoyKey(new Date());
    const feriados = Array.isArray(d.diasPausaFeriado)
      ? (d.diasPausaFeriado as unknown[]).map((x) => String(x))
      : [];
    const pasajerosRaw = Array.isArray(d.pasajeros) ? (d.pasajeros as AnyMap[]) : [];
    const activos = pasajerosRaw.filter((p) => p.activo !== false);
    const nActivos = activos.length;
    const pasajeroNombre =
      str(request.data?.pasajeroNombre) || "un pasajero";
    const hoyEsFeriado = feriados.includes(keyHoy);
    const rutaActiva = d.activa !== false;
    const hayViajeHoy =
      rutaActiva && !hoyEsFeriado && nActivos > 0 &&
      servicioIniciado(d, new Date()) &&
      coincidePatronHoy(d, new Date());

    async function pushAmbos(
      titleEnc: string,
      bodyEnc: string,
      titleChofer: string,
      bodyChofer: string,
      type: string,
      seBusca: "si" | "no",
    ): Promise<void> {
      for (const uid of encargados) {
        await enviarPushUid(uid, titleEnc, bodyEnc, {
          type,
          empresaId,
          plantillaId,
          seBusca,
          rol: "encargado",
        });
      }
      if (choferUid) {
        await enviarPushUid(choferUid, titleChofer, bodyChofer, {
          type,
          empresaId,
          plantillaId,
          seBusca,
          rol: "chofer",
          pasajerosActivos: String(nActivos),
        });
      }
    }

    if (tipo === "feriado") {
      const causa = nota ? ` (${nota})` : "";
      if (hoyEsFeriado) {
        // Siempre avisar al chofer al guardar (aunque el schedule ya haya avisado).
        await pushAmbos(
          "📅 Feriado · no se buscan pasajeros",
          `${empresaNombre} · ${plantillaNombre}\n` +
            `Hoy es feriado/no laborable${causa}. NO se publica ni se busca el grupo.`,
          "📅 Hoy NO hay viaje corporativo",
          `${empresaNombre} · ${plantillaNombre}\n` +
            `Feriado${causa}. No busques pasajeros hoy. ` +
            `Pasajeros en la ruta (otros días): ${nActivos}.`,
          "corporativo_feriado",
          "no",
        );
        await plRef.set(
          {
            ultimaNotificacionFeriadoKey: `${keyHoy}_feriado`,
            actualizadoEn: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        return { ok: true, enviado: true, seBusca: "no", pasajerosActivos: nActivos };
      }

      await pushAmbos(
        "📅 Feriados actualizados",
        `${empresaNombre} · ${plantillaNombre}\n` +
          `Se guardaron ${feriados.length} día(s) feriado${causa}. ` +
          (hayViajeHoy
            ? "Hoy SÍ se buscan pasajeros."
            : "Hoy no opera esta ruta."),
        hayViajeHoy
          ? "✅ Hoy SÍ hay viaje corporativo"
          : "ℹ️ Calendario feriados actualizado",
        `${empresaNombre} · ${plantillaNombre}\n` +
          (hayViajeHoy
            ? `Hoy SÍ hay viaje. Debes buscar ${nActivos} pasajero(s) activo(s).`
            : `Hoy no hay viaje en esta ruta. Feriados marcados: ${feriados.length}. ` +
              `Cuando opere, serán ${nActivos} pasajero(s).`),
        "corporativo_feriado_calendario",
        hayViajeHoy ? "si" : "no",
      );
      return {
        ok: true,
        enviado: true,
        seBusca: hayViajeHoy ? "si" : "no",
        pasajerosActivos: nActivos,
      };
    }

    if (tipo === "pausa_total") {
      await pushAmbos(
        "⏸ Ruta pausada · no se buscan pasajeros",
        `${empresaNombre} · ${plantillaNombre}\n` +
          `Pausa total. NO se publica ni se busca el grupo hasta reactivar.`,
        "⏸ Hoy NO hay viaje corporativo",
        `${empresaNombre} · ${plantillaNombre}\n` +
          `Ruta pausada por el encargado. No vayas a buscar pasajeros. ` +
          `Pasajeros en plantilla: ${nActivos}.`,
        "corporativo_pausa_total",
        "no",
      );
      return { ok: true, enviado: true, seBusca: "no", pasajerosActivos: nActivos };
    }

    if (tipo === "reactivar") {
      await pushAmbos(
        "✅ Ruta reactivada · se buscarán pasajeros",
        `${empresaNombre} · ${plantillaNombre}\n` +
          `Ruta activa otra vez. En días operativos SÍ se busca el grupo (${nActivos} pasajero(s)).`,
        hayViajeHoy
          ? "✅ Hoy SÍ hay viaje · ruta reactivada"
          : "✅ Ruta corporativa reactivada",
        `${empresaNombre} · ${plantillaNombre}\n` +
          (hayViajeHoy
            ? `Hoy SÍ hay viaje. Busca ${nActivos} pasajero(s) activo(s).`
            : `Ruta activa. En el próximo día laboral buscarás ${nActivos} pasajero(s).`),
        "corporativo_reactivar",
        hayViajeHoy ? "si" : "no",
      );
      return {
        ok: true,
        enviado: true,
        seBusca: hayViajeHoy ? "si" : "no",
        pasajerosActivos: nActivos,
      };
    }

    if (tipo === "quitar_pasajero") {
      try {
        await ejecutarSincronizacionOperativaPlantilla({
          empresaId,
          plantillaId,
          enviarPushHora: false,
        });
      } catch (e) {
        logger.warn("avisar quitar_pasajero sync", { plantillaId, e });
      }
      await pushAmbos(
        "👤 Pasajero fuera de la ruta",
        `${empresaNombre} · ${plantillaNombre}\n` +
          `Se quitó a ${pasajeroNombre}. Quedan ${nActivos} pasajero(s) activo(s).`,
        nActivos > 0
          ? (hayViajeHoy
              ? "👤 Sacaron un pasajero · hoy SÍ hay viaje"
              : "👤 Sacaron un pasajero de la ruta")
          : "⚠ Sin pasajeros activos · no hay viaje",
        `${empresaNombre} · ${plantillaNombre}\n` +
          `El encargado quitó a ${pasajeroNombre}. ` +
          (nActivos <= 0
            ? "Ya no quedan pasajeros activos: NO hay viaje que buscar."
            : hayViajeHoy
              ? `Hoy SÍ hay viaje. Ahora son ${nActivos} pasajero(s) a buscar.`
              : `Ahora son ${nActivos} pasajero(s) activos para los días que opere.`),
        "corporativo_quitar_pasajero",
        nActivos > 0 && hayViajeHoy ? "si" : "no",
      );
      return {
        ok: true,
        enviado: true,
        seBusca: nActivos > 0 && hayViajeHoy ? "si" : "no",
        pasajerosActivos: nActivos,
      };
    }

    if (tipo === "agregar_pasajero") {
      try {
        await ejecutarSincronizacionOperativaPlantilla({
          empresaId,
          plantillaId,
          enviarPushHora: false,
        });
      } catch (e) {
        logger.warn("avisar agregar_pasajero sync", { plantillaId, e });
      }
      await pushAmbos(
        "👤 Pasajero agregado / reactivado",
        `${empresaNombre} · ${plantillaNombre}\n` +
          `${pasajeroNombre} está en la ruta. Ahora ${nActivos} pasajero(s) activo(s).`,
        hayViajeHoy
          ? "👤 Sumaron un pasajero · hoy SÍ hay viaje"
          : "👤 Sumaron un pasajero a la ruta",
        `${empresaNombre} · ${plantillaNombre}\n` +
          `El encargado agregó/reactivó a ${pasajeroNombre}. ` +
          (hayViajeHoy
            ? `Hoy SÍ hay viaje. Ahora son ${nActivos} pasajero(s) a buscar.`
            : `Ahora son ${nActivos} pasajero(s) activos cuando opere la ruta.`),
        "corporativo_agregar_pasajero",
        hayViajeHoy ? "si" : "no",
      );
      return {
        ok: true,
        enviado: true,
        seBusca: hayViajeHoy ? "si" : "no",
        pasajerosActivos: nActivos,
      };
    }

    if (tipo === "lanzar_manual") {
      const viajeId = str(request.data?.viajeId);
      const horaStr =
        str(request.data?.nota) ||
        str(d.horaRecogidaGrupo) ||
        str(d.horaRecogida) ||
        "07:00";
      const origen = str(d.origenLabel) || "empresa";
      const horaParsed = parseHora(horaStr);
      const turno = !horaParsed
        ? "Ruta"
        : horaParsed.h < 12
          ? "Mañana"
          : horaParsed.h < 17
            ? "Tarde"
            : "Noche";
      const titleChofer = `🏢 ${turno} ${horaStr} · ruta corporativa`;
      const bodyChofer =
        `${empresaNombre} · ${plantillaNombre}\n` +
        `El encargado te envió la ruta ahora. Ve a ${origen} a las ${horaStr} ` +
        `a buscar ${nActivos} pasajero(s). Abrí Mis rutas → Waze / Maps.`;

      for (const uid of encargados) {
        await enviarPushUid(
          uid,
          "✅ Ruta enviada al chofer",
          `${plantillaNombre} · ${nActivos} pasajero(s) · ${horaStr}`,
          {
            type: "corporativo_asignado",
            empresaId,
            plantillaId,
            viajeId,
            seBusca: "si",
            rol: "encargado",
          },
        );
      }
      if (choferUid) {
        await enviarPushUid(choferUid, titleChofer, bodyChofer, {
          type: "corporativo_asignado",
          empresaId,
          plantillaId,
          viajeId,
          seBusca: "si",
          rol: "chofer",
        });
      }
      return {
        ok: true,
        enviado: true,
        seBusca: "si",
        pasajerosActivos: nActivos,
        viajeId,
      };
    }

    throw new HttpsError("invalid-argument", "tipo inválido");
  },
);

const LOGO_EMPRESA_MAX_BYTES = 3 * 1024 * 1024;

/**
 * Encargado: sube logo de empresa vía Admin SDK (evita firebase_storage/unauthorized en web).
 */
export const encargadoSubirLogoEmpresa = onCall(
  { region: "us-central1", memory: "256MiB", timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }
    const empresaId = str(request.data?.empresaId);
    if (!empresaId) {
      throw new HttpsError("invalid-argument", "Falta empresaId");
    }
    await assertEncargadoOAdminCorporativo(request.auth.uid, empresaId);

    const imageBase64 = str(request.data?.imageBase64);
    if (!imageBase64) {
      throw new HttpsError("invalid-argument", "Falta la imagen");
    }

    let buffer: Buffer;
    try {
      buffer = Buffer.from(imageBase64, "base64");
    } catch {
      throw new HttpsError("invalid-argument", "Imagen inválida (base64)");
    }

    if (buffer.length === 0 || buffer.length > LOGO_EMPRESA_MAX_BYTES) {
      throw new HttpsError(
        "invalid-argument",
        "El logo debe ser mayor que 0 y menor que 3 MB",
      );
    }

    const contentType = str(request.data?.contentType) || "image/jpeg";
    if (!contentType.startsWith("image/")) {
      throw new HttpsError("invalid-argument", "Solo se permiten imágenes");
    }

    const ext = contentType.includes("png") ? "png" : "jpg";
    const ts = Date.now();
    const storagePath = `empresas_corporativas/${empresaId}/logo/logo_${ts}.${ext}`;
    const bucket = getStorage().bucket();
    const file = bucket.file(storagePath);
    const downloadToken = randomUUID();

    await file.save(buffer, {
      resumable: false,
      metadata: {
        contentType,
        metadata: {
          uid: request.auth.uid,
          empresaId,
          firebaseStorageDownloadTokens: downloadToken,
        },
      },
    });

    const encodedPath = encodeURIComponent(storagePath);
    const url =
      `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}` +
      `?alt=media&token=${downloadToken}`;

    await db().collection("empresas_corporativas").doc(empresaId).update({
      logoUrl: url,
      actualizadoEn: FieldValue.serverTimestamp(),
    });

    try {
      const viajesSnap = await db()
        .collection("viajes")
        .where("corporativoEmpresaId", "==", empresaId)
        .where("completado", "==", false)
        .limit(100)
        .get();
      if (!viajesSnap.empty) {
        const batch = db().batch();
        for (const doc of viajesSnap.docs) {
          batch.update(doc.ref, {
            corporativoEmpresaLogoUrl: url,
            actualizadoEn: FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    } catch (e) {
      logger.warn("encargadoSubirLogoEmpresa sync viajes", { empresaId, e });
    }

    return { ok: true, url, storagePath };
  },
);

/**
 * Encargado: «Enviar ahora» — publica con auto-asignación / respaldo del pool.
 */
export const encargadoPublicarRutaCorporativaAhora = onCall(
  { region: "us-central1", memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }
    const empresaId = str(request.data?.empresaId);
    const plantillaId = str(request.data?.plantillaId);
    if (!empresaId || !plantillaId) {
      throw new HttpsError("invalid-argument", "Faltan empresaId o plantillaId");
    }

    const empRef = db().collection("empresas_corporativas").doc(empresaId);
    const empSnap = await empRef.get();
    if (!empSnap.exists) {
      throw new HttpsError("not-found", "Empresa no encontrada");
    }
    const ed = empSnap.data() ?? {};
    const encargados = Array.isArray(ed.encargadoUids)
      ? (ed.encargadoUids as string[]).map(String)
      : [];
    if (!encargados.includes(request.auth.uid)) {
      throw new HttpsError("permission-denied", "Solo el encargado de la empresa");
    }
    if (ed.contratoActivo !== true) {
      throw new HttpsError(
        "failed-precondition",
        "El servicio corporativo aún no está activado por RAI.",
      );
    }

    if (ed.contratoCorporativoAceptado !== true) {
      throw new HttpsError(
        "failed-precondition",
        "El encargado debe firmar el contrato corporativo antes de publicar.",
      );
    }
    if (str(ed.contratoCorporativoVersion) !== CORP_CONTRATO_VERSION) {
      throw new HttpsError(
        "failed-precondition",
        "Contrato corporativo desactualizado. El encargado debe firmar la versión vigente.",
      );
    }

    const now = new Date();
    const periodo = (ed.periodoActual ?? {}) as AnyMap;
    const vigCodigo = evaluarVigenciaCodigoCorporativo(periodo, now);
    if (!vigCodigo.vigente) {
      throw new HttpsError(
        "failed-precondition",
        "El código de verificación expiró o hay pago pendiente. " +
          "Realice el pago para generar un código nuevo.",
      );
    }

    const plRef = empRef.collection("plantillas_ruta").doc(plantillaId);
    const plSnap = await plRef.get();
    if (!plSnap.exists) {
      throw new HttpsError("not-found", "Ruta no encontrada");
    }
    const d = (plSnap.data() ?? {}) as AnyMap;
    if (d.activa === false) {
      throw new HttpsError("failed-precondition", "La ruta está pausada.");
    }

    const choferPreferidoUid = str(d.choferPreferidoUid);
    if (!choferPreferidoUid) {
      throw new HttpsError(
        "failed-precondition",
        "RAI debe asignar un conductor fijo a esta ruta antes de publicar. " +
          "Contactá al administrador RAI.",
      );
    }

    const bloqueo = await bloquearMismoChoferMismaHoraEnEmpresa({
      empresaId,
      plantillaId,
      plantilla: d,
    });
    if (bloqueo) {
      throw new HttpsError("failed-precondition", bloqueo);
    }

    let fechaRecogida = now;
    const isoRecogida = str(request.data?.fechaRecogidaIso);
    if (isoRecogida) {
      const parsed = new Date(isoRecogida);
      if (Number.isFinite(parsed.getTime())) {
        fechaRecogida = parsed;
      }
    } else {
      const horaStr = str(d.horaRecogidaGrupo) || str(d.horaRecogida) || "07:00";
      const parsed = recogidaConHoraZonaRd(horaStr, now);
      if (parsed) {
        fechaRecogida = parsed;
      }
    }
    fechaRecogida = ajustarRecogidaHoySiYaPaso(
      fechaRecogida,
      now,
      CORP_ENVIAR_AHORA_OFFSET_MIN,
    );

    const minPub = minutosPublicarAntesCorporativo(d.minutosPublicarAntes);

    const viajeId = await publicarViajeDesdePlantilla({
      empresaId,
      plantillaId,
      plantilla: d,
      empresaNombre: str(ed.nombre) || "Empresa",
      encargadoUid: request.auth.uid,
      fechaRecogida,
      minutosPublicarAntes: minPub,
      publicacionInmediata: true,
    });

    if (!viajeId) {
      throw new HttpsError(
        "failed-precondition",
        "No se pudo publicar. Revisá pasajeros GPS y que haya choferes en el pool corporativo.",
      );
    }

    const horaPublicada = horaHmEnZonaRd(fechaRecogida);
    const pubKey = `${hoyKey(now)}_pub`;
    await plRef.set(
      {
        ultimoViajeId: viajeId,
        ultimaPublicacionFijaKey: pubKey,
        horaRecogidaGrupo: horaPublicada,
        horaRecogida: horaPublicada,
        ultimoErrorPublicacion: FieldValue.delete(),
        ultimoErrorPublicacionEn: FieldValue.delete(),
        ...camposLimpiarRecogidaPerdida(diaCalendarioRdCorp(now)),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    try {
      await anularViajesObsoletosPlantillaHoy({
        empresaId,
        plantillaId,
        plantilla: d,
        viajeCanonicoId: viajeId,
        operadorUid: request.auth.uid,
      });
    } catch (e) {
      logger.warn("encargadoPublicar anular obsoletos", { viajeId, e });
    }

    const viajeSnap = await db().collection("viajes").doc(viajeId).get();
    const vd = (viajeSnap.data() ?? {}) as AnyMap;
    const choferUid = choferOperativoDesdeViaje(vd);
    const choferPreferido = str(d.choferPreferidoUid);
    if (choferUid || choferPreferido) {
      try {
        await refrescarChoferOperacionTrasPublicar(viajeId, choferPreferido);
        if (choferUid) {
          await ejecutarPromoverViajeCorporativoEnCurso({
            choferUid,
            viajeId,
          });
        }
      } catch (e) {
        logger.warn("encargadoPublicar refresh chofer", {
          choferUid,
          choferPreferido,
          viajeId,
          e,
        });
      }
    }

    return {
      ok: true,
      viajeId,
      choferUid,
      choferNombre: str(vd.nombreTaxista),
      modo: str(vd.corporativoChoferAsignacionModo) || "preferido",
    };
  },
);

function viajeEnCursoBloqueaEliminacionRuta(estado: string): boolean {
  const e = estado.toLowerCase();
  return (
    e === "en_curso" ||
    e === "encurso" ||
    e === "a_bordo" ||
    e === "abordo"
  );
}

/** Reinicia progreso informativo (Waze/entregas) tras cambio del encargado. */
async function reiniciarProgresoRutaCorpInformativa(
  viajeId: string,
): Promise<void> {
  const id = str(viajeId);
  if (!id) return;
  const ref = db().collection("viajes").doc(id);
  const snap = await ref.get();
  if (!snap.exists) return;
  const v = (snap.data() ?? {}) as AnyMap;
  if (v.completado === true) return;
  if (v.corporativoModoInformativo === false) return;
  const estado = str(v.estado).toLowerCase();
  if (
    estado === "completado" ||
    estado === "cancelado" ||
    estado === "rechazado"
  ) {
    return;
  }

  await ref.set(
    {
      corporativoRecogidaAbierta: false,
      corporativoRecogidaAbiertaEn: FieldValue.delete(),
      corporativoLlegadaEmpresaEn: FieldValue.delete(),
      corporativoParadasHechas: [],
      corporativoParadasAbiertas: [],
      corporativoParadaActualIdx: 0,
      multiparadaLegCompletadas: 0,
      multiparadaParadasVisitadas: [],
      multiparadaCompleta: false,
      clienteAbordo: false,
      pickupConfirmadoEn: FieldValue.delete(),
      estado: "aceptado",
      corporativoReiniciadoPorEncargadoEn: FieldValue.serverTimestamp(),
      extras: mergeExtrasCorporativo((v.extras as AnyMap) ?? {}, {
        clienteAbordo: false,
        corporativo: true,
      }),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

/** Si cambió la hora contractual de forma material, no reutilizar viajes viejos. */
async function invalidarViajesSiCambioHoraMaterial(args: {
  empresaId: string;
  plantillaId: string;
  plantilla: AnyMap;
  plRef: DocumentReference;
  horaAnterior: string;
  horaNueva: string;
  operadorUid: string;
}): Promise<number> {
  const prev = normalizarHoraHHmm(args.horaAnterior) || str(args.horaAnterior);
  const next = normalizarHoraHHmm(args.horaNueva) || str(args.horaNueva);
  if (!prev || !next || prev === next) return 0;
  if (minutosEntreHorasContrato(prev, next) < CORPORATIVO_CAMBIO_HORA_MATERIAL_MIN) {
    return 0;
  }

  const ahora = new Date();
  const candidatos = new Map<string, AnyMap>();
  const ultimoId = str(args.plantilla.ultimoViajeId);

  async function considerar(id: string): Promise<void> {
    if (!id || candidatos.has(id)) return;
    const snap = await db().collection("viajes").doc(id).get();
    if (!snap.exists) return;
    candidatos.set(id, (snap.data() ?? {}) as AnyMap);
  }

  if (ultimoId) await considerar(ultimoId);
  try {
    const q = await db()
      .collection("viajes")
      .where("corporativoPlantillaId", "==", args.plantillaId)
      .where("corporativoEmpresaId", "==", args.empresaId)
      .limit(12)
      .get();
    for (const doc of q.docs) {
      await considerar(doc.id);
    }
  } catch (e) {
    logger.warn("invalidarViajesSiCambioHoraMaterial listar", {
      plantillaId: args.plantillaId,
      e,
    });
  }

  let anulados = 0;
  const opUid = str(args.operadorUid) || "sistema";
  for (const [id, data] of candidatos) {
    if (viajeCorporativoEnRutaOperativa(data)) continue;
    const e = str(data.estado).toLowerCase();
    if (e === "cancelado" || e === "rechazado" || data.completado === true) {
      continue;
    }
    if (str(data.corporativoSupersedidoPor).length > 0) continue;
    const fh = fechaHoraViajeCorporativo(data);
    const esHoy =
      esViajeCorporativoDelDiaHoy(data, args.plantilla, ahora) ||
      (fh != null && esMismoDiaCalendarioRd(fh, ahora));
    if (!esHoy) continue;

    const choferUid =
      str(data.uidTaxista) ||
      str(data.taxistaId) ||
      str(data.corporativoChoferPreferidoUid);

    await db()
      .collection("viajes")
      .doc(id)
      .set(
        {
          estado: "cancelado",
          aceptado: false,
          rechazado: true,
          activo: false,
          completado: false,
          corporativoSupersedidoPor: "cambio_hora_material",
          corporativoSupersedidoEn: FieldValue.serverTimestamp(),
          canceladoPor: "encargado",
          canceladoOperadorUid: opUid,
          canceladoMotivo: "supersedido_cambio_hora",
          updatedAt: FieldValue.serverTimestamp(),
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

    if (choferUid) {
      const userRef = db().collection("usuarios").doc(choferUid);
      const uSnap = await userRef.get();
      const u = (uSnap.data() ?? {}) as AnyMap;
      const patch: AnyMap = {
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      };
      if (str(u.viajeActivoId) === id) patch.viajeActivoId = "";
      if (str(u.siguienteViajeId) === id) patch.siguienteViajeId = "";
      if (
        patch.viajeActivoId !== undefined ||
        patch.siguienteViajeId !== undefined
      ) {
        await userRef.set(patch, { merge: true });
      }
    }
    anulados++;
  }

  if (anulados > 0) {
    await args.plRef.set(
      {
        ultimoViajeId: "",
        ultimaPublicacionFijaKey: "",
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    args.plantilla.ultimoViajeId = "";
    args.plantilla.ultimaPublicacionFijaKey = "";
  }

  logger.info("invalidarViajesSiCambioHoraMaterial", {
    empresaId: args.empresaId,
    plantillaId: args.plantillaId,
    horaAnterior: prev,
    horaNueva: next,
    anulados,
  });
  return anulados;
}

/** Anula viajes viejos de la misma plantilla/hoy; queda solo el canónico. */
async function anularViajesObsoletosPlantillaHoy(args: {
  empresaId: string;
  plantillaId: string;
  plantilla: AnyMap;
  viajeCanonicoId: string;
  operadorUid: string;
}): Promise<number> {
  const canonico = str(args.viajeCanonicoId);
  if (!canonico) return 0;

  const activos = await listarViajesActivosPlantillaHoy({
    empresaId: args.empresaId,
    plantillaId: args.plantillaId,
    plantilla: args.plantilla,
    ultimoViajeId: canonico,
  });

  let anulados = 0;
  const opUid = str(args.operadorUid) || "sistema";
  for (const { id, data } of activos) {
    if (id === canonico) continue;
    const e = str(data.estado).toLowerCase();
    if (e === "cancelado" || e === "rechazado" || data.completado === true) {
      continue;
    }

    const choferUid =
      str(data.uidTaxista) ||
      str(data.taxistaId) ||
      str(data.corporativoChoferPreferidoUid);

    await db()
      .collection("viajes")
      .doc(id)
      .set(
        {
          estado: "cancelado",
          aceptado: false,
          rechazado: true,
          activo: false,
          completado: false,
          corporativoSupersedidoPor: canonico,
          corporativoSupersedidoEn: FieldValue.serverTimestamp(),
          canceladoPor: "encargado",
          canceladoOperadorUid: opUid,
          canceladoMotivo: "supersedido_actualizacion_ruta",
          updatedAt: FieldValue.serverTimestamp(),
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

    if (choferUid) {
      const userRef = db().collection("usuarios").doc(choferUid);
      const uSnap = await userRef.get();
      const u = (uSnap.data() ?? {}) as AnyMap;
      const patch: AnyMap = {
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      };
      if (str(u.viajeActivoId) === id) patch.viajeActivoId = "";
      if (str(u.siguienteViajeId) === id) patch.siguienteViajeId = "";
      if (
        patch.viajeActivoId !== undefined ||
        patch.siguienteViajeId !== undefined
      ) {
        await userRef.set(patch, { merge: true });
      }
    }
    anulados++;
  }
  return anulados;
}

function viajeCancelablePorEncargado(estado: string): boolean {
  const e = estado.toLowerCase();
  if (viajeEnCursoBloqueaEliminacionRuta(e)) return false;
  if (
    e === "completado" ||
    e === "finalizado" ||
    e === "cancelado" ||
    e === "rechazado" ||
    e === "cancelado_por_tiempo"
  ) {
    return false;
  }
  return true;
}

async function cancelarViajeCorporativoPorOperador(args: {
  viajeId: string;
  vData: AnyMap;
  operadorUid: string;
  canceladoPor: "encargado" | "admin";
}): Promise<string> {
  const estado = str(args.vData.estado);
  if (!viajeCancelablePorEncargado(estado)) return "";

  const viajeRef = db().collection("viajes").doc(args.viajeId);
  const choferUid =
    str(args.vData.uidTaxista) ||
    str(args.vData.taxistaId) ||
    str(args.vData.corporativoChoferPreferidoUid);

  await viajeRef.set(
    {
      estado: "cancelado",
      aceptado: false,
      rechazado: true,
      activo: false,
      completado: false,
      canceladoPor: args.canceladoPor,
      canceladoOperadorUid: args.operadorUid,
      canceladoEncargadoUid: args.operadorUid,
      canceladoEncargadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  if (choferUid) {
    const userRef = db().collection("usuarios").doc(choferUid);
    const uSnap = await userRef.get();
    const u = (uSnap.data() ?? {}) as AnyMap;
    const patch: AnyMap = {
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    };
    if (str(u.viajeActivoId) === args.viajeId) patch.viajeActivoId = "";
    if (str(u.siguienteViajeId) === args.viajeId) patch.siguienteViajeId = "";
    if (
      patch.viajeActivoId !== undefined ||
      patch.siguienteViajeId !== undefined
    ) {
      await userRef.set(patch, { merge: true });
    }
    try {
      await refrescarChoferOperacionCorporativa(choferUid);
    } catch (e) {
      logger.warn("eliminar ruta refresh chofer", { choferUid, e });
    }
  }
  return choferUid;
}

async function listarViajesActivosPlantillaHoy(args: {
  empresaId: string;
  plantillaId: string;
  plantilla: AnyMap;
  ultimoViajeId: string;
}): Promise<Array<{ id: string; data: AnyMap }>> {
  const out = new Map<string, AnyMap>();
  const ahora = new Date();

  async function considerar(id: string): Promise<void> {
    if (!id || out.has(id)) return;
    const snap = await db().collection("viajes").doc(id).get();
    if (!snap.exists) return;
    const v = (snap.data() ?? {}) as AnyMap;
    if (
      !viajeActivoDePlantillaHoy(
        v,
        args.empresaId,
        args.plantillaId,
        args.plantilla,
        ahora,
      )
    ) {
      return;
    }
    out.set(id, v);
  }

  if (args.ultimoViajeId) await considerar(args.ultimoViajeId);

  try {
    const q = await db()
      .collection("viajes")
      .where("corporativoPlantillaId", "==", args.plantillaId)
      .where("corporativoEmpresaId", "==", args.empresaId)
      .limit(12)
      .get();
    for (const doc of q.docs) {
      await considerar(doc.id);
    }
  } catch (e) {
    logger.warn("eliminar ruta listar viajes", {
      plantillaId: args.plantillaId,
      e,
    });
  }

  return [...out.entries()].map(([id, data]) => ({ id, data }));
}

/** Elimina plantilla corporativa; cancela viajes de hoy no iniciados si aplica. */
export async function ejecutarEliminarPlantillaCorporativa(args: {
  empresaId: string;
  plantillaId: string;
  operadorUid: string;
  canceladoPor: "encargado" | "admin";
}): Promise<{ ok: true; plantillaId: string; viajesCancelados: number }> {
  const empresaId = str(args.empresaId);
  const plantillaId = str(args.plantillaId);
  if (!empresaId || !plantillaId) {
    throw new HttpsError("invalid-argument", "Faltan empresaId o plantillaId");
  }

  const empRef = db().collection("empresas_corporativas").doc(empresaId);
  const empSnap = await empRef.get();
  if (!empSnap.exists) {
    throw new HttpsError("not-found", "Empresa no encontrada");
  }
  const ed = empSnap.data() ?? {};

  const plRef = empRef.collection("plantillas_ruta").doc(plantillaId);
  const plSnap = await plRef.get();
  if (!plSnap.exists) {
    throw new HttpsError("not-found", "Ruta no encontrada");
  }
  const d = (plSnap.data() ?? {}) as AnyMap;
  const plantillaNombre = str(d.nombre) || "Ruta corporativa";
  const empresaNombre = str(ed.nombre) || "Empresa";
  const choferUid = str(d.choferPreferidoUid);
  const rutaKey = rutaKeySegura(empresaId, plantillaId);

  const activosHoy = await listarViajesActivosPlantillaHoy({
    empresaId,
    plantillaId,
    plantilla: d,
    ultimoViajeId: str(d.ultimoViajeId),
  });

  for (const { data } of activosHoy) {
    const estado = str(data.estado);
    if (viajeEnCursoBloqueaEliminacionRuta(estado)) {
      throw new HttpsError(
        "failed-precondition",
        "No se puede eliminar: el chofer ya inició la ruta de hoy. " +
          "Esperá a que termine el viaje o contactá soporte RAI.",
      );
    }
  }

  const choferesAvisar = new Set<string>();
  let viajesCancelados = 0;
  for (const { id, data } of activosHoy) {
    if (!viajeCancelablePorEncargado(str(data.estado))) continue;
    const uidChofer = await cancelarViajeCorporativoPorOperador({
      viajeId: id,
      vData: data,
      operadorUid: args.operadorUid,
      canceladoPor: args.canceladoPor,
    });
    viajesCancelados += 1;
    if (uidChofer) choferesAvisar.add(uidChofer);
  }

  await limpiarAlertaPlantillaSinChofer(empresaId, plantillaId);

  if (choferUid) {
    await db()
      .collection("choferes_corporativos")
      .doc(choferUid)
      .set(
        {
          [`asignacionesRutas.${rutaKey}`]: FieldValue.delete(),
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
  }

  await plRef.delete();

  const avisoOrigen =
    args.canceladoPor === "admin"
      ? "RAI eliminó esta ruta."
      : "El encargado eliminó esta ruta.";
  for (const uid of choferesAvisar) {
    await enviarPushUid(
      uid,
      "🗑 Ruta corporativa eliminada",
      `${empresaNombre} · ${plantillaNombre}\n` +
        `${avisoOrigen} Ya no debés buscar pasajeros hoy.`,
      {
        type: "corporativo_ruta_eliminada",
        empresaId,
        plantillaId,
        rol: "chofer",
      },
    );
  }

  return { ok: true, plantillaId, viajesCancelados };
}

/**
 * Encargado: elimina la plantilla/ruta completa.
 * Cancela viajes de hoy aún no iniciados; bloquea si hay uno en curso.
 */
export const encargadoEliminarRutaCorporativa = onCall(
  { region: "us-central1", memory: "512MiB", timeoutSeconds: 90 },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }
    const empresaId = str(request.data?.empresaId);
    const plantillaId = str(request.data?.plantillaId);
    if (!empresaId || !plantillaId) {
      throw new HttpsError("invalid-argument", "Faltan empresaId o plantillaId");
    }

    const empRef = db().collection("empresas_corporativas").doc(empresaId);
    const empSnap = await empRef.get();
    if (!empSnap.exists) {
      throw new HttpsError("not-found", "Empresa no encontrada");
    }
    const ed = empSnap.data() ?? {};
    const encargados = Array.isArray(ed.encargadoUids)
      ? (ed.encargadoUids as string[]).map(String)
      : [];
    if (!encargados.includes(request.auth.uid)) {
      throw new HttpsError("permission-denied", "Solo el encargado de la empresa");
    }

    return ejecutarEliminarPlantillaCorporativa({
      empresaId,
      plantillaId,
      operadorUid: request.auth.uid,
      canceladoPor: "encargado",
    });
  },
);

/**
 * Encargado: quita un viaje de su historial (oculto, no borra datos de RAI).
 * Si el viaje aún no empezó, lo cancela antes de ocultar.
 */
export const encargadoOcultarViajeHistorialCorporativo = onCall(
  { region: "us-central1", memory: "256MiB", timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }
    const empresaId = str(request.data?.empresaId);
    const viajeId = str(request.data?.viajeId);
    if (!empresaId || !viajeId) {
      throw new HttpsError("invalid-argument", "Faltan empresaId o viajeId");
    }

    await assertEncargadoOAdminCorporativo(request.auth.uid, empresaId);

    const empRef = db().collection("empresas_corporativas").doc(empresaId);
    const histRef = empRef.collection("historial").doc(viajeId);
    const viajeRef = db().collection("viajes").doc(viajeId);

    const [histSnap, viajeSnap] = await Promise.all([
      histRef.get(),
      viajeRef.get(),
    ]);
    if (!histSnap.exists) {
      throw new HttpsError("not-found", "Registro no encontrado en historial");
    }

    const hd = (histSnap.data() ?? {}) as AnyMap;
    if (hd.ocultoEncargado === true) {
      return { ok: true, viajeId, yaOculto: true, viajeCancelado: false };
    }

    const vd = (viajeSnap.data() ?? {}) as AnyMap;
    if (viajeSnap.exists && str(vd.corporativoEmpresaId) !== empresaId) {
      throw new HttpsError("permission-denied", "Viaje de otra empresa");
    }

    const estadoHist = str(hd.estado).toLowerCase();
    const estadoViaje = str(vd.estado).toLowerCase();

    if (
      estadoHist === "anulacion_pendiente" ||
      vd.corporativoAnulacionPendiente === true
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Hay una incidencia pendiente de RAI. Esperá la respuesta antes de quitar este viaje.",
      );
    }
    if (
      viajeEnCursoBloqueaEliminacionRuta(estadoViaje) ||
      viajeEnCursoBloqueaEliminacionRuta(estadoHist)
    ) {
      throw new HttpsError(
        "failed-precondition",
        "No se puede quitar: el chofer tiene esta ruta en curso.",
      );
    }

    let viajeCancelado = false;
    if (viajeSnap.exists && viajeCancelablePorEncargado(estadoViaje)) {
      await cancelarViajeCorporativoPorOperador({
        viajeId,
        vData: vd,
        operadorUid: request.auth.uid,
        canceladoPor: "encargado",
      });
      viajeCancelado = true;
    }

    const patchHist: AnyMap = {
      ocultoEncargado: true,
      ocultoEncargadoEn: FieldValue.serverTimestamp(),
      ocultoEncargadoPorUid: request.auth.uid,
      actualizadoEn: FieldValue.serverTimestamp(),
    };
    if (viajeCancelado) {
      patchHist.estado = "cancelado";
      patchHist.ocultoMotivo = "encargado_quito_historial";
    }

    await histRef.set(patchHist, { merge: true });

    return {
      ok: true,
      viajeId,
      viajeCancelado,
      advertenciaCobro: estadoHist === "completado" && !viajeCancelado,
    };
  },
);

function esViajeCorporativoDoc(v: AnyMap): boolean {
  return (
    v.corporativo === true ||
    str(v.canalAsignacion) === CANAL_CORPORATIVO_FIJO ||
    str(v.categoria).toLowerCase() === "corporativo" ||
    str(v.recaudoDestino) === "empresa_corporativa"
  );
}

function esChoferAsignadoViajeCorporativo(v: AnyMap, uid: string): boolean {
  const u = str(uid);
  if (!u) return false;
  return (
    str(v.uidTaxista) === u ||
    str(v.taxistaId) === u ||
    str(v.corporativoChoferPreferidoUid) === u ||
    str(v.corporativoChoferAsignadoUid) === u
  );
}

function paradasHechasSet(v: AnyMap, total: number): Set<number> {
  const raw = v.corporativoParadasHechas;
  if (Array.isArray(raw)) {
    return new Set(
      raw
        .filter((x): x is number => typeof x === "number" && Number.isFinite(x))
        .map((x) => Math.trunc(x))
        .filter((i) => i >= 0 && i < total),
    );
  }
  let idx = 0;
  if (typeof v.corporativoParadaActualIdx === "number") {
    idx = Math.trunc(v.corporativoParadaActualIdx);
  } else if (typeof v.multiparadaLegCompletadas === "number") {
    idx = Math.trunc(v.multiparadaLegCompletadas);
  }
  idx = Math.max(0, Math.min(idx, total));
  const out = new Set<number>();
  for (let i = 0; i < idx; i++) out.add(i);
  return out;
}

function paradasAbiertasSet(v: AnyMap, total: number): Set<number> {
  const raw = v.corporativoParadasAbiertas;
  if (Array.isArray(raw)) {
    return new Set(
      raw
        .filter((x): x is number => typeof x === "number" && Number.isFinite(x))
        .map((x) => Math.trunc(x))
        .filter((i) => i >= 0 && i < total),
    );
  }
  return new Set<number>();
}

function llegadaEmpresaConfirmada(v: AnyMap): boolean {
  return (
    v.corporativoLlegadaEmpresaEn != null ||
    v.clienteAbordo === true ||
    v.pickupConfirmadoEn != null
  );
}

/**
 * Chofer corporativo informativo: marcar paradas / preparar ruta sin escribir
 * `viajes` desde el cliente (evita permission-denied en reglas).
 */
export const taxistaActualizarRutaCorpInformativa = onCall(
  { region: "us-central1", memory: "256MiB", timeoutSeconds: 45 },
  async (request) => {
    const uid = str(request.auth?.uid);
    if (!uid) throw new HttpsError("unauthenticated", "No autenticado");

    const viajeId = str(request.data?.viajeId);
    const accion = str(request.data?.accion).toLowerCase();
    if (!viajeId) {
      throw new HttpsError("invalid-argument", "Falta viajeId.");
    }
    if (
      ![
        "marcar_abierta",
        "marcar_hecha",
        "marcar_recogida_abierta",
        "preparar",
        "marcar_todas_hechas",
      ].includes(accion)
    ) {
      throw new HttpsError("invalid-argument", "Acción no válida.");
    }

    const ref = db().collection("viajes").doc(viajeId);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Viaje no encontrado.");
    }
    const v = (snap.data() ?? {}) as AnyMap;
    if (!esViajeCorporativoDoc(v)) {
      throw new HttpsError("failed-precondition", "No es viaje corporativo.");
    }
    if (!esChoferAsignadoViajeCorporativo(v, uid)) {
      throw new HttpsError("permission-denied", "Ruta no asignada a tu cuenta.");
    }
    if (v.completado === true) {
      return { ok: true, yaCompletado: true };
    }

    const now = FieldValue.serverTimestamp();
    let patch: AnyMap = {
      corporativoModoInformativo: true,
      updatedAt: now,
      actualizadoEn: now,
    };
    let completa = false;

    if (accion === "marcar_recogida_abierta") {
      const estadoRec = str(v.estado).toLowerCase();
      patch = {
        ...patch,
        corporativoRecogidaAbierta: true,
        corporativoRecogidaAbiertaEn: now,
      };
      if (estadoRec !== "en_curso" && estadoRec !== "completado") {
        patch.estado = "en_curso";
      }
    } else if (accion === "marcar_abierta") {
      const paradaIdx = Math.trunc(Number(request.data?.paradaIdx ?? -1));
      const total = Math.trunc(Number(request.data?.totalPasajeros ?? 0));
      if (paradaIdx < 0 || total <= 0 || paradaIdx >= total) {
        throw new HttpsError("invalid-argument", "Parada inválida.");
      }
      const abiertas = paradasAbiertasSet(v, total);
      abiertas.add(paradaIdx);
      const estadoPar = str(v.estado).toLowerCase();
      patch = {
        ...patch,
        corporativoParadasAbiertas: [...abiertas].sort((a, b) => a - b),
        corporativoParadaAbiertaEn: now,
      };
      if (estadoPar !== "en_curso" && estadoPar !== "completado") {
        patch.estado = "en_curso";
      }
    } else if (accion === "marcar_hecha") {
      const paradaIdx = Math.trunc(Number(request.data?.paradaIdx ?? -1));
      const total = Math.trunc(Number(request.data?.totalPasajeros ?? 0));
      if (paradaIdx < 0 || total <= 0 || paradaIdx >= total) {
        throw new HttpsError("invalid-argument", "Parada inválida.");
      }
      const abiertas = paradasAbiertasSet(v, total);
      if (!abiertas.has(paradaIdx)) {
        throw new HttpsError(
          "failed-precondition",
          "Abrí Waze o Maps a esta parada antes de marcar la entrega.",
        );
      }
      const hechas = paradasHechasSet(v, total);
      hechas.add(paradaIdx);
      const list = [...hechas].sort((a, b) => a - b);
      completa = list.length >= total;
      for (const i of list) abiertas.add(i);
      patch = {
        ...patch,
        corporativoParadasHechas: list,
        corporativoParadasAbiertas: [...abiertas].sort((a, b) => a - b),
        corporativoParadaActualIdx: list.length,
        multiparadaLegsTotal: total,
        multiparadaLegCompletadas: list.length,
        multiparadaCompleta: completa,
        corporativoParadaActualizadaEn: now,
      };
    } else if (accion === "marcar_todas_hechas") {
      let total = Math.trunc(Number(request.data?.totalPasajeros ?? 0));
      const pas = v.corporativoPasajeros;
      if (Array.isArray(pas) && pas.length > 0) {
        total = Math.max(total, pas.length);
      }
      if (total <= 0) {
        completa = true;
        patch = {
          ...patch,
          multiparadaCompleta: true,
          multiparadaLegCompletadas: 0,
          multiparadaLegsTotal: 0,
        };
      } else {
        const list = Array.from({ length: total }, (_, i) => i);
        completa = true;
        patch = {
          ...patch,
          corporativoParadasHechas: list,
          corporativoParadasAbiertas: list,
          corporativoParadaActualIdx: total,
          multiparadaLegsTotal: total,
          multiparadaLegCompletadas: total,
          multiparadaCompleta: true,
          corporativoParadaActualizadaEn: now,
        };
      }
    } else if (accion === "preparar") {
      // Cierre contable: habilita completarViajePorTaxista (exige en_curso).
      const total = Math.trunc(Number(request.data?.totalPasajeros ?? 0));
      if (total > 0) {
        patch.multiparadaLegsTotal = total;
      }
      const estadoPrep = str(v.estado).toLowerCase();
      if (
        estadoPrep !== "completado" &&
        estadoPrep !== "cancelado" &&
        estadoPrep !== "rechazado"
      ) {
        patch.estado = "en_curso";
      }
    }

    await ref.set(patch, { merge: true });
    return { ok: true, completa };
  },
);

/** Chofer abre su ruta corporativa publicada → viaje en curso (sin bloqueo de reglas pool). */
export const taxistaAbrirViajeCorporativoEnCurso = onCall(
  { region: "us-central1", memory: "256MiB", timeoutSeconds: 45 },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }
    const viajeId = str(request.data?.viajeId);
    return ejecutarPromoverViajeCorporativoEnCurso({
      choferUid: request.auth.uid,
      viajeId: viajeId || undefined,
    });
  },
);

/** ADM: alerta sin chofer + sync operativa al asignar/cambiar chofer u hora. */
export const onCorporativoPlantillaRutaSinChoferAlert = onDocumentWritten(
  {
    document: "empresas_corporativas/{empresaId}/plantillas_ruta/{plantillaId}",
    region: "us-central1",
    memory: "512MiB",
    timeoutSeconds: 120,
  },
  async (event) => {
    const empresaId = str(event.params.empresaId);
    const plantillaId = str(event.params.plantillaId);
    if (!empresaId || !plantillaId) return;

    const after = event.data?.after;
    if (!after?.exists) {
      await limpiarAlertaPlantillaSinChofer(empresaId, plantillaId);
      return;
    }

    const before = (event.data?.before?.data() ?? {}) as AnyMap;
    const data = (after.data() ?? {}) as AnyMap;
    const choferUid = str(data.choferPreferidoUid);
    const choferAntes = str(before.choferPreferidoUid);
    const activa = data.activa !== false;
    const horaAntes =
      str(before.horaRecogidaGrupo) || str(before.horaRecogida);
    const horaAhora =
      str(data.horaRecogidaGrupo) || str(data.horaRecogida);
    const choferCambio = choferUid !== choferAntes;
    const horaCambio = horaAntes.length > 0 && horaAntes !== horaAhora;
    const pasajerosCambio =
      firmaPasajerosPlantilla(before) !== firmaPasajerosPlantilla(data);
    const precioAntes = Number(before.precioAcordado ?? 0);
    const precioAhora = Number(data.precioAcordado ?? 0);
    const precioCambio = precioAntes !== precioAhora;
    const origenCambio =
      str(before.origenLabel) !== str(data.origenLabel) ||
      Number(before.origenLat) !== Number(data.origenLat) ||
      Number(before.origenLon) !== Number(data.origenLon);

    if (choferUid || !activa) {
      await limpiarAlertaPlantillaSinChofer(empresaId, plantillaId);
    } else if (activa) {
      await alertarPlantillaSinChofer(empresaId, plantillaId, data);
    }

    if (!choferUid && choferAntes) {
      try {
        await refrescarChoferOperacionCorporativa(choferAntes);
      } catch (e) {
        logger.warn("trigger desasignar refresh chofer", {
          empresaId,
          plantillaId,
          choferAntes,
          e,
        });
      }
      return;
    }

    if (!choferUid || !activa) return;

    if (
      !choferCambio &&
      !horaCambio &&
      !pasajerosCambio &&
      !precioCambio &&
      !origenCambio
    ) {
      return;
    }

    try {
      await ejecutarSincronizacionOperativaPlantilla({
        empresaId,
        plantillaId,
        horaAnterior: horaCambio ? horaAntes : undefined,
        enviarPushHora: horaCambio && !choferCambio,
        notificarCambioPasajeros:
          pasajerosCambio && !choferCambio && !horaCambio,
        forzarRecogidaHoy: choferCambio || horaCambio || precioCambio || origenCambio,
        notificarChoferAsignacion: false,
        operadorUid: choferUid,
      });
    } catch (e) {
      logger.warn("trigger sync plantilla operativa", {
        empresaId,
        plantillaId,
        choferCambio,
        horaCambio,
        e,
      });
    }
  },
);

/** Mantiene chofer_operacion al día cuando cambia un viaje corporativo. */
export const onViajeCorporativoOperacionRefresh = onDocumentWritten(
  {
    document: "viajes/{viajeId}",
    region: "us-central1",
    memory: "256MiB",
  },
  async (event) => {
    const after = (event.data?.after?.data() ?? {}) as AnyMap;
    const before = (event.data?.before?.data() ?? {}) as AnyMap;
    const v = Object.keys(after).length > 0 ? after : before;
    if (!v || Object.keys(v).length === 0) return;
    const esCorp =
      v.corporativo === true ||
      str(v.canalAsignacion) === CANAL_CORPORATIVO_FIJO ||
      str(v.categoria).toLowerCase() === "corporativo";
    if (!esCorp) return;
    const chofer =
      str(after.uidTaxista) ||
      str(after.corporativoChoferAsignadoUid) ||
      str(after.corporativoChoferPreferidoUid) ||
      str(before.uidTaxista) ||
      str(before.corporativoChoferAsignadoUid) ||
      str(before.corporativoChoferPreferidoUid);
    if (!chofer) return;
    try {
      await refrescarChoferOperacionCorporativa(chofer);
    } catch (e) {
      logger.warn("onViajeCorporativoOperacionRefresh", {
        viajeId: event.params.viajeId,
        chofer,
        e,
      });
    }
  },
);

async function notificarAdminsCorporativo(
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  try {
    const admins = await db()
      .collection("usuarios")
      .where("rol", "==", "admin")
      .limit(40)
      .get();
    for (const doc of admins.docs) {
      await enviarPushUid(doc.id, title, body, { ...data, rol: "admin" });
    }
  } catch (e) {
    logger.warn("notificarAdminsCorporativo", { e });
  }
}

/**
 * Encargado/admin: da de baja toda la empresa del servicio corporativo RAI.
 * Cancela viajes de hoy no iniciados, elimina plantillas y desactiva la empresa.
 */
export async function ejecutarDarDeBajaEmpresaCorporativa(args: {
  empresaId: string;
  operadorUid: string;
  motivo?: string;
  canceladoPor?: "encargado" | "admin";
}): Promise<{
  ok: true;
  empresaId: string;
  plantillasEliminadas: number;
  viajesCancelados: number;
}> {
  const empresaId = str(args.empresaId);
  const operadorUid = str(args.operadorUid);
  if (!empresaId || !operadorUid) {
    throw new HttpsError("invalid-argument", "Faltan empresaId u operadorUid");
  }

  const empRef = db().collection("empresas_corporativas").doc(empresaId);
  const empSnap = await empRef.get();
  if (!empSnap.exists) {
    throw new HttpsError("not-found", "Empresa no encontrada");
  }
  const ed = (empSnap.data() ?? {}) as AnyMap;
  if (ed.activa === false) {
    throw new HttpsError(
      "failed-precondition",
      "Esta empresa ya no está activa en RAI.",
    );
  }

  const empresaNombre = str(ed.nombre) || "Empresa";
  const canceladoPor = args.canceladoPor ?? "encargado";
  const motivo = str(args.motivo).slice(0, 500);

  const plSnap = await empRef.collection("plantillas_ruta").get();
  const plantillas = plSnap.docs.map((d) => ({
    id: d.id,
    data: (d.data() ?? {}) as AnyMap,
  }));

  for (const pl of plantillas) {
    const activosHoy = await listarViajesActivosPlantillaHoy({
      empresaId,
      plantillaId: pl.id,
      plantilla: pl.data,
      ultimoViajeId: str(pl.data.ultimoViajeId),
    });
    for (const { data } of activosHoy) {
      if (viajeEnCursoBloqueaEliminacionRuta(str(data.estado))) {
        const nombreRuta = str(pl.data.nombre) || "una ruta";
        throw new HttpsError(
          "failed-precondition",
          `No se puede dar de baja: el chofer ya inició «${nombreRuta}» hoy. ` +
            "Esperá a que termine el viaje o contactá soporte RAI.",
        );
      }
    }
  }

  let plantillasEliminadas = 0;
  let viajesCancelados = 0;
  const choferesAvisar = new Set<string>();

  for (const pl of plantillas) {
    const res = await ejecutarEliminarPlantillaCorporativa({
      empresaId,
      plantillaId: pl.id,
      operadorUid,
      canceladoPor,
    });
    plantillasEliminadas += 1;
    viajesCancelados += res.viajesCancelados;
    const choferUid = str(pl.data.choferPreferidoUid);
    if (choferUid) choferesAvisar.add(choferUid);
  }

  await empRef.set(
    {
      activa: false,
      contratoActivo: false,
      desactivadaEn: FieldValue.serverTimestamp(),
      desactivadaPorUid: operadorUid,
      bajaEncargadoEn: FieldValue.serverTimestamp(),
      bajaEncargadoUid: operadorUid,
      bajaMotivo: motivo || FieldValue.delete(),
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const avisoChofer =
    canceladoPor === "admin"
      ? "RAI dio de baja esta empresa."
      : "El encargado dio de baja la empresa del servicio corporativo.";
  for (const uid of choferesAvisar) {
    await enviarPushUid(
      uid,
      "🏢 Empresa fuera de RAI corporativo",
      `${empresaNombre}\n${avisoChofer} Ya no debés buscar pasajeros de esta empresa.`,
      {
        type: "corporativo_empresa_baja",
        empresaId,
        rol: "chofer",
      },
    );
    try {
      await refrescarChoferOperacionCorporativa(uid);
    } catch (e) {
      logger.warn("baja empresa refresh chofer", { uid, e });
    }
  }

  const motivoTxt = motivo ? `\nMotivo: ${motivo}` : "";
  await notificarAdminsCorporativo(
    "🏢 Empresa corporativa dada de baja",
    `${empresaNombre} · ${canceladoPor === "admin" ? "por RAI" : "por el encargado"}.${motivoTxt}`,
    {
      type: "corporativo_empresa_baja",
      empresaId,
      rol: "admin",
    },
  );

  return {
    ok: true,
    empresaId,
    plantillasEliminadas,
    viajesCancelados,
  };
}

/** Encargado: deja de operar en RAI corporativo (baja voluntaria de la empresa). */
export const encargadoDarDeBajaEmpresaCorporativa = onCall(
  { region: "us-central1", memory: "512MiB", timeoutSeconds: 120 },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }
    const empresaId = str(request.data?.empresaId);
    if (!empresaId) {
      throw new HttpsError("invalid-argument", "Falta empresaId");
    }

    await assertEncargadoOAdminCorporativo(request.auth.uid, empresaId);

    return ejecutarDarDeBajaEmpresaCorporativa({
      empresaId,
      operadorUid: request.auth.uid,
      motivo: str(request.data?.motivo),
      canceladoPor: "encargado",
    });
  },
);

/** Chofer: fuerza refresco del panel operativo (pull-to-refresh en app). */
export const taxistaRefrescarOperacionCorporativa = onCall(
  { region: "us-central1", memory: "256MiB", timeoutSeconds: 45 },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }
    await refrescarChoferOperacionCorporativa(request.auth.uid);
    const snap = await db()
      .collection("chofer_operacion")
      .doc(request.auth.uid)
      .get();
    return {
      ok: true,
      actualizado: snap.exists,
      totalRutas: Number((snap.data()?.resumen as AnyMap)?.totalRutas ?? 0),
      viajesHoy: Number(
        (snap.data()?.resumen as AnyMap)?.viajesPublicadosHoy ?? 0,
      ),
    };
  },
);

/** Tras completar viaje corporativo: sincroniza chofer_operacion (listoParaAbrir → cerrado). */
export const onCorporativoViajeCompletadoSyncOperacion = onDocumentWritten(
  {
    document: "viajes/{viajeId}",
    region: "us-central1",
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  async (event) => {
    const before = (event.data?.before?.data() ?? undefined) as AnyMap | undefined;
    const after = (event.data?.after?.data() ?? undefined) as AnyMap | undefined;
    if (!after || after.corporativo !== true) return;
    const wasDone = before?.completado === true;
    const nowDone = after.completado === true;
    if (!nowDone || wasDone) return;
    const uid = str(after.uidTaxista ?? after.taxistaId);
    if (!uid) return;
    try {
      await refrescarChoferOperacionCorporativa(uid);
      logger.info("onCorporativoViajeCompletadoSyncOperacion", {
        viajeId: str(event.params?.viajeId),
        uid,
      });
    } catch (e) {
      logger.warn("onCorporativoViajeCompletadoSyncOperacion", {
        viajeId: str(event.params?.viajeId),
        uid,
        e,
      });
    }
  },
);

