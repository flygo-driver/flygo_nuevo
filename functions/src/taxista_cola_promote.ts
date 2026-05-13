import {
  FieldValue,
  getFirestore,
  Timestamp,
  type DocumentReference,
  type Transaction,
} from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { logAdminAudit } from "./audit.js";
import {
  mensajeBloqueoOperativo,
  sortColaCandidates,
  taxistaSinBloqueoPrepagoOperativo,
  type AnyMap,
} from "./taxista_cola_promote_logic.js";

const db = () => getFirestore();
const viajes = () => db().collection("viajes");
const usuarios = () => db().collection("usuarios");
const billeteras = () => db().collection("billeteras_taxista");

const ESTADOS_PEND = new Set(["pendiente", "pendiente_pago", "pendiente_admin"]);

/** Retornado dentro de la transacción cuando el taxista queda bloqueado operativo (prepago/legacy). */
const TX_BLOCKED = "__txn_bloqueo_prepago__" as const;

function toStr(v: unknown): string {
  return String(v ?? "").trim();
}

function tipoVehiculoFormateado(tipoServicio: string, tipoRaw: string): string {
  if (tipoServicio === "motor") return "🛵 MOTOR 🛵";
  if (tipoServicio === "turismo") return "🏝️ TURISMO 🏝️";
  if (tipoServicio === "normal") return "🚗 NORMAL";
  return tipoRaw;
}

