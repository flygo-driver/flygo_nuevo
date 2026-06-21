/**
 * Fase 4 — conciliaciones: movimiento_banco ↔ viaje (referencia + monto).
 * Todo confirmación de pago verificado ocurre aquí o en confirmarConciliacion (servidor).
 */
import { FieldValue, getFirestore, Transaction } from "firebase-admin/firestore";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";

import { normalizarReferenciaExtracto } from "./banco_movimientos.js";
import { getFinanceConfig } from "./finance.js";
import {
  elegibleLiquidacionSemanalCache,
  metodoPagoNormalizadoDesde,
} from "./liquidacion_semanal_viaje.js";
import {
  ejecutarVerificacionPoolRecaudoEnTransaction,
  getComisionGiraPorcientoFromRemote,
  precioCentsPoolReserva,
} from "./pool_finance.js";
import { esReferenciaRecaudoPoolValida } from "./pool_referencia.js";
import { esReferenciaRecaudoValida } from "./viaje_referencia.js";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();

/** Actor sistema — auto-verificación pool RAI-P (ref + monto exacto). */
export const SYSTEM_POOL_CONCILIACION_AUTO = "system_pool_conciliacion_auto";

export type ProcesarMovConciliacionResult = {
  movId: string;
  accion: "omitido" | "sin_match" | "propuesta" | "confirmada";
  motivo?: string;
  conciliacionId?: string;
  tipo?: string;
};

export type PoolConciliacionFinanceFlags = {
  conciliacionAutomaticaHabilitada: boolean;
  poolRecaudoAutoVerificarConciliacion: boolean;
};

/** Flags giras recaudo central + conciliación (config/finance). */
export async function getPoolConciliacionFinanceFlags(): Promise<PoolConciliacionFinanceFlags> {
  const cfg = await getFinanceConfig();
  let poolRecaudoAutoVerificarConciliacion = false;
  try {
    const snap = await db().collection("config").doc("finance").get();
    poolRecaudoAutoVerificarConciliacion =
      (snap.data() ?? {}).poolRecaudoAutoVerificarConciliacion === true;
  } catch (e) {
    logger.warn("[getPoolConciliacionFinanceFlags] fallback", e);
  }
  return {
    conciliacionAutomaticaHabilitada: cfg.conciliacionAutomaticaHabilitada,
    poolRecaudoAutoVerificarConciliacion,
  };
}

/** Solo giras RAI-P con ref+monto exacto — nunca viajes taxi ni legacy pool. */
export function debeAutoConfirmarPoolConciliacion(
  matchReglas: string[],
  flags: PoolConciliacionFinanceFlags,
): boolean {
  return (
    flags.conciliacionAutomaticaHabilitada &&
    flags.poolRecaudoAutoVerificarConciliacion &&
    matchReglas.includes("ref_exacta") &&
    matchReglas.includes("monto_exacto")
  );
}

function normalizeRole(raw: unknown): string {
  const r = String(raw ?? "").trim().toLowerCase();
  return r === "administrador" ? "admin" : r;
}

async function getRole(uid: string): Promise<string> {
  const u = await db().collection("usuarios").doc(uid).get();
  const uData = u.data() as AnyMap | undefined;
  const r1 = normalizeRole(uData?.rol);
  if (r1 === "admin") return "admin";
  if (uData?.isAdmin === true || uData?.admin === true) return "admin";
  const r = await db().collection("roles").doc(uid).get();
  return normalizeRole((r.data() as AnyMap | undefined)?.rol);
}

async function assertAdmin(uid: string): Promise<void> {
  if ((await getRole(uid)) !== "admin") {
    throw new HttpsError("permission-denied", "Solo admin");
  }
}

export function precioCentsViaje(data: AnyMap): number {
  const raw = data.precio_cents;
  if (typeof raw === "number" && Number.isFinite(raw) && raw > 0) {
    return Math.trunc(raw);
  }
  const precio = Number(data.precioFinal ?? data.precio ?? data.total ?? 0);
  if (!Number.isFinite(precio) || precio <= 0) return 0;
  return Math.round(precio * 100);
}

export type MatchConciliacionInput = {
  referenciaMovimiento: string;
  montoMovimientoCents: number;
  referenciaViaje: string;
  montoViajeCents: number;
};

