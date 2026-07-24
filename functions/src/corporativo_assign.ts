/**
 * Asignación exclusiva de viaje corporativo al chofer fijo de la ruta.
 */
import {
  FieldValue,
  type DocumentReference,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions";

type AnyMap = Record<string, unknown>;

export const CANAL_CORPORATIVO_FIJO = "corporativo_fijo";

function str(v: unknown): string {
  return String(v ?? "").trim();
}

/** Asigna el viaje al chofer fijo: no aparece en pool público. */
export async function asignarChoferCorporativoFijo(args: {
  viajeRef: DocumentReference;
  choferUid: string;
  esAhora: boolean;
}): Promise<boolean> {
  const choferUid = str(args.choferUid);
  if (!choferUid) return false;

  const db = getFirestore();
  const corpSnap = await db.collection("choferes_corporativos").doc(choferUid).get();
  const corp = (corpSnap.data() ?? {}) as AnyMap;
  const estadoCorp = str(corp.estado).toLowerCase();
  if (!corpSnap.exists || (estadoCorp !== "aprobado" && estadoCorp !== "activo") || corp.activo === false) {
    logger.warn("asignarChoferCorporativoFijo chofer-no-corporativo", { choferUid });
    return false;
  }

  const uRef = db.collection("usuarios").doc(choferUid);

  try {
    await limpiarViajeActivoHuerfanoChofer(db, choferUid);
    return await db.runTransaction(async (tx) => {
      const [vSnap, uSnap] = await Promise.all([
        tx.get(args.viajeRef),
        tx.get(uRef),
      ]);
      if (!vSnap.exists) return false;
      const v = (vSnap.data() ?? {}) as AnyMap;
      const u = (uSnap.data() ?? {}) as AnyMap;

      const yaAsignado = str(v.uidTaxista ?? v.taxistaId);
      if (yaAsignado && yaAsignado !== choferUid) return false;

      const nombre = str(u.nombre ?? u.displayName) || "Conductor RAI";
      const telefono = str(u.telefono);
      const placa = str(u.placa);
      const tipoVeh = str(u.tipoVehiculo ?? "🚗 NORMAL");

      const viajeActivoId = str(u.viajeActivoId);
      const programado = v.programado === true && args.esAhora !== true;

      let ventanaAbierta = args.esAhora;
      if (!ventanaAbierta) {
        const pub = v.publishAt ?? v.acceptAfter ?? v.startWindowAt;
        const publishMs =
          pub instanceof Timestamp ? pub.toMillis() : Date.now();
        if (publishMs <= Date.now()) {
          ventanaAbierta = true;
        } else {
          const minPub =
            typeof v.corporativoMinutosPublicarAntes === "number"
              ? Math.max(3, Math.trunc(v.corporativoMinutosPublicarAntes as number))
              : 90;
          const fh = v.fechaHora;
          let recogidaMs = Date.now();
          if (fh instanceof Timestamp) {
            recogidaMs = fh.toDate().getTime();
          } else if (fh instanceof Date) {
            recogidaMs = fh.getTime();
          }
          const diffMin = (recogidaMs - Date.now()) / 60000;
          const ventanaMin = Math.min(Math.max(minPub + 10, 20), 180);
          ventanaAbierta = diffMin <= ventanaMin || diffMin <= 30;
        }
      }

      let activoBloqueante = false;
      if (viajeActivoId && viajeActivoId !== args.viajeRef.id) {
        const otroSnap = await tx.get(db.collection("viajes").doc(viajeActivoId));
        activoBloqueante =
          otroSnap.exists &&
          viajeOperativoEnCurso((otroSnap.data() ?? {}) as AnyMap, choferUid);
      }
      const activoViaje = ventanaAbierta && !activoBloqueante;

      const patchViaje: AnyMap = {
        canalAsignacion: CANAL_CORPORATIVO_FIJO,
        corporativoChoferAsignadoUid: choferUid,
        corporativoChoferPreferidoUid:
          str(v.corporativoChoferPreferidoUid) || choferUid,
        // Siempre amarrar taxista en corporativo (la ventana solo controla activo/en curso).
        uidTaxista: choferUid,
        taxistaId: choferUid,
        nombreTaxista: nombre,
        telefono,
        placa,
        tipoVehiculo: tipoVeh,
        estado: ventanaAbierta ? "aceptado" : str(v.estado) || "pendiente",
        aceptado: ventanaAbierta || v.aceptado === true,
        rechazado: false,
        activo: activoViaje,
        programado,
        aceptadoEn: ventanaAbierta
          ? FieldValue.serverTimestamp()
          : v.aceptadoEn ?? FieldValue.serverTimestamp(),
        reservadoPor: "",
        reservadoHasta: null,
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      };

      tx.set(args.viajeRef, patchViaje, { merge: true });

      const patchUser: AnyMap = {
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      };

      if (activoViaje) {
        patchUser.viajeActivoId = args.viajeRef.id;
      } else if (viajeActivoId !== args.viajeRef.id) {
        patchUser.siguienteViajeId = args.viajeRef.id;
      }

      tx.set(uRef, patchUser, { merge: true });
      return true;
    });
  } catch (e) {
    logger.error("asignarChoferCorporativoFijo", {
      viajeId: args.viajeRef.id,
      choferUid,
      e,
    });
    return false;
  }
}

/** Repara viajes corporativos con chofer en corp* pero uidTaxista vacío (bloquea la app). */
export async function repararChoferViajeCorporativoSiHaceFalta(
  viajeId: string,
): Promise<boolean> {
  const id = str(viajeId);
  if (!id) return false;
  const db = getFirestore();
  const vRef = db.collection("viajes").doc(id);
  const vSnap = await vRef.get();
  if (!vSnap.exists) return false;
  const v = (vSnap.data() ?? {}) as AnyMap;
  if (!esViajeCorporativoDoc(v)) return false;
  const chofer = str(
    v.corporativoChoferAsignadoUid ?? v.corporativoChoferPreferidoUid,
  );
  if (!chofer) return false;
  const tx = str(v.uidTaxista ?? v.taxistaId);
  const dentroVentana = corporativoListoParaAbrirEnCurso(v);
  if (tx === chofer) {
    if (dentroVentana && v.activo !== true) {
      return asignarChoferCorporativoFijo({
        viajeRef: vRef,
        choferUid: chofer,
        esAhora: true,
      });
    }
    return true;
  }
  return asignarChoferCorporativoFijo({
    viajeRef: vRef,
    choferUid: chofer,
    esAhora: dentroVentana,
  });
}

function esViajeCorporativoDoc(v: AnyMap): boolean {
  const canal = str(v.canalAsignacion);
  if (canal === CANAL_CORPORATIVO_FIJO) return true;
  if (v.corporativo === true) return true;
  if (str(v.categoria).toLowerCase() === "corporativo") return true;
  if (str(v.recaudoDestino) === "empresa_corporativa") return true;
  return false;
}

function viajeCorporativoAsignadoA(v: AnyMap, choferUid: string): boolean {
  if (!esViajeCorporativoDoc(v)) return false;
  const tx = str(v.uidTaxista ?? v.taxistaId);
  if (tx === choferUid) return true;
  if (tx && tx !== choferUid) return false;
  const pref = str(v.corporativoChoferAsignadoUid ?? v.corporativoChoferPreferidoUid);
  return pref === choferUid;
}

function estadoPermiteVerViajeCorporativo(v: AnyMap): boolean {
  if (v.completado === true) return false;
  const estado = str(v.estado).toLowerCase();
  return (
    estado === "aceptado" ||
    estado === "en_camino_pickup" ||
    estado === "encaminopickup" ||
    estado === "a_bordo" ||
    estado === "abordo" ||
    estado === "en_origen_esperando_codigo" ||
    estado === "esperando_codigo_encargado" ||
    estado === "pendiente_codigo" ||
    estado === "en_curso" ||
    estado === "encurso" ||
    estado === "pendiente"
  );
}

function fechaHoraMs(v: AnyMap): number {
  const fh = v.fechaHora;
  if (fh instanceof Timestamp) return fh.toDate().getTime();
  if (fh instanceof Date) return fh.getTime();
  return 0;
}

const TZ_RD_OFFSET = "-04:00";

function diaCalendarioRd(ref: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Santo_Domingo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(ref);
}

/** Normaliza a HH:mm 24h (misma regla que corporativo_rutas / app). */
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
  let h = Number.parseInt(parts[0], 10);
  const mMatch = String(parts[1]).trim().match(/^(\d{1,2})/);
  const m = mMatch ? Number.parseInt(mMatch[1], 10) : NaN;
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

function parseHoraCorporativo(horaStr: string): { h: number; m: number } | null {
  const norm = normalizarHoraHHmm(horaStr);
  if (!norm) return null;
  const [hs, ms] = norm.split(":");
  return { h: Number.parseInt(hs, 10), m: Number.parseInt(ms, 10) };
}

function recogidaConHoraZonaRd(
  horaStr: string,
  ref: Date = new Date(),
): Date | null {
  const p = parseHoraCorporativo(horaStr);
  if (!p) return null;
  const day = diaCalendarioRd(ref);
  const hh = String(p.h).padStart(2, "0");
  const mm = String(p.m).padStart(2, "0");
  const d = new Date(`${day}T${hh}:${mm}:00${TZ_RD_OFFSET}`);
  return Number.isFinite(d.getTime()) ? d : null;
}

function esMismoDiaCalendarioRd(a: Date, b: Date): boolean {
  return diaCalendarioRd(a) === diaCalendarioRd(b);
}

function recogidaOperativaDesdeViaje(v: AnyMap): Date | null {
  const ms = fechaHoraMs(v);
  if (ms > 0) return new Date(ms);
  for (const key of [
    "horaRecogidaGrupo",
    "horaRecogida",
    "corporativoHoraRecogidaGrupo",
  ]) {
    const hora = str(v[key]);
    if (!hora) continue;
    const parsed = recogidaConHoraZonaRd(hora);
    if (parsed) return parsed;
  }
  return null;
}

async function choferOperacionMarcaListo(
  db: ReturnType<typeof getFirestore>,
  choferUid: string,
  viajeId: string,
): Promise<boolean> {
  const opSnap = await db.collection("chofer_operacion").doc(choferUid).get();
  const op = (opSnap.data() ?? {}) as AnyMap;
  for (const raw of [op.viajesHoy, op.rutasFijas, op.rutasActivasLista]) {
    if (!Array.isArray(raw)) continue;
    for (const item of raw) {
      if (!item || typeof item !== "object") continue;
      const m = item as AnyMap;
      if (m.listoParaAbrir !== true) continue;
      const id = str(m.viajeId ?? m.viajeHoyId);
      if (id === viajeId) return true;
    }
  }
  return false;
}

export function corporativoListoParaAbrirEnCurso(v: AnyMap): boolean {
  if (!estadoPermiteVerViajeCorporativo(v)) return false;
  const chofer = str(
    v.uidTaxista ??
      v.taxistaId ??
      v.corporativoChoferAsignadoUid ??
      v.corporativoChoferPreferidoUid,
  );
  const recogida = recogidaOperativaDesdeViaje(v);
  const ahora = new Date();
  const minParaRecogida = recogida
    ? (recogida.getTime() - ahora.getTime()) / 60000
    : 9999;
  if (esViajeCorporativoDoc(v) && chofer) {
    const minPub =
      typeof v.corporativoMinutosPublicarAntes === "number"
        ? Math.max(3, Math.trunc(v.corporativoMinutosPublicarAntes as number))
        : 90;
    const ventanaMin = Math.min(Math.max(minPub + 10, 20), 180);
    if (minParaRecogida <= ventanaMin && minParaRecogida >= -90) return true;
    const publicadoHoy =
      v.publicado === true || v.corporativoPublicadoEn != null;
    if (
      publicadoHoy &&
      recogida &&
      esMismoDiaCalendarioRd(recogida, ahora) &&
      minParaRecogida <= 180 &&
      minParaRecogida >= -120
    ) {
      return true;
    }
    if (recogida && esMismoDiaCalendarioRd(recogida, ahora)) {
      const pub = v.publishAt ?? v.acceptAfter ?? v.startWindowAt;
      if (
        pub instanceof Timestamp &&
        pub.toDate().getTime() <= ahora.getTime()
      ) {
        return true;
      }
      if (minParaRecogida <= minPub + 45) return true;
    }
  }
  const pub = v.publishAt ?? v.acceptAfter ?? v.startWindowAt;
  const publishMs =
    pub instanceof Timestamp ? pub.toMillis() : ahora.getTime();
  return publishMs <= ahora.getTime();
}

async function limpiarViajeActivoHuerfanoChofer(
  db: ReturnType<typeof getFirestore>,
  choferUid: string,
): Promise<void> {
  const uRef = db.collection("usuarios").doc(choferUid);
  const uSnap = await uRef.get();
  const activo = str(uSnap.data()?.viajeActivoId);
  if (!activo) return;
  const vSnap = await db.collection("viajes").doc(activo).get();
  if (!vSnap.exists) {
    await uRef.set(
      {
        viajeActivoId: "",
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return;
  }
  const v = (vSnap.data() ?? {}) as AnyMap;
  const tx = str(v.uidTaxista ?? v.taxistaId);
  if (tx && tx !== choferUid) {
    await uRef.set(
      {
        viajeActivoId: "",
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return;
  }
  const estado = str(v.estado).toLowerCase();
  const terminal =
    v.completado === true ||
    estado === "completado" ||
    estado === "cancelado" ||
    estado === "finalizado" ||
    estado === "rechazado";
  if (v.activo !== true || terminal || estado === "pendiente") {
    await uRef.set(
      {
        viajeActivoId: "",
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
}

function viajeOperativoEnCurso(v: AnyMap, choferUid: string): boolean {
  const tx = str(v.uidTaxista ?? v.taxistaId);
  if (tx !== choferUid) return false;
  if (v.activo !== true || v.completado === true) return false;
  const estado = str(v.estado).toLowerCase();
  if (
    estado === "pendiente" ||
    estado === "completado" ||
    estado === "cancelado" ||
    estado === "finalizado" ||
    estado === "rechazado"
  ) {
    return false;
  }
  return (
    estado === "aceptado" ||
    estado === "en_camino_pickup" ||
    estado === "encaminopickup" ||
    estado === "a_bordo" ||
    estado === "abordo" ||
    estado === "en_origen_esperando_codigo" ||
    estado === "esperando_codigo_encargado" ||
    estado === "pendiente_codigo" ||
    estado === "en_curso" ||
    estado === "encurso"
  );
}

/** Promueve ruta corporativa a viaje activo del chofer (Admin SDK — sin reglas cliente). */
export async function ejecutarPromoverViajeCorporativoEnCurso(args: {
  choferUid: string;
  viajeId?: string;
}): Promise<{ resultado: string; viajeId?: string }> {
  const choferUid = str(args.choferUid);
  if (!choferUid) return { resultado: "error" };

  const db = getFirestore();
  let viajeId = str(args.viajeId);

  if (!viajeId) {
    const uSnap = await db.collection("usuarios").doc(choferUid).get();
    const u = (uSnap.data() ?? {}) as AnyMap;
    for (const raw of [u.viajeActivoId, u.siguienteViajeId]) {
      const id = str(raw);
      if (!id) continue;
      const vSnap = await db.collection("viajes").doc(id).get();
      if (!vSnap.exists) continue;
      const v = (vSnap.data() ?? {}) as AnyMap;
      if (viajeCorporativoAsignadoA(v, choferUid) && estadoPermiteVerViajeCorporativo(v)) {
        viajeId = id;
        break;
      }
    }
  }

  if (!viajeId) return { resultado: "no_encontrado" };

  await limpiarViajeActivoHuerfanoChofer(db, choferUid);

  const vRef = db.collection("viajes").doc(viajeId);
  const uRef = db.collection("usuarios").doc(choferUid);
  const opListo = await choferOperacionMarcaListo(db, choferUid, viajeId);

  try {
    let resultado = "ok";
    await db.runTransaction(async (tx) => {
      const [vSnap, uSnap] = await Promise.all([tx.get(vRef), tx.get(uRef)]);
      if (!vSnap.exists) {
        resultado = "no_encontrado";
        return;
      }
      const v = (vSnap.data() ?? {}) as AnyMap;
      if (!viajeCorporativoAsignadoA(v, choferUid)) {
        resultado = "no_encontrado";
        return;
      }
      if (!estadoPermiteVerViajeCorporativo(v)) {
        resultado = "no_encontrado";
        return;
      }
      if (!corporativoListoParaAbrirEnCurso(v) && !opListo) {
        resultado = "aun_no_es_hora";
        return;
      }

      const u = (uSnap.data() ?? {}) as AnyMap;
      const activoOtro = str(u.viajeActivoId);
      if (activoOtro && activoOtro !== viajeId) {
        const otroSnap = await tx.get(db.collection("viajes").doc(activoOtro));
        const otroVigente =
          otroSnap.exists &&
          viajeOperativoEnCurso((otroSnap.data() ?? {}) as AnyMap, choferUid);
        if (otroVigente) {
          tx.set(
            uRef,
            {
              siguienteViajeId: viajeId,
              updatedAt: FieldValue.serverTimestamp(),
              actualizadoEn: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
          resultado = "otro_viaje_activo";
          return;
        }
        tx.set(
          uRef,
          {
            viajeActivoId: "",
            updatedAt: FieldValue.serverTimestamp(),
            actualizadoEn: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      const nombre = str(u.nombre ?? u.displayName) || "Conductor RAI";
      const telefono = str(u.telefono);
      const placa = str(u.placa);
      const tipoVeh = str(u.tipoVehiculo ?? "🚗 NORMAL");

      const estadoPrev = str(v.estado).toLowerCase();
      const clienteAbordo = v.clienteAbordo === true;
      let nuevoEstado = "aceptado";
      const estadosCodigoCorp = new Set([
        "pendiente_codigo",
        "esperando_codigo_encargado",
        "en_origen_esperando_codigo",
        "a_bordo",
        "abordo",
      ]);
      if (
        v.codigoVerificado !== true &&
        clienteAbordo &&
        estadosCodigoCorp.has(estadoPrev)
      ) {
        nuevoEstado = "en_origen_esperando_codigo";
      } else if (
        v.codigoVerificado !== true &&
        !clienteAbordo &&
        estadosCodigoCorp.has(estadoPrev)
      ) {
        // Estado de código sin abordo confirmado: volver a pickup.
        nuevoEstado = "aceptado";
      }

      tx.set(
        vRef,
        {
          canalAsignacion: CANAL_CORPORATIVO_FIJO,
          corporativoChoferAsignadoUid: choferUid,
          uidTaxista: choferUid,
          taxistaId: choferUid,
          nombreTaxista: nombre,
          telefono,
          placa,
          tipoVehiculo: tipoVeh,
          activo: true,
          aceptado: true,
          estado: nuevoEstado,
          taxistaLiberado: false,
          rechazado: false,
          aceptadoEn: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      tx.set(
        uRef,
        {
          viajeActivoId: viajeId,
          siguienteViajeId: "",
          updatedAt: FieldValue.serverTimestamp(),
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      resultado = "ok";
    });
    return { resultado, viajeId };
  } catch (e) {
    logger.error("ejecutarPromoverViajeCorporativoEnCurso", {
      choferUid,
      viajeId,
      e,
    });
    return { resultado: "error", viajeId };
  }
}
