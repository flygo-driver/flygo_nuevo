import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { multiparadaInitPatch } from "./multiparada.js";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {
  validarPinCorporativoParaInicio,
} from "./corporativo_periodo.js";
import {
  ESTADO_EN_ORIGEN_ESPERANDO,
  validarPinCorporativoConIntentosEnTx,
  notificarEncargadosEmpresaPinBloqueado,
} from "./corporativo_codigo_viaje.js";
import { CANAL_CORPORATIVO_FIJO } from "./corporativo_assign.js";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

function normalizeRole(raw: unknown): string {
  const r = String(raw ?? "").trim().toLowerCase();
  if (r === "administrador") return "admin";
  if (r === "driver") return "taxista";
  return r;
}

async function getRole(uid: string): Promise<string> {
  const u = await db().collection("usuarios").doc(uid).get();
  const r1 = normalizeRole((u.data() as AnyMap | undefined)?.rol);
  if (r1) return r1;
  const r = await db().collection("roles").doc(uid).get();
  return normalizeRole((r.data() as AnyMap | undefined)?.rol);
}

async function assertTaxiOrAdmin(uid: string): Promise<string> {
  const role = await getRole(uid);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }
  return role;
}

function onlyDigits(value: unknown): string {
  return String(value ?? "").replace(/\D/g, "").trim();
}

/** Mismo formato que Flutter `ViajesRepo.crearViajePendiente`: 6 dígitos. */
function generarPinVerificacionSeisDigitos(): string {
  return String(100000 + Math.floor(Math.random() * 900000));
}

function pinVerificacionDelViaje(data: AnyMap): string {
  const codigo = onlyDigits(data.codigoVerificacion);
  if (codigo.length === 6) return codigo;
  const boarding = onlyDigits(data.boardingPin);
  if (boarding.length === 6) return boarding;
  return boarding || codigo;
}

function isValidTransitionToEnCurso(estado: string): boolean {
  return [
    "a_bordo",
    "abordo",
    "aceptado",
    "asignado",
    "en_espera",
    "en_camino_pickup",
    "encamino_pickup",
    "en_origen_esperando_codigo",
    "esperando_codigo_encargado",
    "pendiente_codigo",
  ].includes(estado);
}

function esViajeCorporativoBoarding(data: AnyMap): boolean {
  if (data.corporativo === true) return true;
  if (String(data.categoria ?? "").trim().toLowerCase() === "corporativo") return true;
  if (String(data.canalAsignacion ?? "").trim() === CANAL_CORPORATIVO_FIJO) return true;
  return false;
}

function respuestaEnsurePinViaje(data: AnyMap, pin: string, existed: boolean) {
  return {
    ok: true,
    pin,
    existed,
    estado: String(data.estado ?? "").trim(),
    clienteAbordo: data.clienteAbordo === true,
    codigoVerificado: data.codigoVerificado === true,
  };
}

async function actorAutorizadoParaViaje(
  actorUid: string,
  viajeId: string,
  data: AnyMap,
): Promise<boolean> {
  const uidCliente = String(data.uidCliente ?? data.clienteId ?? "").trim();
  const uidTaxista = String(data.uidTaxista ?? data.taxistaId ?? "").trim();
  if (actorUid === uidCliente || actorUid === uidTaxista) return true;
  const role = await getRole(actorUid);
  if (role === "admin") return true;
  const userSnap = await db().collection("usuarios").doc(actorUid).get();
  const u = (userSnap.data() ?? {}) as AnyMap;
  const viajeActivoId = String(u.viajeActivoId ?? "").trim();
  const siguienteViajeId = String(u.siguienteViajeId ?? "").trim();
  return viajeActivoId === viajeId || siguienteViajeId === viajeId;
}

/** Lectura autoritativa del viaje para el cliente (vía viajeActivoId o uidCliente). */
export const syncViajeEstadoCliente = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  const viajeId = String(request.data?.viajeId ?? request.data?.tripId ?? "").trim();
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const viajeRef = db().collection("viajes").doc(viajeId);
  const snap = await viajeRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Viaje no existe");
  const data = (snap.data() ?? {}) as AnyMap;

  if (!(await actorAutorizadoParaViaje(actorUid, viajeId, data))) {
    throw new HttpsError("permission-denied", "No autorizado para este viaje");
  }

  const pin = pinVerificacionDelViaje(data);
  return {
    ok: true,
    pin: pin.length === 6 ? pin : "",
    estado: String(data.estado ?? "").trim(),
    clienteAbordo: data.clienteAbordo === true,
    codigoVerificado: data.codigoVerificado === true,
  };
});

