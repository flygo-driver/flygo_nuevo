import {
  FieldValue,
  getFirestore,
  Timestamp,
  type Transaction,
} from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import {
  coordsPickupClienteViaje,
  coordsReferenciaEncadenamientoViajeActivo,
  distanciaMetros,
} from "./encadenamiento_coords.js";
import { getComisionPrepagoConfig } from "./finance.js";
import { getComisionViajePorcentajeCached } from "./comision_viaje_pct.js";
import { prepagoInsuficienteParaViajeEfectivo } from "./prepago_comision_viaje.js";
import { assertTaxistaAptoParaClaimPool } from "./taxista_operacion_gate.js";
import {
  taxistaSinBloqueoPrepagoOperativo,
  type AnyMap,
} from "./taxista_cola_promote_logic.js";

const db = () => getFirestore();
const viajes = () => db().collection("viajes");
const usuarios = () => db().collection("usuarios");
const billeteras = () => db().collection("billeteras_taxista");

const ESTADOS_PEND = new Set([
  "pendiente",
  "pendiente_pago",
  "pendiente_admin",
  "pendienteadmin",
  "buscando",
  "disponible",
]);

const DEFAULT_TTL_MIN = 120;
const MAX_TTL_MIN = 180;

type PoolModoConductor = "motor" | "vehiculo";

