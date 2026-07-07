import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { logAdminAudit } from "./audit.js";
import { invalidateComisionViajePctCache } from "./comision_viaje_pct.js";
import {
  invalidateComisionIncentivosCache,
  parseComisionIncentivosConfig,
  type EscalonIncentivo,
  type VentanaIncentivo,
} from "./comision_incentivos_taxista.js";
import { invalidateComisionPrepagoConfigCache } from "./finance.js";

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

function safeJson(data: unknown): AnyMap {
  if (!data || typeof data !== "object") return {};
  return JSON.parse(JSON.stringify(data)) as AnyMap;
}

async function writeHistory(params: {
  configKey: string;
  changedBy: string;
  motivo: string;
  before: AnyMap;
  after: AnyMap;
}): Promise<void> {
  await db().collection("configuraciones_historial").add({
    configKey: params.configKey,
    changedBy: params.changedBy,
    motivo: params.motivo,
    before: params.before,
    after: params.after,
    createdAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Actualiza tarifas críticas (tarifas/general + tarifa_turismo/*) usando Admin SDK y deja historial.
 * No toca lógica de negocio: solo escritura de configuración.
 */
export const updateTarifasCriticas = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  await assertAdmin(uid);

  const motivo = String(request.data?.motivo ?? "").trim();
  if (motivo.length < 6) throw new HttpsError("invalid-argument", "Motivo requerido (min 6 caracteres)");

  const tarifasGeneral = request.data?.tarifasGeneral as AnyMap | undefined;
  const tarifaTurismo = request.data?.tarifaTurismo as AnyMap | undefined;
  if (!tarifasGeneral || typeof tarifasGeneral !== "object") {
    throw new HttpsError("invalid-argument", "Falta tarifasGeneral");
  }
  if (!tarifaTurismo || typeof tarifaTurismo !== "object") {
    throw new HttpsError("invalid-argument", "Falta tarifaTurismo");
  }

  const refGeneral = db().collection("tarifas").doc("general");
  const turColl = db().collection("tarifa_turismo");
  const turIds = ["carro", "jeepeta", "minivan", "bus"] as const;

  const before: AnyMap = {};
  const after: AnyMap = {};

  await db().runTransaction(async (tx) => {
    const gSnap = await tx.get(refGeneral);
    before.tarifas_general = safeJson(gSnap.data() ?? {});

    tx.set(refGeneral, tarifasGeneral, { merge: true });

    const afterGeneral = { ...(gSnap.data() ?? {}), ...tarifasGeneral };
    after.tarifas_general = safeJson(afterGeneral);

    before.tarifa_turismo = {};
    after.tarifa_turismo = {};

    for (const id of turIds) {
      const ref = turColl.doc(id);
      const snap = await tx.get(ref);
      (before.tarifa_turismo as AnyMap)[id] = safeJson(snap.data() ?? {});

      const patch = safeJson((tarifaTurismo as AnyMap)[id] ?? {});
      tx.set(ref, patch, { merge: true });

      (after.tarifa_turismo as AnyMap)[id] = safeJson({ ...(snap.data() ?? {}), ...patch });
    }
  });

  await writeHistory({
    configKey: "tarifas_criticas",
    changedBy: uid,
    motivo,
    before,
    after,
  });

  logAdminAudit({
    action: "update_tarifas_criticas",
    actorUid: uid,
    resourceType: "config",
    resourceId: "tarifas_criticas",
    metadata: { motivoLen: motivo.length },
  });

  return { ok: true };
});

/**
 * Config crítica usada por comisiones prepago (finance.ts). Se escribe por callable + historial.
 */
export const updateComisionPrepagoConfig = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  await assertAdmin(uid);

  const motivo = String(request.data?.motivo ?? "").trim();
  if (motivo.length < 6) throw new HttpsError("invalid-argument", "Motivo requerido (min 6 caracteres)");

  const minimoOperativoRd = Number(request.data?.minimoOperativoRd);
  const umbralPreventivoRd = Number(request.data?.umbralPreventivoRd);
  if (!Number.isFinite(minimoOperativoRd) || minimoOperativoRd <= 0) {
    throw new HttpsError("invalid-argument", "minimoOperativoRd invalido");
  }
  if (!Number.isFinite(umbralPreventivoRd) || umbralPreventivoRd <= 0) {
    throw new HttpsError("invalid-argument", "umbralPreventivoRd invalido");
  }

  const ref = db().collection("config").doc("comision_prepago");
  const beforeSnap = await ref.get();
  const before = safeJson(beforeSnap.data() ?? {});
  const patch = {
    minimoOperativoRd,
    umbralPreventivoRd,
    updatedAt: FieldValue.serverTimestamp(),
  };
  await ref.set(patch, { merge: true });
  const afterSnap = await ref.get();
  const after = safeJson(afterSnap.data() ?? {});

  await writeHistory({
    configKey: "config/comision_prepago",
    changedBy: uid,
    motivo,
    before,
    after,
  });

  logAdminAudit({
    action: "update_comision_prepago_config",
    actorUid: uid,
    resourceType: "config",
    resourceId: "config/comision_prepago",
    metadata: { minimoOperativoRd, umbralPreventivoRd },
  });

  invalidateComisionPrepagoConfigCache();

  return { ok: true };
});

