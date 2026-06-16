import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { logAdminAudit } from "./audit.js";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();

const ESTADOS_ACTIVOS = ["aceptado", "asignado", "en_camino_pickup", "en_camino", "a_bordo", "en_curso"];
const ESTADOS_BUSCANDO = ["pendiente", "buscando", "pendiente_pago"];

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
  const role = await getRole(uid);
  if (role !== "admin") throw new HttpsError("permission-denied", "Solo admin");
}

async function sampleViajesDesde(desde: Timestamp, limit = 1200) {
  try {
    return await db()
      .collection("viajes")
      .where("updatedAt", ">=", desde)
      .orderBy("updatedAt", "desc")
      .limit(limit)
      .get();
  } catch {
    const snap = await db()
      .collection("viajes")
      .where("updatedAt", ">=", desde)
      .limit(limit)
      .get();
    return snap;
  }
}

async function countQuery(q: FirebaseFirestore.Query): Promise<number> {
  const agg = await q.count().get();
  return agg.data().count;
}

async function computeLiveMetrics(): Promise<AnyMap> {
  const now = new Date();
  const from24h = Timestamp.fromDate(new Date(now.getTime() - 24 * 60 * 60 * 1000));

  const [
    expedientesEnRevision,
    solicitudesTurismoPendiente,
    liquidacionesPendiente,
    pagosPendiente,
    viajesActivos,
    viajesBuscando,
    bolasAbiertas,
    bolasEnCurso,
    bolasTransferenciaPendiente,
    alertasNoLeidas,
    incidenciasAbiertas,
    reportesViajeAbiertos,
    bloqueosComision,
    recargasPrepagoPendiente,
    viajesCompletados24h,
    viajesCancelados24h,
  ] = await Promise.all([
    countQuery(db().collection("usuarios").where("docsEstado", "==", "en_revision")),
    countQuery(db().collection("solicitudes_turismo").where("estado", "==", "pendiente")),
    countQuery(db().collection("liquidaciones").where("estado", "==", "pendiente")),
    countQuery(db().collection("pagos_taxistas").where("estado", "==", "pendiente")),
    countQuery(db().collection("viajes").where("estado", "in", ESTADOS_ACTIVOS.slice(0, 10))),
    countQuery(db().collection("viajes").where("estado", "in", ESTADOS_BUSCANDO)),
    countQuery(db().collection("bolas_pueblo").where("estado", "==", "abierta")),
    countQuery(db().collection("bolas_pueblo").where("estado", "==", "en_curso")),
    countQuery(
      db()
        .collection("bolas_pueblo")
        .where("estado", "==", "finalizada")
        .where("metodoPago", "==", "transferencia")
        .where("transferenciaConfirmada", "==", false),
    ).catch(() => -1),
    countQuery(db().collection("admin_alertas").where("leida", "==", false)),
    countQuery(db().collection("incidencias").where("estado", "==", "abierta")),
    countQuery(db().collection("reportes_viaje").where("estado", "==", "pendiente")),
    countQuery(db().collection("usuarios").where("tienePagoPendiente", "==", true)),
    countQuery(
      db()
        .collection("recargas_comision_taxista")
        .where("estado", "==", "pendiente_verificacion"),
    ),
    countQuery(
      db()
        .collection("viajes")
        .where("updatedAt", ">=", from24h)
        .where("estado", "in", ["completado", "completed"]),
    ),
    countQuery(
      db()
        .collection("viajes")
        .where("updatedAt", ">=", from24h)
        .where("estado", "in", ["cancelado", "canceled"]),
    ),
  ]);

  return {
    expedientesEnRevision,
    solicitudesTurismoPendiente,
    liquidacionesPendiente,
    pagosPendiente,
    viajesActivos,
    viajesBuscando,
    bolasAbiertas,
    bolasEnCurso,
    bolasTransferenciaPendiente,
    alertasNoLeidas,
    incidenciasAbiertas,
    reportesViajeAbiertos,
    bloqueosComision,
    recargasPrepagoPendiente,
    viajesCompletados24h,
    viajesCancelados24h,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** Actualiza métricas agregadas cada 2 min (1 lectura barata para miles de usuarios). */
export const refreshAdminMetricsLive = onSchedule("every 2 minutes", async () => {
  try {
    const metrics = await computeLiveMetrics();
    await db().collection("admin_metrics").doc("live").set(metrics, { merge: true });
  } catch (e) {
    console.error("[admin_metrics] refresh failed", e);
  }
});

/** Lectura instantánea de métricas agregadas (fallback: recalcula si falta doc). */
export const getAdminCentroMetricas = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const snap = await db().collection("admin_metrics").doc("live").get();
  if (snap.exists) {
    const data = snap.data() ?? {};
    const updatedAt = data.updatedAt;
    return {
      ok: true,
      source: "cache",
      metrics: data,
      updatedAt: updatedAt instanceof Timestamp ? updatedAt.toDate().toISOString() : null,
    };
  }

  const metrics = await computeLiveMetrics();
  await db().collection("admin_metrics").doc("live").set(metrics, { merge: true });
  return { ok: true, source: "computed", metrics };
});