function toStr(v: unknown): string {
  return String(v ?? "").trim();
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

function publishAtOk(v: AnyMap): boolean {
  const ms = millisOfFirestoreTime(v.publishAt);
  if (ms != null && ms > Date.now()) return false;
  return true;
}

function reservaVigenteParaOtro(v: AnyMap, uidTaxista: string): boolean {
  const reservadoPor = toStr(v.reservadoPor);
  if (!reservadoPor || reservadoPor === uidTaxista) return false;
  const ms = millisOfFirestoreTime(v.reservadoHasta);
  if (ms != null) return ms > Date.now();
  return true;
}

function poolModoConductorFromUser(u: AnyMap): PoolModoConductor {
  let raw = toStr(u.tipoServicio).toLowerCase();
  if (!raw && u.vehiculo && typeof u.vehiculo === "object") {
    raw = toStr((u.vehiculo as AnyMap).tipoServicio).toLowerCase();
  }
  return raw === "motor" ? "motor" : "vehiculo";
}

function viajeCoincideModoConductor(viajeTipo: string, modo: PoolModoConductor): boolean {
  const t = viajeTipo.toLowerCase() || "normal";
  if (modo === "motor") return t === "motor";
  return t !== "motor" && t !== "turismo";
}

function tipoColaViajeParaCola(d: AnyMap): string {
  const s = toStr(d.tipoServicio).toLowerCase();
  if (s === "pool") return "pool";
  return "normal";
}

async function maxMetrosEncadenamientoDesdeConfig(): Promise<number | null> {
  try {
    const s = await db().collection("config").doc("encadenamiento_viajes").get();
    if (!s.exists) return null;
    const raw = (s.data() as AnyMap | undefined)?.maxMetrosPickupDesdeDestinoActivo;
    if (raw == null) return null;
    const n = typeof raw === "number" ? Math.trunc(raw) : Number.parseInt(String(raw), 10);
    if (!Number.isFinite(n) || n <= 0) return null;
    return n;
  } catch {
    return null;
  }
}

export type ReservarSiguienteViajeResult = {
  ok: boolean;
  code: string;
  message?: string;
  viajeId?: string;
};

export async function ejecutarReservarSiguienteViaje(params: {
  uidTaxista: string;
  viajeId: string;
  ttlMin?: number;
}): Promise<ReservarSiguienteViajeResult> {
  const uidTaxista = toStr(params.uidTaxista);
  const viajeId = toStr(params.viajeId);
  if (!uidTaxista || !viajeId) {
    return { ok: false, code: "invalid-argument", message: "Datos incompletos." };
  }

  const ttlMin = Math.min(
    MAX_TTL_MIN,
    Math.max(15, Math.trunc(params.ttlMin ?? DEFAULT_TTL_MIN)),
  );

  const prepagoCfg = await getComisionPrepagoConfig();
  const globalComisionPct = await getComisionViajePorcentajeCached();
  const maxMetros = await maxMetrosEncadenamientoDesdeConfig();

  const uRef = usuarios().doc(uidTaxista);
  const vRef = viajes().doc(viajeId);
  const colaRef = uRef.collection("cola_viajes").doc(viajeId);

  try {
    await db().runTransaction(async (tx: Transaction) => {
      const vSnap = await tx.get(vRef);
      if (!vSnap.exists) {
        throw new HttpsError("not-found", "no-existe");
      }
      const d = vSnap.data() as AnyMap;
      const estado = toStr(d.estado).toLowerCase();
      const uidAsignado = toStr(d.uidTaxista ?? d.taxistaId);
      if (!ESTADOS_PEND.has(estado) || uidAsignado.length > 0) {
        throw new HttpsError("failed-precondition", "viaje-no-disponible");
      }
      if (toStr(d.canalAsignacion) === "corporativo_fijo") {
        throw new HttpsError("failed-precondition", "corporativo-fijo");
      }
      if (!acceptAfterOk(d)) {
        throw new HttpsError("failed-precondition", "acceptAfter-futuro");
      }
      if (!publishAtOk(d)) {
        throw new HttpsError("failed-precondition", "publish-futuro");
      }
      if (reservaVigenteParaOtro(d, uidTaxista)) {
        throw new HttpsError("failed-precondition", "reservado-otro");
      }

      const uSnap = await tx.get(uRef);
      const uData = (uSnap.data() ?? {}) as AnyMap;
      assertTaxistaAptoParaClaimPool(uData);

      const bSnap = await tx.get(billeteras().doc(uidTaxista));
      if (
        !taxistaSinBloqueoPrepagoOperativo(
          uData,
          bSnap.data() as AnyMap | undefined,
          prepagoCfg.minimoOperativoRd,
          prepagoCfg.permitirViajeConPrepagoParcial,
        )
      ) {
        if (uData.tienePagoPendiente === true) {
          throw new HttpsError("failed-precondition", "bloqueado-pago-semanal");
        }
        throw new HttpsError("failed-precondition", "bloqueado-comision-efectivo");
      }

      if (
        prepagoInsuficienteParaViajeEfectivo({
          billeData: bSnap.data() as AnyMap | undefined,
          viajeData: d,
          globalComisionPct,
          permitirViajeConPrepagoParcial: prepagoCfg.permitirViajeConPrepagoParcial,
        })
      ) {
        throw new HttpsError("failed-precondition", "prepago-insuficiente-comision-viaje");
      }

      const viajeActivoId = toStr(uData.viajeActivoId);
      if (!viajeActivoId) {
        throw new HttpsError("failed-precondition", "sin-viaje-activo");
      }

      const siguienteViajeId = toStr(uData.siguienteViajeId);
      if (siguienteViajeId && siguienteViajeId !== viajeId) {
        throw new HttpsError("failed-precondition", "ya-tiene-siguiente");
      }

      const poolModo = poolModoConductorFromUser(uData);
      const viajeTipo = toStr(d.tipoServicio) || "normal";
      if (!viajeCoincideModoConductor(viajeTipo, poolModo)) {
        throw new HttpsError("failed-precondition", "tipo-servicio-no-coincide");
      }

      if (maxMetros != null && maxMetros > 0) {
        const actSnap = await tx.get(viajes().doc(viajeActivoId));
        const refAct = coordsReferenciaEncadenamientoViajeActivo(
          actSnap.exists ? (actSnap.data() as AnyMap) : undefined,
        );
        const pickup = coordsPickupClienteViaje(d);
        if (refAct && pickup) {
          const m = distanciaMetros(refAct, pickup);
          if (m > maxMetros + 1e-6) {
            throw new HttpsError("failed-precondition", "demasiado-lejos");
          }
        }
      }

      const vence = Timestamp.fromDate(new Date(Date.now() + ttlMin * 60_000));

      tx.update(vRef, {
        reservadoPor: uidTaxista,
        reservadoHasta: vence,
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      });

      tx.set(
        uRef,
        {
          siguienteViajeId: viajeId,
          viajeEncoladoId: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      tx.set(
        colaRef,
        {
          viajeId,
          slot: 0,
          estado: "pendiente",
          tipo: tipoColaViajeParaCola(d),
          createdAt: FieldValue.serverTimestamp(),
          source: "reservarSiguienteViaje",
          reservadoHasta: vence,
        },
        { merge: true },
      );
    });

    return { ok: true, code: "reserved", viajeId };
  } catch (e) {
    if (e instanceof HttpsError) {
      return {
        ok: false,
        code: e.message,
        message: e.message,
      };
    }
    const msg = e instanceof Error ? e.message : String(e);
    return { ok: false, code: "error", message: msg };
  }
}

export const reservarSiguienteViaje = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const actor = request.auth.uid;
  const rawUid = toStr(request.data?.uidTaxista);
  const uidTaxista = rawUid.length > 0 ? rawUid : actor;
  if (uidTaxista !== actor) {
    const adminSnap = await usuarios().doc(actor).get();
    const rol = toStr((adminSnap.data() as AnyMap | undefined)?.rol).toLowerCase();
    if (rol !== "admin" && rol !== "administrador") {
      throw new HttpsError("permission-denied", "Solo el propio taxista o admin");
    }
  }

  const viajeId = toStr(request.data?.viajeId);
  const ttlRaw = request.data?.ttlMin;
  const ttlMin =
    typeof ttlRaw === "number" && Number.isFinite(ttlRaw)
      ? Math.trunc(ttlRaw)
      : DEFAULT_TTL_MIN;

  const out = await ejecutarReservarSiguienteViaje({
    uidTaxista,
    viajeId,
    ttlMin,
  });

  if (!out.ok) {
    const code = out.code || "error";
    if (code === "bloqueado-comision-efectivo" || code === "bloqueado-pago-semanal") {
      throw new HttpsError("failed-precondition", code);
    }
    throw new HttpsError("failed-precondition", code);
  }

  return out;
});
