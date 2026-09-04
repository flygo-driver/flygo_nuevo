import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { logAdminAudit } from "./audit.js";
import { syncTaxistaBloqueoOperativo } from "./finance.js";
import { acreditarRecargaPrepagoEnTx } from "./recarga_prepago_credit.js";
import { enviarPushUid } from "./corporativo_notificaciones.js";

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
  const role = await getRole(uid);
  if (role !== "admin") throw new HttpsError("permission-denied", "Solo admin");
}

/** Aviso al chofer; nunca debe tumbar la aprobación/rechazo. */
async function notificarTaxistaRecarga(args: {
  uidTaxista: string;
  recargaId: string;
  aprobada: boolean;
  montoRd?: number;
  notaAdmin?: string;
}): Promise<void> {
  const uid = args.uidTaxista.trim();
  if (!uid) return;
  const monto = Number(args.montoRd ?? 0);
  const titulo = args.aprobada ? "Recarga aprobada" : "Recarga rechazada";
  const cuerpo = args.aprobada
    ? `Se acreditó RD$${monto.toFixed(0)} a tu prepago de comisión. Ya podés seguir operando.`
    : `Tu recarga no fue aprobada. ${args.notaAdmin ?? "Revisá el comprobante y volvé a enviarlo."}`;
  try {
    await enviarPushUid(uid, titulo, cuerpo, {
      tipo: args.aprobada ? "recarga_aprobada" : "recarga_rechazada",
      recargaId: args.recargaId,
    });
  } catch (e) {
    console.error("[notificarTaxistaRecarga]", args.recargaId, e);
  }
}

/**
 * Reconciliar el bloqueo operativo es parte del resultado: si falla, el chofer
 * queda bloqueado con saldo acreditado, así que se registra y se reintenta una vez.
 */
async function reconciliarBloqueoTaxista(uidTaxista: string): Promise<boolean> {
  const uid = uidTaxista.trim();
  if (!uid) return true;
  for (let intento = 0; intento < 2; intento++) {
    try {
      await syncTaxistaBloqueoOperativo(uid);
      return true;
    } catch (e) {
      console.error("[reconciliarBloqueoTaxista]", uid, intento, e);
    }
  }
  return false;
}

export const approveRecargaComision = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  await assertAdmin(actorUid);

  const recargaId = typeof request.data?.recargaId === "string" ? request.data.recargaId.trim() : "";
  const notaAdmin = typeof request.data?.notaAdmin === "string" ? request.data.notaAdmin.trim() : "";
  if (!recargaId) throw new HttpsError("invalid-argument", "Falta recargaId");

  let uidTaxista = "";
  let montoAcreditado = 0;
  let yaEstabaPagada = false;
  let abonoComisionLegacyRd = 0;
  let saldoPrepagoIncrementoRd = 0;

  await db().runTransaction(async (tx) => {
    try {
      const credit = await acreditarRecargaPrepagoEnTx(tx, {
        recargaId,
        actorUid,
        notaAdmin,
        estadosPermitidos: ["pendiente_verificacion"],
        metodoVerificacion: "admin",
      });
      uidTaxista = credit.uidTaxista;
      yaEstabaPagada = credit.yaEstabaPagada;
      montoAcreditado = credit.montoAcreditado;
      abonoComisionLegacyRd = credit.abonoComisionLegacyRd;
      saldoPrepagoIncrementoRd = credit.saldoPrepagoIncrementoRd;
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (msg.includes("no encontrada")) throw new HttpsError("not-found", msg);
      throw new HttpsError("failed-precondition", msg);
    }
  });

  // Aunque sea un reintento: el bloqueo pudo quedar desincronizado antes.
  const bloqueoReconciliado = await reconciliarBloqueoTaxista(uidTaxista);

  // Auditar también los reintentos idempotentes: deja rastro de quién reintentó.
  logAdminAudit({
    action: "approve_recarga_comision",
    actorUid,
    resourceType: "recarga_comision_taxista",
    resourceId: recargaId,
    metadata: {
      uidTaxista,
      montoAcreditadoRd: Number(montoAcreditado.toFixed(2)),
      abonoComisionLegacyRd: Number(abonoComisionLegacyRd.toFixed(2)),
      saldoPrepagoIncrementoRd: Number(saldoPrepagoIncrementoRd.toFixed(2)),
      notaAdminLen: notaAdmin.length,
      reintentoIdempotente: yaEstabaPagada,
      bloqueoReconciliado,
    },
  });

  if (!yaEstabaPagada) {
    await notificarTaxistaRecarga({
      uidTaxista,
      recargaId,
      aprobada: true,
      montoRd: montoAcreditado,
    });
  }

  return {
    ok: true,
    recargaId,
    uidTaxista,
    montoAcreditadoRd: Number(montoAcreditado.toFixed(2)),
    abonoComisionLegacyRd: Number(abonoComisionLegacyRd.toFixed(2)),
    saldoPrepagoIncrementoRd: Number(saldoPrepagoIncrementoRd.toFixed(2)),
    alreadyApproved: yaEstabaPagada,
    bloqueoReconciliado,
  };
});

export const rejectRecargaComision = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  await assertAdmin(actorUid);

  const recargaId = typeof request.data?.recargaId === "string" ? request.data.recargaId.trim() : "";
  const notaAdminRaw = typeof request.data?.notaAdmin === "string" ? request.data.notaAdmin.trim() : "";
  const notaAdmin = notaAdminRaw || "Comprobante no válido";
  if (!recargaId) throw new HttpsError("invalid-argument", "Falta recargaId");

  const recRef = db().collection("recargas_comision_taxista").doc(recargaId);
  let uidTaxista = "";
  let yaEstabaRechazada = false;

  await db().runTransaction(async (tx) => {
    const recSnap = await tx.get(recRef);
    if (!recSnap.exists) throw new HttpsError("not-found", "Recarga no encontrada");
    const m = (recSnap.data() ?? {}) as AnyMap;
    // Se lee siempre: sin uid no se puede reconciliar el bloqueo ni auditar.
    uidTaxista = String(m.uidTaxista ?? "").trim();
    const estado = String(m.estado ?? "").trim().toLowerCase();
    if (estado === "rechazado") {
      yaEstabaRechazada = true;
      return;
    }
    if (estado === "pagado") throw new HttpsError("failed-precondition", "Recarga ya aprobada");
    if (estado !== "pendiente_verificacion") {
      throw new HttpsError("failed-precondition", "Recarga no está pendiente de verificación");
    }
    tx.update(recRef, {
      estado: "rechazado",
      notaAdmin,
      verificadoPor: actorUid,
      verificadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  const bloqueoReconciliado = await reconciliarBloqueoTaxista(uidTaxista);

  logAdminAudit({
    action: "reject_recarga_comision",
    actorUid,
    resourceType: "recarga_comision_taxista",
    resourceId: recargaId,
    metadata: {
      uidTaxista,
      notaAdminLen: notaAdmin.length,
      reintentoIdempotente: yaEstabaRechazada,
      bloqueoReconciliado,
    },
  });

  if (!yaEstabaRechazada) {
    await notificarTaxistaRecarga({
      uidTaxista,
      recargaId,
      aprobada: false,
      notaAdmin,
    });
  }

  return {
    ok: true,
    recargaId,
    uidTaxista,
    alreadyRejected: yaEstabaRechazada,
    bloqueoReconciliado,
  };
});