function assignViajeAAceptadoEnTx(
  tx: Transaction,
  params: {
    uidTaxista: string;
    uRef: DocumentReference;
    vRef: DocumentReference;
    v: AnyMap;
    nombreTaxista: string;
    tel: string;
    plac: string;
    tipo: string;
    marca: string;
    modelo: string;
    color: string;
  },
): void {
  const tipoServicio = toStr(params.v.tipoServicio) || "normal";
  const tipoVeh = tipoVehiculoFormateado(tipoServicio, params.tipo);
  const uidCliente = toStr(params.v.uidCliente ?? params.v.clienteId);

  tx.update(params.vRef, {
    uidTaxista: params.uidTaxista,
    taxistaId: params.uidTaxista,
    nombreTaxista: params.nombreTaxista,
    telefono: params.tel,
    placa: params.plac,
    tipoVehiculo: tipoVeh,
    tipoVehiculoOriginal: params.tipo,
    marca: params.marca,
    modelo: params.modelo,
    color: params.color,
    latTaxista: 0.0,
    lonTaxista: 0.0,
    driverLat: 0.0,
    driverLon: 0.0,
    estado: "aceptado",
    aceptado: true,
    rechazado: false,
    activo: true,
    aceptadoEn: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    actualizadoEn: FieldValue.serverTimestamp(),
    reservadoPor: "",
    reservadoHasta: null,
    ignoradosPor: FieldValue.delete(),
  });

  if (uidCliente) {
    tx.set(
      usuarios().doc(uidCliente),
      {
        viajeActivoId: params.vRef.id,
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  tx.set(
    params.uRef,
    {
      siguienteViajeId: "",
      viajeEncoladoId: FieldValue.delete(),
      viajeActivoId: params.vRef.id,
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function millisOfFirestoreTime(v: unknown): number | null {
  if (v instanceof Timestamp) return v.toMillis();
  if (v && typeof (v as { toMillis?: () => number }).toMillis === "function") {
    try {
      return (v as { toMillis: () => number }).toMillis();
    } catch {
      return null;
    }
  }
  return null;
}

function acceptAfterOk(v: AnyMap): boolean {
  const ms = millisOfFirestoreTime(v.acceptAfter);
  if (ms != null && ms > Date.now()) return false;
  return true;
}

function reservaVencida(v: AnyMap): boolean {
  const ms = millisOfFirestoreTime(v.reservadoHasta);
  if (ms != null) return ms <= Date.now();
  return false;
}

function tripEligibleReserva(
  v: AnyMap,
  uidTaxista: string,
): { ok: boolean; reason?: string } {
  const estado = toStr(v.estado);
  const uidAsignado = toStr(v.uidTaxista);
  const reservadoPor = toStr(v.reservadoPor);

  if (!ESTADOS_PEND.has(estado) || uidAsignado.length > 0) {
    return { ok: false, reason: "viaje_no_disponible" };
  }
  if (reservaVencida(v)) return { ok: false, reason: "reserva_vencida" };
  if (!acceptAfterOk(v)) return { ok: false, reason: "accept_after" };
  if (reservadoPor !== uidTaxista) return { ok: false, reason: "no_reservado_por_taxista" };
  return { ok: true };
}

function tripEligibleEncolado(
  v: AnyMap,
  uidTaxista: string,
): { ok: boolean; reason?: string } {
  const estado = toStr(v.estado);
  const uidAsignado = toStr(v.uidTaxista);
  const reservadoPor = toStr(v.reservadoPor);

  const cupoLibreOPropio = reservadoPor.length === 0 || reservadoPor === uidTaxista;
  const valido =
    ESTADOS_PEND.has(estado) &&
    uidAsignado.length === 0 &&
    cupoLibreOPropio &&
    !reservaVencida(v) &&
    acceptAfterOk(v);

  if (!valido) return { ok: false, reason: "viaje_encolado_invalido" };
  return { ok: true };
}

async function hydrateColaFromLegacy(uid: string, uData: AnyMap): Promise<void> {
  const uRef = usuarios().doc(uid);
  const sig = toStr(uData.siguienteViajeId);
  const enc = toStr(uData.viajeEncoladoId);
  const batch = db().batch();

  if (sig.length > 0) {
    const cref = uRef.collection("cola_viajes").doc(sig);
    const cs = await cref.get();
    if (!cs.exists) {
      batch.set(cref, {
        viajeId: sig,
        slot: 0,
        estado: "pendiente",
        tipo: "normal",
        createdAt: FieldValue.serverTimestamp(),
        source: "legacy_siguienteViajeId",
      });
    }
  }
  if (enc.length > 0 && enc !== sig) {
    const cref = uRef.collection("cola_viajes").doc(enc);
    const cs = await cref.get();
    if (!cs.exists) {
      batch.set(cref, {
        viajeId: enc,
        slot: 1,
        estado: "pendiente",
        tipo: "normal",
        createdAt: FieldValue.serverTimestamp(),
        source: "legacy_viajeEncoladoId",
      });
    }
  }
  await batch.commit();
}

async function tryPromoteOne(
  uidTaxista: string,
  viajeId: string,
  slot: number,
): Promise<string | null | typeof TX_BLOCKED> {
  const uRef = usuarios().doc(uidTaxista);
  const vRef = viajes().doc(viajeId);
  const colaRef = uRef.collection("cola_viajes").doc(viajeId);

  return db().runTransaction(async (tx) => {
    const uSnap = await tx.get(uRef);
    const bSnap = await tx.get(billeteras().doc(uidTaxista));
    const uData = (uSnap.data() ?? {}) as AnyMap;
    if (!taxistaSinBloqueoPrepagoOperativo(uData, bSnap.data() as AnyMap | undefined)) {
      return TX_BLOCKED;
    }

    const vSnap = await tx.get(vRef);
    if (!vSnap.exists) {
      tx.set(
        colaRef,
        { estado: "invalidado", invalidadoEn: FieldValue.serverTimestamp(), motivo: "viaje_inexistente" },
        { merge: true },
      );
      return null;
    }
    const v = vSnap.data() as AnyMap;

    const elig =
      slot === 0 ? tripEligibleReserva(v, uidTaxista) : tripEligibleEncolado(v, uidTaxista);
    if (!elig.ok) {
      tx.set(
        colaRef,
        {
          estado: "invalidado",
          invalidadoEn: FieldValue.serverTimestamp(),
          motivo: elig.reason ?? "no_eligible",
        },
        { merge: true },
      );
      if (toStr(v.reservadoPor) === uidTaxista) {
        tx.update(vRef, {
          reservadoPor: "",
          reservadoHasta: null,
          updatedAt: FieldValue.serverTimestamp(),
          actualizadoEn: FieldValue.serverTimestamp(),
        });
      }
      return null;
    }

    const nombreTaxista = toStr(uData.nombre ?? uData.displayName);
    const tel = toStr(uData.telefono);
    const plac = toStr(uData.placa);
    const tipo = toStr(uData.tipoVehiculo);
    const marca = toStr(uData.marca ?? uData.vehiculoMarca);
    const modelo = toStr(uData.modelo ?? uData.vehiculoModelo);
    const color = toStr(uData.color ?? uData.vehiculoColor);

    assignViajeAAceptadoEnTx(tx, {
      uidTaxista,
      uRef,
      vRef,
      v,
      nombreTaxista,
      tel,
      plac,
      tipo,
      marca,
      modelo,
      color,
    });

    tx.set(
      colaRef,
      {
        estado: "promovido",
        promovidoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return viajeId;
  });
}

export type PromoverSiguienteViajeResult = {
  ok: boolean;
  promotedViajeId: string | null;
  code: string;
  message?: string;
};

export async function ejecutarPromoverSiguienteViaje(uidTaxista: string): Promise<PromoverSiguienteViajeResult> {
  const uRef = usuarios().doc(uidTaxista);
  const uSnap = await uRef.get();
  const uData = (uSnap.data() ?? {}) as AnyMap;
  const bSnap = await billeteras().doc(uidTaxista).get();

  if (!taxistaSinBloqueoPrepagoOperativo(uData, bSnap.data() as AnyMap | undefined)) {
    return {
      ok: false,
      promotedViajeId: null,
      code: "bloqueado_operativo",
      message: mensajeBloqueoOperativo(),
    };
  }

  await hydrateColaFromLegacy(uidTaxista, uData);

  const pendSnap = await uRef
    .collection("cola_viajes")
    .where("estado", "==", "pendiente")
    .limit(24)
    .get();

  const keys = pendSnap.docs.map((d) => {
    const m = d.data() as AnyMap;
    const slot = typeof m.slot === "number" && Number.isFinite(m.slot) ? Math.trunc(m.slot) : 1;
    const ts = m.createdAt as { toMillis?: () => number } | undefined;
    const createdAtMs = ts && typeof ts.toMillis === "function" ? ts.toMillis() : 0;
    return { id: d.id, slot, createdAtMs };
  });
  keys.sort(sortColaCandidates);

  for (const k of keys) {
    const promoted = await tryPromoteOne(uidTaxista, k.id, k.slot);
    if (promoted === TX_BLOCKED) {
      return {
        ok: false,
        promotedViajeId: null,
        code: "bloqueado_operativo",
        message: mensajeBloqueoOperativo(),
      };
    }
    if (promoted) {
      return { ok: true, promotedViajeId: promoted, code: "promoted" };
    }
  }

  return { ok: true, promotedViajeId: null, code: "nothing_to_promote", message: "No hay siguiente viaje válido en cola." };
}

export const promoverSiguienteViaje = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actor = request.auth.uid;
  const rawUid = toStr(request.data?.taxistaUid);
  const uidTaxista = rawUid.length > 0 ? rawUid : actor;
  if (uidTaxista !== actor) {
    const adminSnap = await usuarios().doc(actor).get();
    const rol = toStr((adminSnap.data() as AnyMap | undefined)?.rol).toLowerCase();
    if (rol !== "admin" && rol !== "administrador") {
      throw new HttpsError("permission-denied", "Solo el propio taxista o admin");
    }
  }

  const out = await ejecutarPromoverSiguienteViaje(uidTaxista);
  return out;
});

/** Admin: hidrata cola desde legacy para un taxista (migración manual). */
export const migrarColaViajesTaxistaLegacy = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actor = request.auth.uid;
  const adminSnap = await usuarios().doc(actor).get();
  const rol = toStr((adminSnap.data() as AnyMap | undefined)?.rol).toLowerCase();
  if (rol !== "admin" && rol !== "administrador") {
    throw new HttpsError("permission-denied", "Solo admin");
  }
  const uid = toStr(request.data?.uidTaxista);
  if (!uid) throw new HttpsError("invalid-argument", "uidTaxista requerido");
  const uSnap = await usuarios().doc(uid).get();
  if (!uSnap.exists) throw new HttpsError("not-found", "Usuario no existe");
  await hydrateColaFromLegacy(uid, (uSnap.data() ?? {}) as AnyMap);
  logAdminAudit({
    action: "migrar_cola_viajes_taxista_legacy",
    actorUid: actor,
    resourceType: "usuario",
    resourceId: uid,
    metadata: {},
  });
  return { ok: true };
});
