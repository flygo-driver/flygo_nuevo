/**
 * Fase 4 — conciliaciones: movimiento_banco ↔ viaje (referencia + monto).
 * Todo confirmación de pago verificado ocurre aquí o en confirmarConciliacion (servidor).
 */
import { FieldValue, getFirestore, Transaction } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { normalizarReferenciaExtracto } from "./banco_movimientos.js";
import { getFinanceConfig } from "./finance.js";
import {
  elegibleLiquidacionSemanalCache,
  metodoPagoNormalizadoDesde,
} from "./liquidacion_semanal_viaje.js";
import { esReferenciaRecaudoValida } from "./viaje_referencia.js";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();

function normalizeRole(raw: unknown): string {
  const r = String(raw ?? "").trim().toLowerCase();
  return r === "administrador" ? "admin" : r;
}

async function getRole(uid: string): Promise<string> {
  const u = await db().collection("usuarios").doc(uid).get();
  const r1 = normalizeRole((u.data() as AnyMap | undefined)?.rol);
  if (r1) return r1;
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

/** Evalúa match ref+monto para proponer conciliación. Requiere referencia RAI-V exacta. */
export function evaluarMatchConciliacionViaje(input: MatchConciliacionInput): {
  ok: boolean;
  matchReglas: string[];
  diferenciaCents: number;
  matchScore: number;
} {
  const refM = normalizarReferenciaExtracto(input.referenciaMovimiento);
  const refV = normalizarReferenciaExtracto(input.referenciaViaje);
  const matchReglas: string[] = [];

  if (!esReferenciaRecaudoValida(refM) || !esReferenciaRecaudoValida(refV)) {
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

/** Admin: escanea movimientos sin_match y crea conciliaciones propuesta (flag ON). */
export const proponerConciliacionesAutomaticas = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  await assertAdmin(actorUid);

  const cfg = await getFinanceConfig();
  if (!cfg.conciliacionAutomaticaHabilitada) {
    return { ok: true, omitido: true, motivo: "conciliacionAutomaticaHabilitada=false" };
  }

  const limitRaw = request.data?.limit;
  const limit =
    typeof limitRaw === "number" && limitRaw > 0 && limitRaw <= 80
      ? Math.trunc(limitRaw)
      : 30;

  const movSnap = await db()
    .collection("movimientos_banco")
    .where("estadoConciliacion", "==", "sin_match")
    .where("tipo", "==", "entrada")
    .orderBy("fechaValor", "desc")
    .limit(limit)
    .get();

  let propuestas = 0;
  let omitidos = 0;
  let sinViaje = 0;

  for (const movDoc of movSnap.docs) {
    const mov = movDoc.data() as AnyMap;
    const movId = movDoc.id;
    const refM = String(mov.referenciaNormalizada ?? mov.referenciaBanco ?? "").trim();
    if (!esReferenciaRecaudoValida(normalizarReferenciaExtracto(refM))) {
      omitidos++;
      continue;
    }

    const concId = `prop_${movId}`;
    const concRef = db().collection("conciliaciones").doc(concId);
    const concExisting = await concRef.get();
    if (concExisting.exists) {
      const est = String((concExisting.data() as AnyMap)?.estado ?? "");
      if (est === "propuesta" || est === "confirmada") {
        omitidos++;
        continue;
      }
    }

    const viaje = await buscarViajePorReferenciaRecaudo(refM);
    if (!viaje) {
      sinViaje++;
      continue;
    }

    const v = viaje.data;
    if (!viajeUsaRecaudoRai(v)) {
      omitidos++;
      continue;
    }

    const estadoPago = String(v.estadoPago ?? "").trim().toLowerCase();
    if (estadoPago === "verificado" || v.transferenciaConfirmada === true) {
      omitidos++;
      continue;
    }

    const montoEsperadoCents = precioCentsViaje(v);
    const montoRealCents = Math.trunc(Number(mov.montoCents ?? 0));
    const evalMatch = evaluarMatchConciliacionViaje({
      referenciaMovimiento: refM,
      montoMovimientoCents: montoRealCents,
      referenciaViaje: String(v.referenciaRecaudo ?? refM),
      montoViajeCents: montoEsperadoCents,
    });

    if (!evalMatch.ok) {
      omitidos++;
      continue;
    }

    const now = FieldValue.serverTimestamp();
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

    await movDoc.ref.set(
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

    propuestas++;
  }

  return { ok: true, propuestas, omitidos, sinViaje, escaneados: movSnap.size };
});

async function aplicarConciliacionConfirmadaTx(
  tx: Transaction,
  conciliacionId: string,
  actorUid: string,
  notaAdmin: string,
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
  const viajeId = String(c.viajeId ?? "").trim();
  if (!movId || !viajeId) {
    throw new HttpsError("failed-precondition", "Conciliación incompleta");
  }

  const movRef = db().collection("movimientos_banco").doc(movId);
  const viajeRef = db().collection("viajes").doc(viajeId);
  const movSnap = await tx.get(movRef);
  const viajeSnap = await tx.get(viajeRef);
  if (!movSnap.exists || !viajeSnap.exists) {
    throw new HttpsError("not-found", "Movimiento o viaje no existe");
  }

  const v = (viajeSnap.data() ?? {}) as AnyMap;
  const now = FieldValue.serverTimestamp();
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

  await db().runTransaction(async (tx) => {
    await aplicarConciliacionConfirmadaTx(tx, conciliacionId, actorUid, notaAdmin);
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

    const evalMatch = evaluarMatchConciliacionViaje({
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

    await aplicarConciliacionConfirmadaTx(tx, conciliacionId, actorUid, notaAdmin);
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
