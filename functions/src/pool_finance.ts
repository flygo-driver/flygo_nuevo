import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { logAdminAudit } from "./audit.js";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

function numOr0(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return 0;
}

const MSG_LEGACY_GIRA_SIN_COMISION_ESTIMADA =
  "Esta gira fue creada con una versión anterior del sistema. Por favor, cancélala y crea una nueva.";

function hasComisionGiraEstimadaValida(pool: AnyMap): boolean {
  const raw = pool.comisionGiraEstimadaRd;
  if (typeof raw === "number" && Number.isFinite(raw) && raw > 1e-9) return true;
  if (typeof raw === "string") {
    const n = Number(raw);
    if (Number.isFinite(n) && n > 1e-9) return true;
  }
  return false;
}

function roleFromUserDoc(data: AnyMap | undefined): string {
  if (!data) return "";
  const rol = data.rol;
  return typeof rol === "string" ? rol : "";
}

async function getRole(uid: string): Promise<string> {
  const snap = await db().collection("usuarios").doc(uid).get();
  let rolUsuario = roleFromUserDoc(snap.data() as AnyMap | undefined).trim().toLowerCase();
  if (rolUsuario === "administrador") rolUsuario = "admin";
  if (rolUsuario) return rolUsuario;

  const rolSnap = await db().collection("roles").doc(uid).get();
  const rolRaw = String((rolSnap.data() as AnyMap | undefined)?.rol ?? "").trim().toLowerCase();
  if (rolRaw === "administrador") return "admin";
  return rolRaw;
}

