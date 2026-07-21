/**
 * Período de facturación corporativa: días cobrables (lun–vie, sin feriados)
 * y código de acceso sagrado hasta validar el pago.
 */
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import {
  codigoAccesoDesdePeriodo,
  generarCodigoAccesoPeriodo,
} from "./corporativo_codigo.js";

const MSG_PIN_CORP_INVALIDO =
  "Código incorrecto o período vencido. Contacte a su encargado.";

type AnyMap = Record<string, unknown>;

const TZ_RD = "America/Santo_Domingo";

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function soloFecha(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function onlyDigits(v: unknown): string {
  return String(v ?? "").replace(/\D/g, "");
}

function parseTs(v: unknown): Date | null {
  if (v instanceof Timestamp) return v.toDate();
  if (v instanceof Date && Number.isFinite(v.getTime())) return v;
  const s = str(v);
  if (!s) return null;
  const d = new Date(s);
  return Number.isFinite(d.getTime()) ? d : null;
}

export type VigenciaCodigoCorporativo = {
  vigente: boolean;
  expirado: boolean;
  codigo: string;
  fin: Date | null;
  estadoCodigo: "activo" | "expirado" | "pendiente_pago";
};

/** Evalúa si el PIN del período permite iniciar viajes nuevos. */
export function evaluarVigenciaCodigoCorporativo(
  periodo: AnyMap,
  now = new Date(),
): VigenciaCodigoCorporativo {
  const codigo = codigoAccesoDesdePeriodo(periodo);
  const fin = parseTs(periodo.fin);
  const explicito = periodo.codigoVigente;
  const pendiente = periodo.pendienteCobro === true;
  const estadoRaw = str(periodo.estadoCodigo).toLowerCase();

  if (explicito === false || estadoRaw === "expirado") {
    return {
      vigente: false,
      expirado: true,
      codigo,
      fin,
      estadoCodigo: pendiente ? "pendiente_pago" : "expirado",
    };
  }
  if (fin && fin.getTime() < now.getTime()) {
    return {
      vigente: false,
      expirado: true,
      codigo,
      fin,
      estadoCodigo: pendiente ? "pendiente_pago" : "expirado",
    };
  }
  if (pendiente && explicito !== true) {
    return {
      vigente: false,
      expirado: true,
      codigo,
      fin,
      estadoCodigo: "pendiente_pago",
    };
  }
  return {
    vigente: codigo.length === 6,
    expirado: false,
    codigo,
    fin,
    estadoCodigo: "activo",
  };
}

export function validarPinCorporativoParaInicio(
  periodo: AnyMap,
  pinIngresado: string,
  now = new Date(),
): { ok: boolean; mensaje: string } {
  const vig = evaluarVigenciaCodigoCorporativo(periodo, now);
  const pin = onlyDigits(pinIngresado);
  if (!vig.vigente) {
    return { ok: false, mensaje: MSG_PIN_CORP_INVALIDO };
  }
  if (pin.length !== 6) {
    return { ok: false, mensaje: MSG_PIN_CORP_INVALIDO };
  }
  if (pin !== onlyDigits(vig.codigo)) {
    return { ok: false, mensaje: MSG_PIN_CORP_INVALIDO };
  }
  return { ok: true, mensaje: "" };
}

export { MSG_PIN_CORP_INVALIDO };

export function diaSemanaIso(d: Date): number {
  const js = d.getDay();
  return js === 0 ? 7 : js;
}

/** yyyy-MM-dd en calendario República Dominicana. */
export function diaCalendarioRd(ref: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ_RD,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(ref);
}

/** Días de la semana que cuentan para el ciclo (default lun–vie). */
export function diasSemanaCobrablesEmpresa(ed: AnyMap): number[] {
  const raw = ed.facturacionDiasSemana;
  if (Array.isArray(raw) && raw.length > 0) {
    const out = raw
      .map((x) => Math.trunc(num(x)))
      .filter((d) => d >= 1 && d <= 7);
    if (out.length > 0) return [...new Set(out)].sort((a, b) => a - b);
  }
  return [1, 2, 3, 4, 5];
}

export function esDiaCobrableCalendario(
  fecha: Date,
  diasSemana: number[],
  diasPausa: ReadonlySet<string>,
): boolean {
  const key = diaCalendarioRd(fecha);
  if (diasPausa.has(key)) return false;
  return diasSemana.includes(diaSemanaIso(fecha));
}

/**
 * Fin del período: el último día calendario del enésimo día cobrable
 * (sáb/dom y feriados de plantilla no cuentan).
 */
export function calcularFinPeriodoCobrable(
  inicio: Date,
  cicloDias: number,
  diasSemana: number[],
  diasPausa: ReadonlySet<string>,
): Date {
  const objetivo = Math.max(1, Math.trunc(cicloDias));
  let contados = 0;
  let cursor = soloFecha(inicio);
  const maxScan = Math.max(objetivo * 4, 120);

  for (let i = 0; i < maxScan; i++) {
    if (esDiaCobrableCalendario(cursor, diasSemana, diasPausa)) {
      contados++;
      if (contados >= objetivo) {
        return finDelDiaLocal(cursor);
      }
    }
    cursor = new Date(cursor.getTime() + 86400000);
  }

  return new Date(inicio.getTime() + objetivo * 86400000);
}

function finDelDiaLocal(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
}

/** Unión de `diasPausaFeriado` de plantillas activas de la empresa. */
export async function obtenerDiasPausaEmpresa(empresaId: string): Promise<Set<string>> {
  const out = new Set<string>();
  const id = str(empresaId);
  if (!id) return out;

  try {
    const snap = await getFirestore()
      .collection("empresas_corporativas")
      .doc(id)
      .collection("plantillas_ruta")
      .where("activa", "==", true)
      .limit(40)
      .get();

    for (const doc of snap.docs) {
      const feriados = (doc.data().diasPausaFeriado ?? []) as unknown[];
      if (!Array.isArray(feriados)) continue;
      for (const f of feriados) {
        const k = str(f);
        if (/^\d{4}-\d{2}-\d{2}$/.test(k)) out.add(k);
      }
    }
  } catch {
    // Sin plantillas: solo excluye fines de semana vía diasSemana.
  }

  const extra = await getFirestore()
    .collection("empresas_corporativas")
    .doc(id)
    .get();
  const ed = (extra.data() ?? {}) as AnyMap;
  const empFeriados = ed.diasPausaFeriadoEmpresa;
  if (Array.isArray(empFeriados)) {
    for (const f of empFeriados) {
      const k = str(f);
      if (/^\d{4}-\d{2}-\d{2}$/.test(k)) out.add(k);
    }
  }

  return out;
}

export type PeriodoCorporativoMap = AnyMap;

/** Nuevo período tras pago validado (código nuevo). */
export function nuevoPeriodoTrasPago(
  ed: AnyMap,
  cicloDias: number,
  now: Date,
  diasPausa: ReadonlySet<string>,
): PeriodoCorporativoMap {
  const diasSemana = diasSemanaCobrablesEmpresa(ed);
  const inicio = soloFecha(now);
  const fin = calcularFinPeriodoCobrable(inicio, cicloDias, diasSemana, diasPausa);
  return {
    inicio: Timestamp.fromDate(inicio),
    fin: Timestamp.fromDate(fin),
    cicloDiasCobrables: Math.max(1, Math.trunc(cicloDias)),
    modoFin: "dias_cobrables",
    viajesCount: 0,
    montoTotalRd: 0,
    porChofer: {},
    codigoAcceso: generarCodigoAccesoPeriodo(),
    codigoVigente: true,
    estadoCodigo: "activo",
    pendienteCobro: false,
  };
}

/** Repara inicio/fin sin tocar el código existente. */
export function repararPeriodoSinRotarCodigo(
  ed: AnyMap,
  cicloDias: number,
  now: Date,
  diasPausa: ReadonlySet<string>,
  raw: AnyMap,
): PeriodoCorporativoMap {
  const diasSemana = diasSemanaCobrablesEmpresa(ed);
  const codigo =
    codigoAccesoDesdePeriodo(raw) || generarCodigoAccesoPeriodo();
  const inicioTs = raw.inicio;
  const inicio =
    inicioTs instanceof Timestamp
      ? soloFecha(inicioTs.toDate())
      : soloFecha(now);
  const fin = calcularFinPeriodoCobrable(
    inicio,
    cicloDias,
    diasSemana,
    diasPausa,
  );
  const finDate = fin;
  const vigenteExplicito = raw.codigoVigente;
  const pendiente = raw.pendienteCobro === true;
  const codigoVigente =
    vigenteExplicito === false
      ? false
      : pendiente
        ? false
        : finDate.getTime() >= now.getTime();

  return {
    inicio: Timestamp.fromDate(inicio),
    fin: Timestamp.fromDate(fin),
    cicloDiasCobrables: Math.max(1, Math.trunc(cicloDias)),
    modoFin: "dias_cobrables",
    viajesCount: Math.trunc(num(raw.viajesCount)),
    montoTotalRd: Math.round(num(raw.montoTotalRd) * 100) / 100,
    porChofer:
      typeof raw.porChofer === "object" && raw.porChofer !== null
        ? { ...(raw.porChofer as AnyMap) }
        : {},
    codigoAcceso: codigo,
    codigoVigente,
    estadoCodigo: codigoVigente ? "activo" : pendiente ? "pendiente_pago" : "expirado",
    pendienteCobro: pendiente,
  };
}
