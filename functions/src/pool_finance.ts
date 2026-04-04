import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

function roleFromUserDoc(data: AnyMap | undefined): string {
  if (!data) return "";
  const rol = data.rol;
  return typeof rol === "string" ? rol : "";
}

async function getRole(uid: string): Promise<string> {
  const snap = await db().collection("usuarios").doc(uid).get();
  return roleFromUserDoc(snap.data() as AnyMap | undefined);
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

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (snap.data() ?? {}) as AnyMap;

    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");
    ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);

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

    tx.update(poolRef, {
      estado: "en_ruta",
      asientosFirmesSalida: firmSalida,
      iniciadoAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, poolId, alreadyStarted: false };
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

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (snap.data() ?? {}) as AnyMap;

    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");
    ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);

    const estado = String(pool.estado ?? "abierto");
    if (estado === "finalizado") return { ok: true, poolId, alreadyFinalized: true };
    if (estado !== "en_ruta") {
      throw new HttpsError("failed-precondition", "Solo puedes finalizar un viaje en ruta");
    }

    // Comisión sobre dinero efectivamente registrado como pagado; fallback a monto reservado (legacy / datos viejos).
    const montoPagado = Number(pool.montoPagado ?? 0);
    const montoReservado = Number(pool.montoReservado ?? 0);
    const totalGira =
      Number.isFinite(montoPagado) && montoPagado > 0.009
        ? Math.max(0, montoPagado)
        : Number.isFinite(montoReservado)
          ? Math.max(0, montoReservado)
          : 0;
    const comisionPctAplicada = 0.10; // Regla fija de negocio para giras/pools.
    const montoComision = Math.max(0, totalGira * comisionPctAplicada);
    const montoNetoTaxista = Math.max(0, totalGira - montoComision);

    tx.update(poolRef, {
      estado: "finalizado",
      finalizadoAt: FieldValue.serverTimestamp(),
      totalGira,
      comisionPctAplicada,
      montoComision,
      montoNetoTaxista,
      liquidado: true,
      comisionPendientePagoAdmin: true,
      comisionEstado: "pendiente_transferencia_admin",
      comisionMetodoPago: "transferencia",
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, poolId, alreadyFinalized: false };
  });

  await markIdempotencyDone(idem.ref, result);
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

  const poolRef = db().collection("viajes_pool").doc(poolId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(poolRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pool no existe");
    const pool = (snap.data() ?? {}) as AnyMap;

    const ownerTaxistaId = String(pool.ownerTaxistaId ?? "");
    ensurePoolOwnerOrAdmin(role, uidActor, ownerTaxistaId);

    const estado = String(pool.estado ?? "abierto");
    if (estado === "cancelado") return { ok: true, poolId, alreadyCanceled: true };
    if (estado === "finalizado") {
      throw new HttpsError("failed-precondition", "No se puede cancelar un viaje finalizado");
    }

    tx.update(poolRef, {
      estado: "cancelado",
      canceladoAt: FieldValue.serverTimestamp(),
      motivoCancelacion: motivo,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, poolId, alreadyCanceled: false };
  });

  await markIdempotencyDone(idem.ref, result);
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

  const batch = db().batch();
  for (const doc of resSnap.docs) {
    batch.delete(doc.ref);
  }
  batch.delete(poolRef);
  await batch.commit();

  const result = { ok: true, poolId, deletedReservas: resSnap.size };
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

