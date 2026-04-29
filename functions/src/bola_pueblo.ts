import { randomInt } from "crypto";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, getFirestore, type Firestore } from "firebase-admin/firestore";

import { syncTaxistaComisionTrasBola } from "./finance.js";
import { ledgerComisionBolaPuebloCf } from "./taxista_prepago_ledger.js";

const comisionPct = 0.1;

function generarCodigoVerificacion(): string {
  return String(randomInt(1000, 10000));
}

function esRolTaxista(r: string): boolean {
  const x = (r || "").trim().toLowerCase();
  return x === "taxista" || x === "driver";
}

async function rolUsuario(db: Firestore, uid: string): Promise<string> {
  const snap = await db.collection("usuarios").doc(uid).get();
  const r = snap.data()?.rol;
  return typeof r === "string" ? r.trim().toLowerCase() : "";
}

/**
 * Aceptar oferta en Bola Ahorro (servidor).
 * Evita permission-denied del cliente por reglas estrictas de merge/diff en Firestore.
 */
export const aceptarOfertaBola = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  const bolaId = String(request.data?.bolaId ?? "").trim();
  const ofertaId = String(request.data?.ofertaId ?? "").trim();
  if (!bolaId || !ofertaId) {
    throw new HttpsError("invalid-argument", "Faltan bolaId u ofertaId.");
  }

  const db = getFirestore();
  const pubRef = db.collection("bolas_pueblo").doc(bolaId);
  const pubSnap = await pubRef.get();
  if (!pubSnap.exists) {
    throw new HttpsError("not-found", "Publicación no encontrada.");
  }

  const pub = pubSnap.data()!;
  const createdByUid = String(pub.createdByUid ?? "");
  if (createdByUid !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Solo quien publicó puede aceptar una oferta."
    );
  }
  if (pub.estado !== "abierta") {
    throw new HttpsError(
      "failed-precondition",
      "Esta publicación ya no está abierta."
    );
  }

  const ofRef = pubRef.collection("ofertas").doc(ofertaId);
  const ofSnap = await ofRef.get();
  if (!ofSnap.exists) {
    throw new HttpsError("not-found", "Oferta no encontrada.");
  }
  const ofData = ofSnap.data()!;
  const montoAcordado = Number(ofData.montoRd ?? 0);
  if (!(montoAcordado > 0)) {
    throw new HttpsError("invalid-argument", "Monto acordado inválido.");
  }

  const createdByRol = String(pub.createdByRol ?? "").toLowerCase();
  const offerUid = String(ofData.fromUid ?? "");
  const offerRol = String(ofData.fromRol ?? "").toLowerCase();

  let uidTaxista = "";
  let uidCliente = "";
  if (esRolTaxista(createdByRol)) {
    uidTaxista = createdByUid;
    uidCliente = offerUid;
  } else if (esRolTaxista(offerRol)) {
    uidTaxista = offerUid;
    uidCliente = createdByUid;
  }
  if (!uidTaxista || !uidCliente) {
    throw new HttpsError(
      "failed-precondition",
      "No se pudo asignar cliente y conductor. La oferta debe ser de un conductor (rol taxista o driver)."
    );
  }

  const tipoPub = String(pub.tipo ?? "").trim().toLowerCase();
  if (tipoPub === "oferta") {
    if (!esRolTaxista(createdByRol)) {
      throw new HttpsError(
        "failed-precondition",
        "«Voy para» debe ser una publicación de conductor.",
      );
    }
    if (esRolTaxista(offerRol)) {
      throw new HttpsError(
        "failed-precondition",
        "Solo un pasajero puede quedar vinculado a esta ruta.",
      );
    }
  } else if (tipoPub === "pedido") {
    if (esRolTaxista(createdByRol)) {
      throw new HttpsError(
        "failed-precondition",
        "Un pedido Bola debe ser del pasajero.",
      );
    }
    if (!esRolTaxista(offerRol)) {
      throw new HttpsError(
        "failed-precondition",
        "Solo se puede aceptar una oferta de conductor en un pedido.",
      );
    }
  }

  const comision = Number.parseFloat((montoAcordado * comisionPct).toFixed(2));
  const gananciaNeta = Number.parseFloat((montoAcordado - comision).toFixed(2));
  const codigo = generarCodigoVerificacion();

  const ofertasSnap = await pubRef.collection("ofertas").get();
  const batch = db.batch();

  batch.set(
    pubRef,
    {
      estado: "acordada",
      ofertaAceptadaId: ofertaId,
      montoAcordadoRd: Number.parseFloat(montoAcordado.toFixed(2)),
      comisionPct,
      comisionRd: comision,
      gananciaNetaChoferRd: gananciaNeta,
      uidTaxista,
      uidCliente,
      estadoViajeBola: "acordada",
      codigoVerificacionBola: codigo,
      codigoGeneradoEn: FieldValue.serverTimestamp(),
      codigoVerificado: false,
      codigoVerificadoEn: FieldValue.delete(),
      metodoPago: "efectivo",
      metodoPagoUpdatedAt: FieldValue.serverTimestamp(),
      pickupConfirmadoTaxista: false,
      pickupConfirmadoTaxistaEn: FieldValue.delete(),
      acordadaEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  batch.set(
    ofRef,
    { estado: "aceptada", updatedAt: FieldValue.serverTimestamp() },
    { merge: true }
  );

  for (const d of ofertasSnap.docs) {
    if (d.id === ofertaId) continue;
    batch.set(
      d.ref,
      { estado: "rechazada", updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
  }

  await batch.commit();

  // Sincronizar viaje espejo del pool (si existe) creado con [bolaPuebloId].
  const viajesSnap = await db
    .collection("viajes")
    .where("bolaPuebloId", "==", bolaId)
    .limit(8)
    .get();

  if (!viajesSnap.empty) {
    const uSnap = await db.collection("usuarios").doc(uidTaxista).get();
    const ud = uSnap.data() ?? {};
    const nombreTaxista = String(ud.nombre ?? "").trim() || "Conductor";
    const telefonoTx = String(ud.telefono ?? "").trim();
    const placaTx = String(ud.placa ?? "").trim();

    const precioCents = Math.round(montoAcordado * 100);
    const comisionCents = Math.round(comision * 100);
    const gananciaCents = Math.round(gananciaNeta * 100);

    const viajePatch: Record<string, unknown> = {
      bolaNegociacionAbierta: false,
      uidTaxista,
      taxistaId: uidTaxista,
      uidCliente,
      clienteId: uidCliente,
      nombreTaxista,
      telefono: telefonoTx,
      telefonoTaxista: telefonoTx,
      placa: placaTx,
      precio: Number.parseFloat(montoAcordado.toFixed(2)),
      comision: Number.parseFloat(comision.toFixed(2)),
      gananciaTaxista: Number.parseFloat(gananciaNeta.toFixed(2)),
      precio_cents: precioCents,
      comision_cents: comisionCents,
      ganancia_cents: gananciaCents,
      estado: "aceptado",
      aceptado: true,
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    };

    for (const v of viajesSnap.docs) {
      await v.ref.set(viajePatch, { merge: true });
    }
  }

  return { ok: true };
});

/**
 * Conductor acepta la contraoferta del pasajero (pedido): el pasajero publicó un monto distinto al de la oferta del chofer.
 */
export const aceptarContraofertaClienteBola = onCall(async (request) => {
  const uidTaxista = request.auth?.uid;
  if (!uidTaxista) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  const bolaId = String(request.data?.bolaId ?? "").trim();
  const ofertaId = String(request.data?.ofertaId ?? "").trim();
  if (!bolaId || !ofertaId) {
    throw new HttpsError("invalid-argument", "Faltan bolaId u ofertaId.");
  }

  const db = getFirestore();
  const callerRol = await rolUsuario(db, uidTaxista);
  if (!esRolTaxista(callerRol)) {
    throw new HttpsError("permission-denied", "Solo conductores pueden aceptar esta contraoferta.");
  }

  const pubRef = db.collection("bolas_pueblo").doc(bolaId);
  const pubSnap = await pubRef.get();
  if (!pubSnap.exists) {
    throw new HttpsError("not-found", "Publicación no encontrada.");
  }

  const pub = pubSnap.data()!;
  if (String(pub.tipo ?? "") !== "pedido") {
    throw new HttpsError("failed-precondition", "Solo aplica a publicaciones tipo pedido.");
  }
  if (esRolTaxista(String(pub.createdByRol ?? "").toLowerCase())) {
    throw new HttpsError("failed-precondition", "El pedido debe ser del pasajero.");
  }
  if (pub.estado !== "abierta") {
    throw new HttpsError("failed-precondition", "Esta publicación ya no está abierta.");
  }

  const ofRef = pubRef.collection("ofertas").doc(ofertaId);
  const ofSnap = await ofRef.get();
  if (!ofSnap.exists) {
    throw new HttpsError("not-found", "Contraoferta no encontrada.");
  }
  const ofData = ofSnap.data()!;
  if (ofData.esContraofertaCliente !== true) {
    throw new HttpsError("invalid-argument", "Esta fila no es una contraoferta del pasajero.");
  }
  if (String(ofData.contraOfertaParaUid ?? "") !== uidTaxista) {
    throw new HttpsError("permission-denied", "Solo el conductor indicado puede aceptar esta contraoferta.");
  }
  const uidCliente = String(pub.createdByUid ?? "");
  const fromUid = String(ofData.fromUid ?? "");
  if (!uidCliente || fromUid !== uidCliente) {
    throw new HttpsError("failed-precondition", "La contraoferta no coincide con el publicador del pedido.");
  }
  if (String(ofData.estado ?? "") !== "pendiente") {
    throw new HttpsError("failed-precondition", "Esta contraoferta ya fue respondida.");
  }

  const montoAcordado = Number(ofData.montoRd ?? 0);
  if (!(montoAcordado > 0)) {
    throw new HttpsError("invalid-argument", "Monto inválido.");
  }

  const comision = Number.parseFloat((montoAcordado * comisionPct).toFixed(2));
  const gananciaNeta = Number.parseFloat((montoAcordado - comision).toFixed(2));
  const codigo = generarCodigoVerificacion();

  const ofertasSnap = await pubRef.collection("ofertas").get();
  const batch = db.batch();

  batch.set(
    pubRef,
    {
      estado: "acordada",
      ofertaAceptadaId: ofertaId,
      montoAcordadoRd: Number.parseFloat(montoAcordado.toFixed(2)),
      comisionPct,
      comisionRd: comision,
      gananciaNetaChoferRd: gananciaNeta,
      uidTaxista,
      uidCliente,
      estadoViajeBola: "acordada",
      codigoVerificacionBola: codigo,
      codigoGeneradoEn: FieldValue.serverTimestamp(),
      codigoVerificado: false,
      codigoVerificadoEn: FieldValue.delete(),
      metodoPago: "efectivo",
      metodoPagoUpdatedAt: FieldValue.serverTimestamp(),
      pickupConfirmadoTaxista: false,
      pickupConfirmadoTaxistaEn: FieldValue.delete(),
      acordadaEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  batch.set(
    ofRef,
    { estado: "aceptada", updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );

  for (const d of ofertasSnap.docs) {
    if (d.id === ofertaId) continue;
    batch.set(
      d.ref,
      { estado: "rechazada", updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  }

  await batch.commit();

  const viajesSnap = await db
    .collection("viajes")
    .where("bolaPuebloId", "==", bolaId)
    .limit(8)
    .get();

  if (!viajesSnap.empty) {
    const uSnap = await db.collection("usuarios").doc(uidTaxista).get();
    const ud = uSnap.data() ?? {};
    const nombreTaxista = String(ud.nombre ?? "").trim() || "Conductor";
    const telefonoTx = String(ud.telefono ?? "").trim();
    const placaTx = String(ud.placa ?? "").trim();

    const precioCents = Math.round(montoAcordado * 100);
    const comisionCents = Math.round(comision * 100);
    const gananciaCents = Math.round(gananciaNeta * 100);

    const viajePatch: Record<string, unknown> = {
      bolaNegociacionAbierta: false,
      uidTaxista,
      taxistaId: uidTaxista,
      uidCliente,
      clienteId: uidCliente,
      nombreTaxista,
      telefono: telefonoTx,
      telefonoTaxista: telefonoTx,
      placa: placaTx,
      precio: Number.parseFloat(montoAcordado.toFixed(2)),
      comision: Number.parseFloat(comision.toFixed(2)),
      gananciaTaxista: Number.parseFloat(gananciaNeta.toFixed(2)),
      precio_cents: precioCents,
      comision_cents: comisionCents,
      ganancia_cents: gananciaCents,
      estado: "aceptado",
      aceptado: true,
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    };

    for (const v of viajesSnap.docs) {
      await v.ref.set(viajePatch, { merge: true });
    }
  }

  return { ok: true };
});

/**
 * Conductor rechaza la contraoferta del pasajero; la bola sigue abierta.
 */
export const rechazarContraofertaClienteBola = onCall(async (request) => {
  const uidTaxista = request.auth?.uid;
  if (!uidTaxista) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  const bolaId = String(request.data?.bolaId ?? "").trim();
  const ofertaId = String(request.data?.ofertaId ?? "").trim();
  const motivo = String(request.data?.motivo ?? "").trim();
  if (!bolaId || !ofertaId) {
    throw new HttpsError("invalid-argument", "Faltan bolaId u ofertaId.");
  }

  const db = getFirestore();
  const pubRef = db.collection("bolas_pueblo").doc(bolaId);
  const pubSnap = await pubRef.get();
  if (!pubSnap.exists) {
    throw new HttpsError("not-found", "Publicación no encontrada.");
  }
  const pub = pubSnap.data()!;
  if (pub.estado !== "abierta") {
    throw new HttpsError("failed-precondition", "Esta publicación ya no está abierta.");
  }

  const ofRef = pubRef.collection("ofertas").doc(ofertaId);
  const ofSnap = await ofRef.get();
  if (!ofSnap.exists) {
    throw new HttpsError("not-found", "Oferta no encontrada.");
  }
  const ofData = ofSnap.data()!;
  if (ofData.esContraofertaCliente !== true) {
    throw new HttpsError("invalid-argument", "No es una contraoferta del pasajero.");
  }
  if (String(ofData.contraOfertaParaUid ?? "") !== uidTaxista) {
    throw new HttpsError("permission-denied", "No podés rechazar esta contraoferta.");
  }
  if (String(ofData.estado ?? "") !== "pendiente") {
    throw new HttpsError("failed-precondition", "Esta contraoferta ya fue respondida.");
  }

  await ofRef.set(
    {
      estado: "rechazada",
      ...(motivo ? { motivoRechazo: motivo } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { ok: true };
});

/**
 * Cliente o taxista asignados: actualizar forma de pago (evita permission-denied
 * del cliente por diff/merge estricto en reglas de `bolas_pueblo`).
 */
export const actualizarMetodoPagoBola = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }
  const bolaId = String(request.data?.bolaId ?? "").trim();
  const metodoRaw = String(request.data?.metodoPago ?? "").trim().toLowerCase();
  if (!bolaId) {
    throw new HttpsError("invalid-argument", "Falta bolaId.");
  }
  if (metodoRaw !== "efectivo" && metodoRaw !== "transferencia") {
    throw new HttpsError("invalid-argument", "Método de pago inválido.");
  }

  const db = getFirestore();
  const ref = db.collection("bolas_pueblo").doc(bolaId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Publicación no encontrada.");
  }
  const d = snap.data()!;
  const uidTx = String(d.uidTaxista ?? "").trim();
  const uidCli = String(d.uidCliente ?? "").trim();
  const estado = String(d.estado ?? "");

  if (!uidTx || !uidCli) {
    throw new HttpsError("failed-precondition", "Faltan participantes en el acuerdo.");
  }
  if (uid !== uidTx && uid !== uidCli) {
    throw new HttpsError("permission-denied", "Solo el cliente o el conductor asignados.");
  }
  if (estado !== "acordada" && estado !== "en_curso") {
    throw new HttpsError(
      "failed-precondition",
      "Solo se puede cambiar el pago en viaje acordado o en curso.",
    );
  }

  await ref.set(
    {
      metodoPago: metodoRaw,
      metodoPagoUpdatedBy: uid,
      metodoPagoUpdatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { ok: true };
});

/**
 * Confirmación de llegada al destino (cliente o taxista). Solo servidor escribe
 * finalizada + comisionAplicada + billetera (reglas bloquean eso al cliente).
 */
export const finalizarBolaPueblo = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }
  const bolaId = String(request.data?.bolaId ?? "").trim();
  if (!bolaId) {
    throw new HttpsError("invalid-argument", "Falta bolaId.");
  }

  const db = getFirestore();
  const ref = db.collection("bolas_pueblo").doc(bolaId);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      throw new HttpsError("not-found", "Publicación no encontrada.");
    }
    const d = snap.data()!;
    const uidTx = String(d.uidTaxista ?? "").trim();
    const uidCli = String(d.uidCliente ?? "").trim();
    const estado = String(d.estado ?? "");

    if (!uidTx || !uidCli) {
      throw new HttpsError("failed-precondition", "Faltan participantes en el acuerdo.");
    }
    if (uid !== uidTx && uid !== uidCli) {
      throw new HttpsError("permission-denied", "Solo el cliente o el conductor asignados.");
    }
    if (estado !== "en_curso") {
      throw new HttpsError(
        "failed-precondition",
        "Solo se confirma llegada con el traslado en curso.",
      );
    }
    if (d.codigoVerificado !== true) {
      throw new HttpsError(
        "failed-precondition",
        "El inicio del traslado no está verificado.",
      );
    }

    const comision = Number(d.comisionRd ?? 0);
    if (!Number.isFinite(comision) || comision < 0) {
      throw new HttpsError("failed-precondition", "Comisión inválida en la publicación.");
    }

    const metodoPago = String(d.metodoPago ?? "efectivo").toLowerCase().trim();
    const updates: Record<string, unknown> = {
      updatedAt: FieldValue.serverTimestamp(),
      metodoPago: metodoPago === "transferencia" ? "transferencia" : "efectivo",
    };
    if (uid === uidTx) {
      updates.confirmacionTaxistaFinal = true;
      updates.confirmacionTaxistaFinalEn = FieldValue.serverTimestamp();
    }
    if (uid === uidCli) {
      updates.confirmacionClienteFinal = true;
      updates.confirmacionClienteFinalEn = FieldValue.serverTimestamp();
    }

    const taxistaOk = uid === uidTx || d.confirmacionTaxistaFinal === true;
    const clienteOk = uid === uidCli || d.confirmacionClienteFinal === true;

    if (taxistaOk && clienteOk) {
      updates.estado = "finalizada";
      updates.estadoViajeBola = "finalizada";
      updates.finalizadaEn = FieldValue.serverTimestamp();
      if (d.comisionAplicada !== true) {
        const bRef = db.collection("billeteras_taxista").doc(uidTx);
        const bSnap = await tx.get(bRef);
        const b0 = (bSnap.data() ?? {}) as Record<string, unknown>;
        const rawPend = b0.comisionPendiente;
        const pend =
          typeof rawPend === "number" && Number.isFinite(rawPend)
            ? rawPend
            : typeof rawPend === "string"
              ? Number.parseFloat(rawPend) || 0
              : 0;
        const rawSaldo = b0.saldoPrepagoComisionRd;
        let saldo =
          typeof rawSaldo === "number" && Number.isFinite(rawSaldo)
            ? rawSaldo
            : typeof rawSaldo === "string"
              ? Number.parseFloat(rawSaldo) || 0
              : 0;
        const flag = b0.primerViajeComisionGratisConsumido === true;
        const pendAntes = pend;
        const saldoIni = saldo;
        const baseUpd = {
          updatedAt: FieldValue.serverTimestamp(),
          ultimaBolaFinalizadaId: bolaId,
          ultimaComisionBolaRd: comision,
        };
        if (!flag && pend < 1e-6) {
          await ledgerComisionBolaPuebloCf(tx, {
            uidTaxista: uidTx,
            bolaId,
            fuente: "finalizar_bola_pueblo_cf",
            comisionTotalRd: comision,
            pendienteAntes: pendAntes,
            saldoPrepagoAntes: saldoIni,
            pendienteDespues: pendAntes,
            saldoPrepagoDespues: saldoIni,
            primerEfectivoSinDescuento: true,
          });
          tx.set(
            bRef,
            { ...baseUpd, primerViajeComisionGratisConsumido: true },
            { merge: true },
          );
        } else {
          let p = pend;
          const fromPend = Math.min(p, comision);
          p = Number.parseFloat((p - fromPend).toFixed(2));
          const rem = comision - fromPend;
          saldo = Math.max(0, Number.parseFloat((saldo - rem).toFixed(2)));
          await ledgerComisionBolaPuebloCf(tx, {
            uidTaxista: uidTx,
            bolaId,
            fuente: "finalizar_bola_pueblo_cf",
            comisionTotalRd: comision,
            pendienteAntes: pendAntes,
            saldoPrepagoAntes: saldoIni,
            pendienteDespues: p,
            saldoPrepagoDespues: saldo,
            primerEfectivoSinDescuento: false,
          });
          tx.set(
            bRef,
            {
              ...baseUpd,
              comisionPendiente: p,
              saldoPrepagoComisionRd: saldo,
              primerViajeComisionGratisConsumido: true,
            },
            { merge: true },
          );
        }
        updates.comisionAplicada = true;
      }
    }

    tx.set(ref, updates, { merge: true });
  });

  const after = await ref.get();
  const fd = after.data();
  if (fd && String(fd.estado ?? "") === "finalizada") {
    const ut = String(fd.uidTaxista ?? "").trim();
    if (ut) {
      await syncTaxistaComisionTrasBola(ut);
    }
  }

  return { ok: true };
});