/** Evalúa match ref+monto para proponer conciliación (RAI-V o RAI-P). */
export function evaluarMatchConciliacionReferencia(input: MatchConciliacionInput): {
  ok: boolean;
  matchReglas: string[];
  diferenciaCents: number;
  matchScore: number;
} {
  const refM = normalizarReferenciaExtracto(input.referenciaMovimiento);
  const refV = normalizarReferenciaExtracto(input.referenciaViaje);
  const matchReglas: string[] = [];

  if (!esReferenciaRecaudoValida(refM) && !esReferenciaRecaudoPoolValida(refM)) {
    return { ok: false, matchReglas, diferenciaCents: 0, matchScore: 0 };
  }
  if (!esReferenciaRecaudoValida(refV) && !esReferenciaRecaudoPoolValida(refV)) {
    return { ok: false, matchReglas, diferenciaCents: 0, matchScore: 0 };
  }
  if (refM !== refV) {
    return { ok: false, matchReglas, diferenciaCents: 0, matchScore: 0 };
  }
  matchReglas.push("ref_exacta");

  const esperado = Math.max(0, Math.trunc(input.montoViajeCents));
  const real = Math.max(0, Math.trunc(input.montoMovimientoCents));
  const diferenciaCents = real - esperado;

  if (diferenciaCents === 0 && esperado > 0) {
    matchReglas.push("monto_exacto");
  } else if (esperado > 0) {
    matchReglas.push("monto_discrepancia");
  } else {
    return { ok: false, matchReglas, diferenciaCents, matchScore: 0 };
  }

  const ok = matchReglas.includes("ref_exacta") && esperado > 0 && real > 0;
  const matchScore = ok
    ? matchReglas.includes("monto_exacto")
      ? 1
      : 0.75
    : 0;
  return { ok, matchReglas, diferenciaCents, matchScore };
}

/** @deprecated alias */
export const evaluarMatchConciliacionViaje = evaluarMatchConciliacionReferencia;

function esReferenciaRecaudoCualquieraValida(ref: string): boolean {
  const n = normalizarReferenciaExtracto(ref);
  return esReferenciaRecaudoValida(n) || esReferenciaRecaudoPoolValida(n);
}

async function buscarReservaPoolPorReferenciaRecaudo(ref: string): Promise<{
  poolId: string;
  reservaId: string;
  data: AnyMap;
} | null> {
  const refNorm = normalizarReferenciaExtracto(ref);
  if (!esReferenciaRecaudoPoolValida(refNorm)) return null;

  const q = await db()
    .collectionGroup("reservas")
    .where("referenciaRecaudo", "==", refNorm)
    .limit(3)
    .get();

  if (q.empty) return null;
  if (q.size > 1) {
    logger.warn("[conciliacion] referenciaRecaudo pool ambigua", { ref: refNorm, count: q.size });
  }
  const doc = q.docs[0];
  const poolId = doc.ref.parent.parent?.id ?? "";
  if (!poolId) return null;
  return { poolId, reservaId: doc.id, data: (doc.data() ?? {}) as AnyMap };
}

function viajeUsaRecaudoRai(d: AnyMap): boolean {
  const ref = String(d.referenciaRecaudo ?? "").trim();
  if (ref) return true;
  return String(d.recaudoDestino ?? "").trim().toLowerCase() === "rai";
}

async function buscarViajePorReferenciaRecaudo(ref: string): Promise<{
  id: string;
  data: AnyMap;
} | null> {
  const refNorm = normalizarReferenciaExtracto(ref);
  if (!esReferenciaRecaudoValida(refNorm)) return null;

  const q = await db()
    .collection("viajes")
    .where("referenciaRecaudo", "==", refNorm)
    .limit(3)
    .get();

  if (q.empty) return null;
  if (q.size > 1) {
    logger.warn("[conciliacion] referenciaRecaudo ambigua", { ref: refNorm, count: q.size });
  }
  const doc = q.docs[0];
  return { id: doc.id, data: (doc.data() ?? {}) as AnyMap };
}

async function intentarAutoConfirmarPoolPropuesta(
  concId: string,
  flags: PoolConciliacionFinanceFlags,
  matchReglas: string[],
): Promise<boolean> {
  if (!debeAutoConfirmarPoolConciliacion(matchReglas, flags)) return false;
  const pctRemote = await getComisionGiraPorcientoFromRemote();
  try {
    await db().runTransaction(async (tx) => {
      await aplicarConciliacionConfirmadaTx(
        tx,
        concId,
        SYSTEM_POOL_CONCILIACION_AUTO,
        "Auto: ref RAI-P + monto exacto en cuenta RAI",
        pctRemote,
      );
    });
    logger.info("[conciliacion] pool auto-confirmada", { concId });
    return true;
  } catch (e) {
    logger.warn("[conciliacion] pool auto-confirm falló", { concId, e });
    return false;
  }
}