async function ensureIdempotencyStart(
  key: string,
  op: string,
  uid: string,
): Promise<{
  done: boolean;
  result?: AnyMap;
  ref: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
}> {
  const ref = db().collection("idempotency_keys").doc(`${op}_${key}`);
  const snap = await ref.get();
  if (snap.exists) {
    const data = (snap.data() ?? {}) as AnyMap;
    if (data.status === "done" && typeof data.result === "object" && data.result) {
      return { done: true, result: data.result as AnyMap, ref };
    }
  }
  await ref.set(
    {
      op,
      uid,
      status: "started",
      startedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { done: false, ref };
}

async function markIdempotencyDone(
  ref: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>,
  result: AnyMap,
): Promise<void> {
  await ref.set(
    {
      status: "done",
      result,
      doneAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function ensurePoolOwnerOrAdmin(role: string, uidActor: string, ownerTaxistaId: string): void {
  if (role === "admin") return;
  if (role !== "taxista" || ownerTaxistaId !== uidActor) {
    throw new HttpsError("permission-denied", "No autorizado para este pool");
  }
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

async function getComisionGiraPorcientoFromRemote(): Promise<number> {
  try {
    const snap = await db().collection("configuracion_globals").doc("app").get();
    const v = (snap.data() ?? {})["comision_gira_porcentaje"];
    let n = typeof v === "number" && Number.isFinite(v) ? v : 0.1;
    if (n > 0 && n <= 1.001) n *= 100;
    return Math.min(100, Math.max(0, n));
  } catch {
    return 10;
  }
}

function priceMultSentido(sentido: unknown): number {
  return String(sentido ?? "").trim().toLowerCase() === "ida_y_vuelta" ? 2 : 1;
}

function comisionRealRdFromAsientos(
  pool: AnyMap,
  asientosReales: number,
  pct: number,
): number {
  const mult = priceMultSentido(pool.sentido);
  const precio = Number(pool.precioPorAsiento ?? 0);
  if (!Number.isFinite(precio) || precio < 0) return 0;
  if (!Number.isFinite(asientosReales) || asientosReales <= 0) return 0;
  const base = asientosReales * mult * precio;
  return round2(base * (pct / 100));
}

/** Cupos que cuentan para salir: pagados + reservas en efectivo (compromiso al abordar). No cuenta transferencia pendiente de comprobante. */
function firmSeatsFromReservaDocs(
  docs: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>[],
): number {
  let firm = 0;
  for (const d of docs) {
    const r = (d.data() ?? {}) as AnyMap;
    const e = String(r.estado ?? "").toLowerCase().trim();
    const m = String(r.metodoPago ?? "").toLowerCase().trim();
    const s = Number(r.seats ?? 0);
    if (!Number.isFinite(s) || s <= 0) continue;
    if (e === "pagado") firm += s;
    else if (e === "reservado" && m === "efectivo") firm += s;
  }
  return firm;
}

/** Firma después de marcar una reserva como pagada (la reserva sigue en snapshot como reservado hasta el commit). */
function firmSeatsAfterConfirmPayment(
  docs: FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>[],
  confirmedId: string,
): number {
  let firm = 0;
  for (const d of docs) {
    const raw = (d.data() ?? {}) as AnyMap;
    const r = d.id === confirmedId ? { ...raw, estado: "pagado" } : raw;
    const e = String(r.estado ?? "").toLowerCase().trim();
    const m = String(r.metodoPago ?? "").toLowerCase().trim();
    const s = Number(r.seats ?? 0);
    if (!Number.isFinite(s) || s <= 0) continue;
    if (e === "pagado") firm += s;
    else if (e === "reservado" && m === "efectivo") firm += s;
  }
  return firm;
}

/** Registro contable `reserva_comision` al crear gira (solo backend; el cliente ya no escribe en `ledger_giras`). */
export const appendLedgerGiraReserva = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "append_ledger_gira_reserva", uidActor);
  if (idem.done) return idem.result;

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (snap.data() ?? {}) as AnyMap;
    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");
    ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);
    if (!hasComisionGiraEstimadaValida(pool)) {
      throw new HttpsError("failed-precondition", MSG_LEGACY_GIRA_SIN_COMISION_ESTIMADA);
    }
    const etapa = String(pool.prepagoComisionEtapa ?? "").trim().toLowerCase();
    if (etapa !== "reservada_creacion") {
      throw new HttpsError(
        "failed-precondition",
        "La gira no está en etapa de reserva; no se puede registrar el asiento contable.",
      );
    }
    const reserved = round2(Math.max(0, numOr0(pool.comisionGiraEstimadaRd)));
    const led = db().collection("ledger_giras").doc();
    tx.set(led, {
      tipo: "reserva_comision",
      poolId,
      uidTaxista: ownerTaxistaId,
      monto: reserved,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, poolId, monto: reserved };
  });

  await markIdempotencyDone(idem.ref, result as AnyMap);
  logger.info("[PRE_TEST] appendLedgerGiraReserva ok", { uidActor, poolId, result });
  return result;
});

/**
 * Devolución de reserva prepago al marcar pools por pago semanal (misma lógica que el cliente tenía en transacción).
 */
export const refundGiraReservaPagoSemanal = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "refund_gira_reserva_pago_semanal", uidActor);
  if (idem.done) return idem.result;

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const ps = await tx.get(poolRef);
    if (!ps.exists) {
      return { ok: true, poolId, skipped: true, reason: "no_pool" };
    }
    const p = (ps.data() ?? {}) as AnyMap;
    if (p.canceladoPorPagoSemanal !== true) {
      return { ok: true, poolId, skipped: true, reason: "not_pago_semanal_flag" };
    }
    const reserved = Math.max(0, numOr0(p.comisionGiraEstimadaRd));
    const etapa = String(p.prepagoComisionEtapa ?? "").trim().toLowerCase();
    if (reserved <= 1e-9 || etapa !== "reservada_creacion") {
      return { ok: true, poolId, skipped: true, reason: "no_reserva_reembolsable" };
    }
    const owner = String(p.ownerTaxistaId ?? "").trim();
    if (!owner) throw new HttpsError("failed-precondition", "Pool sin dueño");
    ensurePoolOwnerOrAdmin(role, uidActor, owner);

    const billeRef = db().collection("billeteras_taxista").doc(owner);
    const bs = await tx.get(billeRef);
    const bille = (bs.data() ?? {}) as AnyMap;
    const prep = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
    const reserv = Math.max(0, numOr0(bille.saldoReservadoParaGiras));
    if (reserv + 1e-9 < reserved) {
      logger.error("[GIRA_PREPAGO] refund pago semanal reserv insuficiente", { poolId, reserv, reserved });
      throw new HttpsError("failed-precondition", "Saldo reservado inconsistente para devolución por pago semanal.");
    }
    tx.set(
      billeRef,
      {
        saldoPrepagoComisionRd: round2(prep + reserved),
        saldoReservadoParaGiras: round2(reserv - reserved),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.update(poolRef, {
      prepagoComisionEtapa: "devuelta_pago_semanal",
      comisionGiraEstimadaRd: 0,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const led = db().collection("ledger_giras").doc();
    tx.set(led, {
      tipo: "devolucion_reserva",
      poolId,
      uidTaxista: owner,
      monto: reserved,
      motivo: "pago_semanal_cierra_pool",
      createdAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, poolId, comisionDevuelta: reserved, skipped: false };
  });

  await markIdempotencyDone(idem.ref, result as AnyMap);
  logger.info("[PRE_TEST] refundGiraReservaPagoSemanal", { uidActor, poolId, result });
  return result;
});

export const confirmPoolReservationPayment = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const reservaId = typeof request.data?.reservaId === "string" ? request.data.reservaId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!reservaId) throw new HttpsError("invalid-argument", "Falta reservaId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "confirm_pool_reservation_payment", uidActor);
  if (idem.done) return idem.result;

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const resRef = poolRef.collection("reservas").doc(reservaId);

  const result = await db().runTransaction(async (tx) => {
    const poolSnap = await tx.get(poolRef);
    if (!poolSnap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (poolSnap.data() ?? {}) as AnyMap;

    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");
    ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);

    const allResSnap = await tx.get(poolRef.collection("reservas").limit(500));
    const resSnap = await tx.get(resRef);
    if (!resSnap.exists) throw new HttpsError("not-found", "Reserva no encontrada");
    const res = (resSnap.data() ?? {}) as AnyMap;
    const estadoReserva = String(res.estado ?? "");
    if (estadoReserva === "pagado") {
      return { ok: true, poolId, reservaId, alreadyProcessed: true };
    }
    if (estadoReserva !== "reservado") {
      throw new HttpsError("failed-precondition", `Estado de reserva no válido: ${estadoReserva}`);
    }

    const seats = Number(res.seats ?? 0);
    if (!Number.isFinite(seats) || seats <= 0) {
      throw new HttpsError("failed-precondition", "Reserva con seats inválidos");
    }
    const total = Number(res.total ?? 0);
    const pag = Number(pool.asientosPagados ?? 0);
    const minConf = Number(pool.minParaConfirmar ?? 0);
    const estadoPool = String(pool.estado ?? "abierto");
    const firmSalida = firmSeatsAfterConfirmPayment(allResSnap.docs, reservaId);

    tx.update(resRef, {
      estado: "pagado",
      pagadoAt: FieldValue.serverTimestamp(),
      pagadoPor: uidActor,
      updatedAt: FieldValue.serverTimestamp(),
    });

    tx.update(poolRef, {
      asientosPagados: pag + seats,
      montoPagado: Number(pool.montoPagado ?? 0) + (Number.isFinite(total) ? total : 0),
      asientosFirmesSalida: firmSalida,
      ...(((pag + seats) >= minConf && estadoPool !== "confirmado")
        ? { estado: "confirmado" }
        : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return { ok: true, poolId, reservaId, alreadyProcessed: false };
  });

  await markIdempotencyDone(idem.ref, result);
  return result;
});

export const startPoolTrip = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "start_pool_trip", uidActor);
  if (idem.done) return idem.result;

  logger.info("[PRE_TEST] startPoolTrip llamada", { uidActor, poolId });

  const pctRemote = await getComisionGiraPorcientoFromRemote();
  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (snap.data() ?? {}) as AnyMap;

    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");
    ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);

    if (ownerTaxistaId) {
      const ownerRef = db().collection("usuarios").doc(ownerTaxistaId);
      const ownerSnap = await tx.get(ownerRef);
      const ownerData = (ownerSnap.data() ?? {}) as AnyMap;
      if (ownerData.tienePagoPendiente === true) {
        throw new HttpsError("failed-precondition", "Taxista con pago pendiente no puede iniciar pool");
      }
    }

    const estado = String(pool.estado ?? "abierto");
    const reservados = Number(pool.asientosReservados ?? 0);
    const minConf = Number(pool.minParaConfirmar ?? 0);

    const allResSnap = await tx.get(poolRef.collection("reservas").limit(500));
    const firmSalida = firmSeatsFromReservaDocs(allResSnap.docs);

    if (estado === "en_ruta") return { ok: true, poolId, alreadyStarted: true };
    if (estado === "cancelado" || estado === "finalizado") {
      throw new HttpsError("failed-precondition", `No se puede iniciar desde estado ${estado}`);
    }
    if (!Number.isFinite(reservados) || reservados <= 0) {
      throw new HttpsError("failed-precondition", "No hay reservas activas en el anuncio");
    }
    if (!Number.isFinite(firmSalida) || firmSalida <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "No hay cupos firmes para salir: se requiere pago verificado (transferencia) o reserva en efectivo.",
      );
    }
    if (Number.isFinite(minConf) && minConf > 0 && firmSalida < minConf) {
      throw new HttpsError(
        "failed-precondition",
        "No alcanza el mínimo de cupos firmes (pagados o efectivo) para iniciar el viaje.",
      );
    }

    if (!hasComisionGiraEstimadaValida(pool)) {
      logger.warn("[PRE_TEST] startPoolTrip bloqueado sin comisionGiraEstimadaRd válida", {
        poolId,
        uidActor,
      });
      throw new HttpsError("failed-precondition", MSG_LEGACY_GIRA_SIN_COMISION_ESTIMADA);
    }
    const etapa = String(pool.prepagoComisionEtapa ?? "").trim().toLowerCase();
    if (etapa !== "reservada_creacion") {
      logger.warn("[PRE_TEST] startPoolTrip etapa inconsistente", { poolId, uidActor, etapa });
      throw new HttpsError(
        "failed-precondition",
        "Estado de reserva de comisión inconsistente; contactá soporte.",
      );
    }
    if (!ownerTaxistaId) {
      throw new HttpsError("failed-precondition", "Pool sin dueño registrado");
    }

    const cap = Number(pool.capacidad ?? 0);
    const duRaw = pool.asientosConfirmadosPorDueno;
    let duVal = 0;
    if (typeof duRaw === "number" && Number.isFinite(duRaw)) {
      duVal = duRaw;
    } else if (typeof duRaw === "string") {
      const p = Number.parseFloat(String(duRaw).trim());
      if (Number.isFinite(p)) duVal = p;
    }
    const duenoProvided = duVal > 0;

    let asientosReales = firmSalida;
    if (duenoProvided) {
      asientosReales = Math.min(firmSalida, Math.max(1, Math.trunc(duVal)));
    }
    if (Number.isFinite(cap) && cap > 0) {
      asientosReales = Math.min(asientosReales, cap);
    }

    const reserved = round2(Math.max(0, numOr0(pool.comisionGiraEstimadaRd)));
    const pctPool = numOr0(pool.comisionGiraPctUsado);
    const pct = pctPool > 1e-6 ? pctPool : pctRemote;
    const comisionReal = comisionRealRdFromAsientos(pool, asientosReales, pct);

    if (comisionReal - reserved > 1e-6) {
      logger.error("[GIRA_PREPAGO] start comisionReal > reservada", { poolId, comisionReal, reserved });
      throw new HttpsError(
        "failed-precondition",
        "La comisión calculada supera la reserva de prepago; contactá soporte.",
      );
    }
    const excess = round2(reserved - comisionReal);
    const billeRef = db().collection("billeteras_taxista").doc(ownerTaxistaId);
    const billeSnap = await tx.get(billeRef);
    const bille = (billeSnap.data() ?? {}) as AnyMap;
    const prep = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
    const reservWallet = Math.max(0, numOr0(bille.saldoReservadoParaGiras));
    logger.info("[PRE_TEST] startPoolTrip saldos antes", {
      uidActor,
      poolId,
      prepAntes: prep,
      reservWalletAntes: reservWallet,
      reserved,
      comisionReal,
    });
    if (reservWallet + 1e-9 < reserved) {
      logger.error("[GIRA_PREPAGO] start saldoReservado insuficiente", { poolId, reservWallet, reserved });
      throw new HttpsError(
        "failed-precondition",
        "Saldo reservado insuficiente para confirmar la comisión de esta gira.",
      );
    }
    const descAcum = Math.max(0, numOr0(bille.comisionesDescontadas));
    const prepNuevo = round2(prep + excess);
    const reservNuevo = round2(reservWallet - reserved);
    const descNuevo = round2(descAcum + comisionReal);
    tx.set(
      billeRef,
      {
        saldoPrepagoComisionRd: prepNuevo,
        saldoReservadoParaGiras: reservNuevo,
        comisionesDescontadas: descNuevo,
        ultimaComisionGiraPoolId: poolId,
        ultimaComisionGiraRd: comisionReal,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    const led = db().collection("ledger_giras").doc();
    tx.set(led, {
      tipo: "confirmacion_comision_inicio",
      poolId,
      uidTaxista: ownerTaxistaId,
      monto: comisionReal,
      montoDevueltoExceso: excess,
      asientosReales,
      pctUsado: pct,
      createdAt: FieldValue.serverTimestamp(),
    });

    tx.update(poolRef, {
      estado: "en_ruta",
      asientosFirmesSalida: firmSalida,
      asientosRealesComision: asientosReales,
      comisionGiraRealRd: comisionReal,
      comisionGiraExcesoDevueltoRd: excess,
      prepagoComisionEtapa: "confirmada_inicio",
      iniciadoAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    logger.info("[GIRA_PREPAGO] startPoolTrip prepago confirmado", {
      poolId,
      comisionReal,
      excess,
      asientosReales,
    });
    logger.info("[PRE_TEST] startPoolTrip saldos después", {
      uidActor,
      poolId,
      prepDespues: prepNuevo,
      reservWalletDespues: reservNuevo,
    });
    return {
      ok: true,
      poolId,
      alreadyStarted: false,
      comisionReal,
      comisionDevuelta: excess,
      asientosReales,
    };
  });

  await markIdempotencyDone(idem.ref, result);
  return result;
});

