/**
 * Código de verificación corporativo en origen: intentos, liberación del chofer,
 * solicitud al encargado y cancelación por tiempo.
 */
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import type { DocumentReference, Transaction } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import {
  evaluarVigenciaCodigoCorporativo,
  validarPinCorporativoParaInicio,
} from "./corporativo_periodo.js";
import { generarCodigoAccesoPeriodo } from "./corporativo_codigo.js";
import {
  enviarPushUid,
  registrarHistorialNotificacionCorp,
} from "./corporativo_notificaciones.js";
import { CANAL_CORPORATIVO_FIJO } from "./corporativo_assign.js";
import { esCorporativoModoInformativo } from "./multiparada.js";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

const MAX_INTENTOS = 3;
/** Gracia en origen: empleados suelen subir unos minutos después de la hora fijada. */
export const TIMEOUT_ESPERA_CODIGO_CORP_MINUTOS = 20;
const TIMEOUT_MS = TIMEOUT_ESPERA_CODIGO_CORP_MINUTOS * 60 * 1000;

/** Inicio del reloj: max(llegada chofer, hora de recogida programada). */
function inicioEsperaCodigoCorp(d: AnyMap): Date | null {
  const llegada = parseTs(d.tiempoLlegadaOrigen);
  const fechaHora = parseTs(d.fechaHora);
  if (llegada && fechaHora) {
    return llegada.getTime() > fechaHora.getTime() ? llegada : fechaHora;
  }
  return llegada ?? fechaHora;
}

function debeCancelarPorTiempoCodigo(d: AnyMap, ahoraMs = Date.now()): boolean {
  const inicio = inicioEsperaCodigoCorp(d);
  if (!inicio) return false;
  return ahoraMs - inicio.getTime() >= TIMEOUT_MS;
}

export const ESTADO_EN_ORIGEN_ESPERANDO = "en_origen_esperando_codigo";
export const ESTADO_CODIGO_BLOQUEADO = "codigo_bloqueado";
export const ESTADO_ESPERANDO_ENCARGADO = "esperando_codigo_encargado";
export const ESTADO_PENDIENTE_CODIGO = "pendiente_codigo";
export const ESTADO_CANCELADO_TIEMPO = "cancelado_por_tiempo";

const ESTADOS_ESPERA_CODIGO = new Set([
  ESTADO_EN_ORIGEN_ESPERANDO,
  "a_bordo",
  "abordo",
  ESTADO_ESPERANDO_ENCARGADO,
  ESTADO_PENDIENTE_CODIGO,
]);

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function onlyDigits(v: unknown): string {
  return String(v ?? "").replace(/\D/g, "");
}

function esViajeCorporativo(data: AnyMap): boolean {
  if (data.corporativo === true) return true;
  if (str(data.categoria).toLowerCase() === "corporativo") return true;
  if (str(data.canalAsignacion) === CANAL_CORPORATIVO_FIJO) return true;
  if (str(data.recaudoDestino) === "empresa_corporativa") return true;
  return false;
}

function parseTs(v: unknown): Date | null {
  if (v instanceof Timestamp) return v.toDate();
  if (v instanceof Date && Number.isFinite(v.getTime())) return v;
  const s = str(v);
  if (!s) return null;
  const d = new Date(s);
  return Number.isFinite(d.getTime()) ? d : null;
}

function encargadoUids(ed: AnyMap): string[] {
  const raw = ed.encargadoUids;
  if (!Array.isArray(raw)) return [];
  return raw.map((x) => str(x)).filter(Boolean);
}

