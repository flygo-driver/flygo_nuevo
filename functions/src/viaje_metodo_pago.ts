/**
 * Cliente: elige o cambia método de pago durante el viaje (no al programar).
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { getFinanceConfig } from "./finance.js";
import { metodoPagoNormalizadoDesde } from "./liquidacion_semanal_viaje.js";

type AnyMap = Record<string, unknown>;

function metodoLabel(metodoRaw: string): string {
  if (metodoRaw === "efectivo") return "Efectivo";
  if (metodoRaw === "tarjeta") return "Tarjeta";
  return "Transferencia";
}

function metodoEsTarjeta(metodoPago: unknown): boolean {
  const m = String(metodoPago ?? "").toLowerCase();
  return m.includes("tarjeta") || m.includes("card");
}

function viajeTarjetaSinCobrar(d: AnyMap): boolean {
  const ep = String(d.estadoPago ?? "").trim().toLowerCase();
  const paymentObj = (d.payment ?? {}) as AnyMap;
  const ps = String(paymentObj.status ?? "").trim().toLowerCase();
  return ep !== "verificado" && ps !== "captured";
}

function normalizeEstadoViajeDoc(raw: unknown): string {
  const s = String(raw ?? "").trim().toLowerCase().replace(/\s+/g, "_");
  if (s === "encurso" || s === "en_curso" || s === "en_curzo") return "en_curso";
  if (
    s === "a_bordo" ||
    s === "abordo" ||
    s === "a_bordo_pickup" ||
    s === "cliente_a_bordo"
  ) {
    return "a_bordo";
  }
  if (
    s === "en_camino_pickup" ||
    s === "en_camino" ||
    s === "encaminopickup" ||
    s === "encamino_pickup" ||
    s === "encamino"
  ) {
    return "en_camino_pickup";
  }
  if (s === "finalizado" || s === "completado") return "completado";
  if (s === "cancelado" || s === "cancelled") return "cancelado";
  return s;
}

function estadoPermiteCambioMetodoPago(estadoNorm: string, completado: boolean): boolean {
  if (completado || estadoNorm === "completado") return false;
  if (estadoNorm === "cancelado" || estadoNorm === "cancelled") return false;
  return (
    estadoNorm === "aceptado" ||
    estadoNorm === "en_camino_pickup" ||
    estadoNorm === "a_bordo" ||
    estadoNorm === "en_curso"
  );
}

function bolaIdDesdeViajeDoc(v: AnyMap): string {
  if (String(v.tipoServicio ?? "").trim() !== "bola_ahorro") return "";
  return String(v.bolaPuebloId ?? v.bolaId ?? "").trim();
}

export const actualizarMetodoPagoViaje = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  const viajeId = String(request.data?.viajeId ?? "").trim();
  const metodoRaw = String(request.data?.metodoPago ?? "").trim().toLowerCase();
  if (!viajeId) {
    throw new HttpsError("invalid-argument", "Falta viajeId.");
  }
  if (metodoRaw !== "efectivo" && metodoRaw !== "transferencia" && metodoRaw !== "tarjeta") {
    throw new HttpsError("invalid-argument", "Método de pago inválido.");
  }
  if (metodoRaw === "tarjeta") {
    const financeCfg = await getFinanceConfig();
    if (!financeCfg.pagosConTarjetaAzulHabilitados) {
      throw new HttpsError(
        "failed-precondition",
        "El pago con tarjeta no está habilitado en este momento.",
      );
    }
  }

  const db = getFirestore();
  const viajeRef = db.collection("viajes").doc(viajeId);
  const snap = await viajeRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Viaje no encontrado.");
  }
  const d = (snap.data() ?? {}) as AnyMap;

  const uidCliente = String(d.uidCliente ?? d.clienteId ?? "").trim();
  if (uidCliente !== uid) {
    throw new HttpsError("permission-denied", "No autorizado para este viaje.");
  }

  const tipoSrv = String(d.tipoServicio ?? "").trim().toLowerCase();
  if (tipoSrv === "corporativo") {
    throw new HttpsError(
      "failed-precondition",
      "Los viajes corporativos no usan este flujo de pago.",
    );
  }

  const uidTaxista = String(d.uidTaxista ?? d.taxistaId ?? "").trim();
  if (!uidTaxista) {
    throw new HttpsError("failed-precondition", "Aún no hay conductor asignado.");
  }

  const completado = d.completado === true;
  const estadoNorm = normalizeEstadoViajeDoc(d.estado);
  if (!estadoPermiteCambioMetodoPago(estadoNorm, completado)) {
    throw new HttpsError(
      "failed-precondition",
      "Solo podés elegir el pago con el viaje activo.",
    );
  }

  const metodoActual = metodoPagoNormalizadoDesde(d);
  if (metodoActual === metodoRaw) {
    return { ok: true, viajeId, metodoPago: metodoLabel(metodoRaw) };
  }

  if (metodoEsTarjeta(d.metodoPago) && !viajeTarjetaSinCobrar(d)) {
    throw new HttpsError("failed-precondition", "La tarjeta ya fue cobrada.");
  }

  const metodoViaje = metodoLabel(metodoRaw);
  const now = FieldValue.serverTimestamp();

  await db.runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    if (!vSnap.exists) {
      throw new HttpsError("not-found", "Viaje no encontrado.");
    }
    const v = (vSnap.data() ?? {}) as AnyMap;

    const uidCliTx = String(v.uidCliente ?? v.clienteId ?? "").trim();
    if (uidCliTx !== uid) {
      throw new HttpsError("permission-denied", "No autorizado para este viaje.");
    }
    if (metodoEsTarjeta(v.metodoPago) && !viajeTarjetaSinCobrar(v)) {
      throw new HttpsError("failed-precondition", "La tarjeta ya fue cobrada.");
    }

    const patch: AnyMap = {
      metodoPago: metodoViaje,
      metodoPagoNormalizado: metodoRaw,
      metodoPagoUpdatedBy: uid,
      metodoPagoUpdatedAt: now,
      estadoPago: "pendiente",
      updatedAt: now,
      actualizadoEn: now,
    };

    if (metodoRaw !== "transferencia") {
      patch.transferenciaConfirmada = false;
    }

    if (
      metodoEsTarjeta(v.metodoPago) &&
      metodoRaw !== "tarjeta" &&
      viajeTarjetaSinCobrar(v)
    ) {
      patch.metodoPagoAnterior = "tarjeta";
      if (metodoRaw === "efectivo") {
        patch.tarjetaCambioEfectivoEn = now;
      }
      patch["payment.supersededByEfectivo"] = metodoRaw === "efectivo";
      patch["payment.supersededAt"] = now;
      patch["payment.updatedAt"] = now;

      const pagoAzulId = String(v.pagoAzulId ?? `azul_${viajeId}`).trim();
      const pagoRef = db.collection("pagos_azul").doc(pagoAzulId);
      const pSnap = await tx.get(pagoRef);
      if (pSnap.exists) {
        tx.update(pagoRef, {
          estado: "failed",
          supersededByEfectivo: metodoRaw === "efectivo",
          supersededAt: now,
          lastError:
            metodoRaw === "efectivo"
              ? "Cliente cambió a pago en efectivo"
              : "Cliente cambió método de pago",
          updatedAt: now,
        });
      }
    }

    tx.update(viajeRef, patch);

    const bolaId = bolaIdDesdeViajeDoc(v);
    if (bolaId) {
      tx.set(
        db.collection("bolas_pueblo").doc(bolaId),
        {
          metodoPago: metodoRaw,
          metodoPagoUpdatedBy: uid,
          metodoPagoUpdatedAt: now,
          updatedAt: now,
        },
        { merge: true },
      );
    }
  });

  logger.info("[actualizarMetodoPagoViaje] ok", { viajeId, metodoRaw, uid });
  return { ok: true, viajeId, metodoPago: metodoViaje };
});
