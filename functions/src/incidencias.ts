import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { logAdminAudit } from "./audit.js";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

const TIPOS = new Set(["viaje", "usuario", "pago"]);
const ESTADOS = new Set(["abierta", "en_proceso", "resuelta"]);
const PRIORIDADES = new Set(["baja", "media", "alta"]);

function asTrimmed(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function normalizeRole(raw: unknown): string {
  const r = String(raw ?? "").trim().toLowerCase();
  return r === "administrador" ? "admin" : r;
}

async function getRole(uid: string): Promise<string> {
  const uSnap = await db().collection("usuarios").doc(uid).get();
  const rolUsuario = normalizeRole((uSnap.data() as AnyMap | undefined)?.rol);
  if (rolUsuario) return rolUsuario;

  const rSnap = await db().collection("roles").doc(uid).get();
  return normalizeRole((rSnap.data() as AnyMap | undefined)?.rol);
}

async function assertAdmin(uid: string): Promise<void> {
  const role = await getRole(uid);
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Solo administradores");
  }
}

export const createIncidencia = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  await assertAdmin(actorUid);

  const tipo = asTrimmed(request.data?.tipo).toLowerCase();
  const descripcion = asTrimmed(request.data?.descripcion);
  const prioridad = asTrimmed(request.data?.prioridad).toLowerCase();
  const asignadoA = asTrimmed(request.data?.asignadoA) || null;
  const refId = asTrimmed(request.data?.refId) || null;

  if (!TIPOS.has(tipo)) throw new HttpsError("invalid-argument", "tipo invalido");
  if (descripcion.length < 8) {
    throw new HttpsError("invalid-argument", "descripcion demasiado corta");
  }
  if (!PRIORIDADES.has(prioridad)) {
    throw new HttpsError("invalid-argument", "prioridad invalida");
  }

  const doc = await db().collection("incidencias").add({
    tipo,
    descripcion,
    estado: "abierta",
    prioridad,
    creadoPor: actorUid,
    asignadoA,
    resueltoPor: null,
    refId,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    resolvedAt: null,
  });

  logAdminAudit({
    action: "create_incidencia",
    actorUid,
    resourceType: "incidencia",
    resourceId: doc.id,
    metadata: { tipo, prioridad, asignadoA, refId },
  });

  return { ok: true, incidenciaId: doc.id };
});

export const listIncidencias = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  await assertAdmin(actorUid);

  const estado = asTrimmed(request.data?.estado).toLowerCase();
  const prioridad = asTrimmed(request.data?.prioridad).toLowerCase();
  const tipo = asTrimmed(request.data?.tipo).toLowerCase();
  const limitRaw = Number(request.data?.limit ?? 100);
  const limit = Number.isFinite(limitRaw) ? Math.min(Math.max(Math.trunc(limitRaw), 1), 300) : 100;

  let q: FirebaseFirestore.Query<FirebaseFirestore.DocumentData> = db()
    .collection("incidencias")
    .orderBy("createdAt", "desc")
    .limit(limit);

  if (estado && ESTADOS.has(estado)) q = q.where("estado", "==", estado);
  if (prioridad && PRIORIDADES.has(prioridad)) q = q.where("prioridad", "==", prioridad);
  if (tipo && TIPOS.has(tipo)) q = q.where("tipo", "==", tipo);

  const snap = await q.get();
  const items = snap.docs.map((d) => ({ id: d.id, ...(d.data() as AnyMap) }));
  return { ok: true, items };
});

export const assignIncidencia = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  await assertAdmin(actorUid);

  const incidenciaId = asTrimmed(request.data?.incidenciaId);
  const asignadoA = asTrimmed(request.data?.asignadoA);
  if (!incidenciaId) throw new HttpsError("invalid-argument", "Falta incidenciaId");
  if (!asignadoA) throw new HttpsError("invalid-argument", "Falta asignadoA");

  const ref = db().collection("incidencias").doc(incidenciaId);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Incidencia no existe");
    const estado = asTrimmed((snap.data() as AnyMap | undefined)?.estado).toLowerCase();
    tx.update(ref, {
      asignadoA,
      estado: estado === "abierta" ? "en_proceso" : estado || "en_proceso",
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  logAdminAudit({
    action: "assign_incidencia",
    actorUid,
    resourceType: "incidencia",
    resourceId: incidenciaId,
    metadata: { asignadoA },
  });

  return { ok: true, incidenciaId, asignadoA };
});

export const resolveIncidencia = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  await assertAdmin(actorUid);

  const incidenciaId = asTrimmed(request.data?.incidenciaId);
  const notaResolucion = asTrimmed(request.data?.notaResolucion);
  if (!incidenciaId) throw new HttpsError("invalid-argument", "Falta incidenciaId");

  const ref = db().collection("incidencias").doc(incidenciaId);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Incidencia no existe");
    tx.update(ref, {
      estado: "resuelta",
      resueltoPor: actorUid,
      notaResolucion: notaResolucion || null,
      resolvedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  logAdminAudit({
    action: "resolve_incidencia",
    actorUid,
    resourceType: "incidencia",
    resourceId: incidenciaId,
    metadata: { notaResolucionLen: notaResolucion.length },
  });

  return { ok: true, incidenciaId };
});