function estadoEsCompletado(raw: unknown): boolean {
  const e = String(raw ?? "").trim().toLowerCase();
  return e === "completado" || e === "completed";
}

function estadoEsCancelado(raw: unknown): boolean {
  const e = String(raw ?? "").trim().toLowerCase();
  return e === "cancelado" || e === "canceled";
}

function estadoEsActivo(raw: unknown): boolean {
  const e = String(raw ?? "").trim().toLowerCase();
  return ESTADOS_ACTIVOS.includes(e);
}

/** Resumen estadístico server-side (evita leer miles de viajes en cliente). */
export const getAdminStatsResumen = onCall(async (request) => {
  try {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
    await assertAdmin(request.auth.uid);

    const dias = Math.min(Math.max(Number(request.data?.dias ?? 7), 1), 90);
    const desde = Timestamp.fromDate(new Date(Date.now() - dias * 24 * 60 * 60 * 1000));

    const safeCount = async (label: string, q: FirebaseFirestore.Query): Promise<number> => {
      try {
        return await countQuery(q);
      } catch (e) {
        console.warn(`[getAdminStatsResumen] count ${label} failed`, e);
        return -1;
      }
    };

    const base = db().collection("viajes").where("updatedAt", ">=", desde);
    let [total, completados, cancelados, activosAhora] = await Promise.all([
      safeCount("total", base),
      safeCount("completados", base.where("estado", "in", ["completado", "completed"])),
      safeCount("cancelados", base.where("estado", "in", ["cancelado", "canceled"])),
      safeCount("activos", db().collection("viajes").where("estado", "in", ESTADOS_ACTIVOS.slice(0, 10))),
    ]);

    if (total < 0 || completados < 0 || cancelados < 0) {
      const snap = await sampleViajesDesde(desde, 1200);
      total = snap.size;
      completados = 0;
      cancelados = 0;
      activosAhora = activosAhora < 0 ? 0 : activosAhora;
      for (const d of snap.docs) {
        const data = d.data() as AnyMap;
        const st = data.estado;
        if (estadoEsCompletado(st)) completados++;
        if (estadoEsCancelado(st)) cancelados++;
        if (estadoEsActivo(st)) activosAhora++;
      }
    }

    if (activosAhora < 0) {
      try {
        activosAhora = await safeCount(
          "activos_retry",
          db().collection("viajes").where("estado", "in", ESTADOS_ACTIVOS.slice(0, 10)),
        );
      } catch {
        activosAhora = 0;
      }
    }

    const tasaCancel = total > 0 ? cancelados / total : 0;

    return {
      ok: true,
      dias,
      total: Math.max(0, total),
      completados: Math.max(0, completados),
      cancelados: Math.max(0, cancelados),
      tasaCancel: Number(tasaCancel.toFixed(4)),
      activosAhora: Math.max(0, activosAhora),
    };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("[getAdminStatsResumen] unhandled", e);
    throw new HttpsError(
      "internal",
      e instanceof Error ? e.message : "Error calculando estadísticas admin",
    );
  }
});

/** Viajes activos paginados para torre de control. */
export const listViajesActivosAdmin = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const limit = Math.min(Math.max(Number(request.data?.limit ?? 50), 1), 100);
  const modo = String(request.data?.modo ?? "activos").trim().toLowerCase();
  const estados = modo === "buscando" ? ESTADOS_BUSCANDO : ESTADOS_ACTIVOS.slice(0, 10);

  let q = db()
    .collection("viajes")
    .where("estado", "in", estados)
    .orderBy("updatedAt", "desc")
    .limit(limit);

  const cursor = String(request.data?.cursor ?? "").trim();
  if (cursor) {
    const cursorSnap = await db().collection("viajes").doc(cursor).get();
    if (cursorSnap.exists) {
      q = q.startAfter(cursorSnap);
    }
  }

  const snap = await q.get();
  const items = snap.docs.map((d) => {
    const data = d.data() as AnyMap;
    return {
      id: d.id,
      estado: data.estado ?? "",
      tipoServicio: data.tipoServicio ?? "",
      uidCliente: data.uidCliente ?? "",
      uidTaxista: data.uidTaxista ?? "",
      origen: data.origen ?? data.origenTexto ?? "",
      destino: data.destino ?? data.destinoTexto ?? "",
      tarifa: data.tarifa ?? data.precio ?? 0,
      updatedAt: data.updatedAt instanceof Timestamp ? data.updatedAt.toDate().toISOString() : null,
    };
  });

  const nextCursor = snap.docs.length === limit ? snap.docs[snap.docs.length - 1].id : null;
  return { ok: true, items, nextCursor, count: items.length };
});

