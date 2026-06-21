import { FieldValue, getFirestore } from "firebase-admin/firestore";

const CONFIG_DOC = "comision_incentivos_taxista";
const STATS_COLL = "taxistas_stats";
const TTL_MS = 60_000;

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

export type VentanaIncentivo = "semana" | "mes";

export interface EscalonIncentivo {
  viajesMinimos: number;
  comisionPct: number;
  etiqueta: string;
}

export interface ComisionIncentivosConfig {
  activo: boolean;
  ventana: VentanaIncentivo;
  escalones: EscalonIncentivo[];
}

export interface IncentivoFinalizarResult {
  pctEfectiva: number;
  statsPatch: AnyMap;
  viajePatch: AnyMap;
}

let _cfgCache: { loadedAt: number; cfg: ComisionIncentivosConfig } | null = null;

function clampPct(v: number): number {
  if (!Number.isFinite(v)) return 20;
  return Math.min(100, Math.max(0, v));
}

function toInt(v: unknown, fb: number): number {
  if (typeof v === "number" && Number.isFinite(v)) return Math.trunc(v);
  if (typeof v === "string") {
    const n = Number.parseInt(v.trim(), 10);
    if (Number.isFinite(n)) return n;
  }
  return fb;
}

function parseEscalones(raw: unknown): EscalonIncentivo[] {
  if (!Array.isArray(raw)) return [];
  const out: EscalonIncentivo[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const m = item as AnyMap;
    const viajesMinimos = toInt(m.viajesMinimos, 0);
    const comisionPct = clampPct(Number(m.comisionPct ?? m.comision_pct ?? 20));
    const etiqueta = String(m.etiqueta ?? m.label ?? "").trim() || `Nivel ${viajesMinimos}`;
    if (viajesMinimos < 1) continue;
    out.push({ viajesMinimos, comisionPct, etiqueta });
  }
  out.sort((a, b) => a.viajesMinimos - b.viajesMinimos);
  return out;
}

export function parseComisionIncentivosConfig(data: AnyMap | undefined): ComisionIncentivosConfig {
  const ventanaRaw = String(data?.ventana ?? "semana").trim().toLowerCase();
  const ventana: VentanaIncentivo = ventanaRaw === "mes" ? "mes" : "semana";
  const escalones = parseEscalones(data?.escalones);
  return {
    activo: data?.activo === true && escalones.length > 0,
    ventana,
    escalones: escalones.length > 0
      ? escalones
      : [{ viajesMinimos: 20, comisionPct: 15, etiqueta: "Conductor activo" }],
  };
}

export function invalidateComisionIncentivosCache(): void {
  _cfgCache = null;
}

export async function getComisionIncentivosTaxistaConfigCached(): Promise<ComisionIncentivosConfig> {
  const now = Date.now();
  if (_cfgCache && now - _cfgCache.loadedAt < TTL_MS) {
    return _cfgCache.cfg;
  }
  try {
    const snap = await db().collection("config").doc(CONFIG_DOC).get();
    const cfg = parseComisionIncentivosConfig((snap.data() ?? {}) as AnyMap);
    _cfgCache = { loadedAt: now, cfg };
    return cfg;
  } catch (e) {
    console.error("[getComisionIncentivosTaxistaConfigCached]", e);
    const cfg = parseComisionIncentivosConfig(undefined);
    _cfgCache = { loadedAt: now, cfg: { ...cfg, activo: false } };
    return _cfgCache.cfg;
  }
}