/** Procesa un movimiento banco (entrada sin_match) → propuesta y/o verificación pool. */
export async function procesarMovimientoBancoConciliacion(
  movId: string,
  mov: AnyMap,
  flags: PoolConciliacionFinanceFlags,
): Promise<ProcesarMovConciliacionResult> {
  if (!flags.conciliacionAutomaticaHabilitada) {
    return { movId, accion: "omitido", motivo: "conciliacionAutomaticaHabilitada=false" };
  }

  const tipoMov = String(mov.tipo ?? "").trim().toLowerCase();
  const estadoConc = String(mov.estadoConciliacion ?? "sin_match").trim().toLowerCase();
  if (tipoMov !== "entrada") {
    return { movId, accion: "omitido", motivo: "no_entrada" };
  }
  if (estadoConc !== "sin_match" && estadoConc !== "discrepancia" && estadoConc !== "parcial") {
    return { movId, accion: "omitido", motivo: `estado_${estadoConc || "—"}` };
  }

  const refM = String(mov.referenciaNormalizada ?? mov.referenciaBanco ?? "").trim();
  const refNorm = normalizarReferenciaExtracto(refM);
  if (!esReferenciaRecaudoCualquieraValida(refNorm)) {
    return { movId, accion: "omitido", motivo: "ref_no_rai" };
  }

  const concId = `prop_${movId}`;
  const concRef = db().collection("conciliaciones").doc(concId);
  const concExisting = await concRef.get();
  if (concExisting.exists) {
    const c = (concExisting.data() ?? {}) as AnyMap;
    const est = String(c.estado ?? "");
    if (est === "confirmada") {
      return { movId, accion: "omitido", motivo: "ya_confirmada", conciliacionId: concId };
    }
    if (est === "propuesta") {
      const tipo = String(c.tipo ?? "");
      const reglas = Array.isArray(c.matchReglas)
        ? (c.matchReglas as unknown[]).map((x) => String(x))
        : [];
      if (tipo === "pool_reserva_entrada") {
        const ok = await intentarAutoConfirmarPoolPropuesta(concId, flags, reglas);
        if (ok) {
          return {
            movId,
            accion: "confirmada",
            conciliacionId: concId,
            tipo: "pool_reserva_entrada",
          };
        }
      }
      return { movId, accion: "omitido", motivo: "propuesta_pendiente", conciliacionId: concId };
    }
  }

  const montoRealCents = Math.trunc(Number(mov.montoCents ?? 0));
  const now = FieldValue.serverTimestamp();
  const movRef = db().collection("movimientos_banco").doc(movId);

  if (esReferenciaRecaudoPoolValida(refNorm)) {
    const poolRes = await buscarReservaPoolPorReferenciaRecaudo(refNorm);
    if (!poolRes) {
      return { movId, accion: "sin_match", motivo: "reserva_pool_no_encontrada" };
    }
    const r = poolRes.data;
    const estadoPago = String(r.estadoPago ?? "").trim().toLowerCase();
    const estadoRes = String(r.estado ?? "").trim().toLowerCase();
    if (estadoPago === "verificado" || estadoRes === "pagado") {
      return { movId, accion: "omitido", motivo: "reserva_ya_pagada" };
    }
    if (String(r.recaudoDestino ?? "").trim().toLowerCase() !== "rai") {
      return { movId, accion: "omitido", motivo: "pool_no_recaudo_rai" };
    }

    const montoEsperadoCents = precioCentsPoolReserva(r);
    const evalMatch = evaluarMatchConciliacionReferencia({
      referenciaMovimiento: refM,
      montoMovimientoCents: montoRealCents,
      referenciaViaje: String(r.referenciaRecaudo ?? refM),
      montoViajeCents: montoEsperadoCents,
    });
    if (!evalMatch.ok) {
      return { movId, accion: "omitido", motivo: "match_pool_invalido" };
    }

    await concRef.set({
      tipo: "pool_reserva_entrada",
      estado: "propuesta",
      movimientoBancoId: movId,
      poolId: poolRes.poolId,
      reservaId: poolRes.reservaId,
      montoEsperadoCents,
      montoRealCents,
      diferenciaCents: evalMatch.diferenciaCents,
      referenciaRecaudo: refNorm,
      matchScore: evalMatch.matchScore,
      matchReglas: evalMatch.matchReglas,
      resueltoPor: "system",
      nota: evalMatch.matchReglas.includes("monto_discrepancia")
        ? "Discrepancia de monto pool: revisar antes de confirmar."
        : "",
      createdAt: now,
      updatedAt: now,
    });

    await movRef.set(
      {
        estadoConciliacion: evalMatch.matchReglas.includes("monto_discrepancia")
          ? "discrepancia"
          : "parcial",
        conciliacionId: concId,
        poolId: poolRes.poolId,
        reservaId: poolRes.reservaId,
        updatedAt: now,
      },
      { merge: true },
    );

    if (await intentarAutoConfirmarPoolPropuesta(concId, flags, evalMatch.matchReglas)) {
      return {
        movId,
        accion: "confirmada",
        conciliacionId: concId,
        tipo: "pool_reserva_entrada",
      };
    }

    return {
      movId,
      accion: "propuesta",
      conciliacionId: concId,
      tipo: "pool_reserva_entrada",
    };
  }

  const viaje = await buscarViajePorReferenciaRecaudo(refM);
  if (!viaje) {
    return { movId, accion: "sin_match", motivo: "viaje_no_encontrado" };
  }

  const v = viaje.data;
  if (!viajeUsaRecaudoRai(v)) {
    return { movId, accion: "omitido", motivo: "viaje_no_recaudo_rai" };
  }

  const estadoPago = String(v.estadoPago ?? "").trim().toLowerCase();
  if (estadoPago === "verificado" || v.transferenciaConfirmada === true) {
    return { movId, accion: "omitido", motivo: "viaje_ya_verificado" };
  }

  const montoEsperadoCents = precioCentsViaje(v);
  const evalMatch = evaluarMatchConciliacionReferencia({
    referenciaMovimiento: refM,
    montoMovimientoCents: montoRealCents,
    referenciaViaje: String(v.referenciaRecaudo ?? refM),
    montoViajeCents: montoEsperadoCents,
  });

  if (!evalMatch.ok) {
    return { movId, accion: "omitido", motivo: "match_viaje_invalido" };
  }

  await concRef.set({
    tipo: "viaje_entrada",
    estado: "propuesta",
    movimientoBancoId: movId,
    viajeId: viaje.id,
    montoEsperadoCents,
    montoRealCents,
    diferenciaCents: evalMatch.diferenciaCents,
    referenciaRecaudo: normalizarReferenciaExtracto(String(v.referenciaRecaudo ?? refM)),
    matchScore: evalMatch.matchScore,
    matchReglas: evalMatch.matchReglas,
    resueltoPor: "system",
    nota: evalMatch.matchReglas.includes("monto_discrepancia")
      ? "Discrepancia de monto: requiere revisión admin antes de confirmar."
      : "",
    createdAt: now,
    updatedAt: now,
  });

  await movRef.set(
    {
      estadoConciliacion: evalMatch.matchReglas.includes("monto_discrepancia")
        ? "discrepancia"
        : "parcial",
      conciliacionId: concId,
      viajeId: viaje.id,
      updatedAt: now,
    },
    { merge: true },
  );

  return {
    movId,
    accion: "propuesta",
    conciliacionId: concId,
    tipo: "viaje_entrada",
  };
}