/**
 * Promo MxK 3x1 (doc: /config/promo_3x1).
 * Cambios solo vía admin callable + historial.
 */
export const updatePromo3x1Config = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  await assertAdmin(uid);

  const motivo = String(request.data?.motivo ?? "").trim();
  if (motivo.length < 6) throw new HttpsError("invalid-argument", "Motivo requerido (min 6 caracteres)");

  const activa = request.data?.activa === true;
  const porcentaje = Number(request.data?.porcentaje);
  const m = Number(request.data?.m);
  const k = Number(request.data?.k);

  if (!Number.isFinite(porcentaje) || porcentaje < 0 || porcentaje > 95) {
    throw new HttpsError("invalid-argument", "porcentaje invalido");
  }
  if (!Number.isFinite(m) || m < 1 || m > 50) {
    throw new HttpsError("invalid-argument", "m invalido (1–50)");
  }
  if (!Number.isFinite(k) || k < 1 || k > 50) {
    throw new HttpsError("invalid-argument", "k invalido (1–50)");
  }

  const modo = `${m}x${k}`;
  const ref = db().collection("config").doc("promo_3x1");

  const beforeSnap = await ref.get();
  const before = safeJson(beforeSnap.data() ?? {});

  await ref.set(
    {
      activa,
      porcentaje,
      modo,
      m,
      k,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const afterSnap = await ref.get();
  const after = safeJson(afterSnap.data() ?? {});

  await writeHistory({
    configKey: "config/promo_3x1",
    changedBy: uid,
    motivo,
    before,
    after,
  });

  logAdminAudit({
    action: "update_promo_3x1_config",
    actorUid: uid,
    resourceType: "config",
    resourceId: "config/promo_3x1",
    metadata: { activa, porcentaje, m, k },
  });

  return { ok: true };
});

/**
 * Promo MxK globales (doc: /config/promociones).
 */
export const updatePromocionesMxKConfig = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  await assertAdmin(uid);

  const motivo = String(request.data?.motivo ?? "").trim();
  if (motivo.length < 6) throw new HttpsError("invalid-argument", "Motivo requerido (min 6 caracteres)");

  const activa = request.data?.activa === true;
  const porcentaje = Number(request.data?.porcentaje);
  const m = Number(request.data?.m);
  const k = Number(request.data?.k);

  if (!Number.isFinite(porcentaje) || porcentaje < 0 || porcentaje > 95) {
    throw new HttpsError("invalid-argument", "porcentaje invalido");
  }
  if (!Number.isFinite(m) || m < 1 || m > 999) {
    throw new HttpsError("invalid-argument", "m invalido (1–999)");
  }
  if (!Number.isFinite(k) || k < 1 || k > 999) {
    throw new HttpsError("invalid-argument", "k invalido (1–999)");
  }

  const modo = `${m}x${k}`;
  const descripcion = `${m}x${k} - ${porcentaje}% descuento`;

  const ref = db().collection("config").doc("promociones");
  const beforeSnap = await ref.get();
  const before = safeJson(beforeSnap.data() ?? {});

  await ref.set(
    {
      activa,
      tipo: "mxk",
      m,
      k,
      modo,
      porcentaje,
      viajesRequeridos: m,
      viajesGratis: k,
      descripcion,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const afterSnap = await ref.get();
  const after = safeJson(afterSnap.data() ?? {});

  await writeHistory({
    configKey: "config/promociones",
    changedBy: uid,
    motivo,
    before,
    after,
  });

  logAdminAudit({
    action: "update_promociones_mxk_config",
    actorUid: uid,
    resourceType: "config",
    resourceId: "config/promociones",
    metadata: { activa, porcentaje, m, k },
  });

  return { ok: true };
});

/**
 * Porcentaje global de comisión en viajes en efectivo (`config/comision`, campo `porcentaje`).
 * Solo admin; invalida caché en Cloud Functions.
 */
