/**
 * Fase 3 — movimientos_banco (extracto Popular) + asignación server-side de referenciaRecaudo.
 */
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { getFinanceConfig } from "./finance.js";
import {
  extraerBancoTransaccionIdDeFila,
  movimientoBancoDocIdHash,
  resolveMovimientoBancoDocId,
} from "./banco_movimiento_id.js";
import { asignarReferenciaRecaudoUnicaEnViaje } from "./referencia_recaudo_registry.js";
import { asignarQrRecaudoEnViaje } from "./recaudo_qr.js";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();

const RAI_V_PATTERN = /RAI-V-[A-Z0-9]{1,8}-[0-9A-F]{2}/;

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
  if ((await getRole(uid)) !== "admin") {
    throw new HttpsError("permission-denied", "Solo admin");
  }
}

/** Normaliza texto de extracto; extrae RAI-V-… si está embebido en descripción. */
export function normalizarReferenciaExtracto(raw: unknown): string {
  const text = String(raw ?? "").trim().toUpperCase();
  if (!text) return "";
  const compact = text.replace(/\s+/g, "");
  const m = compact.match(RAI_V_PATTERN);
  if (m) return m[0];
  return compact.slice(0, 64);
}

export function montoCentsDesdeExtracto(raw: unknown): number {
  if (typeof raw === "number" && Number.isFinite(raw)) {
    return Math.round(Math.abs(raw) * 100);
  }
  let s = String(raw ?? "")
    .trim()
    .replace(/[^\d.,-]/g, "");
  if (!s) return 0;

  const lastComma = s.lastIndexOf(",");
  const lastDot = s.lastIndexOf(".");
  if (lastComma > lastDot) {
    s = s.replace(/\./g, "").replace(",", ".");
  } else if (lastDot > lastComma) {
    s = s.replace(/,/g, "");
  } else {
    s = s.replace(/,/g, "");
  }

  const n = Number.parseFloat(s);
  if (!Number.isFinite(n)) return 0;
  return Math.round(Math.abs(n) * 100);
}

export function parseFechaExtracto(raw: unknown): Date | null {
  if (raw instanceof Timestamp) return raw.toDate();
  if (raw instanceof Date && !Number.isNaN(raw.getTime())) return raw;
  const s = String(raw ?? "").trim();
  if (!s) return null;
  const iso = Date.parse(s);
  if (!Number.isNaN(iso)) return new Date(iso);
  const dmY = s.match(/^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})/);
  if (dmY) {
    const dd = Number.parseInt(dmY[1], 10);
    const mm = Number.parseInt(dmY[2], 10);
    let yy = Number.parseInt(dmY[3], 10);
    if (yy < 100) yy += 2000;
    const d = new Date(Date.UTC(yy, mm - 1, dd));
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

/** @deprecated Preferir resolveMovimientoBancoDocId */
export function movimientoBancoDocId(input: {
  fechaValor: Date;
  referenciaNormalizada: string;
  montoCents: number;
  tipo: string;
}): string {
  return movimientoBancoDocIdHash(input);
}

export { resolveMovimientoBancoDocId, extraerBancoTransaccionIdDeFila } from "./banco_movimiento_id.js";

export type FilaExtractoPopular = {
  fecha?: unknown;
  monto?: unknown;
  referencia?: unknown;
  descripcion?: unknown;
  bancoTransaccionId?: unknown;
};

function filaDesdeMap(row: AnyMap): FilaExtractoPopular {
  const pick = (...keys: string[]) => {
    for (const k of keys) {
      if (row[k] !== undefined && row[k] !== null && String(row[k]).trim() !== "") {
        return row[k];
      }
    }
    return undefined;
  };
  return {
    fecha: pick("fecha", "fechaValor", "date", "fecha_valor"),
    monto: pick("monto", "montoRd", "amount", "valor", "credito", "debito"),
    referencia: pick("referencia", "referenciaBanco", "referenciaRecaudo", "ref"),
    descripcion: pick("descripcion", "concepto", "detalle", "memo"),
    bancoTransaccionId: pick(
      "bancoTransaccionId",
      "bancotransaccionid",
      "transaccionId",
      "transaccion_id",
      "idTransaccion",
      "txnId",
      "txn_id",
      "id_movimiento",
      "numeroReferencia",
      "referenciaUnica",
    ),
  };
}

function parseCsvLine(line: string, sep: string): string[] {
  return line.split(sep).map((c) => c.trim().replace(/^"|"$/g, ""));
}

/** CSV flexible: primera fila = encabezados. */
export function parseCsvExtractoPopular(csv: string): FilaExtractoPopular[] {
  const lines = csv
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0);
  if (lines.length < 2) return [];

  const sep = lines[0].includes(";") ? ";" : ",";
  const headers = parseCsvLine(lines[0], sep).map((h) => h.toLowerCase());
  const out: FilaExtractoPopular[] = [];

  for (let i = 1; i < lines.length; i++) {
    const cols = parseCsvLine(lines[i], sep);
    const row: AnyMap = {};
    for (let c = 0; c < headers.length && c < cols.length; c++) {
      row[headers[c]] = cols[c];
    }
    out.push(filaDesdeMap(row));
  }
  return out;
}

function esMetodoTransferencia(metodoPago: unknown): boolean {
  const m = String(metodoPago ?? "").toLowerCase();
  return m.includes("transfer");
}

/**
 * Al crear viaje transferencia (flag ON), asigna referenciaRecaudo solo desde servidor.
 */
