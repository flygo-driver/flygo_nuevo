import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { logAdminAudit } from "./audit.js";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();
const storage = () => getStorage();

const REPORT_TYPES = new Set(["viajes", "pagos", "comisiones", "bloqueos", "incidencias"]);

function roleFromData(data: AnyMap | undefined): string {
  const raw = String(data?.rol ?? "").trim().toLowerCase();
  return raw === "administrador" ? "admin" : raw;
}

async function getRole(uid: string): Promise<string> {
  const u = await db().collection("usuarios").doc(uid).get();
  const r1 = roleFromData(u.data() as AnyMap | undefined);
  if (r1) return r1;
  const r = await db().collection("roles").doc(uid).get();
  return roleFromData(r.data() as AnyMap | undefined);
}

async function assertAdmin(uid: string): Promise<void> {
  const role = await getRole(uid);
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Solo admin");
  }
}

function parseDate(input: unknown, fallback: Date): Date {
  if (typeof input !== "string") return fallback;
  const d = new Date(input);
  if (Number.isNaN(d.getTime())) return fallback;
  return d;
}

function csvCell(v: unknown): string {
  const raw = String(v ?? "").replace(/"/g, "\"\"");
  return `"${raw}"`;
}

function toIso(v: unknown): string {
  if (v instanceof Timestamp) return v.toDate().toISOString();
  if (v instanceof Date) return v.toISOString();
  if (typeof v === "string") {
    const d = new Date(v);
    if (!Number.isNaN(d.getTime())) return d.toISOString();
  }
  return "";
}

async function reportViajes(fromTs: Timestamp, toTs: Timestamp): Promise<string> {
  const snap = await db()
    .collection("viajes")
    .where("updatedAt", ">=", fromTs)
    .where("updatedAt", "<=", toTs)
    .orderBy("updatedAt", "desc")
    .limit(5000)
    .get();
  const sb = new StringBuilder();
  sb.line("id,estado,uidCliente,uidTaxista,precio,comision,updatedAt");
  for (const d of snap.docs) {
    const m = d.data() as AnyMap;
    sb.line([
      csvCell(d.id),
      csvCell(m.estado),
      csvCell(m.uidCliente ?? m.clienteId),
      csvCell(m.uidTaxista ?? m.taxistaId),
      csvCell(m.precio ?? m.precioFinal),
      csvCell(m.comision),
      csvCell(toIso(m.updatedAt)),
    ].join(","));
  }
  return sb.toString();
}

async function reportPagos(fromTs: Timestamp, toTs: Timestamp): Promise<string> {
  const snap = await db()
    .collection("pagos_taxistas")
    .where("updatedAt", ">=", fromTs)
    .where("updatedAt", "<=", toTs)
    .orderBy("updatedAt", "desc")
    .limit(5000)
    .get();
  const sb = new StringBuilder();
  sb.line("id,uidTaxista,estado,monto,notaAdmin,verificadoPor,updatedAt");
  for (const d of snap.docs) {
    const m = d.data() as AnyMap;
    sb.line([
      csvCell(d.id),
      csvCell(m.uidTaxista),
      csvCell(m.estado),
      csvCell(m.monto ?? m.montoRd ?? m.total),
      csvCell(m.notaAdmin),
      csvCell(m.verificadoPor),
      csvCell(toIso(m.updatedAt)),
    ].join(","));
  }
  return sb.toString();
}

async function reportComisiones(fromTs: Timestamp, toTs: Timestamp): Promise<string> {
  const snap = await db()
    .collection("billeteras_taxista")
    .where("updatedAt", ">=", fromTs)
    .where("updatedAt", "<=", toTs)
    .orderBy("updatedAt", "desc")
    .limit(5000)
    .get();
  const sb = new StringBuilder();
  sb.line("uidTaxista,comisionPendiente,saldoPrepagoComisionRd,primerViajeComisionGratisConsumido,updatedAt");
  for (const d of snap.docs) {
    const m = d.data() as AnyMap;
    sb.line([
      csvCell(d.id),
      csvCell(m.comisionPendiente),
      csvCell(m.saldoPrepagoComisionRd),
      csvCell(m.primerViajeComisionGratisConsumido),
      csvCell(toIso(m.updatedAt)),
    ].join(","));
  }
  return sb.toString();
}