// Genera / renueva PIN de abordaje (6 dígitos, mismo criterio que codigoVerificacion del pool).
export const ensureViajeCodigoVerificacion = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  const viajeId = String(request.data?.viajeId ?? request.data?.tripId ?? "").trim();
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const viajeRef = db().collection("viajes").doc(viajeId);
  const snap = await viajeRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Viaje no existe");
  const data = (snap.data() ?? {}) as AnyMap;
  if (!(await actorAutorizadoParaViaje(actorUid, viajeId, data))) {
    throw new HttpsError("permission-denied", "No autorizado para este viaje");
  }

  let pin = pinVerificacionDelViaje(data);
  if (pin.length === 6) {
    return respuestaEnsurePinViaje(data, pin, true);
  }

  pin = generarPinVerificacionSeisDigitos();
  await viajeRef.update({
    codigoVerificacion: pin,
    codigoVerificado: false,
    updatedAt: FieldValue.serverTimestamp(),
    actualizadoEn: FieldValue.serverTimestamp(),
  });
  const fresh = (await viajeRef.get()).data() ?? data;
  return respuestaEnsurePinViaje(fresh as AnyMap, pin, false);
});

export const issueBoardingPin = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  const role = await assertTaxiOrAdmin(actorUid);
  const viajeId = String(request.data?.viajeId ?? request.data?.tripId ?? "").trim();
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const ttlRaw = Number(request.data?.ttlMinutes ?? 240);
  const ttlMinutes = Number.isFinite(ttlRaw)
    ? Math.min(Math.max(Math.floor(ttlRaw), 5), 24 * 60)
    : 240;

  const viajeRef = db().collection("viajes").doc(viajeId);
  const viajeSnap = await viajeRef.get();
  if (!viajeSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
  const data = (viajeSnap.data() ?? {}) as AnyMap;
  const uidTaxista = String(data.uidTaxista ?? data.taxistaId ?? "").trim();
  if (role !== "admin" && uidTaxista !== actorUid) {
    throw new HttpsError("permission-denied", "No autorizado para este viaje");
  }

  const pin = generarPinVerificacionSeisDigitos();
  const expMs = Date.now() + ttlMinutes * 60 * 1000;
  const expiraTs = Timestamp.fromMillis(expMs);

  await viajeRef.update({
    boardingPin: pin,
    boardingPinExpira: expMs,
    boardingPinExpiresAt: expiraTs,
    codigoVerificacion: pin,
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { ok: true, pin, expiresAt: new Date(expMs).toISOString() };
});

// Confirma el PIN al abordar (cliente/taxista/admin).
export const confirmBoarding = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  const role = await getRole(actorUid);
  if (!["cliente", "taxista", "admin"].includes(role)) {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const viajeId = String(request.data?.viajeId ?? request.data?.tripId ?? "").trim();
  const pinIngresado = onlyDigits(request.data?.pin);
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");
  if (!pinIngresado) throw new HttpsError("invalid-argument", "Falta pin");

  const ref = db().collection("viajes").doc(viajeId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Viaje no existe");

  const data = (snap.data() ?? {}) as AnyMap;
  const uidTaxista = String(data.uidTaxista ?? data.taxistaId ?? "").trim();
  const uidCliente = String(data.uidCliente ?? data.clienteId ?? "").trim();
  if (
    role !== "admin" &&
    actorUid !== uidTaxista &&
    actorUid !== uidCliente
  ) {
    throw new HttpsError("permission-denied", "No autorizado para este viaje");
  }

  const pinDoc = pinVerificacionDelViaje(data);
  if (!pinDoc || pinDoc.length !== 6 || pinDoc !== pinIngresado) {
    throw new HttpsError("permission-denied", "PIN incorrecto");
  }
  const expira = Number(data.boardingPinExpira ?? 0);
  if (Number.isFinite(expira) && expira > 0 && Date.now() > expira) {
    throw new HttpsError("failed-precondition", "PIN expirado");
  }

  await ref.update({
    estado: "a_bordo",
    codigoVerificado: true,
    codigoVerificadoEn: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true, estado: "a_bordo" };
});

/**
 * Taxista marca «Cliente a bordo» (Admin SDK).
 * Evita permission-denied del write cliente en laptop/web cuando el rol
 * solo está en roles/{uid} o hay carrera de estado.
 */
export const marcarClienteAbordoSeguro = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  const role = await assertTaxiOrAdmin(actorUid);
  const viajeId = String(request.data?.viajeId ?? request.data?.tripId ?? "").trim();
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const viajeRef = db().collection("viajes").doc(viajeId);

  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(viajeRef);
    if (!snap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const data = (snap.data() ?? {}) as AnyMap;
    const uidTaxista = String(data.uidTaxista ?? data.taxistaId ?? "").trim();
    if (role !== "admin" && uidTaxista !== actorUid) {
      throw new HttpsError("permission-denied", "No autorizado para este viaje");
    }

    const estado = String(data.estado ?? "").trim().toLowerCase();
    if (estado === "a_bordo" || estado === "abordo") {
      return { ok: true, viajeId, alreadyAbordo: true };
    }
    if (estado === "en_curso" || estado === "encurso") {
      return { ok: true, viajeId, alreadyAbordo: true, enCurso: true };
    }
    const permitido =
      estado === "aceptado" ||
      estado === "asignado" ||
      estado === "en_camino_pickup" ||
      estado === "encamino_pickup" ||
      estado === "en_camino";
    if (!permitido) {
      throw new HttpsError(
        "failed-precondition",
        `Estado inválido para a_bordo: ${estado || "(vacío)"}`,
      );
    }

    let pin = pinVerificacionDelViaje(data);
    if (pin.length !== 6) {
      pin = generarPinVerificacionSeisDigitos();
    }

    const esCorp = esViajeCorporativoBoarding(data);
    const patchAbordo: AnyMap = {
      activo: true,
      clienteAbordo: true,
      clienteAbordoEn: FieldValue.serverTimestamp(),
      pickupConfirmadoEn: FieldValue.serverTimestamp(),
      codigoVerificacion: pin,
      codigoVerificado: false,
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    };
    if (esCorp) {
      patchAbordo.estado = ESTADO_EN_ORIGEN_ESPERANDO;
      patchAbordo.tiempoLlegadaOrigen = FieldValue.serverTimestamp();
      patchAbordo.intentosCodigo = 0;
      patchAbordo.codigoBloqueado = false;
      patchAbordo.esperandoCodigo = false;
      patchAbordo.taxistaLiberado = false;
    } else {
      patchAbordo.estado = "a_bordo";
    }

    tx.update(viajeRef, patchAbordo);
    return { ok: true, viajeId, alreadyAbordo: false };
  });

  // Best-effort: desactivar otros viajes activos del mismo chofer.
  try {
    const qs = await db()
      .collection("viajes")
      .where("uidTaxista", "==", actorUid)
      .where("activo", "==", true)
      .get();
    const batch = db().batch();
    let n = 0;
    for (const doc of qs.docs) {
      if (doc.id === viajeId) continue;
      batch.update(doc.ref, {
        activo: false,
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      });
      n++;
    }
    if (n > 0) await batch.commit();
  } catch {
    /* no bloquear abordaje */
  }

  return result;
});