export function liberarTaxistaEnTx(
  tx: Transaction,
  choferUid: string,
  viajeId: string,
): void {
  if (!choferUid) return;
  const uRef = db().collection("usuarios").doc(choferUid);
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

async function postMensajeChatViaje(args: {
  viajeId: string;
  deUid: string;
  texto: string;
}): Promise<void> {
  const viajeId = str(args.viajeId);
  const deUid = str(args.deUid);
  const texto = str(args.texto);
  if (!viajeId || !deUid || !texto) return;

  const vSnap = await db().collection("viajes").doc(viajeId).get();
  if (!vSnap.exists) return;
  const vd = (vSnap.data() ?? {}) as AnyMap;
  const uidCli = str(vd.uidCliente ?? vd.clienteId);
  const uidTx = str(vd.uidTaxista ?? vd.taxistaId);
  if (!uidCli || !uidTx) return;

  const chatRef = db().collection("chats").doc(viajeId);
  const chatSnap = await chatRef.get();
  if (!chatSnap.exists) {
    await chatRef.set({
      participantes: [uidCli, uidTx],
      viajeId,
      lastMessage: "",
      lastAt: FieldValue.serverTimestamp(),
      creadoAt: FieldValue.serverTimestamp(),
    });
  }

  const msgRef = chatRef.collection("mensajes").doc();
  await msgRef.set({
    de: deUid,
    texto,
    ts: FieldValue.serverTimestamp(),
    tipo: "texto",
    sistema: true,
  });
  await chatRef.set(
    {
      lastMessage: texto,
      lastAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function notificarEncargadosEmpresa(args: {
  empresaId: string;
  viajeId: string;
  titulo: string;
  cuerpo: string;
  tipo: string;
}): Promise<void> {
  const empSnap = await db()
    .collection("empresas_corporativas")
    .doc(args.empresaId)
    .get();
  if (!empSnap.exists) return;
  const ed = (empSnap.data() ?? {}) as AnyMap;
  for (const uid of encargadoUids(ed)) {
    const ok = await enviarPushUid(uid, args.titulo, args.cuerpo, {
      tipo: args.tipo,
      viajeId: args.viajeId,
      empresaId: args.empresaId,
    });
    await registrarHistorialNotificacionCorp({
      empresaId: args.empresaId,
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

function pinCorporativoValido(
  periodo: AnyMap,
  pinIngresado: string,
  codigoRespaldoViaje: string,
): { ok: boolean; mensaje: string } {
  const pin = onlyDigits(pinIngresado);
  if (pin.length !== 6) {
    return { ok: false, mensaje: "Código incorrecto o período vencido. Contacte a su encargado." };
  }
  const respaldo = onlyDigits(codigoRespaldoViaje);
  if (respaldo.length === 6 && pin === respaldo) {
    return { ok: true, mensaje: "" };
  }
  return validarPinCorporativoParaInicio(periodo, pin);
}

export type ResultadoPinCorpTx =
  | { ok: true }
  | {
      ok: false;
      mensaje: string;
      intentosRestantes?: number;
      codigoBloqueado?: boolean;
      bloqueadoEnTx?: boolean;
    };

/** Valida PIN corporativo en transacción; incrementa intentos y bloquea al 3.er fallo. */
export async function validarPinCorporativoConIntentosEnTx(
  tx: Transaction,
  viajeRef: DocumentReference,
  data: AnyMap,
  periodo: AnyMap,
  pinIngresado: string,
  choferUid: string,
): Promise<ResultadoPinCorpTx> {
  if (data.codigoBloqueado === true) {
    return {
      ok: false,
      mensaje: "Viaje bloqueado por intentos fallidos. Contacte al encargado.",
      codigoBloqueado: true,
      intentosRestantes: 0,
    };
  }

  const vig = evaluarVigenciaCodigoCorporativo(periodo);
  const respaldo = onlyDigits(data.codigoRespaldoViaje);
  const val = pinCorporativoValido(periodo, pinIngresado, respaldo);
  if (val.ok) {
    return { ok: true };
  }

  const intentosPrev = Math.trunc(num(data.intentosCodigo));
  const intentos = intentosPrev + 1;
  const patch: AnyMap = {
    intentosCodigo: intentos,
    updatedAt: FieldValue.serverTimestamp(),
    actualizadoEn: FieldValue.serverTimestamp(),
  };
  if (!data.tiempoLlegadaOrigen) {
    patch.tiempoLlegadaOrigen = FieldValue.serverTimestamp();
  }

  if (intentos >= MAX_INTENTOS) {
    patch.codigoBloqueado = true;
    patch.estado = ESTADO_CODIGO_BLOQUEADO;
    patch.activo = false;
    patch.taxistaLiberado = true;
    patch.esperandoCodigo = false;
    tx.update(viajeRef, patch);
    liberarTaxistaEnTx(tx, choferUid, viajeRef.id);
    return {
      ok: false,
      mensaje:
        "Código incorrecto 3 veces. Viaje bloqueado; el encargado fue notificado.",
      intentosRestantes: 0,
      codigoBloqueado: true,
      bloqueadoEnTx: true,
    };
  }

  tx.update(viajeRef, patch);
  return {
    ok: false,
    mensaje: val.mensaje || "Código incorrecto.",
    intentosRestantes: MAX_INTENTOS - intentos,
  };
}

export async function notificarEncargadosEmpresaPinBloqueado(args: {
  empresaId: string;
  viajeId: string;
}): Promise<void> {
  await notificarEncargadosEmpresa({
    empresaId: args.empresaId,
    viajeId: args.viajeId,
    titulo: "Código bloqueado",
    cuerpo:
      "El código de verificación ha sido fallado 3 veces. Por favor, verifique y envíe un código de respaldo.",
    tipo: "codigo_bloqueado",
  });
}

/** Chofer: no tengo código → chat + liberar. */
export const taxistaSolicitarCodigoCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const choferUid = request.auth.uid;
  const viajeId = str(request.data?.viajeId);
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const viajeRef = db().collection("viajes").doc(viajeId);
  const vSnap = await viajeRef.get();
  if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
  const data = (vSnap.data() ?? {}) as AnyMap;

  if (!esViajeCorporativo(data)) {
    throw new HttpsError("failed-precondition", "No es viaje corporativo");
  }
  const txUid = str(data.uidTaxista ?? data.taxistaId);
  if (txUid !== choferUid) {
    throw new HttpsError("permission-denied", "No autorizado");
  }
  if (data.codigoVerificado === true) {
    throw new HttpsError("failed-precondition", "El código ya fue verificado");
  }
  const estado = str(data.estado).toLowerCase();
  if (!ESTADOS_ESPERA_CODIGO.has(estado) && estado !== "aceptado" && estado !== "en_camino_pickup") {
    throw new HttpsError("failed-precondition", "Estado no válido para solicitar código");
  }

  const empresaId = str(data.corporativoEmpresaId);
  const nombreChofer = str(
    (await db().collection("usuarios").doc(choferUid).get()).data()?.nombre,
  ) || "Conductor";

  await db().runTransaction(async (tx) => {
    const snap = await tx.get(viajeRef);
    if (!snap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const vd = (snap.data() ?? {}) as AnyMap;
    tx.update(viajeRef, {
      esperandoCodigo: true,
      taxistaLiberado: true,
      estado: ESTADO_ESPERANDO_ENCARGADO,
      activo: false,
      tiempoLlegadaOrigen:
        vd.tiempoLlegadaOrigen ?? FieldValue.serverTimestamp(),
      codigoSolicitadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    });
    liberarTaxistaEnTx(tx, choferUid, viajeId);
  });

  const cuerpo = `${nombreChofer} solicita el código de verificación para el viaje ${viajeId.slice(0, 8)}…`;
  if (empresaId) {
    await notificarEncargadosEmpresa({
      empresaId,
      viajeId,
      titulo: "Código de verificación solicitado",
      cuerpo,
      tipo: "codigo_solicitado",
    });
  }

  const uidEnc = str(data.uidCliente ?? data.clienteId);
  if (uidEnc) {
    await postMensajeChatViaje({
      viajeId,
      deUid: choferUid,
      texto: `🚕 Solicito el código de verificación del período para iniciar la ruta corporativa.`,
    });
  }

  return { ok: true, viajeId, estado: ESTADO_ESPERANDO_ENCARGADO };
});

/** Encargado: envía código por chat (opcional código de respaldo de un solo viaje). */
export const encargadoEnviarCodigoCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const actorUid = request.auth.uid;
  const viajeId = str(request.data?.viajeId);
  const generarRespaldo = request.data?.generarCodigoRespaldo === true;
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const viajeRef = db().collection("viajes").doc(viajeId);
  const vSnap = await viajeRef.get();
  if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
  const data = (vSnap.data() ?? {}) as AnyMap;
  const empresaId = str(data.corporativoEmpresaId);
  if (!empresaId) throw new HttpsError("failed-precondition", "Sin empresa corporativa");

  const empSnap = await db().collection("empresas_corporativas").doc(empresaId).get();
  const ed = (empSnap.data() ?? {}) as AnyMap;
  const encargados = encargadoUids(ed);
  const esAdmin =
    str(
      (await db().collection("usuarios").doc(actorUid).get()).data()?.rol,
    ).toLowerCase() === "admin";
  if (!esAdmin && !encargados.includes(actorUid)) {
    throw new HttpsError("permission-denied", "Solo encargado o admin");
  }

  const periodo = (ed.periodoActual ?? {}) as AnyMap;
  const vig = evaluarVigenciaCodigoCorporativo(periodo);
  let codigoEnviar = vig.codigo;
  let codigoRespaldo = onlyDigits(data.codigoRespaldoViaje);

  if (generarRespaldo || !vig.vigente || codigoEnviar.length !== 6) {
    codigoRespaldo = generarCodigoAccesoPeriodo();
    codigoEnviar = codigoRespaldo;
  }

  const choferUid = str(data.uidTaxista ?? data.taxistaId);

  await viajeRef.set(
    {
      estado: ESTADO_PENDIENTE_CODIGO,
      esperandoCodigo: false,
      taxistaLiberado: false,
      codigoBloqueado: false,
      intentosCodigo: 0,
      activo: true,
      codigoRespaldoViaje: codigoRespaldo.length === 6 ? codigoRespaldo : FieldValue.delete(),
      codigoEnviadoEncargadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const textoChat = generarRespaldo
    ? `🔐 Código de respaldo para iniciar la ruta: ${codigoEnviar}`
    : `🔐 Código del período: ${codigoEnviar}`;

  await postMensajeChatViaje({
    viajeId,
    deUid: actorUid,
    texto: textoChat,
  });

  if (choferUid) {
    await enviarPushUid(
      choferUid,
      "Código de verificación disponible",
      `El encargado envió el código para tu ruta corporativa.`,
      { tipo: "codigo_enviado", viajeId, empresaId },
    );
  }

  return {
    ok: true,
    viajeId,
    codigoEnviado: codigoEnviar.length === 6,
    generoRespaldo: generarRespaldo,
  };
});

/** Cancela viajes corporativos sin código tras la gracia en origen (20 min). */
export const scheduledCancelarViajesSinCodigoCorporativo = onSchedule(
  {
    schedule: "every 2 minutes",
    timeZone: "America/Santo_Domingo",
    memory: "256MiB",
  },
  async () => {
    const snap = await db()
      .collection("viajes")
      .where("corporativo", "==", true)
      .where("codigoVerificado", "==", false)
      .where("activo", "==", true)
      .limit(80)
      .get();

    let cancelados = 0;
    for (const doc of snap.docs) {
      const d = doc.data() as AnyMap;
      const estado = str(d.estado).toLowerCase();
      if (
        estado === ESTADO_CODIGO_BLOQUEADO ||
        estado === ESTADO_CANCELADO_TIEMPO ||
        estado === ESTADO_ESPERANDO_ENCARGADO
      ) {
        continue;
      }
      if (!ESTADOS_ESPERA_CODIGO.has(estado) && estado !== "aceptado" && estado !== "en_camino_pickup") {
        continue;
      }

      if (!debeCancelarPorTiempoCodigo(d)) continue;

      const choferUid = str(d.uidTaxista ?? d.taxistaId);
      const empresaId = str(d.corporativoEmpresaId);

      await db().runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        if (!fresh.exists) return;
        const vd = (fresh.data() ?? {}) as AnyMap;
        if (vd.codigoVerificado === true) return;
        const est = str(vd.estado).toLowerCase();
        if (est === ESTADO_CANCELADO_TIEMPO) return;

        if (!debeCancelarPorTiempoCodigo(vd)) return;

        tx.update(doc.ref, {
          estado: ESTADO_CANCELADO_TIEMPO,
          activo: false,
          taxistaLiberado: true,
          canceladoPor: "sistema_tiempo_codigo",
          motivoCancelacion: `Tiempo de espera del código agotado (${TIMEOUT_ESPERA_CODIGO_CORP_MINUTOS} min)`,
          canceladoEn: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          actualizadoEn: FieldValue.serverTimestamp(),
        });
        liberarTaxistaEnTx(tx, choferUid, doc.id);
      });

      cancelados += 1;
      if (empresaId) {
        await notificarEncargadosEmpresa({
          empresaId,
          viajeId: doc.id,
          titulo: "Viaje cancelado por tiempo",
          cuerpo: `El viaje ${doc.id.slice(0, 8)}… fue cancelado: tiempo de espera del código agotado.`,
          tipo: "codigo_tiempo_agotado",
        });
      }
    }

    if (cancelados > 0) {
      logger.info("scheduledCancelarViajesSinCodigoCorporativo", { cancelados });
    }
  },
);

function esChoferAsignadoViajeCorp(v: AnyMap, uid: string): boolean {
  const u = str(uid);
  if (!u) return false;
  const taxista = str(v.uidTaxista ?? v.taxistaId);
  if (taxista === u) return true;
  const pref = str(v.corporativoChoferPreferidoUid);
  if (pref === u) return true;
  const asig = str(v.corporativoChoferAsignadoUid);
  return asig === u;
}

/** Chofer informativo: deja la ruta del día → libera chofer, avisa encargado y RAI. */
export const taxistaAbandonarRutaCorpInformativa = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const choferUid = request.auth.uid;
  const viajeId = str(request.data?.viajeId);
  const motivo = str(request.data?.motivo).slice(0, 500);
  if (!viajeId) {
    throw new HttpsError("invalid-argument", "Falta viajeId.");
  }

  const viajeRef = db().collection("viajes").doc(viajeId);
  const vSnap = await viajeRef.get();
  if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no encontrado.");
  const data = (vSnap.data() ?? {}) as AnyMap;

  if (!esViajeCorporativo(data)) {
    throw new HttpsError("failed-precondition", "No es viaje corporativo.");
  }
  if (!esCorporativoModoInformativo(data)) {
    throw new HttpsError(
      "failed-precondition",
      "Solo aplica a rutas corporativas informativas (sin PIN).",
    );
  }
  if (!esChoferAsignadoViajeCorp(data, choferUid)) {
    throw new HttpsError("permission-denied", "Ruta no asignada a tu cuenta.");
  }
  if (data.completado === true) {
    return { ok: true, yaCompletado: true };
  }

  const empresaId = str(data.corporativoEmpresaId);
  const empresaNombre =
    str(data.corporativoEmpresaNombre) || "Empresa corporativa";
  const nombreChofer =
    str(
      (await db().collection("usuarios").doc(choferUid).get()).data()?.nombre,
    ) || "Conductor";

  await db().runTransaction(async (tx) => {
    const snap = await tx.get(viajeRef);
    if (!snap.exists) throw new HttpsError("not-found", "Viaje no encontrado.");
    const vd = (snap.data() ?? {}) as AnyMap;
    if (vd.completado === true) return;

    const uRef = db().collection("usuarios").doc(choferUid);
    const uSnap = await tx.get(uRef);
    const u = (uSnap.data() ?? {}) as AnyMap;
    const userPatch: AnyMap = {
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    };
    if (str(u.viajeActivoId) === viajeId || !str(u.viajeActivoId)) {
      userPatch.viajeActivoId = "";
    }
    if (str(u.siguienteViajeId) === viajeId) {
      userPatch.siguienteViajeId = FieldValue.delete();
    }
    if (str(u.viajeEncoladoId) === viajeId) {
      userPatch.viajeEncoladoId = FieldValue.delete();
    }
    tx.set(uRef, userPatch, { merge: true });

    tx.set(
      viajeRef,
      {
        corporativoChoferAbandono: true,
        corporativoChoferAbandonoEn: FieldValue.serverTimestamp(),
        corporativoChoferAbandonoMotivo: motivo,
        corporativoChoferAbandonoUid: choferUid,
        corporativoRequiereReasignacion: true,
        taxistaLiberado: true,
        activo: false,
        aceptado: false,
        estado: "pendiente",
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });

  const textoChat =
    `🚕 ${nombreChofer} dejó la ruta corporativa de hoy.` +
    (motivo ? `\nMotivo: ${motivo}` : "") +
    "\nRAI y la empresa fueron notificados. Coordiná reasignación si hace falta.";

  const uidEnc = str(data.uidCliente ?? data.clienteId);
  if (uidEnc) {
    await postMensajeChatViaje({
      viajeId,
      deUid: choferUid,
      texto: textoChat,
    });
  }

  if (empresaId) {
    await notificarEncargadosEmpresa({
      empresaId,
      viajeId,
      titulo: "Chofer dejó la ruta",
      cuerpo: `${nombreChofer} abandonó la ruta de ${empresaNombre}. Revisá reasignación.`,
      tipo: "chofer_abandono_ruta",
    });
  }

  return { ok: true, viajeId, empresaId, empresaNombre };
});