/** Escanea movimientos sin_match (job interno / callable admin). */
export async function procesarLoteMovimientosSinMatch(limit = 30): Promise<{
  propuestas: number;
  confirmadas: number;
  omitidos: number;
  sinMatch: number;
  escaneados: number;
}> {
  const flags = await getPoolConciliacionFinanceFlags();
  if (!flags.conciliacionAutomaticaHabilitada) {
    return { propuestas: 0, confirmadas: 0, omitidos: 0, sinMatch: 0, escaneados: 0 };
  }

  const movSnap = await db()
    .collection("movimientos_banco")
    .where("estadoConciliacion", "==", "sin_match")
    .where("tipo", "==", "entrada")
    .orderBy("fechaValor", "desc")
    .limit(limit)
    .get();

  let propuestas = 0;
  let confirmadas = 0;
  let omitidos = 0;
  let sinMatch = 0;

  for (const movDoc of movSnap.docs) {
    const r = await procesarMovimientoBancoConciliacion(
      movDoc.id,
      movDoc.data() as AnyMap,
      flags,
    );
    if (r.accion === "propuesta") propuestas++;
    else if (r.accion === "confirmada") confirmadas++;
    else if (r.accion === "sin_match") sinMatch++;
    else omitidos++;
  }

  return {
    propuestas,
    confirmadas,
    omitidos,
    sinMatch,
    escaneados: movSnap.size,
  };
}