/** Taxista inicia navegación al pickup (Admin SDK). */
export const marcarEnCaminoPickupSeguro = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  const role = await assertTaxiOrAdmin(actorUid);
  const viajeId = String(request.data?.viajeId ?? request.data?.tripId ?? "").trim();
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const viajeRef = db().collection("viajes").doc(viajeId);
  return await db().runTransaction(async (tx) => {
    const snap = await tx.get(viajeRef);
    if (!snap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const data = (snap.data() ?? {}) as AnyMap;
    const uidTaxista = String(data.uidTaxista ?? data.taxistaId ?? "").trim();
    if (role !== "admin" && uidTaxista !== actorUid) {
      throw new HttpsError("permission-denied", "No autorizado para este viaje");
    }

    const estado = String(data.estado ?? "").trim().toLowerCase();
    if (
      estado === "en_camino_pickup" ||
      estado === "encamino_pickup" ||
      estado === "a_bordo" ||
      estado === "abordo" ||
      estado === "en_curso" ||
      estado === "encurso"
    ) {
      return { ok: true, viajeId, already: true, estado };
    }
    const permitido =
      estado === "aceptado" ||
      estado === "asignado";
    if (!permitido) {
      throw new HttpsError(
        "failed-precondition",
        `Estado inválido para en_camino_pickup: ${estado || "(vacío)"}`,
      );
    }

    tx.update(viajeRef, {
      estado: "en_camino_pickup",
      activo: true,
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    });
    return { ok: true, viajeId, already: false };
  });
});