export const onViajeCreatedAsignarReferenciaRecaudo = onDocumentCreated(
  "viajes/{viajeId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const viajeId = String(event.params.viajeId ?? "").trim();
    if (!viajeId) return;

    const d = snap.data() as AnyMap;
    if (String(d.referenciaRecaudo ?? "").trim()) return;
    if (!esMetodoTransferencia(d.metodoPago)) return;

    const cfg = await getFinanceConfig();
    if (!cfg.transferenciaRecaudoEnCuentaRai) return;

    const referenciaRecaudo = await asignarReferenciaRecaudoUnicaEnViaje(snap.ref, viajeId);
    await asignarQrRecaudoEnViaje(snap.ref, viajeId, d, referenciaRecaudo);
    logger.info("[onViajeCreatedAsignarReferenciaRecaudo] ok", { viajeId, referenciaRecaudo });
  },
);

/** Admin: importa extracto Popular (JSON filas o CSV) → movimientos_banco (idempotente). */
export const importarExtractoPopular = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const actorUid = request.auth.uid;
  await assertAdmin(actorUid);

  const importVersion =
    typeof request.data?.importVersion === "string"
      ? request.data.importVersion.trim()
      : "popular_csv_v1";
  const cuentaRai =
    typeof request.data?.cuentaRaiUltimos4 === "string"
      ? request.data.cuentaRaiUltimos4.trim()
      : "";

  let filas: FilaExtractoPopular[] = [];
  if (Array.isArray(request.data?.filas)) {
    filas = (request.data.filas as AnyMap[]).map((r) => filaDesdeMap(r));
  } else if (typeof request.data?.csv === "string" && request.data.csv.trim()) {
    filas = parseCsvExtractoPopular(request.data.csv);
  } else {
    throw new HttpsError("invalid-argument", "Enviá filas (array) o csv (string)");
  }

  if (filas.length === 0) {
    throw new HttpsError("invalid-argument", "Extracto vacío o CSV inválido");
  }
  if (filas.length > 500) {
    throw new HttpsError("invalid-argument", "Máximo 500 filas por importación");
  }

  const batchRef = db().collection("import_batches_banco").doc();
  const importBatchId = batchRef.id;
  const now = FieldValue.serverTimestamp();

  let creados = 0;
  let omitidos = 0;
  let invalidos = 0;

  const writer = db().bulkWriter();
  writer.onWriteError((err) => {
    if (err.failedAttempts < 3) return true;
    logger.error("[importarExtractoPopular] write error", err);
    return false;
  });

  for (const fila of filas) {
    const montoCents = montoCentsDesdeExtracto(fila.monto);
    if (montoCents <= 0) {
      invalidos++;
      continue;
    }
    const fechaValor = parseFechaExtracto(fila.fecha) ?? new Date();
    const refRaw = String(fila.referencia ?? "").trim();
    const descRaw = String(fila.descripcion ?? "").trim();
    const referenciaNormalizada = normalizarReferenciaExtracto(
      refRaw || descRaw,
    );
    const referenciaBanco = refRaw || descRaw || referenciaNormalizada;
    const bancoTransaccionId = extraerBancoTransaccionIdDeFila(fila as AnyMap);

    const resolved = resolveMovimientoBancoDocId({
      bancoTransaccionId,
      fechaValor,
      referenciaNormalizada,
      montoCents,
      tipo: "entrada",
    });
    const ref = db().collection("movimientos_banco").doc(resolved.docId);
    const existing = await ref.get();
    if (existing.exists) {
      omitidos++;
      continue;
    }

    writer.set(ref, {
      tipo: "entrada",
      origen: "popular_extracto",
      importVersion,
      fechaValor: Timestamp.fromDate(fechaValor),
      fechaRegistro: now,
      montoCents,
      moneda: "DOP",
      referenciaBanco,
      referenciaNormalizada,
      descripcion: descRaw,
      cuentaRai,
      bancoTransaccionId: resolved.bancoTransaccionId || null,
      movimientoIdSource: resolved.idSource,
      estadoConciliacion: "sin_match",
      importBatchId,
      rawPayload: {
        fecha: fila.fecha ?? null,
        monto: fila.monto ?? null,
        referencia: fila.referencia ?? null,
        descripcion: fila.descripcion ?? null,
        bancoTransaccionId: fila.bancoTransaccionId ?? null,
      },
      createdAt: now,
      updatedAt: now,
    });
    creados++;
  }

  await writer.close();

  await batchRef.set({
    origen: "popular_extracto",
    importVersion,
    actorUid,
    filasRecibidas: filas.length,
    creados,
    omitidos,
    invalidos,
    createdAt: now,
  });

  return {
    ok: true,
    importBatchId,
    creados,
    omitidos,
    invalidos,
    filasRecibidas: filas.length,
  };
});

/** Admin: cola de movimientos sin conciliar (Fase 4 consumirá esto). */
export const listarMovimientosSinConciliar = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  await assertAdmin(request.auth.uid);

  const limitRaw = request.data?.limit;
  const limit =
    typeof limitRaw === "number" && limitRaw > 0 && limitRaw <= 100
      ? Math.trunc(limitRaw)
      : 40;

  const snap = await db()
    .collection("movimientos_banco")
    .where("estadoConciliacion", "==", "sin_match")
    .orderBy("fechaValor", "desc")
    .limit(limit)
    .get();

  return {
    ok: true,
    movimientos: snap.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
  };
});
