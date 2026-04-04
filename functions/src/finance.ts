import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

function toCents(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return Math.round(v * 100);
  return 0;
}

function fromCents(c: number): number {
  return c / 100;
}

function comision20(precioCents: number): number {
  return Math.floor((precioCents * 20 + 50) / 100);
}

function roleFromUserDoc(data: AnyMap | undefined): string {
  if (!data) return "";
  const rol = data.rol;
  return typeof rol === "string" ? rol : "";
}

async function syncTienePagoPendiente(uidTaxista: string): Promise<void> {
  const abiertos = await db()
    .collection("pagos_taxistas")
    .where("uidTaxista", "==", uidTaxista)
    .where("estado", "in", ["pendiente", "vencido", "pendiente_verificacion", "rechazado"])
    .limit(1)
    .get();
  await db().collection("usuarios").doc(uidTaxista).set(
    {
      tienePagoPendiente: !abiertos.empty,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function getRole(uid: string): Promise<string> {
  const snap = await db().collection("usuarios").doc(uid).get();
  return roleFromUserDoc(snap.data() as AnyMap | undefined);
}

async function ensureIdempotencyStart(
  key: string,
  op: string,
  uid: string,
): Promise<{ done: boolean; result?: AnyMap; ref: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData> }> {
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

export const finalizarViajeSeguro = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const viajeIdRaw = request.data?.viajeId;
  const idemRaw = request.data?.idempotencyKey;
  const viajeId = typeof viajeIdRaw === "string" ? viajeIdRaw.trim() : "";
  const idemKey = typeof idemRaw === "string" ? idemRaw.trim() : "";
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const idem = await ensureIdempotencyStart(idemKey, "finalizar_viaje_seguro", uidActor);
  if (idem.done) return idem.result;

  const viajeRef = db().collection("viajes").doc(viajeId);
  const result = await db().runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const d = (vSnap.data() ?? {}) as AnyMap;

    const uidTaxista = String(d.uidTaxista ?? d.taxistaId ?? "");
    const uidCliente = String(d.uidCliente ?? d.clienteId ?? "");
    const estado = String(d.estado ?? "");
    const completado = d.completado === true;
    if (role === "taxista" && uidTaxista !== uidActor) {
      throw new HttpsError("permission-denied", "No autorizado para este viaje");
    }

    if (completado || estado === "completado") {
      return { ok: true, viajeId, alreadyCompleted: true };
    }
    if (estado !== "en_curso") {
      throw new HttpsError("failed-precondition", "El viaje no está en curso");
    }

    const precioCentsDb = typeof d.precio_cents === "number" ? Math.trunc(d.precio_cents) : null;
    const comisionCentsDb = typeof d.comision_cents === "number" ? Math.trunc(d.comision_cents) : null;
    const gananciaCentsDb = typeof d.ganancia_cents === "number" ? Math.trunc(d.ganancia_cents) : null;

    const precioCents = (precioCentsDb !== null && precioCentsDb > 0)
      ? precioCentsDb
      : toCents(d.precioFinal ?? d.precio ?? d.total ?? 0);
    const comisionCents = (comisionCentsDb !== null && comisionCentsDb >= 0)
      ? comisionCentsDb
      : comision20(precioCents);
    const gananciaCents = (gananciaCentsDb !== null && gananciaCentsDb >= 0)
      ? gananciaCentsDb
      : Math.max(0, precioCents - comisionCents);

    const metodo = String(d.metodoPago ?? "").toLowerCase().trim();
    const esEfectivo = metodo.includes("efectivo");
    const metodoAsiento = esEfectivo ? "efectivo" : (metodo.includes("transfer") ? "transferencia" : "tarjeta");
    const pagoRegistrado = d.pagoRegistrado === true;

    if (!pagoRegistrado) {
      tx.update(viajeRef, {
        metodoPago: esEfectivo ? "Efectivo" : (metodo.includes("transfer") ? "Transferencia" : "Tarjeta"),
        "payment.status": esEfectivo ? "cash_collected" : "bank_transfer_received",
        "payment.provider": esEfectivo ? "cash" : "transfer",
        "payment.updatedAt": FieldValue.serverTimestamp(),
        precio_cents: precioCents,
        comision_cents: comisionCents,
        ganancia_cents: gananciaCents,
        precio: fromCents(precioCents),
        total: fromCents(precioCents),
        comision: fromCents(comisionCents),
        comisionFlygo: fromCents(comisionCents),
        gananciaTaxista: fromCents(gananciaCents),
        pagoRegistrado: true,
        liquidado: false,
        pagoDetalle: {
          taxistaId: uidTaxista,
          metodo: metodoAsiento,
          total_cents: precioCents,
          comision_cents: comisionCents,
          ganancia_cents: gananciaCents,
          createdAt: FieldValue.serverTimestamp(),
        },
        "settlement.commission": fromCents(comisionCents),
        "settlement.driverAmount": fromCents(gananciaCents),
        "settlement.status": "pending",
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      });

      const billeRef = db().collection("billeteras_taxista").doc(uidTaxista);
      tx.set(
        billeRef,
        {
          ...(esEfectivo ? { comisionPendiente: FieldValue.increment(fromCents(comisionCents)) } : {}),
          ultimoViajeId: viajeId,
          ultimaComisionCents: comisionCents,
          ultimaGananciaCents: gananciaCents,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      const asientoRef = db().collection("pagos").doc(`viaje_${viajeId}_asiento`);
      const asientoSnap = await tx.get(asientoRef);
      if (!asientoSnap.exists) {
        tx.set(asientoRef, {
          tipo: "taxista",
          viajeId,
          uidTaxista,
          monto: esEfectivo ? -fromCents(comisionCents) : fromCents(gananciaCents),
          metodo: metodoAsiento,
          estado: esEfectivo ? "comision_pendiente" : "por_liquidar",
          fecha: new Date().toISOString(),
          provider: esEfectivo ? "cash" : "transfer",
          createdAt: FieldValue.serverTimestamp(),
        });
      }
    }

    tx.update(viajeRef, {
      estado: "completado",
      completado: true,
      activo: false,
      precio_cents: precioCents,
      comision_cents: comisionCents,
      ganancia_cents: gananciaCents,
      precio: fromCents(precioCents),
      comision: fromCents(comisionCents),
      gananciaTaxista: fromCents(gananciaCents),
      comisionCalculada: true,
      comisionCalculadaEn: FieldValue.serverTimestamp(),
      finalizadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    });

    tx.set(
      db().collection("usuarios").doc(uidTaxista),
      {
        viajeActivoId: "",
        updatedAt: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    if (uidCliente) {
      tx.set(
        db().collection("usuarios").doc(uidCliente),
        {
          viajeActivoId: "",
          updatedAt: FieldValue.serverTimestamp(),
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    return { ok: true, viajeId, alreadyCompleted: false };
  });

  await markIdempotencyDone(idem.ref, result);
  return result;
});

export const approvePayment = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  if ((await getRole(uid)) !== "admin") throw new HttpsError("permission-denied", "Solo admin");

  const pagoId = typeof request.data?.pagoId === "string" ? request.data.pagoId.trim() : "";
  const notaAdmin = typeof request.data?.notaAdmin === "string" ? request.data.notaAdmin.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!pagoId) throw new HttpsError("invalid-argument", "Falta pagoId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "approve_payment", uid);
  if (idem.done) return idem.result;

  const pagoRef = db().collection("pagos_taxistas").doc(pagoId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(pagoRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pago no encontrado");
    const data = (snap.data() ?? {}) as AnyMap;
    const estado = String(data.estado ?? "").trim().toLowerCase();
    const uidTaxista = String(data.uidTaxista ?? "");
    if (!uidTaxista) throw new HttpsError("failed-precondition", "Pago sin uidTaxista");

    if (estado === "pagado") return { ok: true, pagoId, alreadyProcessed: true, estado: "pagado" };
    if (estado === "rechazado") throw new HttpsError("failed-precondition", "Pago ya rechazado");
    if (estado !== "pendiente" && estado !== "pendiente_verificacion") {
      throw new HttpsError("failed-precondition", `Estado no válido: ${estado}`);
    }

    tx.update(pagoRef, {
      estado: "pagado",
      fechaPago: FieldValue.serverTimestamp(),
      verificadoPor: uid,
      verificadoEn: FieldValue.serverTimestamp(),
      notaAdmin,
      updatedAt: FieldValue.serverTimestamp(),
    });

    tx.set(
      db().collection("usuarios").doc(uidTaxista),
      {
        semanaPendiente: null,
        ultimoPago: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return { ok: true, pagoId, alreadyProcessed: false, estado: "pagado" };
  });

  const pagoSnap = await pagoRef.get();
  const uidTaxista = String((pagoSnap.data() ?? {}).uidTaxista ?? "");
  if (uidTaxista) await syncTienePagoPendiente(uidTaxista);
  await markIdempotencyDone(idem.ref, result);
  return result;
});

export const rejectPayment = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  if ((await getRole(uid)) !== "admin") throw new HttpsError("permission-denied", "Solo admin");

  const pagoId = typeof request.data?.pagoId === "string" ? request.data.pagoId.trim() : "";
  const notaAdminRaw = typeof request.data?.notaAdmin === "string" ? request.data.notaAdmin.trim() : "";
  const notaAdmin = notaAdminRaw || "Comprobante no válido";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!pagoId) throw new HttpsError("invalid-argument", "Falta pagoId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "reject_payment", uid);
  if (idem.done) return idem.result;

  const pagoRef = db().collection("pagos_taxistas").doc(pagoId);
  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(pagoRef);
    if (!snap.exists) throw new HttpsError("not-found", "Pago no encontrado");
    const data = (snap.data() ?? {}) as AnyMap;
    const estado = String(data.estado ?? "").trim().toLowerCase();

    if (estado === "rechazado") return { ok: true, pagoId, alreadyProcessed: true, estado: "rechazado" };
    if (estado === "pagado") throw new HttpsError("failed-precondition", "Pago ya aprobado");
    if (estado !== "pendiente" && estado !== "pendiente_verificacion") {
      throw new HttpsError("failed-precondition", `Estado no válido: ${estado}`);
    }

    tx.update(pagoRef, {
      estado: "rechazado",
      notaAdmin,
      verificadoPor: uid,
      verificadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { ok: true, pagoId, alreadyProcessed: false, estado: "rechazado" };
  });

  const pagoSnap = await pagoRef.get();
  const uidTaxista = String((pagoSnap.data() ?? {}).uidTaxista ?? "");
  if (uidTaxista) await syncTienePagoPendiente(uidTaxista);
  await markIdempotencyDone(idem.ref, result);
  return result;
});

export const aceptarViajeSeguro = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const viajeId = typeof request.data?.viajeId === "string" ? request.data.viajeId.trim() : "";
  const nombreTaxista = typeof request.data?.nombreTaxista === "string" ? request.data.nombreTaxista.trim() : "";
  const telefono = typeof request.data?.telefono === "string" ? request.data.telefono.trim() : "";
  const placa = typeof request.data?.placa === "string" ? request.data.placa.trim() : "";
  const tipoVehiculo = typeof request.data?.tipoVehiculo === "string" ? request.data.tipoVehiculo.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "aceptar_viaje_seguro", uidActor);
  if (idem.done) return idem.result;

  const viajeRef = db().collection("viajes").doc(viajeId);
  const userRef = db().collection("usuarios").doc(uidActor);
  const result = await db().runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const d = (vSnap.data() ?? {}) as AnyMap;

    const estado = String(d.estado ?? "");
    const uidTaxistaActual = String(d.uidTaxista ?? "");
    const taxistaIdActual = String(d.taxistaId ?? "");
    const now = new Date();

    const estadoPermitido = estado === "pendiente" || estado === "pendiente_pago" || estado === "pendiente_admin" || estado === "buscando" || estado === "disponible";
    if (!estadoPermitido) throw new HttpsError("failed-precondition", "estado-no-pendiente");

    if (uidTaxistaActual || taxistaIdActual) {
      if (uidTaxistaActual === uidActor || taxistaIdActual === uidActor) {
        return { ok: true, viajeId, alreadyTaken: true };
      }
      throw new HttpsError("failed-precondition", "ya-asignado");
    }

    const acceptAfter = d.acceptAfter;
    if (acceptAfter && typeof (acceptAfter as { toDate?: () => Date }).toDate === "function") {
      const aa = (acceptAfter as { toDate: () => Date }).toDate();
      if (aa > now) throw new HttpsError("failed-precondition", "acceptAfter-futuro");
    }

    const reservadoPor = String(d.reservadoPor ?? "");
    const reservadoHastaRaw = d.reservadoHasta;
    if (reservadoPor && reservadoPor !== uidActor) {
      const reservadoHasta = reservadoHastaRaw && typeof (reservadoHastaRaw as { toDate?: () => Date }).toDate === "function"
        ? (reservadoHastaRaw as { toDate: () => Date }).toDate()
        : null;
      const vigente = !reservadoHasta || reservadoHasta > now;
      if (vigente) throw new HttpsError("failed-precondition", "reservado-otro");
    }

    const uSnap = await tx.get(userRef);
    const uData = (uSnap.data() ?? {}) as AnyMap;
    if (uData.tienePagoPendiente === true) {
      throw new HttpsError("failed-precondition", "bloqueado-pago-semanal");
    }
    const viajeActivoId = String(uData.viajeActivoId ?? "");
    if (viajeActivoId) throw new HttpsError("failed-precondition", "taxista-ocupado");

    const tel = telefono || String(uData.telefono ?? "");
    const placaFinal = placa || String(uData.placa ?? "");
    const tipo = tipoVehiculo || String(uData.tipoVehiculo ?? "");
    const marca = String(uData.marca ?? uData.vehiculoMarca ?? "");
    const modelo = String(uData.modelo ?? uData.vehiculoModelo ?? "");
    const color = String(uData.color ?? uData.vehiculoColor ?? "");

    const tipoServicio = String(d.tipoServicio ?? "normal");
    let tipoVehiculoFormateado = tipo;
    if (tipoServicio === "motor") tipoVehiculoFormateado = "🛵 MOTOR 🛵";
    else if (tipoServicio === "turismo") tipoVehiculoFormateado = "🏝️ TURISMO 🏝️";
    else if (tipoServicio === "normal") tipoVehiculoFormateado = "🚗 NORMAL";

    tx.update(viajeRef, {
      uidTaxista: uidActor,
      taxistaId: uidActor,
      nombreTaxista: nombreTaxista || String(uData.nombre ?? uData.displayName ?? "taxista"),
      telefono: tel,
      placa: placaFinal,
      tipoVehiculo: tipoVehiculoFormateado,
      tipoVehiculoOriginal: tipo,
      marca,
      modelo,
      color,
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

    tx.set(userRef, {
      viajeActivoId: viajeId,
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true, viajeId, alreadyTaken: false };
  });

  await markIdempotencyDone(idem.ref, result as AnyMap);
  return result;
});

export const cancelarViajeTaxistaSeguro = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uidActor = request.auth.uid;
  const role = await getRole(uidActor);
  if (role !== "taxista" && role !== "admin") {
    throw new HttpsError("permission-denied", "Rol no autorizado");
  }

  const viajeId = typeof request.data?.viajeId === "string" ? request.data.viajeId.trim() : "";
  const idemKey = typeof request.data?.idempotencyKey === "string" ? request.data.idempotencyKey.trim() : "";
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");
  if (!idemKey) throw new HttpsError("invalid-argument", "Falta idempotencyKey");

  const idem = await ensureIdempotencyStart(idemKey, "cancelar_viaje_taxista_seguro", uidActor);
  if (idem.done) return idem.result;

  const viajeRef = db().collection("viajes").doc(viajeId);
  const userRef = db().collection("usuarios").doc(uidActor);

  const result = await db().runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
    const d = (vSnap.data() ?? {}) as AnyMap;

    const uidTxRaw = String(d.uidTaxista ?? "");
    const taxistaIdRaw = String(d.taxistaId ?? "");
    const uidTx = uidTxRaw.trim() ? uidTxRaw.trim() : taxistaIdRaw.trim();
    if (role === "taxista" && uidTx !== uidActor) {
      throw new HttpsError("permission-denied", "No autorizado para este viaje");
    }

    const estado = String(d.estado ?? "");
    const cancelable = estado === "aceptado" || estado === "en_camino_pickup" || estado === "enCaminoPickup";
    if (!cancelable) {
      throw new HttpsError("failed-precondition", "No se puede cancelar en este estado");
    }

    tx.update(viajeRef, {
      estado: "pendiente",
      aceptado: false,
      rechazado: false,
      activo: false,
      uidTaxista: "",
      taxistaId: "",
      nombreTaxista: "",
      telefono: "",
      placa: "",
      marca: "",
      modelo: "",
      color: "",
      republicado: true,
      canceladoPor: "taxista",
      canceladoTaxistaEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
      pickupConfirmadoEn: FieldValue.delete(),
      inicioEnRutaEn: FieldValue.delete(),
      finalizadoEn: FieldValue.delete(),
      reservadoPor: "",
      reservadoHasta: null,
    });

    tx.set(userRef, {
      viajeActivoId: "",
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true, viajeId };
  });

  await markIdempotencyDone(idem.ref, result as AnyMap);
  return result;
});