// Inicio de viaje autoritativo: exige código verificado por backend o PIN válido.
export const iniciarViajeSeguro = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  const role = await assertTaxiOrAdmin(actorUid);
  const viajeId = String(request.data?.viajeId ?? "").trim();
  const pinIngresado = onlyDigits(request.data?.pin);
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const viajeRef = db().collection("viajes").doc(viajeId);
  const preSnap = await viajeRef.get();
  const preData = (preSnap.data() ?? {}) as AnyMap;
  const empCorpId = String(preData.corporativoEmpresaId ?? "").trim();
  const empCorpRef =
    empCorpId.length > 0
      ? db().collection("empresas_corporativas").doc(empCorpId)
      : null;

  type TxResult =
    | { ok: true; viajeId: string; alreadyStarted?: boolean }
    | {
        ok: false;
        pinError: {
          mensaje: string;
          intentosRestantes?: number;
          codigoBloqueado?: boolean;
        };
      };

  const txResult = await db().runTransaction(async (tx): Promise<TxResult> => {
    const snap = await tx.get(viajeRef);
    if (!snap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const data = (snap.data() ?? {}) as AnyMap;
    const uidTaxista = String(data.uidTaxista ?? data.taxistaId ?? "").trim();
    const estado = String(data.estado ?? "").trim().toLowerCase();

    if (role !== "admin" && uidTaxista !== actorUid) {
      throw new HttpsError("permission-denied", "No autorizado para este viaje");
    }
    if (estado === "en_curso") {
      return { ok: true, viajeId, alreadyStarted: true };
    }
    if (!isValidTransitionToEnCurso(estado)) {
      throw new HttpsError("failed-precondition", "Estado no válido para iniciar viaje");
    }

    const codigoVerificado = data.codigoVerificado === true;
    const esCorp =
      data.corporativo === true ||
      String(data.categoria ?? "").trim() === "corporativo";

    if (data.codigoBloqueado === true && esCorp) {
      return {
        ok: false,
        pinError: {
          mensaje:
            "Viaje bloqueado por intentos fallidos. Contacte al encargado.",
          intentosRestantes: 0,
          codigoBloqueado: true,
        },
      };
    }

    let pinPeriodoCorp = "";
    let pinViaCorpOk = codigoVerificado;
    if (!codigoVerificado && esCorp && empCorpRef) {
      const empSnap = await tx.get(empCorpRef);
      const periodo = (empSnap.data()?.periodoActual ?? {}) as AnyMap;
      pinPeriodoCorp = onlyDigits(periodo.codigoAcceso);
      const respaldo = onlyDigits(data.codigoRespaldoViaje);
      const pinOkRespaldo =
        pinIngresado.length === 6 &&
        respaldo.length === 6 &&
        pinIngresado === respaldo;
      if (pinOkRespaldo) {
        pinViaCorpOk = true;
      } else {
        const valTx = await validarPinCorporativoConIntentosEnTx(
          tx,
          viajeRef,
          data,
          periodo,
          pinIngresado,
          uidTaxista,
        );
        if (!valTx.ok) {
          return {
            ok: false,
            pinError: {
              mensaje: valTx.mensaje,
              intentosRestantes: valTx.intentosRestantes,
              codigoBloqueado: valTx.codigoBloqueado,
            },
          };
        }
        pinViaCorpOk = true;
      }
    }

    if (!pinViaCorpOk) {
      if (esCorp) {
        if (pinPeriodoCorp.length !== 6 && onlyDigits(data.codigoRespaldoViaje).length !== 6) {
          throw new HttpsError(
            "failed-precondition",
            "No hay código de período vigente. El encargado debe verlo en Cuenta RAI.",
          );
        }
      } else {
        const pinDoc = pinVerificacionDelViaje(data);
        const pinViajeOk =
          pinDoc.length === 6 &&
          pinIngresado.length > 0 &&
          pinIngresado === pinDoc;
        if (!pinViajeOk) {
          throw new HttpsError(
            "failed-precondition",
            "Código de verificación inválido",
          );
        }
      }
    }

    const multiInit = multiparadaInitPatch(data);
    const syncPinCorp =
      esCorp && pinPeriodoCorp.length === 6
        ? { codigoVerificacion: pinPeriodoCorp, corporativoCodigoEsPeriodo: true }
        : {};
    tx.update(viajeRef, {
      estado: "en_curso",
      codigoVerificado: true,
      codigoVerificadoEn: FieldValue.serverTimestamp(),
      inicioViaje: FieldValue.serverTimestamp(),
      viajeIniciadoEn: FieldValue.serverTimestamp(),
      inicioEnRutaEn: FieldValue.serverTimestamp(),
      activo: true,
      esperandoCodigo: false,
      taxistaLiberado: false,
      codigoBloqueado: false,
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
      ...syncPinCorp,
      ...(multiInit ?? {}),
    });
    return { ok: true, viajeId, alreadyStarted: false };
  });

  if (!txResult.ok) {
    const pe = txResult.pinError;
    if (pe.codigoBloqueado && empCorpId) {
      await notificarEncargadosEmpresaPinBloqueado({
        empresaId: empCorpId,
        viajeId,
      });
    }
    const details: AnyMap = {};
    if (pe.intentosRestantes != null) details.intentosRestantes = pe.intentosRestantes;
    if (pe.codigoBloqueado) details.codigoBloqueado = true;
    throw new HttpsError("failed-precondition", pe.mensaje, details);
  }

  return txResult;
});