/** Admin: escanea movimientos sin_match y crea conciliaciones propuesta (flag ON). */
export const proponerConciliacionesAutomaticas = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const flags = await getPoolConciliacionFinanceFlags();
  if (!flags.conciliacionAutomaticaHabilitada) {
    return { ok: true, omitido: true, motivo: "conciliacionAutomaticaHabilitada=false" };
  }

  const limitRaw = request.data?.limit;
  const limit =
    typeof limitRaw === "number" && limitRaw > 0 && limitRaw <= 80
      ? Math.trunc(limitRaw)
      : 30;

  const batch = await procesarLoteMovimientosSinMatch(limit);

  return {
    ok: true,
    propuestas: batch.propuestas,
    confirmadas: batch.confirmadas,
    omitidos: batch.omitidos,
    sinMatch: batch.sinMatch,
    sinViaje: batch.sinMatch,
    escaneados: batch.escaneados,
  };
});

async function aplicarConciliacionConfirmadaTx(
  tx: Transaction,
  conciliacionId: string,
  actorUid: string,
  notaAdmin: string,
  pctRemotePool: number,
): Promise<void> {
  const concRef = db().collection("conciliaciones").doc(conciliacionId);
  const concSnap = await tx.get(concRef);
  if (!concSnap.exists) throw new HttpsError("not-found", "Conciliación no encontrada");

  const c = (concSnap.data() ?? {}) as AnyMap;
  const estado = String(c.estado ?? "");
  if (estado === "confirmada") return;
  if (estado !== "propuesta") {
    throw new HttpsError("failed-precondition", "Conciliación no está en propuesta");
  }

  const movId = String(c.movimientoBancoId ?? "").trim();
  if (!movId) {
    throw new HttpsError("failed-precondition", "Conciliación incompleta");
  }

  const movRef = db().collection("movimientos_banco").doc(movId);
  const movSnap = await tx.get(movRef);
  if (!movSnap.exists) {
    throw new HttpsError("not-found", "Movimiento no existe");
  }

  const now = FieldValue.serverTimestamp();
  const tipo = String(c.tipo ?? "viaje_entrada").trim();

  if (tipo === "pool_reserva_entrada") {
    const poolId = String(c.poolId ?? "").trim();
    const reservaId = String(c.reservaId ?? "").trim();
    if (!poolId || !reservaId) {
      throw new HttpsError("failed-precondition", "Conciliación pool incompleta");
    }

    await ejecutarVerificacionPoolRecaudoEnTransaction(
      tx,
      poolId,
      reservaId,
      actorUid,
      pctRemotePool,
    );

    tx.update(movRef, {
      estadoConciliacion: "conciliado",
      conciliacionId: conciliacionId,
      poolId,
      reservaId,
      updatedAt: now,
    });
    tx.update(concRef, {
      estado: "confirmada",
      resueltoPor: actorUid,
      resueltoEn: now,
      nota: notaAdmin || String(c.nota ?? ""),
      updatedAt: now,
    });
    return;
  }

  const viajeId = String(c.viajeId ?? "").trim();
  if (!viajeId) {
    throw new HttpsError("failed-precondition", "Conciliación incompleta");
  }

  const viajeRef = db().collection("viajes").doc(viajeId);
  const viajeSnap = await tx.get(viajeRef);
  if (!viajeSnap.exists) {
    throw new HttpsError("not-found", "Viaje no existe");
  }

  const v = (viajeSnap.data() ?? {}) as AnyMap;
  const metodoNorm = metodoPagoNormalizadoDesde(v);
  const patchViaje: AnyMap = {
    estadoPago: "verificado",
    transferenciaConfirmada: true,
    conciliacionId: conciliacionId,
    conciliacionEstado: "confirmada",
    movimientoBancoEntradaId: movId,
    conciliacionConfirmadaEn: now,
    conciliacionConfirmadaPor: actorUid,
    "payment.status": "bank_transfer_validated",
    "payment.provider": "transfer",
    "payment.updatedAt": now,
    updatedAt: now,
    actualizadoEn: now,
  };

  if (metodoNorm === "transferencia" || metodoNorm === "tarjeta") {
    patchViaje.elegibleLiquidacionSemanal = elegibleLiquidacionSemanalCache({
      ...v,
      ...patchViaje,
      liquidado: v.liquidado === true,
    });
  }

  tx.update(viajeRef, patchViaje);
  tx.update(movRef, {
    estadoConciliacion: "conciliado",
    conciliacionId: conciliacionId,
    viajeId,
    updatedAt: now,
  });
  tx.update(concRef, {
    estado: "confirmada",
    resueltoPor: actorUid,
    resueltoEn: now,
    nota: notaAdmin || String(c.nota ?? ""),
    updatedAt: now,
  });
}

