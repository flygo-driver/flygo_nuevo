/**
 * Acumula viajes corporativos completados en el período de facturación de la empresa.
 */
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  codigoAccesoDesdePeriodo,
  generarCodigoAccesoPeriodo,
} from "./corporativo_codigo.js";
import {
  nuevoPeriodoTrasPago,
  obtenerDiasPausaEmpresa,
  repararPeriodoSinRotarCodigo,
  evaluarVigenciaCodigoCorporativo,
} from "./corporativo_periodo.js";
import { liquidacionCentsCorporativoDesdeViaje } from "./corporativo_tarifa_config.js";
import { esCorporativoModoInformativo } from "./multiparada.js";
import {
  enviarPushUid,
  registrarHistorialNotificacionCorp,
} from "./corporativo_notificaciones.js";
import {
  habilitarViajesCorporativosParaLiquidacionSemanal,
} from "./corporativo_chofer_liquidacion.js";

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function parseTs(v: unknown): Date | null {
  if (v instanceof Timestamp) return v.toDate();
  if (v instanceof Date) return v;
  if (typeof v === "string") {
    const d = new Date(v);
    return Number.isFinite(d.getTime()) ? d : null;
  }
  return null;
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

/** Tras pagar un período, oculta del historial operativo las rutas ya cerradas. */
export async function archivarHistorialOperativoTrasPago(
  empresaId: string,
): Promise<number> {
  const empresaRef = getFirestore()
    .collection("empresas_corporativas")
    .doc(empresaId);
  const snap = await empresaRef.collection("historial").limit(250).get();
  if (snap.empty) return 0;

  const batch = getFirestore().batch();
  let n = 0;
  const archivables = new Set([
    "completado",
    "no_ejecutado",
    "cancelado",
    "anulado",
  ]);

  for (const doc of snap.docs) {
    const d = doc.data() as AnyMap;
    if (d.archivado === true) continue;
    const est = str(d.estado).toLowerCase();
    if (!archivables.has(est)) continue;
    batch.set(
      doc.ref,
      {
        archivado: true,
        archivadoEn: FieldValue.serverTimestamp(),
        archivadoMotivo: "periodo_pagado",
      },
      { merge: true },
    );
    n++;
    if (n >= 400) break;
  }
  if (n > 0) await batch.commit();
  return n;
}

function periodoDesdeEmpresa(
  ed: AnyMap,
  cicloDias: number,
  now: Date,
  diasPausa: ReadonlySet<string>,
): AnyMap {
  const raw = (ed.periodoActual ?? {}) as AnyMap;
  const inicio = parseTs(raw.inicio);
  const fin = parseTs(raw.fin);
  const codigo = codigoAccesoDesdePeriodo(raw);

  if (!inicio) {
    return nuevoPeriodoTrasPago(ed, cicloDias, now, diasPausa);
  }

  if (!fin || str(raw.modoFin) !== "dias_cobrables" || !codigo) {
    return repararPeriodoSinRotarCodigo(ed, cicloDias, now, diasPausa, raw);
  }

  return {
    inicio: raw.inicio ?? Timestamp.fromDate(inicio),
    fin: raw.fin ?? Timestamp.fromDate(fin),
    cicloDiasCobrables: Math.max(1, Math.trunc(cicloDias)),
    modoFin: "dias_cobrables",
    viajesCount: Math.trunc(num(raw.viajesCount)),
    montoTotalRd: round2(num(raw.montoTotalRd)),
    porChofer:
      typeof raw.porChofer === "object" && raw.porChofer !== null
        ? { ...(raw.porChofer as AnyMap) }
        : {},
    codigoAcceso: codigo,
    pendienteCobro: raw.pendienteCobro === true,
  };
}

/** Si el período venció con saldo, archiva liquidación pendiente sin rotar el código. */
function archivarPeriodoVencidoEnTx(
  tx: FirebaseFirestore.Transaction,
  empresaRef: FirebaseFirestore.DocumentReference,
  ed: AnyMap,
  cicloDias: number,
  now: Date,
  diasPausa: ReadonlySet<string>,
): AnyMap {
  const raw = (ed.periodoActual ?? {}) as AnyMap;
  const fin = parseTs(raw.fin);
  if (!fin || fin.getTime() > now.getTime()) {
    return periodoDesdeEmpresa(ed, cicloDias, now, diasPausa);
  }

  const montoTotalRd = round2(num(raw.montoTotalRd));
  const viajesCount = Math.trunc(num(raw.viajesCount));
  const codigoActual =
    codigoAccesoDesdePeriodo(raw) || generarCodigoAccesoPeriodo();

  if (montoTotalRd > 0 || viajesCount > 0) {
    const liqRef = empresaRef.collection("liquidaciones").doc();
    tx.set(liqRef, {
      periodoInicio: raw.inicio ?? null,
      periodoFin: raw.fin ?? null,
      viajesCount,
      montoTotalRd,
      porChofer: raw.porChofer ?? {},
      estado: "pendiente_cobro",
      cierreAutomatico: true,
      codigoPeriodoAlCierre: codigoActual,
      ...metaLiquidacionEmpresa(ed, cicloDias),
      creadoEn: FieldValue.serverTimestamp(),
    });
  }

  const siguiente = repararPeriodoSinRotarCodigo(ed, cicloDias, now, diasPausa, {
    ...raw,
    viajesCount: 0,
    montoTotalRd: 0,
    porChofer: {},
    pendienteCobro: montoTotalRd > 0 || viajesCount > 0 || raw.pendienteCobro === true,
    codigoVigente: false,
    estadoCodigo: "expirado",
  });
  return {
    ...siguiente,
    codigoAcceso: codigoActual,
    codigoVigente: false,
    estadoCodigo: "expirado",
    pendienteCobro: montoTotalRd > 0 || viajesCount > 0 || raw.pendienteCobro === true,
  };
}

function ensurePeriodoVigente(
  ed: AnyMap,
  cicloDias: number,
  now: Date,
  diasPausa: ReadonlySet<string>,
): AnyMap {
  return periodoDesdeEmpresa(ed, cicloDias, now, diasPausa);
}

/** Metadatos comerciales sellados en cada liquidación (auditoría B2B). */
function metaLiquidacionEmpresa(ed: AnyMap, cicloDias: number): AnyMap {
  const forma = str(ed.formaPagoRai).toLowerCase();
  return {
    facturacionCicloDias: cicloDias,
    formaPagoRai: forma || null,
  };
}

/** ¿Quedan liquidaciones archivadas sin cobrar? */
async function hayLiquidacionesPendientesCobro(empresaId: string): Promise<boolean> {
  const snap = await getFirestore()
    .collection("empresas_corporativas")
    .doc(empresaId)
    .collection("liquidaciones")
    .where("estado", "==", "pendiente_cobro")
    .limit(1)
    .get();
  return !snap.empty;
}

/**
 * Tras pagar la última liquidación pendiente: nuevo período + código nuevo.
 * El período archivado conserva viajes y montos en `liquidaciones`.
 */
async function intentarRenovarCodigoTrasSaldarDeuda(
  empresaId: string,
): Promise<{ renovado: boolean; codigoAcceso?: string }> {
  if (await hayLiquidacionesPendientesCobro(empresaId)) {
    return { renovado: false };
  }

  const empresaRef = getFirestore()
    .collection("empresas_corporativas")
    .doc(empresaId);
  const eSnap = await empresaRef.get();
  if (!eSnap.exists) return { renovado: false };

  const ed = (eSnap.data() ?? {}) as AnyMap;
  const periodo = (ed.periodoActual ?? {}) as AnyMap;
  const now = new Date();
  const vig = evaluarVigenciaCodigoCorporativo(periodo, now);
  if (vig.vigente) return { renovado: false };

  const cicloDias = Math.max(1, Math.trunc(num(ed.facturacionCicloDias) || 15));
  const diasPausa = await obtenerDiasPausaEmpresa(empresaId);
  const nuevo = nuevoPeriodoTrasPago(ed, cicloDias, now, diasPausa);
  const codigoAcceso = str(nuevo.codigoAcceso);

  await empresaRef.set(
    {
      periodoActual: {
        ...nuevo,
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  logger.info("corporativo codigo renovado tras saldar deuda", {
    empresaId,
    codigoAcceso,
  });
  return { renovado: true, codigoAcceso };
}

/** Aviso único a encargados cuando el corte archiva liquidación pendiente. */
async function notificarEncargadosCortePeriodoConDeuda(args: {
  empresaId: string;
  empresaRef: FirebaseFirestore.DocumentReference;
  empresaData: AnyMap;
  montoRd: number;
  viajesCount: number;
  periodoFin: Date;
}): Promise<void> {
  const encargados = Array.isArray(args.empresaData.encargadoUids)
    ? (args.empresaData.encargadoUids as unknown[]).map(str).filter(Boolean)
    : [];
  if (encargados.length === 0) return;

  const key = `ultimaNotifPeriodoCerrado_${args.periodoFin.toISOString().slice(0, 10)}`;
  if (str(args.empresaData[key]) === "1") return;

  const nombreEmpresa = str(args.empresaData.nombre) || "Su empresa";
  const montoTxt = Math.round(args.montoRd).toLocaleString("es-DO");
  const titulo = "Período corporativo cerrado";
  const viajesTxt =
    args.viajesCount === 1 ? "1 viaje" : `${args.viajesCount} viajes`;
  const cuerpo =
    args.montoRd > 0
      ? `${nombreEmpresa}: liquidación de RD$${montoTxt} (${viajesTxt}). ` +
        "Pagá en Cuenta para renovar el código. Tus rutas siguen guardadas."
      : `${nombreEmpresa}: período cerrado (${viajesTxt}). ` +
        "Pagá en Cuenta para renovar el código y seguir enviando rutas.";

  for (const uid of encargados) {
    const ok = await enviarPushUid(uid, titulo, cuerpo, {
      type: "corporativo_periodo_cerrado",
      empresaId: args.empresaId,
      rol: "encargado",
    });
    await registrarHistorialNotificacionCorp({
      empresaId: args.empresaId,
      uidDestino: uid,
      canal: "fcm",
      tipo: "corporativo_periodo_cerrado",
      titulo,
      cuerpo,
      enviado: ok,
    });
  }

  await args.empresaRef.set(
    { [key]: "1", actualizadoEn: FieldValue.serverTimestamp() },
    { merge: true },
  );
}

/** Suma un viaje corporativo al período actual (idempotente por viajeId). */
export async function acumularViajeCorporativoEnPeriodo(
  viajeId: string,
  d: AnyMap,
): Promise<void> {
  const empresaId = str(d.corporativoEmpresaId);
  if (!empresaId) return;

  const db = getFirestore();
  const empresaRef = db.collection("empresas_corporativas").doc(empresaId);
  const viajeRef = db.collection("viajes").doc(viajeId);
  const histRef = empresaRef.collection("historial").doc(viajeId);

  const monto = round2(num(d.precio ?? d.precioFinal ?? d.total ?? 0));
  let montoChofer = round2(
    num(d.gananciaTaxista) ||
      (typeof d.ganancia_cents === "number"
        ? num(d.ganancia_cents) / 100
        : 0) ||
      0,
  );
  if (montoChofer <= 0) {
    const estimado = round2(num(d.corporativoPagoChoferEstimadoRd));
    if (estimado > 0) montoChofer = estimado;
  }
  if (montoChofer <= 0) {
    const corpLiq = liquidacionCentsCorporativoDesdeViaje(
      d as Record<string, unknown>,
      10,
    );
    if (corpLiq && corpLiq.gananciaCents > 0) {
      montoChofer = round2(corpLiq.gananciaCents / 100);
    }
  }
  if (montoChofer <= 0) {
    logger.warn("corporativo acumular: monto chofer no resuelto", {
      viajeId,
      empresaId,
    });
  }
  const choferUid = str(
    d.uidTaxista ??
      d.taxistaId ??
      d.corporativoChoferAsignadoUid ??
      d.corporativoChoferPreferidoUid,
  );
  const choferNombre = str(d.nombreTaxista) || "Chofer asignado";
  const plantillaNombre = str(d.corporativoPlantillaNombre);

  try {
    await db.runTransaction(async (tx) => {
      const vSnap = await tx.get(viajeRef);
      if (!vSnap.exists) return;
      const vd = (vSnap.data() ?? {}) as AnyMap;
      if (vd.corporativoContabilizado === true) return;
      if (vd.corporativoOmitidoSinCodigo === true) return;

      // Modo informativo (sin PIN): cuenta como ruta ejecutada al completar.
      const corpInformativo = esCorporativoModoInformativo(vd);
      if (vd.codigoVerificado !== true && !corpInformativo) {
        tx.set(
          viajeRef,
          {
            corporativoOmitidoSinCodigo: true,
            corporativoContabilizado: false,
            actualizadoEn: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        tx.set(
          histRef,
          {
            estado: "no_ejecutado",
            motivoNoCobro: "sin_codigo_verificacion",
            monto: 0,
            choferUid,
            choferNombre,
            plantillaNombre,
            actualizadoEn: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        logger.info("corporativo no contabilizado sin codigo", { viajeId, empresaId });
        return;
      }

      const eSnap = await tx.get(empresaRef);
      if (!eSnap.exists) return;
      const ed = (eSnap.data() ?? {}) as AnyMap;

      const cicloDias = Math.max(1, Math.trunc(num(ed.facturacionCicloDias) || 15));
      const now = new Date();
      const diasPausa = await obtenerDiasPausaEmpresa(empresaId);
      let periodo = periodoDesdeEmpresa(ed, cicloDias, now, diasPausa);
      const finPrev = parseTs(((ed.periodoActual ?? {}) as AnyMap).fin);
      if (finPrev && finPrev.getTime() <= now.getTime()) {
        periodo = archivarPeriodoVencidoEnTx(tx, empresaRef, ed, cicloDias, now, diasPausa);
      }

      const viajesCount = Math.trunc(num(periodo.viajesCount)) + 1;
      const montoTotalRd = round2(num(periodo.montoTotalRd) + monto);
      const porChofer = { ...((periodo.porChofer ?? {}) as AnyMap) };

      if (choferUid) {
        const prev = (porChofer[choferUid] ?? {}) as AnyMap;
        porChofer[choferUid] = {
          nombre: choferNombre || str(prev.nombre) || "Chofer",
          viajes: Math.trunc(num(prev.viajes)) + 1,
          montoRd: round2(num(prev.montoRd) + montoChofer),
        };
      }

      tx.set(
        empresaRef,
        {
          periodoActual: {
            ...periodo,
            viajesCount,
            montoTotalRd,
            porChofer,
            actualizadoEn: FieldValue.serverTimestamp(),
          },
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      tx.set(
        viajeRef,
        {
          corporativoContabilizado: true,
          corporativoOmitidoSinCodigo: false,
          ...(choferUid
            ? {
                corporativoChoferAcumuladoPeriodoRd: round2(
                  num((porChofer[choferUid] as AnyMap)?.montoRd),
                ),
                corporativoChoferViajesPeriodo: Math.trunc(
                  num((porChofer[choferUid] as AnyMap)?.viajes),
                ),
                corporativoPeriodoInicio: periodo.inicio ?? null,
                corporativoPeriodoFin: periodo.fin ?? null,
              }
            : {}),
        },
        { merge: true },
      );

      tx.set(
        histRef,
        {
          estado: "completado",
          monto,
          choferUid,
          choferNombre,
          plantillaNombre,
          codigoVerificado: vd.codigoVerificado === true || corpInformativo,
          completadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });
  } catch (e) {
    logger.error("acumularViajeCorporativoEnPeriodo", { viajeId, empresaId, e });
  }
}

/** Revierte monto del período si el viaje estaba contabilizado. */
function revertirPeriodoSiContabilizado(
  tx: FirebaseFirestore.Transaction,
  empresaRef: FirebaseFirestore.DocumentReference,
  eFresh: FirebaseFirestore.DocumentSnapshot,
  monto: number,
  choferUid: string,
  estabaContabilizado: boolean,
  montoChofer?: number,
): void {
  if (!estabaContabilizado || !eFresh.exists) return;
  const ed2 = (eFresh.data() ?? {}) as AnyMap;
  const periodo = { ...((ed2.periodoActual ?? {}) as AnyMap) };
  const viajesCount = Math.max(0, Math.trunc(num(periodo.viajesCount)) - 1);
  const montoTotalRd = Math.max(0, round2(num(periodo.montoTotalRd) - monto));
  const porChofer = { ...((periodo.porChofer ?? {}) as AnyMap) };
  const montoChoferRev = round2(
    montoChofer != null && montoChofer > 0 ? montoChofer : monto,
  );
  if (choferUid && porChofer[choferUid]) {
    const prev = (porChofer[choferUid] ?? {}) as AnyMap;
    const vCh = Math.max(0, Math.trunc(num(prev.viajes)) - 1);
    const mCh = Math.max(0, round2(num(prev.montoRd) - montoChoferRev));
    if (vCh <= 0 && mCh <= 0) {
      delete porChofer[choferUid];
    } else {
      porChofer[choferUid] = {
        ...prev,
        viajes: vCh,
        montoRd: mCh,
      };
    }
  }
  tx.set(
    empresaRef,
    {
      periodoActual: {
        ...periodo,
        viajesCount,
        montoTotalRd,
        porChofer,
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function aplicarAnulacionDefinitiva(opts: {
  tx: FirebaseFirestore.Transaction;
  empresaRef: FirebaseFirestore.DocumentReference;
  viajeRef: FirebaseFirestore.DocumentReference;
  histRef: FirebaseFirestore.DocumentReference;
  eFresh: FirebaseFirestore.DocumentSnapshot;
  vd: AnyMap;
  hd: AnyMap;
  uid: string;
  motivo: string;
  aprobadoPorUid?: string;
}): void {
  const {
    tx,
    empresaRef,
    viajeRef,
    histRef,
    eFresh,
    vd,
    hd,
    uid,
    motivo,
    aprobadoPorUid,
  } = opts;
  const monto = round2(num(vd.precio ?? vd.precioFinal ?? hd.monto ?? 0));
  const montoChofer = round2(
    num(vd.gananciaTaxista) ||
      (typeof vd.ganancia_cents === "number"
        ? num(vd.ganancia_cents) / 100
        : 0) ||
      monto,
  );
  const choferUid = str(
    vd.uidTaxista ?? vd.taxistaId ?? vd.corporativoChoferAsignadoUid,
  );
  const estabaContabilizado = vd.corporativoContabilizado === true;

  revertirPeriodoSiContabilizado(
    tx,
    empresaRef,
    eFresh,
    monto,
    choferUid,
    estabaContabilizado,
    montoChofer,
  );

  tx.set(
    viajeRef,
    {
      corporativoAnulado: true,
      corporativoAnulacionPendiente: false,
      corporativoContabilizado: false,
      corporativoOmitidoSinCodigo: true,
      anuladoPorUid: uid,
      anuladoMotivo: motivo,
      anuladoEn: FieldValue.serverTimestamp(),
      ...(aprobadoPorUid
        ? { anulacionAprobadaPorUid: aprobadoPorUid }
        : {}),
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  tx.set(
    histRef,
    {
      estado: "no_ejecutado",
      motivoNoCobro: motivo,
      monto: 0,
      montoAntesAnulacion: monto,
      anuladoPorUid: uid,
      anuladoEn: FieldValue.serverTimestamp(),
      ...(aprobadoPorUid
        ? { anulacionAprobadaPorUid: aprobadoPorUid }
        : {}),
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

/**
 * Encargado solicita anular cobro (feriado / fraude / no laboró).
 * No revierte dinero hasta que Admin RAI apruebe (anti-fraude inverso).
 * Admin puede anular en el acto.
 */
export const encargadoAnularViajeCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const uid = request.auth.uid;
  const db = getFirestore();
  const empresaId = str(request.data?.empresaId);
  const viajeId = str(request.data?.viajeId);
  const motivo = str(request.data?.motivo).slice(0, 200) || "no_laboro_feriado";

  if (!empresaId || !viajeId) {
    throw new HttpsError("invalid-argument", "Faltan empresaId o viajeId");
  }

  const empresaRef = db.collection("empresas_corporativas").doc(empresaId);
  const eSnap = await empresaRef.get();
  if (!eSnap.exists) throw new HttpsError("not-found", "Empresa no encontrada");
  const ed = (eSnap.data() ?? {}) as AnyMap;

  const adminSnap = await db.collection("usuarios").doc(uid).get();
  const rol = String(adminSnap.data()?.rol ?? "").toLowerCase();
  const esAdmin = rol === "admin";
  if (!esAdmin && !esEncargadoEmpresa(ed, uid)) {
    throw new HttpsError("permission-denied", "Solo encargado o admin RAI");
  }

  const viajeRef = db.collection("viajes").doc(viajeId);
  const histRef = empresaRef.collection("historial").doc(viajeId);
  let pendiente = false;

  await db.runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    const hSnap = await tx.get(histRef);
    const eFresh = await tx.get(empresaRef);
    if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no encontrado");
    const vd = (vSnap.data() ?? {}) as AnyMap;
    const hd = (hSnap.data() ?? {}) as AnyMap;
    if (str(vd.corporativoEmpresaId) !== empresaId) {
      throw new HttpsError("permission-denied", "Viaje de otra empresa");
    }
    if (vd.corporativoAnulado === true) {
      return;
    }

    // Admin RAI: anula al momento (confianza operativa).
    if (esAdmin) {
      aplicarAnulacionDefinitiva({
        tx,
        empresaRef,
        viajeRef,
        histRef,
        eFresh,
        vd,
        hd,
        uid,
        motivo,
        aprobadoPorUid: uid,
      });
      return;
    }

    // Encargado: solo solicitud — el cobro sigue hasta que RAI apruebe.
    if (
      vd.corporativoAnulacionPendiente === true ||
      str(hd.estado).toLowerCase() === "anulacion_pendiente"
    ) {
      pendiente = true;
      return;
    }

    const monto = round2(num(vd.precio ?? vd.precioFinal ?? hd.monto ?? 0));
    pendiente = true;
    tx.set(
      viajeRef,
      {
        corporativoAnulacionPendiente: true,
        anulacionSolicitadaPorUid: uid,
        anulacionMotivo: motivo,
        anulacionSolicitadaEn: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.set(
      histRef,
      {
        estado: "anulacion_pendiente",
        motivoAnulacion: motivo,
        monto,
        anulacionSolicitadaPorUid: uid,
        anulacionSolicitadaEn: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });

  logger.info("encargadoAnularViajeCorporativo", {
    empresaId,
    viajeId,
    uid,
    motivo,
    esAdmin,
    pendiente,
  });
  return {
    ok: true,
    empresaId,
    viajeId,
    pendiente: esAdmin ? false : pendiente,
  };
});

/**
 * Admin RAI aprueba o rechaza una solicitud de anulación del encargado.
 * Aprobar → quita el cobro del período. Rechazar → el día sigue cobrado.
 */
export const adminResolverAnulacionCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const uid = request.auth.uid;
  const db = getFirestore();
  const adminSnap = await db.collection("usuarios").doc(uid).get();
  const rol = String(adminSnap.data()?.rol ?? "").toLowerCase();
  if (rol !== "admin") {
    throw new HttpsError("permission-denied", "Solo administración RAI");
  }

  const empresaId = str(request.data?.empresaId);
  const viajeId = str(request.data?.viajeId);
  const accion = str(request.data?.accion).toLowerCase(); // aprobar | rechazar
  const notaAdmin = str(request.data?.notaAdmin).slice(0, 300);

  if (!empresaId || !viajeId) {
    throw new HttpsError("invalid-argument", "Faltan empresaId o viajeId");
  }
  if (accion !== "aprobar" && accion !== "rechazar") {
    throw new HttpsError("invalid-argument", "accion debe ser aprobar o rechazar");
  }

  const empresaRef = db.collection("empresas_corporativas").doc(empresaId);
  const viajeRef = db.collection("viajes").doc(viajeId);
  const histRef = empresaRef.collection("historial").doc(viajeId);

  await db.runTransaction(async (tx) => {
    const vSnap = await tx.get(viajeRef);
    const hSnap = await tx.get(histRef);
    const eFresh = await tx.get(empresaRef);
    if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no encontrado");
    const vd = (vSnap.data() ?? {}) as AnyMap;
    const hd = (hSnap.data() ?? {}) as AnyMap;
    if (str(vd.corporativoEmpresaId) !== empresaId) {
      throw new HttpsError("permission-denied", "Viaje de otra empresa");
    }
    if (vd.corporativoAnulado === true) {
      return;
    }
    const pendiente =
      vd.corporativoAnulacionPendiente === true ||
      str(hd.estado).toLowerCase() === "anulacion_pendiente";
    if (!pendiente) {
      throw new HttpsError(
        "failed-precondition",
        "No hay anulación pendiente para este viaje",
      );
    }

    const motivo =
      str(hd.motivoAnulacion || vd.anulacionMotivo) || "no_laboro_feriado";
    const solicitanteUid = str(
      hd.anulacionSolicitadaPorUid || vd.anulacionSolicitadaPorUid || uid,
    );

    if (accion === "aprobar") {
      aplicarAnulacionDefinitiva({
        tx,
        empresaRef,
        viajeRef,
        histRef,
        eFresh,
        vd,
        hd,
        uid: solicitanteUid || uid,
        motivo,
        aprobadoPorUid: uid,
      });
      if (notaAdmin) {
        tx.set(
          histRef,
          { anulacionNotaAdmin: notaAdmin },
          { merge: true },
        );
      }
      return;
    }

    // Rechazar: el cobro se mantiene.
    tx.set(
      viajeRef,
      {
        corporativoAnulacionPendiente: false,
        anulacionRechazadaPorUid: uid,
        anulacionRechazadaEn: FieldValue.serverTimestamp(),
        anulacionNotaAdmin: notaAdmin || null,
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.set(
      histRef,
      {
        estado: "completado",
        anulacionRechazadaPorUid: uid,
        anulacionRechazadaEn: FieldValue.serverTimestamp(),
        anulacionNotaAdmin: notaAdmin || null,
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });

  logger.info("adminResolverAnulacionCorporativo", {
    empresaId,
    viajeId,
    uid,
    accion,
  });
  return { ok: true, empresaId, viajeId, accion };
});

/** Admin: empresa pagó → archiva período y pone cuenta en cero. */
export const marcarCuentaCorporativoPagada = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const db = getFirestore();
  const adminSnap = await db.collection("usuarios").doc(request.auth.uid).get();
  const rol = String(adminSnap.data()?.rol ?? "").toLowerCase();
  if (rol !== "admin") {
    throw new HttpsError("permission-denied", "Solo administración RAI");
  }

  const empresaId = str(request.data?.empresaId);
  if (!empresaId) {
    throw new HttpsError("invalid-argument", "Falta empresaId");
  }

  const empresaRef = db.collection("empresas_corporativas").doc(empresaId);
  const now = new Date();
  let codigoNuevo = "";
  const diasPausa = await obtenerDiasPausaEmpresa(empresaId);
  let periodoPagadoInicio: Date | null = null;
  let periodoPagadoFin: Date | null = null;

  await db.runTransaction(async (tx) => {
    const eSnap = await tx.get(empresaRef);
    if (!eSnap.exists) {
      throw new HttpsError("not-found", "Empresa no encontrada");
    }
    const ed = (eSnap.data() ?? {}) as AnyMap;
    const cicloDias = Math.max(1, Math.trunc(num(ed.facturacionCicloDias) || 15));
    const periodo = (ed.periodoActual ?? {}) as AnyMap;
    periodoPagadoInicio = parseTs(periodo.inicio);
    periodoPagadoFin = parseTs(periodo.fin);
    const montoTotalRd = round2(num(periodo.montoTotalRd));
    const viajesCount = Math.trunc(num(periodo.viajesCount));

    if (montoTotalRd > 0 || viajesCount > 0) {
      const liqRef = empresaRef.collection("liquidaciones").doc();
      tx.set(liqRef, {
        periodoInicio: periodo.inicio ?? null,
        periodoFin: periodo.fin ?? null,
        viajesCount,
        montoTotalRd,
        porChofer: periodo.porChofer ?? {},
        estado: "pagado",
        pagadoEn: FieldValue.serverTimestamp(),
        pagadoPorUid: request.auth!.uid,
        ...metaLiquidacionEmpresa(ed, cicloDias),
        creadoEn: FieldValue.serverTimestamp(),
      });
    }

    const nuevoPeriodo = nuevoPeriodoTrasPago(ed, cicloDias, now, diasPausa);
    codigoNuevo = str(nuevoPeriodo.codigoAcceso);
    tx.set(
      empresaRef,
      {
        periodoActual: {
          ...nuevoPeriodo,
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        ultimoPagoEn: FieldValue.serverTimestamp(),
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });

  try {
    await archivarHistorialOperativoTrasPago(empresaId);
  } catch (e) {
    logger.warn("archivarHistorialOperativoTrasPago", { empresaId, e });
  }

  try {
    await habilitarViajesCorporativosParaLiquidacionSemanal({
      empresaId,
      periodoInicio: periodoPagadoInicio,
      periodoFin: periodoPagadoFin,
      pagadoPorUid: request.auth!.uid,
    });
  } catch (e) {
    logger.warn("[CORP_LIQ] marcarCuentaCorporativoPagada", { empresaId, e });
  }

  return { ok: true, empresaId, codigoAcceso: codigoNuevo };
});

/** Admin: marca liquidación archivada pendiente_cobro como pagada. */
export const marcarLiquidacionCorporativoPagada = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const db = getFirestore();
  const adminSnap = await db.collection("usuarios").doc(request.auth.uid).get();
  const rol = String(adminSnap.data()?.rol ?? "").toLowerCase();
  if (rol !== "admin") {
    throw new HttpsError("permission-denied", "Solo administración RAI");
  }

  const empresaId = str(request.data?.empresaId);
  const liquidacionId = str(request.data?.liquidacionId);
  if (!empresaId || !liquidacionId) {
    throw new HttpsError("invalid-argument", "Faltan empresaId o liquidacionId");
  }

  const liqRef = db
    .collection("empresas_corporativas")
    .doc(empresaId)
    .collection("liquidaciones")
    .doc(liquidacionId);

  let periodoPagadoInicio: Date | null = null;
  let periodoPagadoFin: Date | null = null;

  await db.runTransaction(async (tx) => {
    const liqSnap = await tx.get(liqRef);
    if (!liqSnap.exists) {
      throw new HttpsError("not-found", "Liquidación no encontrada");
    }
    const ld = (liqSnap.data() ?? {}) as AnyMap;
    periodoPagadoInicio = parseTs(ld.periodoInicio);
    periodoPagadoFin = parseTs(ld.periodoFin);
    const estado = str(ld.estado).toLowerCase();
    if (estado === "pagado") return;
    if (estado !== "pendiente_cobro") {
      throw new HttpsError(
        "failed-precondition",
        "Solo liquidaciones pendientes de cobro",
      );
    }
    tx.set(
      liqRef,
      {
        estado: "pagado",
        pagadoEn: FieldValue.serverTimestamp(),
        pagadoPorUid: request.auth!.uid,
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });

  try {
    await archivarHistorialOperativoTrasPago(empresaId);
  } catch (e) {
    logger.warn("archivarHistorialOperativoTrasPago liq", { empresaId, e });
  }

  try {
    await habilitarViajesCorporativosParaLiquidacionSemanal({
      empresaId,
      periodoInicio: periodoPagadoInicio,
      periodoFin: periodoPagadoFin,
      pagadoPorUid: request.auth!.uid,
      liquidacionEmpresaId: liquidacionId,
    });
  } catch (e) {
    logger.warn("[CORP_LIQ] marcarLiquidacionCorporativoPagada", { empresaId, e });
  }

  const renov = await intentarRenovarCodigoTrasSaldarDeuda(empresaId);

  return {
    ok: true,
    empresaId,
    liquidacionId,
    ...(renov.renovado && renov.codigoAcceso
      ? { codigoAcceso: renov.codigoAcceso, periodoRenovado: true }
      : {}),
  };
});

const METODOS_PAGO_CORP = new Set([
  "transferencia",
  "deposito",
  "cheque",
  "efectivo",
  "otro",
]);

function esEncargadoEmpresa(ed: AnyMap, uid: string): boolean {
  const uids = Array.isArray(ed.encargadoUids) ? (ed.encargadoUids as unknown[]) : [];
  return uids.map((x) => str(x)).includes(uid);
}

/**
 * Encargado reporta pago a RAI: método + bauche/comprobante.
 * Crea `pagos_reportados/{id}` con estado pendiente_validacion.
 */
export const reportarPagoCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const uid = request.auth.uid;
  const db = getFirestore();

  const empresaId = str(request.data?.empresaId);
  const metodoPago = str(request.data?.metodoPago).toLowerCase();
  const comprobanteUrl = str(request.data?.comprobanteUrl);
  const referencia = str(request.data?.referenciaBancaria).slice(0, 80);
  const nota = str(request.data?.nota).slice(0, 400);
  const liquidacionId = str(request.data?.liquidacionId);
  const montoRd = round2(num(request.data?.montoRd));

  if (!empresaId) {
    throw new HttpsError("invalid-argument", "Falta empresaId");
  }
  if (!METODOS_PAGO_CORP.has(metodoPago)) {
    throw new HttpsError(
      "invalid-argument",
      "Método de pago inválido (transferencia, deposito, cheque, efectivo u otro)",
    );
  }
  if (!comprobanteUrl || comprobanteUrl.length < 12) {
    throw new HttpsError("invalid-argument", "Falta la foto del bauche/comprobante");
  }
  if (montoRd <= 0) {
    throw new HttpsError("invalid-argument", "Indica el monto pagado");
  }

  const empresaRef = db.collection("empresas_corporativas").doc(empresaId);
  const eSnap = await empresaRef.get();
  if (!eSnap.exists) {
    throw new HttpsError("not-found", "Empresa no encontrada");
  }
  const ed = (eSnap.data() ?? {}) as AnyMap;
  if (!esEncargadoEmpresa(ed, uid)) {
    throw new HttpsError("permission-denied", "Solo el encargado de la empresa");
  }

  const periodo = (ed.periodoActual ?? {}) as AnyMap;
  let montoEsperado = round2(num(periodo.montoTotalRd));
  let periodoInicio = periodo.inicio ?? null;
  let periodoFin = periodo.fin ?? null;
  let destino = "periodo_actual";

  if (liquidacionId) {
    const liqSnap = await empresaRef.collection("liquidaciones").doc(liquidacionId).get();
    if (!liqSnap.exists) {
      throw new HttpsError("not-found", "Liquidación no encontrada");
    }
    const ld = (liqSnap.data() ?? {}) as AnyMap;
    const est = str(ld.estado).toLowerCase();
    if (est === "pagado") {
      throw new HttpsError("failed-precondition", "Esa liquidación ya está pagada");
    }
    montoEsperado = round2(num(ld.montoTotalRd));
    periodoInicio = ld.periodoInicio ?? null;
    periodoFin = ld.periodoFin ?? null;
    destino = "liquidacion";
  }

  const pagoRef = empresaRef.collection("pagos_reportados").doc();
  await pagoRef.set({
    empresaId,
    empresaNombre: str(ed.nombre),
    montoRd,
    montoEsperadoRd: montoEsperado,
    metodoPago,
    referenciaBancaria: referencia || null,
    nota: nota || null,
    comprobanteUrl,
    liquidacionId: liquidacionId || null,
    destino,
    periodoInicio,
    periodoFin,
    estado: "pendiente_validacion",
    reportadoPorUid: uid,
    reportadoEn: FieldValue.serverTimestamp(),
    creadoEn: FieldValue.serverTimestamp(),
    actualizadoEn: FieldValue.serverTimestamp(),
  });

  if (liquidacionId) {
    await empresaRef.collection("liquidaciones").doc(liquidacionId).set(
      {
        pagoReportadoId: pagoRef.id,
        pagoReportadoEn: FieldValue.serverTimestamp(),
        pagoReportadoEstado: "pendiente_validacion",
        pagoMetodo: metodoPago,
        pagoComprobanteUrl: comprobanteUrl,
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } else {
    await empresaRef.set(
      {
        ultimoPagoReportado: {
          pagoId: pagoRef.id,
          montoRd,
          metodoPago,
          estado: "pendiente_validacion",
          comprobanteUrl,
          reportadoEn: FieldValue.serverTimestamp(),
        },
        actualizadoEn: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  logger.info("reportarPagoCorporativo", {
    empresaId,
    pagoId: pagoRef.id,
    metodoPago,
    montoRd,
  });

  return { ok: true, pagoId: pagoRef.id, estado: "pendiente_validacion" };
});

/** Admin: valida o rechaza bauche reportado por el encargado. */
export const adminValidarPagoCorporativo = onCall(async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "No autenticado");
  }
  const db = getFirestore();
  const adminSnap = await db.collection("usuarios").doc(request.auth.uid).get();
  const rol = String(adminSnap.data()?.rol ?? "").toLowerCase();
  if (rol !== "admin") {
    throw new HttpsError("permission-denied", "Solo administración RAI");
  }

  const empresaId = str(request.data?.empresaId);
  const pagoId = str(request.data?.pagoId);
  const accion = str(request.data?.accion).toLowerCase(); // validar | rechazar
  const notaAdmin = str(request.data?.notaAdmin).slice(0, 400);

  if (!empresaId || !pagoId) {
    throw new HttpsError("invalid-argument", "Faltan empresaId o pagoId");
  }
  if (accion !== "validar" && accion !== "rechazar") {
    throw new HttpsError("invalid-argument", "accion debe ser validar o rechazar");
  }

  const pagoRef = db
    .collection("empresas_corporativas")
    .doc(empresaId)
    .collection("pagos_reportados")
    .doc(pagoId);

  const pagoSnap = await pagoRef.get();
  if (!pagoSnap.exists) {
    throw new HttpsError("not-found", "Pago reportado no encontrado");
  }
  const pd = (pagoSnap.data() ?? {}) as AnyMap;
  if (str(pd.estado).toLowerCase() !== "pendiente_validacion") {
    throw new HttpsError("failed-precondition", "Este pago ya fue procesado");
  }

  const nuevoEstado = accion === "validar" ? "validado" : "rechazado";
  await pagoRef.set(
    {
      estado: nuevoEstado,
      validadoPorUid: request.auth.uid,
      validadoEn: FieldValue.serverTimestamp(),
      notaAdmin: notaAdmin || null,
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  const liquidacionId = str(pd.liquidacionId);
  const destinoPago = str(pd.destino).toLowerCase();

  if (liquidacionId) {
    const liqPatch: AnyMap = {
      pagoReportadoEstado: nuevoEstado,
      actualizadoEn: FieldValue.serverTimestamp(),
    };
    // Validar bauche = liquidación saldada (flujo B2B cerrado).
    if (accion === "validar") {
      liqPatch.estado = "pagado";
      liqPatch.pagadoEn = FieldValue.serverTimestamp();
      liqPatch.pagadoPorUid = request.auth.uid;
      liqPatch.pagoValidadoId = pagoId;
    }
    await db
      .collection("empresas_corporativas")
      .doc(empresaId)
      .collection("liquidaciones")
      .doc(liquidacionId)
      .set(liqPatch, { merge: true });
  }

  // Pago del período abierto validado → archiva como pagado y renueva ciclo + CÓDIGO NUEVO.
  let codigoAccesoNuevo = "";
  let periodoPagadoInicio: Date | null = null;
  let periodoPagadoFin: Date | null = null;
  if (accion === "validar" && !liquidacionId && destinoPago === "periodo_actual") {
    const empresaRef = db.collection("empresas_corporativas").doc(empresaId);
    const now = new Date();
    const diasPausa = await obtenerDiasPausaEmpresa(empresaId);
    await db.runTransaction(async (tx) => {
      const eSnap = await tx.get(empresaRef);
      if (!eSnap.exists) return;
      const ed = (eSnap.data() ?? {}) as AnyMap;
      const cicloDias = Math.max(1, Math.trunc(num(ed.facturacionCicloDias) || 15));
      const periodo = (ed.periodoActual ?? {}) as AnyMap;
      periodoPagadoInicio = parseTs(periodo.inicio);
      periodoPagadoFin = parseTs(periodo.fin);
      const montoTotalRd = round2(num(periodo.montoTotalRd));
      const viajesCount = Math.trunc(num(periodo.viajesCount));
      if (montoTotalRd > 0 || viajesCount > 0) {
        const liqRef = empresaRef.collection("liquidaciones").doc();
        tx.set(liqRef, {
          periodoInicio: periodo.inicio ?? null,
          periodoFin: periodo.fin ?? null,
          viajesCount,
          montoTotalRd,
          porChofer: periodo.porChofer ?? {},
          estado: "pagado",
          pagadoEn: FieldValue.serverTimestamp(),
          pagadoPorUid: request.auth!.uid,
          pagoValidadoId: pagoId,
          ...metaLiquidacionEmpresa(ed, cicloDias),
          creadoEn: FieldValue.serverTimestamp(),
        });
      }
      const nuevo = nuevoPeriodoTrasPago(ed, cicloDias, now, diasPausa);
      codigoAccesoNuevo = str(nuevo.codigoAcceso);
      tx.set(
        empresaRef,
        {
          periodoActual: {
            ...nuevo,
            actualizadoEn: FieldValue.serverTimestamp(),
          },
          ultimoPagoEn: FieldValue.serverTimestamp(),
          actualizadoEn: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });
  }

  await db.collection("empresas_corporativas").doc(empresaId).set(
    {
      ultimoPagoReportado: {
        pagoId,
        montoRd: num(pd.montoRd),
        metodoPago: str(pd.metodoPago),
        estado: nuevoEstado,
        comprobanteUrl: str(pd.comprobanteUrl),
        reportadoEn: pd.reportadoEn ?? null,
        validadoEn: FieldValue.serverTimestamp(),
      },
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  if (accion === "validar") {
    try {
      await archivarHistorialOperativoTrasPago(empresaId);
    } catch (e) {
      logger.warn("archivarHistorialOperativoTrasPago pago", { empresaId, e });
    }
    if (!codigoAccesoNuevo && liquidacionId) {
      const renov = await intentarRenovarCodigoTrasSaldarDeuda(empresaId);
      if (renov.renovado && renov.codigoAcceso) {
        codigoAccesoNuevo = renov.codigoAcceso;
      }
    }

    let pIni: Date | null = periodoPagadoInicio;
    let pFin: Date | null = periodoPagadoFin;
    if (liquidacionId) {
      const liqSnap = await db
        .collection("empresas_corporativas")
        .doc(empresaId)
        .collection("liquidaciones")
        .doc(liquidacionId)
        .get();
      if (liqSnap.exists) {
        const ld = (liqSnap.data() ?? {}) as AnyMap;
        pIni = parseTs(ld.periodoInicio);
        pFin = parseTs(ld.periodoFin);
      }
    }

    try {
      await habilitarViajesCorporativosParaLiquidacionSemanal({
        empresaId,
        periodoInicio: pIni,
        periodoFin: pFin,
        pagadoPorUid: request.auth!.uid,
        liquidacionEmpresaId: liquidacionId || undefined,
        pagoEmpresaId: pagoId,
      });
    } catch (e) {
      logger.warn("[CORP_LIQ] adminValidarPagoCorporativo", { empresaId, pagoId, e });
    }
  }

  return {
    ok: true,
    empresaId,
    pagoId,
    estado: nuevoEstado,
    ...(codigoAccesoNuevo ? { codigoAcceso: codigoAccesoNuevo } : {}),
  };
});

/** Diario: archiva períodos vencidos con saldo pendiente (no pierde deuda). */
export const scheduledCorporativoCortePeriodos = onSchedule(
  {
    schedule: "every 24 hours",
    timeZone: "America/Santo_Domingo",
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    let corteados = 0;
    let revisados = 0;
    let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | undefined;

    // Pagina todas las empresas activas (sin tope artificial de 60).
    while (true) {
      let q: FirebaseFirestore.Query = db
        .collection("empresas_corporativas")
        .where("activa", "==", true)
        .limit(100);
      if (lastDoc) q = q.startAfter(lastDoc);

      let snap: FirebaseFirestore.QuerySnapshot;
      try {
        snap = await q.get();
      } catch (e) {
        logger.error("scheduledCorporativoCortePeriodos query", e);
        break;
      }
      if (snap.empty) break;

      for (const doc of snap.docs) {
        revisados += 1;
        const ed = (doc.data() ?? {}) as AnyMap;
        const raw = (ed.periodoActual ?? {}) as AnyMap;
        const cicloDias = Math.max(
          1,
          Math.trunc(num(ed.facturacionCicloDias) || 15),
        );
        const diasPausa = await obtenerDiasPausaEmpresa(doc.id);

        if (str(raw.modoFin) !== "dias_cobrables") {
          try {
            const reparado = repararPeriodoSinRotarCodigo(
              ed,
              cicloDias,
              now,
              diasPausa,
              raw,
            );
            await doc.ref.set(
              {
                periodoActual: {
                  ...reparado,
                  actualizadoEn: FieldValue.serverTimestamp(),
                },
                actualizadoEn: FieldValue.serverTimestamp(),
              },
              { merge: true },
            );
            const finReparado = parseTs(reparado.fin);
            if (!finReparado || finReparado.getTime() > now.getTime()) {
              continue;
            }
          } catch (e) {
            logger.warn("scheduledCorporativoCortePeriodos reparar fin", {
              empresaId: doc.id,
              e,
            });
          }
        }

        const fin = parseTs(raw.fin);
        if (!fin || fin.getTime() > now.getTime()) continue;

        const montoAntesCorte = round2(num(raw.montoTotalRd));
        const viajesAntesCorte = Math.trunc(num(raw.viajesCount));
        const huboDeudaArchivar =
          montoAntesCorte > 0 || viajesAntesCorte > 0;

        try {
          await db.runTransaction(async (tx) => {
            const fresh = await tx.get(doc.ref);
            if (!fresh.exists) return;
            const freshEd = (fresh.data() ?? {}) as AnyMap;
            const freshRaw = (freshEd.periodoActual ?? {}) as AnyMap;
            const freshFin = parseTs(freshRaw.fin);
            if (!freshFin || freshFin.getTime() > now.getTime()) return;
            const freshCiclo = Math.max(
              1,
              Math.trunc(num(freshEd.facturacionCicloDias) || 15),
            );
            const nuevo = archivarPeriodoVencidoEnTx(
              tx,
              doc.ref,
              freshEd,
              freshCiclo,
              now,
              diasPausa,
            );
            tx.set(
              doc.ref,
              {
                periodoActual: {
                  ...nuevo,
                  actualizadoEn: FieldValue.serverTimestamp(),
                },
                actualizadoEn: FieldValue.serverTimestamp(),
              },
              { merge: true },
            );
          });
          corteados += 1;
          logger.info("scheduledCorporativoCortePeriodos archivado", {
            empresaId: doc.id,
            cicloDias,
          });
          if (huboDeudaArchivar) {
            try {
              await notificarEncargadosCortePeriodoConDeuda({
                empresaId: doc.id,
                empresaRef: doc.ref,
                empresaData: ed,
                montoRd: montoAntesCorte,
                viajesCount: viajesAntesCorte,
                periodoFin: fin,
              });
            } catch (e) {
              logger.warn("scheduledCorporativoCortePeriodos push encargado", {
                empresaId: doc.id,
                e,
              });
            }
          }
        } catch (e) {
          logger.error("scheduledCorporativoCortePeriodos", {
            empresaId: doc.id,
            e,
          });
        }
      }

      lastDoc = snap.docs[snap.docs.length - 1];
      if (snap.size < 100) break;
    }

    logger.info("scheduledCorporativoCortePeriodos done", {
      revisados,
      corteados,
    });
  },
);

/**
 * Viajes corporativos publicados que nunca usaron el código
 * (feriado, no laboró, enfermo, cancelado) → se cierran sin cobrar.
 * Ventana: 2h después de la hora de recogida.
 */
export const scheduledCorporativoExpirarSinCodigo = onSchedule(
  {
    schedule: "every 30 minutes",
    timeZone: "America/Santo_Domingo",
    memory: "256MiB",
    timeoutSeconds: 120,
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const limite = new Date(now.getTime() - 2 * 60 * 60 * 1000);

    let empresasSnap: FirebaseFirestore.QuerySnapshot;
    try {
      empresasSnap = await db
        .collection("empresas_corporativas")
        .where("activa", "==", true)
        .limit(40)
        .get();
    } catch (e) {
      logger.error("scheduledCorporativoExpirarSinCodigo empresas", e);
      return;
    }

    for (const emp of empresasSnap.docs) {
      const empresaId = emp.id;
      let histSnap: FirebaseFirestore.QuerySnapshot;
      try {
        histSnap = await db
          .collection("empresas_corporativas")
          .doc(empresaId)
          .collection("historial")
          .orderBy("creadoEn", "desc")
          .limit(30)
          .get();
      } catch (e) {
        logger.warn("scheduledCorporativoExpirarSinCodigo hist", { empresaId, e });
        continue;
      }

      for (const hDoc of histSnap.docs) {
        const h = (hDoc.data() ?? {}) as AnyMap;
        const estadoH = str(h.estado).toLowerCase();
        if (
          estadoH === "completado" ||
          estadoH === "no_ejecutado" ||
          estadoH === "cancelado" ||
          estadoH === "fallo_asignacion"
        ) {
          continue;
        }

        const viajeId = str(h.viajeId) || hDoc.id;
        if (!viajeId) continue;

        try {
          const vRef = db.collection("viajes").doc(viajeId);
          const vSnap = await vRef.get();
          if (!vSnap.exists) continue;
          const vd = (vSnap.data() ?? {}) as AnyMap;
          if (vd.corporativo !== true) continue;
          if (vd.codigoVerificado === true) continue;
          if (vd.completado === true) continue;
          if (vd.corporativoOmitidoSinCodigo === true) continue;

          const fecha = parseTs(vd.fechaHora) ?? parseTs(h.fechaRecogida);
          if (!fecha || fecha.getTime() > limite.getTime()) continue;

          const estadoV = str(vd.estado).toLowerCase();
          if (estadoV === "completado" || estadoV === "cancelado") continue;

          await vRef.set(
            {
              estado: "cancelado",
              cancelado: true,
              completado: false,
              activo: false,
              corporativoOmitidoSinCodigo: true,
              corporativoContabilizado: false,
              motivoCancelacion: "sin_codigo_ventana_expirada",
              canceladoEn: FieldValue.serverTimestamp(),
              actualizadoEn: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );

          await hDoc.ref.set(
            {
              estado: "no_ejecutado",
              motivoNoCobro: "sin_codigo_verificacion",
              monto: 0,
              actualizadoEn: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );

          const uidT = str(vd.uidTaxista ?? vd.taxistaId);
          if (uidT) {
            const uRef = db.collection("usuarios").doc(uidT);
            const uSnap = await uRef.get();
            const u = (uSnap.data() ?? {}) as AnyMap;
            const patch: AnyMap = {
              actualizadoEn: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            };
            if (str(u.viajeActivoId) === viajeId) patch.viajeActivoId = "";
            if (str(u.siguienteViajeId) === viajeId) patch.siguienteViajeId = "";
            if (Object.keys(patch).length > 2) {
              await uRef.set(patch, { merge: true });
            }
          }

          logger.info("corporativo expirado sin codigo", { empresaId, viajeId });
        } catch (e) {
          logger.warn("scheduledCorporativoExpirarSinCodigo viaje", {
            empresaId,
            viajeId,
            e,
          });
        }
      }
    }
  },
);