export const finalizePoolTrip = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "finalize_pool_trip", uidActor);
  if (idem.done) return idem.result;

  logger.info("[PRE_TEST] finalizePoolTrip llamada", { uidActor, poolId });

  const pctRemote = await getComisionGiraPorcientoFromRemote();
  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (snap.data() ?? {}) as AnyMap;

    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");
    ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);

    const estado = String(pool.estado ?? "abierto");
    if (estado === "finalizado") return { ok: true, poolId, alreadyFinalized: true };

    const etapa = String(pool.prepagoComisionEtapa ?? "").trim().toLowerCase();
    const reserved = Math.max(0, numOr0(pool.comisionGiraEstimadaRd));

    // Caso borde: finalizar sin haber iniciado → misma lógica que cancelación de reserva.
    if (estado !== "en_ruta") {
      if (reserved > 1e-9 && etapa === "reservada_creacion" && ownerTaxistaId) {
        const billeRef = db().collection("billeteras_taxista").doc(ownerTaxistaId);
        const billeSnap = await tx.get(billeRef);
        const bille = (billeSnap.data() ?? {}) as AnyMap;
        const prep = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
        const reservWallet = Math.max(0, numOr0(bille.saldoReservadoParaGiras));
        if (reservWallet + 1e-9 < reserved) {
          throw new HttpsError("failed-precondition", "No se puede devolver reserva: saldo inconsistente");
        }
        tx.set(
          billeRef,
          {
            saldoPrepagoComisionRd: Number((prep + reserved).toFixed(2)),
            saldoReservadoParaGiras: Number((reservWallet - reserved).toFixed(2)),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        const uref = db().collection("usuarios").doc(ownerTaxistaId);
        const us = await tx.get(uref);
        const ud = (us.data() ?? {}) as AnyMap;
        const canceladas = Math.max(0, Math.trunc(numOr0(ud.girasCanceladasAntesDeIniciar))) + 1;
        tx.set(
          uref,
          {
            girasCanceladasAntesDeIniciar: canceladas,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        tx.update(poolRef, {
          estado: "cancelado",
          prepagoComisionEtapa: "devuelta_finalize_sin_inicio",
          comisionGiraEstimadaRd: 0,
          motivoCancelacion: "Finalización sin inicio: devolución automática de reserva",
          canceladoAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        const led = db().collection("ledger_giras").doc();
        tx.set(led, {
          tipo: "devolucion_reserva",
          poolId,
          uidTaxista: ownerTaxistaId,
          monto: reserved,
          motivo: "finalize_sin_inicio",
          createdAt: FieldValue.serverTimestamp(),
        });
        logger.info("[GIRA_PREPAGO] finalizePoolTrip tratado como cancel refund", { poolId, reserved });
        return { ok: true, poolId, refundedAsCancel: true, comisionDevuelta: reserved };
      }
      throw new HttpsError("failed-precondition", "Solo puedes finalizar un viaje en ruta");
    }

    const montoPagado = Number(pool.montoPagado ?? 0);
    const montoReservado = Number(pool.montoReservado ?? 0);
    const totalGira =
      Number.isFinite(montoPagado) && montoPagado > 0.009
        ? Math.max(0, montoPagado)
        : Number.isFinite(montoReservado)
          ? Math.max(0, montoReservado)
          : 0;

    if (etapa === "confirmada_inicio") {
      const comisionYa = Math.max(0, numOr0(pool.comisionGiraRealRd));
      const pctPool = numOr0(pool.comisionGiraPctUsado);
      const pct = pctPool > 1e-6 ? pctPool : pctRemote;
      tx.update(poolRef, {
        estado: "finalizado",
        finalizadoAt: FieldValue.serverTimestamp(),
        totalGira,
        comisionPctAplicada: pct / 100,
        montoComision: 0,
        montoComisionTotal: comisionYa,
        montoComisionCobradaPrepago: comisionYa,
        montoComisionPendienteAdmin: 0,
        montoNetoTaxista: Math.max(0, totalGira - comisionYa),
        liquidado: true,
        comisionPendientePagoAdmin: false,
        comisionEstado: "descontada_prepago_inicio",
        comisionMetodoPago: "prepago",
        updatedAt: FieldValue.serverTimestamp(),
      });
      logger.info("[GIRA_PREPAGO] finalizePoolTrip sin nuevo descuento (prepago en inicio)", { poolId });
      return { ok: true, poolId, alreadyFinalized: false, prepagoEnInicio: true, comisionYaDescontada: comisionYa };
    }

    const comisionPctAplicada = pctRemote / 100;
    const montoComision = Math.max(0, totalGira * comisionPctAplicada);
    const montoNetoTaxista = Math.max(0, totalGira - montoComision);

    let montoComisionCobradaPrepago = 0;
    let montoComisionPendienteAdmin = montoComision;
    if (ownerTaxistaId) {
      const billeRef = db().collection("billeteras_taxista").doc(ownerTaxistaId);
      const billeSnap = await tx.get(billeRef);
      const bille = (billeSnap.data() ?? {}) as AnyMap;
      const saldoAntes = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
      montoComisionCobradaPrepago = Math.min(saldoAntes, montoComision);
      montoComisionPendienteAdmin = Math.max(0, montoComision - montoComisionCobradaPrepago);
      const saldoDespues = Number((saldoAntes - montoComisionCobradaPrepago).toFixed(2));
      tx.set(
        billeRef,
        {
          saldoPrepagoComisionRd: saldoDespues,
          ultimaComisionPoolId: poolId,
          ultimaComisionPoolRd: Number(montoComision.toFixed(2)),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }

    tx.update(poolRef, {
      estado: "finalizado",
      finalizadoAt: FieldValue.serverTimestamp(),
      totalGira,
      comisionPctAplicada,
      montoComision: Number(montoComisionPendienteAdmin.toFixed(2)),
      montoComisionTotal: Number(montoComision.toFixed(2)),
      montoComisionCobradaPrepago: Number(montoComisionCobradaPrepago.toFixed(2)),
      montoComisionPendienteAdmin: Number(montoComisionPendienteAdmin.toFixed(2)),
      montoNetoTaxista,
      liquidado: true,
      comisionPendientePagoAdmin: montoComisionPendienteAdmin > 1e-6,
      comisionEstado:
        montoComisionPendienteAdmin > 1e-6
          ? "pendiente_transferencia_admin"
          : "descontada_prepago",
      comisionMetodoPago:
        montoComisionPendienteAdmin > 1e-6
          ? "transferencia"
          : "prepago",
      updatedAt: FieldValue.serverTimestamp(),
    });
    logger.info("[GIRA_PREPAGO] finalizePoolTrip legacy descuento al finalizar", { poolId });
    return { ok: true, poolId, alreadyFinalized: false, legacy: true };
  });

  await markIdempotencyDone(idem.ref, result);
  logger.info("[PRE_TEST] finalizePoolTrip resultado", { uidActor, poolId, result });
  return result;
});

export const cancelPoolTrip = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const motivo = typeof request.data?.motivo === "string" ? request.data.motivo.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "cancel_pool_trip", uidActor);
  if (idem.done) return idem.result;

  logger.info("[PRE_TEST] cancelPoolTrip llamada", {
    uidActor,
    poolId,
    motivoLen: motivo.length,
  });

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (snap.data() ?? {}) as AnyMap;

    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");
    ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);

    const estado = String(pool.estado ?? "abierto").trim().toLowerCase();
    if (estado === "cancelado" || estado === "cancelado_por_admin") {
      return { ok: true, poolId, alreadyCanceled: true, comisionDevuelta: 0 };
    }
    if (estado === "finalizado") {
      throw new HttpsError("failed-precondition", "No se puede cancelar un viaje finalizado");
    }
    if (estado === "en_ruta") {
      throw new HttpsError("failed-precondition", "No se puede cancelar una gira ya iniciada");
    }

    const reserved = Math.max(0, numOr0(pool.comisionGiraEstimadaRd));
    const etapa = String(pool.prepagoComisionEtapa ?? "").trim().toLowerCase();

    if (reserved > 1e-9 && etapa === "reservada_creacion" && ownerTaxistaId) {
      const billeRef = db().collection("billeteras_taxista").doc(ownerTaxistaId);
      const billeSnap = await tx.get(billeRef);
      const bille = (billeSnap.data() ?? {}) as AnyMap;
      const prep = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
      const reservWallet = Math.max(0, numOr0(bille.saldoReservadoParaGiras));
      logger.info("[PRE_TEST] cancelPoolTrip saldos antes devolución", {
        uidActor,
        poolId,
        prepAntes: prep,
        reservWalletAntes: reservWallet,
        reserved,
      });
      if (reservWallet + 1e-9 < reserved) {
        logger.error("[GIRA_PREPAGO] cancel saldo reservado insuficiente", { poolId, reservWallet, reserved });
        throw new HttpsError("failed-precondition", "Saldo reservado inconsistente; contactá soporte.");
      }
      tx.set(
        billeRef,
        {
          saldoPrepagoComisionRd: Number((prep + reserved).toFixed(2)),
          saldoReservadoParaGiras: Number((reservWallet - reserved).toFixed(2)),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      const uref = db().collection("usuarios").doc(ownerTaxistaId);
      const us = await tx.get(uref);
      const ud = (us.data() ?? {}) as AnyMap;
      const canceladas = Math.max(0, Math.trunc(numOr0(ud.girasCanceladasAntesDeIniciar))) + 1;
      tx.set(
        uref,
        {
          girasCanceladasAntesDeIniciar: canceladas,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      const led = db().collection("ledger_giras").doc();
      tx.set(led, {
        tipo: "devolucion_reserva",
        poolId,
        uidTaxista: ownerTaxistaId,
        monto: reserved,
        motivo: motivo || "cancelacion",
        createdAt: FieldValue.serverTimestamp(),
      });

      tx.update(poolRef, {
        estado: "cancelado",
        prepagoComisionEtapa: "devuelta_cancelacion",
        comisionGiraEstimadaRd: 0,
        canceladoAt: FieldValue.serverTimestamp(),
        motivoCancelacion: motivo,
        updatedAt: FieldValue.serverTimestamp(),
      });
      logger.info("[GIRA_PREPAGO] cancelPoolTrip devolución reserva", { poolId, reserved });
      const prepDespues = Number((prep + reserved).toFixed(2));
      const reservDespues = Number((reservWallet - reserved).toFixed(2));
      logger.info("[PRE_TEST] cancelPoolTrip saldos después devolución", {
        uidActor,
        poolId,
        prepDespues,
        reservWalletDespues: reservDespues,
      });
      return { ok: true, poolId, alreadyCanceled: false, comisionDevuelta: reserved };
    }

    tx.update(poolRef, {
      estado: "cancelado",
      canceladoAt: FieldValue.serverTimestamp(),
      motivoCancelacion: motivo,
      updatedAt: FieldValue.serverTimestamp(),
    });
    logger.info("[GIRA_PREPAGO] cancelPoolTrip sin reserva prepago", { poolId });
    return { ok: true, poolId, alreadyCanceled: false, comisionDevuelta: 0 };
  });

  await markIdempotencyDone(idem.ref, result);
  logger.info("[PRE_TEST] cancelPoolTrip resultado", { uidActor, poolId, result });
  return result;
});

/**
 * Solo administración: anula una gira/excursión ya finalizada (corrección operativa,
 * disputa, error de cierre). Quita la comisión pendiente de validación en panel admin.
 */
export const adminVoidFinalizedPool = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const motivo = typeof request.data?.motivo === "string" ? request.data.motivo.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const roleRaw = await getRole(uidActor);
  const roleNorm = String(roleRaw ?? "").trim().toLowerCase();
  if (roleNorm !== "admin") {
    throw new HttpsError("permission-denied", "Solo administradores pueden anular giras finalizadas");
  }

  const idem = await ensureIdempotencyStart(idemKey, "admin_void_finalized_pool", uidActor);
  if (idem.done) return idem.result;

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (snap.data() ?? {}) as AnyMap;

    const estado = String(pool.estado ?? "abierto");
    const yaAnulada = pool.anuladaTrasFinalizar === true;
    if (estado === "cancelado" && yaAnulada) {
      return { ok: true, poolId, alreadyVoided: true };
    }
    if (estado === "cancelado" && !yaAnulada) {
      throw new HttpsError(
        "failed-precondition",
        "Esta gira está cancelada por flujo normal; no requiere anulación post-finalizado",
      );
    }
    if (estado !== "finalizado") {
      throw new HttpsError(
        "failed-precondition",
        "Solo se puede usar tras finalizar la gira (estado actual: " + estado + ")",
      );
    }

    tx.update(poolRef, {
      estado: "cancelado",
      anuladaTrasFinalizar: true,
      anuladaTrasFinalizarAt: FieldValue.serverTimestamp(),
      anuladaTrasFinalizarPor: uidActor,
      motivoAnulacionAdmin: motivo || "Anulación administrativa tras cierre",
      comisionPendientePagoAdmin: false,
      comisionEstado: "anulada_admin",
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, poolId, alreadyVoided: false };
  });

  await markIdempotencyDone(idem.ref, result);
  logAdminAudit({
    action: "admin_void_finalized_pool",
    actorUid: uidActor,
    resourceType: "viajes_pool",
    resourceId: poolId,
    metadata: {
      motivoLen: motivo.length,
      result: result as AnyMap,
    },
  });
  return result;
});