/** Admin: confirma propuesta → viaje verificado + movimiento conciliado. */
export const confirmarConciliacion = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  await assertAdmin(actorUid);

  const conciliacionId =
    typeof request.data?.conciliacionId === "string"
      ? request.data.conciliacionId.trim()
      : "";
  const notaAdmin =
    typeof request.data?.notaAdmin === "string" ? request.data.notaAdmin.trim() : "";
  if (!conciliacionId) throw new HttpsError("invalid-argument", "Falta conciliacionId");

  const concPre = await db().collection("conciliaciones").doc(conciliacionId).get();
  const tipoPre = String((concPre.data() as AnyMap | undefined)?.tipo ?? "viaje_entrada");
  const pctRemotePool =
    tipoPre === "pool_reserva_entrada" ? await getComisionGiraPorcientoFromRemote() : 0;

  await db().runTransaction(async (tx) => {
    await aplicarConciliacionConfirmadaTx(tx, conciliacionId, actorUid, notaAdmin, pctRemotePool);
  });

  return { ok: true, conciliacionId, estado: "confirmada" };
});

/** Admin: rechaza propuesta; movimiento vuelve a sin_match. */
export const rechazarConciliacion = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  await assertAdmin(actorUid);

  const conciliacionId =
    typeof request.data?.conciliacionId === "string"
      ? request.data.conciliacionId.trim()
      : "";
  const notaAdmin =
    typeof request.data?.notaAdmin === "string" ? request.data.notaAdmin.trim() : "";
  if (!conciliacionId) throw new HttpsError("invalid-argument", "Falta conciliacionId");

  const concRef = db().collection("conciliaciones").doc(conciliacionId);
  await db().runTransaction(async (tx) => {
    const concSnap = await tx.get(concRef);
    if (!concSnap.exists) throw new HttpsError("not-found", "Conciliación no encontrada");
    const c = (concSnap.data() ?? {}) as AnyMap;
    if (String(c.estado ?? "") === "confirmada") {
      throw new HttpsError("failed-precondition", "Conciliación ya confirmada");
    }

    const movId = String(c.movimientoBancoId ?? "").trim();
    const now = FieldValue.serverTimestamp();

    tx.update(concRef, {
      estado: "rechazada",
      resueltoPor: actorUid,
      resueltoEn: now,
      nota: notaAdmin,
      updatedAt: now,
    });

    if (movId) {
      tx.update(db().collection("movimientos_banco").doc(movId), {
        estadoConciliacion: "sin_match",
        conciliacionId: FieldValue.delete(),
        viajeId: FieldValue.delete(),
        poolId: FieldValue.delete(),
        reservaId: FieldValue.delete(),
        updatedAt: now,
      });
    }
  });

  return { ok: true, conciliacionId, estado: "rechazada" };
});