async function reportBloqueos(fromTs: Timestamp, toTs: Timestamp): Promise<string> {
  const snap = await db()
    .collection("usuarios")
    .where("updatedAt", ">=", fromTs)
    .where("updatedAt", "<=", toTs)
    .orderBy("updatedAt", "desc")
    .limit(5000)
    .get();
  const sb = new StringBuilder();
  sb.line("uid,rol,tienePagoPendiente,bloqueado,motivo,updatedAt");
  for (const d of snap.docs) {
    const m = d.data() as AnyMap;
    const tienePagoPendiente = m.tienePagoPendiente === true;
    const bloqueado = m.bloqueado === true || tienePagoPendiente;
    if (!bloqueado) continue;
    sb.line([
      csvCell(d.id),
      csvCell(m.rol),
      csvCell(tienePagoPendiente),
      csvCell(bloqueado),
      csvCell(m.motivoBloqueo ?? "pago/comision"),
      csvCell(toIso(m.updatedAt)),
    ].join(","));
  }
  return sb.toString();
}

async function reportIncidencias(fromTs: Timestamp, toTs: Timestamp): Promise<string> {
  const snap = await db()
    .collection("incidencias")
    .where("createdAt", ">=", fromTs)
    .where("createdAt", "<=", toTs)
    .orderBy("createdAt", "desc")
    .limit(5000)
    .get();
  const sb = new StringBuilder();
  sb.line("id,tipo,estado,prioridad,creadoPor,asignadoA,resueltoPor,createdAt,resolvedAt,refId");
  for (const d of snap.docs) {
    const m = d.data() as AnyMap;
    sb.line([
      csvCell(d.id),
      csvCell(m.tipo),
      csvCell(m.estado),
      csvCell(m.prioridad),
      csvCell(m.creadoPor),
      csvCell(m.asignadoA),
      csvCell(m.resueltoPor),
      csvCell(toIso(m.createdAt)),
      csvCell(toIso(m.resolvedAt)),
      csvCell(m.refId),
    ].join(","));
  }
  return sb.toString();
}

class StringBuilder {
  private parts: string[] = [];
  line(s: string): void {
    this.parts.push(s, "\n");
  }
  toString(): string {
    return this.parts.join("");
  }
}

export const generateAdminReport = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  await assertAdmin(uid);

  const reportType = String(request.data?.reportType ?? "").trim().toLowerCase();
  if (!REPORT_TYPES.has(reportType)) {
    throw new HttpsError("invalid-argument", "reportType invalido");
  }

  const now = new Date();
  const fromDate = parseDate(request.data?.from, new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000));
  const toDate = parseDate(request.data?.to, now);
  if (fromDate.getTime() > toDate.getTime()) {
    throw new HttpsError("invalid-argument", "Rango de fechas invalido");
  }
  const maxRangeMs = 90 * 24 * 60 * 60 * 1000;
  if (toDate.getTime() - fromDate.getTime() > maxRangeMs) {
    throw new HttpsError("invalid-argument", "Rango maximo permitido: 90 dias");
  }

  const fromTs = Timestamp.fromDate(fromDate);
  const toTs = Timestamp.fromDate(toDate);

  let csv = "";
  if (reportType === "viajes") csv = await reportViajes(fromTs, toTs);
  else if (reportType === "pagos") csv = await reportPagos(fromTs, toTs);
  else if (reportType === "comisiones") csv = await reportComisiones(fromTs, toTs);
  else if (reportType === "bloqueos") csv = await reportBloqueos(fromTs, toTs);
  else csv = await reportIncidencias(fromTs, toTs);

  const filePath = `admin_reports/${uid}/${Date.now()}_${reportType}.csv`;
  const bucket = storage().bucket();
  const file = bucket.file(filePath);
  await file.save(csv, {
    resumable: false,
    contentType: "text/csv; charset=utf-8",
    metadata: {
      cacheControl: "private, max-age=0, no-transform",
    },
  });

  const expiresAt = Date.now() + 60 * 60 * 1000;
  const [url] = await file.getSignedUrl({
    action: "read",
    expires: expiresAt,
  });

  logAdminAudit({
    action: "generate_admin_report",
    actorUid: uid,
    resourceType: "admin_report",
    resourceId: filePath,
    metadata: {
      reportType,
      from: fromDate.toISOString(),
      to: toDate.toISOString(),
      expiresAt,
    },
  });

  return {
    ok: true,
    reportType,
    path: filePath,
    downloadUrl: url,
    expiresAt,
  };
});