/** Clave de ventana para reiniciar contador (semana ISO o mes calendario). */
export function ventanaClave(ventana: VentanaIncentivo, now: Date): string {
  if (ventana === "mes") {
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
  }
  const d = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const weekNo = Math.ceil((((d.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(weekNo).padStart(2, "0")}`;
}

function resolverEscalon(
  viajes: number,
  globalPct: number,
  escalones: EscalonIncentivo[],
): {
  pctEfectiva: number;
  activo: EscalonIncentivo | null;
  proximo: EscalonIncentivo | null;
} {
  let activo: EscalonIncentivo | null = null;
  for (let i = escalones.length - 1; i >= 0; i--) {
    if (viajes >= escalones[i].viajesMinimos) {
      activo = escalones[i];
      break;
    }
  }
  let proximo: EscalonIncentivo | null = null;
  for (const e of escalones) {
    if (e.viajesMinimos > viajes) {
      proximo = e;
      break;
    }
  }
  let pctEfectiva = globalPct;
  if (activo) {
    pctEfectiva = Math.min(globalPct, activo.comisionPct);
  }
  return { pctEfectiva: clampPct(pctEfectiva), activo, proximo };
}

/**
 * Incrementa contador del taxista y resuelve % de comisión (solo en finalizar).
 * Fuente de verdad del conteo: doc `taxistas_stats/{uid}` (escrito por Admin SDK).
 */
export function aplicarIncentivoComisionEnFinalizar(args: {
  cfg: ComisionIncentivosConfig;
  globalPct: number;
  statsData: AnyMap | undefined;
  now: Date;
}): IncentivoFinalizarResult {
  const globalPct = clampPct(args.globalPct);
  const stats = args.statsData ?? {};
  const ventana = args.cfg.activo ? args.cfg.ventana : ("semana" as VentanaIncentivo);
  const clave = ventanaClave(ventana, args.now);

  let viajes = 0;
  if (String(stats.ventanaClave ?? "") === clave && String(stats.ventana ?? ventana) === ventana) {
    viajes = Math.max(0, toInt(stats.viajesCompletadosVentana, 0));
  }
  viajes += 1;

  if (!args.cfg.activo) {
    const statsPatch: AnyMap = {
      ventana,
      ventanaClave: clave,
      viajesCompletadosVentana: viajes,
      comisionPctGlobal: globalPct,
      comisionPctActual: globalPct,
      comisionIncentivoActivo: false,
      escalonActivoEtiqueta: "",
      proximoEscalonViajes: null,
      proximoEscalonPct: null,
      proximoEscalonEtiqueta: "",
      updatedAt: FieldValue.serverTimestamp(),
    };
    return {
      pctEfectiva: globalPct,
      statsPatch,
      viajePatch: {
        comisionPorcentajeGlobal: globalPct,
        comisionIncentivoActivo: false,
        comisionIncentivoViajesVentana: viajes,
      },
    };
  }

  const { pctEfectiva, activo, proximo } = resolverEscalon(
    viajes,
    globalPct,
    args.cfg.escalones,
  );

  const statsPatch: AnyMap = {
    ventana,
    ventanaClave: clave,
    viajesCompletadosVentana: viajes,
    comisionPctGlobal: globalPct,
    comisionPctActual: pctEfectiva,
    comisionIncentivoActivo: activo != null && pctEfectiva < globalPct,
    escalonActivoEtiqueta: activo?.etiqueta ?? "",
    proximoEscalonViajes: proximo?.viajesMinimos ?? null,
    proximoEscalonPct: proximo?.comisionPct ?? null,
    proximoEscalonEtiqueta: proximo?.etiqueta ?? "",
    updatedAt: FieldValue.serverTimestamp(),
  };

  const viajePatch: AnyMap = {
    comisionPorcentajeGlobal: globalPct,
    comisionIncentivoActivo: activo != null && pctEfectiva < globalPct,
    comisionIncentivoViajesVentana: viajes,
    comisionIncentivoEscalon: activo?.etiqueta ?? "",
    comisionIncentivoProximoViajes: proximo?.viajesMinimos ?? null,
    comisionIncentivoProximoPct: proximo?.comisionPct ?? null,
  };

  return { pctEfectiva, statsPatch, viajePatch };
}

export function statsDocRef(uidTaxista: string) {
  return db().collection(STATS_COLL).doc(uidTaxista);
}