/**
 * Borra el documento del pool y sus reservas (solo si no hay compromisos activos).
 * Evita “basura” en Firestore cuando el operador cancela un anuncio sin cupos vendidos.
 */
export const deletePoolForOwner = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "delete_pool_for_owner", uidActor);
  if (idem.done) return idem.result;

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const poolSnap = await poolRef.get();
  if (!poolSnap.exists) {
    const r = { ok: true, poolId, alreadyDeleted: true };
    await markIdempotencyDone(idem.ref, r);
    return r;
  }

  const pool = (poolSnap.data() ?? {}) as AnyMap;
  const ownerTaxistaId = String(pool.ownerTaxistaId ?? "").trim();
  ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);

  const estado = String(pool.estado ?? "").trim().toLowerCase();
  if (estado === "en_ruta" || estado === "finalizado") {
    throw new HttpsError(
      "failed-precondition",
      "No se puede borrar un viaje en curso o ya finalizado",
    );
  }

  const occ = Number(pool.asientosReservados ?? 0);
  const pag = Number(pool.asientosPagados ?? 0);
  const montoPag = Number(pool.montoPagado ?? 0);
  const montoRes = Number(pool.montoReservado ?? 0);
  if (!Number.isFinite(occ) || !Number.isFinite(pag)) {
    throw new HttpsError("failed-precondition", "Datos del pool inconsistentes");
  }
  if (occ > 0 || pag > 0 || montoPag > 0.009 || montoRes > 0.009) {
    throw new HttpsError(
      "failed-precondition",
      "No se puede borrar: hay reservas o montos registrados. Cancelá reservas o usá “Limpiar vencidas”.",
    );
  }

  const resSnap = await poolRef.collection("reservas").get();
  for (const doc of resSnap.docs) {
    const e = String(doc.data()?.estado ?? "").trim().toLowerCase();
    if (e === "pagado" || e === "reservado") {
      throw new HttpsError(
        "failed-precondition",
        "Hay reservas activas en este anuncio; no se puede borrar todavía.",
      );
    }
  }

  if (resSnap.size > 400) {
    throw new HttpsError("resource-exhausted", "Demasiadas reservas; contactá soporte.");
  }

  const reserved = Math.max(0, numOr0(pool.comisionGiraEstimadaRd));
  const etapa = String(pool.prepagoComisionEtapa ?? "").trim().toLowerCase();

  await db().runTransaction(async (tx) => {
    const pSnap = await tx.get(poolRef);
    if (!pSnap.exists) return;
    const p = (pSnap.data() ?? {}) as AnyMap;
    const res2 = Math.max(0, numOr0(p.comisionGiraEstimadaRd));
    const et2 = String(p.prepagoComisionEtapa ?? "").trim().toLowerCase();
    if (res2 > 1e-9 && et2 === "reservada_creacion" && ownerTaxistaId) {
      const billeRef = db().collection("billeteras_taxista").doc(ownerTaxistaId);
      const billeSnap = await tx.get(billeRef);
      const bille = (billeSnap.data() ?? {}) as AnyMap;
      const prep = Math.max(0, numOr0(bille.saldoPrepagoComisionRd));
      const reservWallet = Math.max(0, numOr0(bille.saldoReservadoParaGiras));
      if (reservWallet + 1e-9 >= res2) {
        tx.set(
          billeRef,
          {
            saldoPrepagoComisionRd: Number((prep + res2).toFixed(2)),
            saldoReservadoParaGiras: Number((reservWallet - res2).toFixed(2)),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        const led = db().collection("ledger_giras").doc();
        tx.set(led, {
          tipo: "devolucion_reserva",
          poolId,
          uidTaxista: ownerTaxistaId,
          monto: res2,
          motivo: "delete_pool_owner",
          createdAt: FieldValue.serverTimestamp(),
        });
      }
    }
    for (const doc of resSnap.docs) {
      tx.delete(doc.ref);
    }
    tx.delete(poolRef);
  });

  const result = { ok: true, poolId, deletedReservas: resSnap.size, comisionDevuelta: reserved };
  await markIdempotencyDone(idem.ref, result);
  return result;
});