/** Uso RAI asistente (top del día). */
export const listRaiAsistenteUsageAdmin = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const limit = Math.min(Math.max(Number(request.data?.limit ?? 50), 1), 200);
  const today = new Date().toISOString().slice(0, 10);

  const snap = await db()
    .collection("rai_asistente_usage")
    .where("day", "==", today)
    .orderBy("count", "desc")
    .limit(limit)
    .get()
    .catch(async () => {
      // Sin índice compuesto: fallback lectura limitada.
      const all = await db().collection("rai_asistente_usage").limit(500).get();
      return all;
    });

  let docs = snap.docs;
  if (docs.length > 1 && docs[0].data().count === undefined) {
    docs = docs
      .filter((d) => String((d.data() as AnyMap).day ?? "") === today)
      .sort((a, b) => Number((b.data() as AnyMap).count ?? 0) - Number((a.data() as AnyMap).count ?? 0))
      .slice(0, limit);
  }

  const items = await Promise.all(
    docs.map(async (d) => {
      const data = d.data() as AnyMap;
      const uid = d.id;
      let nombre = "";
      try {
        const u = await db().collection("usuarios").doc(uid).get();
        nombre = String((u.data() as AnyMap | undefined)?.nombre ?? "");
      } catch {
        /* ignore */
      }
      return {
        uid,
        nombre,
        count: Number(data.count ?? 0),
        day: String(data.day ?? today),
        limit: 50,
      };
    }),
  );

  const totalCalls = items.reduce((s, i) => s + i.count, 0);
  return { ok: true, day: today, totalCalls, items };
});

/** Auditoría admin paginada (Admin SDK only en backend). */
export const listAdminAudit = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const limit = Math.min(Math.max(Number(request.data?.limit ?? 40), 1), 100);
  let q = db().collection("admin_audit").orderBy("ts", "desc").limit(limit);

  const cursor = String(request.data?.cursor ?? "").trim();
  if (cursor) {
    const c = await db().collection("admin_audit").doc(cursor).get();
    if (c.exists) q = q.startAfter(c);
  }

  const snap = await q.get();
  const items = snap.docs.map((d) => {
    const data = d.data() as AnyMap;
    const ts = data.ts;
    return {
      id: d.id,
      action: data.action ?? "",
      actorUid: data.actorUid ?? "",
      resourceType: data.resourceType ?? "",
      resourceId: data.resourceId ?? "",
      outcome: data.outcome ?? "",
      ts: ts instanceof Timestamp ? ts.toDate().toISOString() : null,
      metadata: data.metadata ?? {},
    };
  });

  const nextCursor = snap.docs.length === limit ? snap.docs[snap.docs.length - 1].id : null;
  return { ok: true, items, nextCursor };
});

/** Marcar alerta como leída. */
export const marcarAdminAlertaLeida = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  await assertAdmin(uid);

  const alertaId = String(request.data?.alertaId ?? "").trim();
  if (!alertaId) throw new HttpsError("invalid-argument", "Falta alertaId");

  const ref = db().collection("admin_alertas").doc(alertaId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Alerta no encontrada");

  await ref.update({
    leida: true,
    leidaEn: FieldValue.serverTimestamp(),
    leidaPor: uid,
  });

  logAdminAudit({
    action: "marcar_alerta_leida",
    actorUid: uid,
    resourceType: "admin_alertas",
    resourceId: alertaId,
  });

  return { ok: true };
});

/** Marcar todas las alertas como leídas. */
export const marcarTodasAdminAlertasLeidas = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  await assertAdmin(uid);

  const snap = await db().collection("admin_alertas").where("leida", "==", false).limit(200).get();
  if (snap.empty) return { ok: true, updated: 0 };

  const batch = db().batch();
  for (const d of snap.docs) {
    batch.update(d.ref, {
      leida: true,
      leidaEn: FieldValue.serverTimestamp(),
      leidaPor: uid,
    });
  }
  await batch.commit();
  return { ok: true, updated: snap.size };
});