/** Admin: concilia manualmente movimiento ↔ viaje (crea propuesta y confirma). */
export const conciliarViajeConMovimiento = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  await assertAdmin(actorUid);

  const movimientoBancoId =
    typeof request.data?.movimientoBancoId === "string"
      ? request.data.movimientoBancoId.trim()
      : "";
  const viajeId =
    typeof request.data?.viajeId === "string" ? request.data.viajeId.trim() : "";
  const notaAdmin =
    typeof request.data?.notaAdmin === "string" ? request.data.notaAdmin.trim() : "";
  if (!movimientoBancoId || !viajeId) {
    throw new HttpsError("invalid-argument", "Faltan movimientoBancoId o viajeId");
  }

  const conciliacionId = `manual_${movimientoBancoId}_${viajeId}`.slice(0, 120);

  await db().runTransaction(async (tx) => {
    const movRef = db().collection("movimientos_banco").doc(movimientoBancoId);
    const viajeRef = db().collection("viajes").doc(viajeId);
    const movSnap = await tx.get(movRef);
    const viajeSnap = await tx.get(viajeRef);
    if (!movSnap.exists || !viajeSnap.exists) {
      throw new HttpsError("not-found", "Movimiento o viaje no existe");
    }

    const mov = (movSnap.data() ?? {}) as AnyMap;
    const v = (viajeSnap.data() ?? {}) as AnyMap;
    const montoEsperadoCents = precioCentsViaje(v);
    const montoRealCents = Math.trunc(Number(mov.montoCents ?? 0));
    const refV = String(v.referenciaRecaudo ?? "");
    const refM = String(mov.referenciaNormalizada ?? mov.referenciaBanco ?? "");

    const evalMatch = evaluarMatchConciliacionReferencia({
      referenciaMovimiento: refM,
      montoMovimientoCents: montoRealCents,
      referenciaViaje: refV,
      montoViajeCents: montoEsperadoCents,
    });

    if (!evalMatch.matchReglas.includes("ref_exacta")) {
      throw new HttpsError(
        "failed-precondition",
        "Referencias no coinciden (se requiere RAI-V exacta)",
      );
    }

    const now = FieldValue.serverTimestamp();
    const concRef = db().collection("conciliaciones").doc(conciliacionId);
    tx.set(
      concRef,
      {
        tipo: "viaje_entrada",
        estado: "propuesta",
        movimientoBancoId,
        viajeId,
        montoEsperadoCents,
        montoRealCents,
        diferenciaCents: evalMatch.diferenciaCents,
        referenciaRecaudo: normalizarReferenciaExtracto(refV || refM),
        matchScore: evalMatch.matchScore,
        matchReglas: [...evalMatch.matchReglas, "manual_admin"],
        resueltoPor: actorUid,
        nota: notaAdmin,
        createdAt: now,
        updatedAt: now,
      },
      { merge: true },
    );

    await aplicarConciliacionConfirmadaTx(tx, conciliacionId, actorUid, notaAdmin, 0);
  });

  return { ok: true, conciliacionId, estado: "confirmada" };
});

/** Admin: lista conciliaciones propuesta pendientes de confirmación. */
export const listarConciliacionesPropuestas = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const limitRaw = request.data?.limit;
  const limit =
    typeof limitRaw === "number" && limitRaw > 0 && limitRaw <= 100
      ? Math.trunc(limitRaw)
      : 40;

  const snap = await db()
    .collection("conciliaciones")
    .where("estado", "==", "propuesta")
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get();

  return {
    ok: true,
    conciliaciones: snap.docs.map((d) => ({ id: d.id, ...d.data() })),
  };
});

/** Al crear movimiento banco (extracto): propone y auto-verifica giras RAI-P si flags ON. */
export const onMovimientoBancoCreatedConciliar = onDocumentCreated(
  "movimientos_banco/{movId}",
  async (event) => {
    const movId = event.params.movId;
    const mov = (event.data?.data() ?? {}) as AnyMap;
    const flags = await getPoolConciliacionFinanceFlags();
    if (!flags.conciliacionAutomaticaHabilitada) return;

    try {
      const r = await procesarMovimientoBancoConciliacion(movId, mov, flags);
      if (r.accion === "confirmada" || r.accion === "propuesta") {
        logger.info("[onMovimientoBancoCreatedConciliar]", r);
      }
    } catch (e) {
      logger.error("[onMovimientoBancoCreatedConciliar] error", { movId, e });
    }
  },
);

/** Respaldo cada 15 min: cola sin_match (no reemplaza revisión admin en discrepancias). */
export const scheduledProcesarConciliacionesBanco = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "America/Santo_Domingo",
  },
  async () => {
    const flags = await getPoolConciliacionFinanceFlags();
    if (!flags.conciliacionAutomaticaHabilitada) return;

    try {
      const batch = await procesarLoteMovimientosSinMatch(40);
      if (batch.propuestas > 0 || batch.confirmadas > 0) {
        logger.info("[scheduledProcesarConciliacionesBanco]", batch);
      }
    } catch (e) {
      logger.error("[scheduledProcesarConciliacionesBanco]", e);
    }
  },
);