export const setComisionPorcentaje = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  await assertAdmin(uid);

  const motivo = String(request.data?.motivo ?? "").trim();
  if (motivo.length < 6) throw new HttpsError("invalid-argument", "Motivo requerido (min 6 caracteres)");

  const porcentaje = Number(request.data?.porcentaje);
  if (!Number.isFinite(porcentaje) || porcentaje < 0 || porcentaje > 100) {
    throw new HttpsError("invalid-argument", "porcentaje invalido (0–100)");
  }

  const ref = db().collection("config").doc("comision");
  const beforeSnap = await ref.get();
  const before = safeJson(beforeSnap.data() ?? {});

  await ref.set(
    {
      porcentaje,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  // Legacy giras: % fijo 10 (independiente del % global de viajes).
  await db()
    .collection("configuracion_globals")
    .doc("app")
    .set(
      {
        comision_gira_porcentaje: 10,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

  invalidateComisionViajePctCache();

  const afterSnap = await ref.get();
  const after = safeJson(afterSnap.data() ?? {});

  await writeHistory({
    configKey: "config/comision",
    changedBy: uid,
    motivo,
    before,
    after,
  });

  logAdminAudit({
    action: "set_comision_porcentaje",
    actorUid: uid,
    resourceType: "config",
    resourceId: "config/comision",
    metadata: { porcentaje },
  });

  return { ok: true, porcentaje };
});

function parseEscalonesInput(raw: unknown): EscalonIncentivo[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new HttpsError("invalid-argument", "escalones requerido (array no vacio)");
  }
  if (raw.length > 12) {
    throw new HttpsError("invalid-argument", "maximo 12 escalones");
  }
  const out: EscalonIncentivo[] = [];
  const seen = new Set<number>();
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const m = item as AnyMap;
    const viajesMinimos = Math.trunc(Number(m.viajesMinimos));
    const comisionPct = Number(m.comisionPct);
    const etiqueta = String(m.etiqueta ?? "").trim();
    if (!Number.isFinite(viajesMinimos) || viajesMinimos < 1 || viajesMinimos > 999) {
      throw new HttpsError("invalid-argument", "viajesMinimos invalido (1–999)");
    }
    if (!Number.isFinite(comisionPct) || comisionPct < 0 || comisionPct > 100) {
      throw new HttpsError("invalid-argument", "comisionPct invalido (0–100)");
    }
    if (seen.has(viajesMinimos)) {
      throw new HttpsError("invalid-argument", `viajesMinimos duplicado: ${viajesMinimos}`);
    }
    seen.add(viajesMinimos);
    out.push({
      viajesMinimos,
      comisionPct,
      etiqueta: etiqueta || `Nivel ${viajesMinimos}`,
    });
  }
  if (out.length === 0) {
    throw new HttpsError("invalid-argument", "escalones vacio tras validacion");
  }
  out.sort((a, b) => a.viajesMinimos - b.viajesMinimos);
  return out;
}

/**
 * Incentivos por volumen de viajes completados (`config/comision_incentivos_taxista`).
 * El conteo se actualiza en `finalizarViajeSeguro` (Admin SDK).
 */
export const updateComisionIncentivosTaxistaConfig = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  await assertAdmin(uid);

  const motivo = String(request.data?.motivo ?? "").trim();
  if (motivo.length < 6) throw new HttpsError("invalid-argument", "Motivo requerido (min 6 caracteres)");

  const activo = request.data?.activo === true;
  const ventanaRaw = String(request.data?.ventana ?? "semana").trim().toLowerCase();
  const ventana: VentanaIncentivo = ventanaRaw === "mes" ? "mes" : "semana";
  const escalones = parseEscalonesInput(request.data?.escalones);

  if (activo && escalones.length === 0) {
    throw new HttpsError("invalid-argument", "Activo requiere al menos un escalon");
  }

  const ref = db().collection("config").doc("comision_incentivos_taxista");
  const beforeSnap = await ref.get();
  const before = safeJson(beforeSnap.data() ?? {});

  const patch = {
    activo,
    ventana,
    escalones,
    updatedAt: FieldValue.serverTimestamp(),
  };
  await ref.set(patch, { merge: true });

  invalidateComisionIncentivosCache();

  const afterSnap = await ref.get();
  const after = safeJson(afterSnap.data() ?? {});
  const parsed = parseComisionIncentivosConfig(after);

  await writeHistory({
    configKey: "config/comision_incentivos_taxista",
    changedBy: uid,
    motivo,
    before,
    after,
  });

  logAdminAudit({
    action: "update_comision_incentivos_taxista_config",
    actorUid: uid,
    resourceType: "config",
    resourceId: "config/comision_incentivos_taxista",
    metadata: { activo, ventana, escalones: escalones.length },
  });

  return { ok: true, activo: parsed.activo, ventana: parsed.ventana, escalones: parsed.escalones };
});

/**
 * Tramos larga distancia (`config/tarifas_tramos`).
 */
export const updateTarifasTramosConfig = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "No autenticado");
  const uid = request.auth.uid;
  await assertAdmin(uid);

  const motivo = String(request.data?.motivo ?? "").trim();
  if (motivo.length < 6) throw new HttpsError("invalid-argument", "Motivo requerido (min 6 caracteres)");

  const tarifasTramos = request.data?.tarifasTramos as AnyMap | undefined;
  if (!tarifasTramos || typeof tarifasTramos !== "object") {
    throw new HttpsError("invalid-argument", "Falta tarifasTramos");
  }

  const ref = db().collection("config").doc("tarifas_tramos");
  const beforeSnap = await ref.get();
  const before = safeJson(beforeSnap.data() ?? {});

  await ref.set(
    {
      ...tarifasTramos,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const afterSnap = await ref.get();
  const after = safeJson(afterSnap.data() ?? {});

  await writeHistory({
    configKey: "config/tarifas_tramos",
    changedBy: uid,
    motivo,
    before,
    after,
  });

  logAdminAudit({
    action: "update_tarifas_tramos_config",
    actorUid: uid,
    resourceType: "config",
    resourceId: "config/tarifas_tramos",
    metadata: { activo: after.activo === true },
  });

  return { ok: true };
});