export const reservePoolSeats = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidCliente = request.auth.uid;

  const poolId = typeof request.data?.poolId === "string" ? request.data.poolId.trim() : "";
  const metodoPago = typeof request.data?.metodoPago === "string"
    ? request.data.metodoPago.trim().toLowerCase()
    : "";
  const seatsRaw = Number(request.data?.seats ?? 0);
  const seats = Number.isFinite(seatsRaw) ? Math.trunc(seatsRaw) : 0;
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";

  if (!poolId) throw new HttpsError("invalid-argument", "Falta poolId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");
  if (seats <= 0) throw new HttpsError("invalid-argument", "Asientos inválidos");
  if (metodoPago !== "transferencia" && metodoPago !== "efectivo") {
    throw new HttpsError("invalid-argument", "Método de pago inválido");
  }

  const idem = await ensureIdempotencyStart(idemKey, "reserve_pool_seats", uidCliente);
  if (idem.done) return idem.result;

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const poolSnap = await tx.get(poolRef);
    if (!poolSnap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (poolSnap.data() ?? {}) as AnyMap;

    const allResSnap = await tx.get(poolRef.collection("reservas").limit(500));

    const estado = String(pool.estado ?? "").trim().toLowerCase();
    const permitido = ["abierto", "preconfirmado", "confirmado", "activo", "disponible", "buscando"];
    if (!permitido.includes(estado)) {
      throw new HttpsError("failed-precondition", "Este viaje no admite nuevas reservas");
    }

    // Refuerzo por pagos semanales:
    // Si el dueño del pool (taxista) tiene una comisión semanal pendiente,
    // rechazamos la reserva aunque el pool esté en estado "abierto".
    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "").trim();
    if (ownerTaxistaId) {
      const ownerRef = db().collection("usuarios").doc(ownerTaxistaId);
      const ownerSnap = await tx.get(ownerRef);
      const ownerData = (ownerSnap.data() ?? {}) as AnyMap;
      const tienePagoPendiente = ownerData.tienePagoPendiente === true;
      if (tienePagoPendiente) {
        throw new HttpsError(
          "failed-precondition",
          "El taxista del viaje tiene pago semanal pendiente. No se puede reservar hasta que se verifique el pago."
        );
      }
    }

    const cap = Number(pool.capacidad ?? 0);
    const occ = Number(pool.asientosReservados ?? 0);
    if (!Number.isFinite(cap) || cap <= 0) {
      throw new HttpsError("failed-precondition", "Capacidad inválida del viaje");
    }
    if (!Number.isFinite(occ) || occ < 0) {
      throw new HttpsError("failed-precondition", "Ocupación inválida del viaje");
    }
    if (occ + seats > cap) throw new HttpsError("failed-precondition", "No hay suficientes cupos");

    const precio = Number(pool.precioPorAsiento ?? 0);
    const mult = String(pool.sentido ?? "") === "ida_y_vuelta" ? 2 : 1;
    const depositPctRaw = Number(pool.depositPct ?? 0);
    const depositPct = Number.isFinite(depositPctRaw)
      ? Math.min(1, Math.max(0, depositPctRaw))
      : 0;
    const total = Math.max(0, precio * seats * mult);
    const deposit = Math.max(0, total * depositPct);
    const expiresAt = new Date(Date.now() + 2 * 60 * 60 * 1000); // 2 horas

    let firmSalida = firmSeatsFromReservaDocs(allResSnap.docs);
    if (metodoPago === "efectivo") firmSalida += seats;

    // Snapshot de contacto del cliente para el dueño del viaje
    const userRef = db().collection("usuarios").doc(uidCliente);
    const userSnap = await tx.get(userRef);
    const ud = (userSnap.data() ?? {}) as AnyMap;
    const clienteNombre = String(ud.nombre ?? "");
    const clienteTelefono = String(ud.telefono ?? "");
    const clienteWhatsApp = String(ud.whatsapp ?? ud.telefono ?? "");
    const clienteEmail = String(ud.email ?? request.auth?.token?.email ?? "");

    const resRef = poolRef.collection("reservas").doc();
    tx.set(resRef, {
      uidCliente,
      seats,
      estado: "reservado",
      metodoPago,
      total,
      deposit,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt,
      clienteNombre,
      clienteTelefono,
      clienteWhatsApp,
      clienteEmail,
    });

    const nuevoOcc = occ + seats;
    const minConf = Number(pool.minParaConfirmar ?? 0);
    const next: AnyMap = {
      asientosReservados: nuevoOcc,
      montoReservado: Number(pool.montoReservado ?? 0) + total,
      asientosFirmesSalida: firmSalida,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (nuevoOcc >= cap) next.estado = "lleno";
    else if (Number.isFinite(minConf) && minConf > 0 && nuevoOcc >= minConf && estado === "abierto") {
      next.estado = "preconfirmado";
    }
    tx.update(poolRef, next);

    return { ok: true, poolId, reservaId: resRef.id };
  });

  await markIdempotencyDone(idem.ref, result);
  return result;
});

