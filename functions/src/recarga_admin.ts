import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { logAdminAudit } from "./audit.js";
import { syncTaxistaBloqueoOperativo } from "./finance.js";
import { ledgerRecargaPrepagoVerificadaCf } from "./taxista_prepago_ledger.js";

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

export const approveRecargaComision = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  await assertAdmin(actorUid);

  const recargaId = typeof request.data?.recargaId === "string" ? request.data.recargaId.trim() : "";
  const notaAdmin = typeof request.data?.notaAdmin === "string" ? request.data.notaAdmin.trim() : "";
  if (!recargaId) throw new HttpsError("invalid-argument", "Falta recargaId");

  const recRef = db().collection("recargas_comision_taxista").doc(recargaId);
  let uidTaxista = "";
  let montoAcreditado = 0;
  let yaEstabaPagada = false;
  let abonoComisionLegacyRd = 0;
  let saldoPrepagoIncrementoRd = 0;

  await db().runTransaction(async (tx) => {
    const recSnap = await tx.get(recRef);
    if (!recSnap.exists) throw new HttpsError("not-found", "Recarga no encontrada");
    const m = (recSnap.data() ?? {}) as AnyMap;
    const estado = String(m.estado ?? "").trim().toLowerCase();
    uidTaxista = String(m.uidTaxista ?? "").trim();
    if (!uidTaxista) throw new HttpsError("failed-precondition", "Recarga sin taxista");

    if (estado === "pagado") {
      // Idempotencia: no re-acreditar; igual forzamos sync de pools/bloqueo al salir (p. ej. doc marcado a mano sin sync).
      yaEstabaPagada = true;
      return;
    }
    if (estado !== "pendiente_verificacion") {
      throw new HttpsError("failed-precondition", "Recarga no está pendiente de verificación");
    }

    const montoRaw = m.montoDeclaradoRd;
    montoAcreditado = typeof montoRaw === "number" ? montoRaw : Number(montoRaw ?? 0);
    if (!Number.isFinite(montoAcreditado) || montoAcreditado <= 0) {
      const altRaw = m.montoElegidoRd;
      const alt = typeof altRaw === "number" ? altRaw : Number(altRaw ?? 0);
      if (Number.isFinite(alt) && alt > 0) {
        montoAcreditado = alt;
      }
    }
    if (!Number.isFinite(montoAcreditado) || montoAcreditado <= 0) {
      throw new HttpsError("failed-precondition", "Monto inválido en solicitud (montoDeclaradoRd / montoElegidoRd)");
    }

    const bRef = db().collection("billeteras_taxista").doc(uidTaxista);
    const bSnap = await tx.get(bRef);
    const bData = (bSnap.data() ?? {}) as AnyMap;
    const saldoAntes = Number(bData.saldoPrepagoComisionRd ?? 0) || 0;
    const pendAntes = Number(bData.comisionPendiente ?? 0) || 0;

    // El depósito verificado por admin primero paga comisión legacy (`comisionPendiente`);
    // lo que sobra acredita a prepago. Sin esto, con legacy ≥ RD$500 el taxista sigue bloqueado
    // aunque el prepago suba (caso captura: prepago alto + legacy 786,77).
    const abonoLegacy = Math.min(Math.max(0, montoAcreditado), Math.max(0, pendAntes));
    const restoPrepago = Math.max(0, Number((montoAcreditado - abonoLegacy).toFixed(2)));
    const pendDespues = Math.max(0, Number((pendAntes - abonoLegacy).toFixed(2)));
    const saldoDespues = Number((saldoAntes + restoPrepago).toFixed(2));
    abonoComisionLegacyRd = abonoLegacy;
    saldoPrepagoIncrementoRd = restoPrepago;

    await ledgerRecargaPrepagoVerificadaCf(tx, {
      uidTaxista,
      recargaId,
      saldoPrepagoAntes: saldoAntes,
      saldoPrepagoDespues: saldoDespues,
      comisionPendienteAntes: pendAntes,
      comisionPendienteDespues: pendDespues,
      montoAcreditadoRd: montoAcreditado,
      referencia: `recarga:${recargaId}`,
    });

    const billePatch: Record<string, unknown> = {
      saldoPrepagoComisionRd: saldoDespues,
      comisionPendiente: pendDespues,
      ultimaRecargaPrepagoComisionEn: FieldValue.serverTimestamp(),
      ultimaRecargaPrepagoComisionMonto: Number(montoAcreditado.toFixed(2)),
      ultimaRecargaPrepagoComisionRef: `recarga:${recargaId}`,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (abonoLegacy + 1e-9 > 0) {
      billePatch.ultimaRecargaAbonoLegacyRd = Number(abonoLegacy.toFixed(2));
      billePatch.ultimaRecargaAbonoLegacyEn = FieldValue.serverTimestamp();
    }

    tx.set(bRef, billePatch, { merge: true });

    tx.update(recRef, {
      estado: "pagado",
      notaAdmin,
      verificadoPor: actorUid,
      verificadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  if (uidTaxista) {
    await syncTaxistaBloqueoOperativo(uidTaxista);
  }

  if (!yaEstabaPagada) {
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
      },
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

  await db().runTransaction(async (tx) => {
    const recSnap = await tx.get(recRef);
    if (!recSnap.exists) throw new HttpsError("not-found", "Recarga no encontrada");
    const m = (recSnap.data() ?? {}) as AnyMap;
    const estado = String(m.estado ?? "").trim().toLowerCase();
    if (estado === "rechazado") return;
    if (estado === "pagado") throw new HttpsError("failed-precondition", "Recarga ya aprobada");
    if (estado !== "pendiente_verificacion") {
      throw new HttpsError("failed-precondition", "Recarga no está pendiente de verificación");
    }
    uidTaxista = String(m.uidTaxista ?? "").trim();
    tx.update(recRef, {
      estado: "rechazado",
      notaAdmin,
      verificadoPor: actorUid,
      verificadoEn: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  if (uidTaxista) {
    await syncTaxistaBloqueoOperativo(uidTaxista);
  }

  logAdminAudit({
    action: "reject_recarga_comision",
    actorUid,
    resourceType: "recarga_comision_taxista",
    resourceId: recargaId,
    metadata: {
      uidTaxista,
      notaAdminLen: notaAdmin.length,
    },
  });

  return { ok: true, recargaId, uidTaxista };
});
