import { FieldValue, getFirestore } from "firebase-admin/firestore";



const DOC = "corporativo";

const TTL_MS = 60_000;



type AnyMap = Record<string, unknown>;



export type CorporativoTarifaConfig = {

  modeloTarifa: string;

  minimoViajeRd: number;

  factorKmCarretera: number;

  recargoZonaDificilPorcentaje: number;

  recargoTransferenciaPorcentaje: number;
  tasaImpuestoTransferencia: number;
  retencionIsrPorcentaje: number;

  itbisPorcentaje: number;

  incluirItbisEnPrecioViaje: boolean;

  usarComisionGlobalViaje: boolean;

  comisionPlataformaPorcentaje: number;

  dinamicaBaseRd: number;

  dinamicaPorKmCortoRd: number;

  dinamicaPorKmLargoRd: number;

  dinamicaUmbralKmLargo: number;

  dinamicaPorMinutoRd: number;

  dinamicaMinutosPorKm: number;

  dinamicaMinutosPorParada: number;

  dinamicaMinutosMinimo: number;

  dinamicaMinutosEmbarqueEmpresa: number;

  kmMinimoPorTramo: number;

  dinamicaCargoPorParadaRd: number;

  /** Precio gasolina RD$/litro (referencia RD). */
  precioCombustibleLitroRd: number;

  /** Rendimiento típico urbano (km/l). */
  rendimientoVehiculoKmPorLitro: number;

  /** Multiplicador sobre costo combustible (desgaste, aceite, margen operativo). */
  factorOperativoSobreCombustible: number;

  /** Recargo B2B a la empresa sobre costo operativo calculado (ej. 5 = +5%). */
  recargoEmpresaServicioPorcentaje: number;

};



const DEFAULTS: CorporativoTarifaConfig = {

  modeloTarifa: "dinamica",

  minimoViajeRd: 550,

  factorKmCarretera: 1.15,

  recargoZonaDificilPorcentaje: 0,

  recargoTransferenciaPorcentaje: 0.2,
  tasaImpuestoTransferencia: 0.002,
  retencionIsrPorcentaje: 2,

  itbisPorcentaje: 18,

  incluirItbisEnPrecioViaje: false,

  usarComisionGlobalViaje: false,

  comisionPlataformaPorcentaje: 10,

  dinamicaBaseRd: 200,

  dinamicaPorKmCortoRd: 18,

  dinamicaPorKmLargoRd: 24,

  dinamicaUmbralKmLargo: 12,

  dinamicaPorMinutoRd: 7,

  dinamicaMinutosPorKm: 1.4,

  dinamicaMinutosPorParada: 5,

  dinamicaMinutosMinimo: 10,

  dinamicaMinutosEmbarqueEmpresa: 12,

  kmMinimoPorTramo: 0.85,

  dinamicaCargoPorParadaRd: 75,

  precioCombustibleLitroRd: 330,

  rendimientoVehiculoKmPorLitro: 11,

  factorOperativoSobreCombustible: 1.35,

  recargoEmpresaServicioPorcentaje: 5,

};



let _cache: { loadedAt: number; cfg: CorporativoTarifaConfig } | null = null;



const db = () => getFirestore();



function num(v: unknown, fallback: number): number {

  const n = Number(v);

  return Number.isFinite(n) ? n : fallback;

}



function clamp(n: number, min: number, max: number): number {

  return Math.min(max, Math.max(min, n));

}



function din(d: AnyMap, nue: string, leg: string, fallback: number): number {

  return num(d[nue] ?? d[leg], fallback);

}



function normalizeModelo(raw: unknown): string {

  const m = String(raw ?? DEFAULTS.modeloTarifa).trim().toLowerCase();

  if (m === "carro") return "carro";

  if (m === "uber_x" || m === "" || m === "dinamica") return "dinamica";

  return String(raw ?? DEFAULTS.modeloTarifa).trim() || "dinamica";

}




function resolverTasaImpuestoTransferencia(d: AnyMap): number {
  const fromSnake = num(d["tasa_impuesto_transferencia"], NaN);
  if (Number.isFinite(fromSnake) && fromSnake >= 0 && fromSnake <= 1) return fromSnake;
  const fromCamel = num(d["tasaImpuestoTransferencia"], NaN);
  if (Number.isFinite(fromCamel) && fromCamel >= 0 && fromCamel <= 1) return fromCamel;
  const pct = num(d["recargoTransferenciaPorcentaje"], NaN);
  if (Number.isFinite(pct)) {
    if (pct === 15 || pct === 6) return 0.002;
    if (pct > 0 && pct <= 1) return pct / 100;
    if (pct > 0 && pct < 0.01) return pct;
    if (pct > 0 && pct < 5) return pct / 100;
  }
  return DEFAULTS.tasaImpuestoTransferencia;
}

export function parseCorporativoTarifaConfig(data: AnyMap | undefined): CorporativoTarifaConfig {

  const d = data ?? {};

  return {

    modeloTarifa: normalizeModelo(d.modeloTarifa),

    minimoViajeRd: Math.max(0, Math.trunc(num(d.minimoViajeRd, DEFAULTS.minimoViajeRd))),

    factorKmCarretera: clamp(num(d.factorKmCarretera, DEFAULTS.factorKmCarretera), 1, 2.5),

    recargoZonaDificilPorcentaje: clamp(

      num(d.recargoZonaDificilPorcentaje, DEFAULTS.recargoZonaDificilPorcentaje),

      0,

      100,

    ),

    tasaImpuestoTransferencia: clamp(resolverTasaImpuestoTransferencia(d), 0, 1),
    recargoTransferenciaPorcentaje: clamp(resolverTasaImpuestoTransferencia(d) * 100, 0, 100),
    retencionIsrPorcentaje: clamp(num(d["retencionIsrPorcentaje"] ?? d["retencion_isr_porcentaje"], DEFAULTS.retencionIsrPorcentaje), 0, 100),


    itbisPorcentaje: clamp(num(d.itbisPorcentaje, DEFAULTS.itbisPorcentaje), 0, 100),

    incluirItbisEnPrecioViaje: d.incluirItbisEnPrecioViaje === true,

    usarComisionGlobalViaje: d.usarComisionGlobalViaje === true,

    comisionPlataformaPorcentaje: clamp(

      num(d.comisionPlataformaPorcentaje, DEFAULTS.comisionPlataformaPorcentaje),

      0,

      100,

    ),

    dinamicaBaseRd: din(d, "dinamicaBaseRd", "uberBaseRd", DEFAULTS.dinamicaBaseRd),

    dinamicaPorKmCortoRd: din(

      d,

      "dinamicaPorKmCortoRd",

      "uberPorKmCortoRd",

      DEFAULTS.dinamicaPorKmCortoRd,

    ),

    dinamicaPorKmLargoRd: din(

      d,

      "dinamicaPorKmLargoRd",

      "uberPorKmLargoRd",

      DEFAULTS.dinamicaPorKmLargoRd,

    ),

    dinamicaUmbralKmLargo: din(

      d,

      "dinamicaUmbralKmLargo",

      "uberUmbralKmLargo",

      DEFAULTS.dinamicaUmbralKmLargo,

    ),

    dinamicaPorMinutoRd: din(

      d,

      "dinamicaPorMinutoRd",

      "uberPorMinutoRd",

      DEFAULTS.dinamicaPorMinutoRd,

    ),

    dinamicaMinutosPorKm: din(

      d,

      "dinamicaMinutosPorKm",

      "uberMinutosPorKm",

      DEFAULTS.dinamicaMinutosPorKm,

    ),

    dinamicaMinutosPorParada: din(

      d,

      "dinamicaMinutosPorParada",

      "uberMinutosPorParada",

      DEFAULTS.dinamicaMinutosPorParada,

    ),

    dinamicaMinutosMinimo: din(

      d,

      "dinamicaMinutosMinimo",

      "uberMinutosMinimo",

      DEFAULTS.dinamicaMinutosMinimo,

    ),

    dinamicaMinutosEmbarqueEmpresa: clamp(
      num(d.dinamicaMinutosEmbarqueEmpresa, DEFAULTS.dinamicaMinutosEmbarqueEmpresa),
      0,
      120,
    ),

    kmMinimoPorTramo: clamp(
      num(d.kmMinimoPorTramo, DEFAULTS.kmMinimoPorTramo),
      0,
      5,
    ),

    dinamicaCargoPorParadaRd: Math.max(
      0,
      Math.trunc(
        num(d.dinamicaCargoPorParadaRd, DEFAULTS.dinamicaCargoPorParadaRd),
      ),
    ),

    precioCombustibleLitroRd: Math.max(
      0,
      Math.trunc(
        num(d.precioCombustibleLitroRd, DEFAULTS.precioCombustibleLitroRd),
      ),
    ),

    rendimientoVehiculoKmPorLitro: clamp(
      num(
        d.rendimientoVehiculoKmPorLitro,
        DEFAULTS.rendimientoVehiculoKmPorLitro,
      ),
      1,
      40,
    ),

    factorOperativoSobreCombustible: clamp(
      num(
        d.factorOperativoSobreCombustible,
        DEFAULTS.factorOperativoSobreCombustible,
      ),
      1,
      3,
    ),

    recargoEmpresaServicioPorcentaje: clamp(
      num(
        d.recargoEmpresaServicioPorcentaje,
        DEFAULTS.recargoEmpresaServicioPorcentaje,
      ),
      0,
      50,
    ),

  };

}



export function invalidateCorporativoTarifaConfigCache(): void {

  _cache = null;

}



export async function getCorporativoTarifaConfigCached(): Promise<CorporativoTarifaConfig> {

  const now = Date.now();

  if (_cache && now - _cache.loadedAt < TTL_MS) return _cache.cfg;

  try {

    const snap = await db().collection("config").doc(DOC).get();

    const cfg = parseCorporativoTarifaConfig(snap.data() as AnyMap | undefined);

    _cache = { loadedAt: now, cfg };

    return cfg;

  } catch (e) {

    console.error("[getCorporativoTarifaConfigCached]", e);

    _cache = { loadedAt: now, cfg: DEFAULTS };

    return DEFAULTS;

  }

}



export async function getComisionCorporativoPorcentajeCached(

  globalPct: number,

): Promise<number> {

  const cfg = await getCorporativoTarifaConfigCached();

  if (cfg.usarComisionGlobalViaje) return clamp(globalPct, 0, 100);

  return cfg.comisionPlataformaPorcentaje;

}



export function distanciaKmLineaRectaRuta(args: {

  origenLat: number;

  origenLon: number;

  pasajeros: Array<{ lat: number; lon: number }>;

  kmMinimoPorTramo?: number;

}): number {

  const pts = args.pasajeros.filter(

    (p) => Number.isFinite(p.lat) && Number.isFinite(p.lon) && !(p.lat === 0 && p.lon === 0),

  );

  if (pts.length === 0) return 0;

  const minLeg = Math.max(0, Number(args.kmMinimoPorTramo ?? DEFAULTS.kmMinimoPorTramo));

  let total = 0;

  let lat = args.origenLat;

  let lon = args.origenLon;

  for (const p of pts) {

    const leg = haversineKm(lat, lon, p.lat, p.lon);

    total += minLeg > 0 ? Math.max(leg, minLeg) : leg;

    lat = p.lat;

    lon = p.lon;

  }

  return total;

}



function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {

  const r = 6371;

  const dLat = deg2rad(lat2 - lat1);

  const dLon = deg2rad(lon2 - lon1);

  const a =

    Math.sin(dLat / 2) ** 2 +

    Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) * Math.sin(dLon / 2) ** 2;

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return r * c;

}



function deg2rad(deg: number): number {

  return (deg * Math.PI) / 180;

}



function esModeloDinamica(modelo: string): boolean {

  const m = (modelo || "dinamica").trim().toLowerCase();

  return m !== "carro";

}



function cargoKmDinamica(km: number, cfg: CorporativoTarifaConfig): number {

  const k = clamp(km, 0, 500);

  const umbral = cfg.dinamicaUmbralKmLargo;

  if (k <= umbral) return k * cfg.dinamicaPorKmCortoRd;

  return umbral * cfg.dinamicaPorKmCortoRd + (k - umbral) * cfg.dinamicaPorKmLargoRd;

}



function minutosEstimadosDinamica(

  km: number,

  cfg: CorporativoTarifaConfig,

  numParadas = 1,

): number {

  const paradas = Math.max(1, numParadas);

  const embarque = cfg.dinamicaMinutosEmbarqueEmpresa;

  const porTiempo = km * cfg.dinamicaMinutosPorKm;

  const porEntregas = paradas * cfg.dinamicaMinutosPorParada;

  return Math.max(cfg.dinamicaMinutosMinimo, embarque + porTiempo + porEntregas);

}



/** Precio base Carro simplificado (modelo legacy). */

export function precioBaseCarroReferenciaSync(km: number): number {

  const k = clamp(km, 1, 500);

  const base = 50;

  const porKm = 25;

  const minimo = 150;

  const nucleo = base + k * porKm;

  return Math.max(nucleo, minimo);

}



function costoCombustibleRdPorKm(cfg: CorporativoTarifaConfig): number {

  const litro = Math.max(0, cfg.precioCombustibleLitroRd);

  const rend = Math.max(1, cfg.rendimientoVehiculoKmPorLitro);

  return litro / rend;

}



function cargoCombustibleOperativoRd(

  kmCotizados: number,

  cfg: CorporativoTarifaConfig,

): number {

  const factor = Math.max(1, cfg.factorOperativoSobreCombustible);

  return Math.round(kmCotizados * costoCombustibleRdPorKm(cfg) * factor);

}



/** Liquidación Ley 30-26: 10% RAI / 90% chofer sobre Precio_Base. */
export function liquidarPrecioBaseCorporativo(
  precioBaseServicioRd: number,
  cfg: CorporativoTarifaConfig,
  extras: AnyMap = {},
): ReturnType<typeof calcularPrecioCorporativoDesdeKm> {
  const base = Math.max(0, Math.round(precioBaseServicioRd));
  const tasa = Number.isFinite(cfg.tasaImpuestoTransferencia)
    ? cfg.tasaImpuestoTransferencia
    : resolverTasaImpuestoTransferencia({
        tasaImpuestoTransferencia: cfg.tasaImpuestoTransferencia,
        recargoTransferenciaPorcentaje: cfg.recargoTransferenciaPorcentaje,
      } as AnyMap);
  const impuestoTransferenciaRd = Math.round(base * tasa);
  const montoTotalFacturaRd = base + impuestoTransferenciaRd;
  const comisionPct = clamp(cfg.comisionPlataformaPorcentaje, 0, 100);
  const comisionPlataformaRd = Math.round(base * (comisionPct / 100));
  const pagoChoferRd = Math.round(base * ((100 - comisionPct) / 100));
  const retencionIsrRd = Math.round(
    base * ((cfg.retencionIsrPorcentaje ?? 2) / 100),
  );

  return {
    kmLineaRecta: 0,
    kmCotizados: 0,
    tarifaBaseRd: 0,
    recargoZonaRd: 0,
    subtotalFacturaRd: base,
    precioBaseServicioRd: base,
    cargoCompaniaRd: comisionPlataformaRd,
    comisionPlataformaRd,
    pagoChoferRd,
    retencionIsrRd,
    impuestoTransferenciaRd,
    tasa_impuesto_transferencia: tasa,
    tasaImpuestoTransferencia: tasa,
    recargoFacturaRd: impuestoTransferenciaRd,
    recargoTransferenciaRd: impuestoTransferenciaRd,
    montoTotalFacturaRd,
    precioViajeRd: montoTotalFacturaRd,
    gananciaRaiEstimadaRd: comisionPlataformaRd,
    itbisRaiEstimadoRd: 0,
    itbisRd: 0,
    precioConItbisRd: montoTotalFacturaRd,
    modeloTarifa: normalizeModelo(cfg.modeloTarifa),
    cargoKmRd: 0,
    cargoTiempoRd: 0,
    minutosEstimados: 0,
    ...extras,
  };
}



/** Desglose unificado: tarifa contratada, plantilla o cálculo automático RD. */
export function construirDesgloseTarifaCorporativoViaje(args: {
  kmLineaRecta: number;
  cfg: CorporativoTarifaConfig;
  numParadas: number;
  tarifaContratadaRd?: number;
  precioAcordadoPlantillaRd?: number;
}): ReturnType<typeof calcularPrecioCorporativoDesdeKm> {
  const kmLinea = args.kmLineaRecta;
  const kmCotizados = clamp(kmLinea * args.cfg.factorKmCarretera, 0.1, 500);
  const tarifa = Math.max(0, Math.trunc(Number(args.tarifaContratadaRd ?? 0)));
  if (tarifa > 0) {
    return liquidarPrecioBaseCorporativo(tarifa, args.cfg, {
      kmLineaRecta: kmLinea,
      kmCotizados,
      tarifaOrigen: "contratada",
    });
  }
  const acordado = Math.max(
    0,
    Math.trunc(Number(args.precioAcordadoPlantillaRd ?? 0)),
  );
  if (acordado > 0) {
    return liquidarPrecioBaseCorporativo(acordado, args.cfg, {
      kmLineaRecta: kmLinea,
      kmCotizados,
      tarifaOrigen: "plantilla",
    });
  }
  return calcularPrecioCorporativoDesdeKm(
    kmLinea,
    args.cfg,
    args.numParadas,
  );
}



export function calcularPrecioCorporativoDesdeKm(
  kmLineaRecta: number,
  cfg: CorporativoTarifaConfig,
  numParadas = 1,
): {
  kmLineaRecta: number;
  kmCotizados: number;
  tarifaBaseRd: number;
  recargoZonaRd: number;
  subtotalFacturaRd: number;
  precioBaseServicioRd?: number;
  cargoCompaniaRd: number;
  comisionPlataformaRd?: number;
  pagoChoferRd?: number;
  retencionIsrRd?: number;
  impuestoTransferenciaRd?: number;
  tasa_impuesto_transferencia?: number;
  tasaImpuestoTransferencia?: number;
  recargoFacturaRd: number;
  recargoTransferenciaRd: number;
  montoTotalFacturaRd?: number;
  precioViajeRd: number;
  gananciaRaiEstimadaRd: number;
  itbisRaiEstimadoRd: number;
  itbisRd: number;
  precioConItbisRd: number;
  modeloTarifa: string;
  cargoKmRd: number;
  cargoTiempoRd: number;
  minutosEstimados: number;
  cargoCombustibleRd?: number;
  costoOperativoRd?: number;
  recargoEmpresaServicioRd?: number;
  recargoEmpresaServicioPorcentaje?: number;
} {
  if (!(kmLineaRecta > 0)) {
    return {
      kmLineaRecta: 0,
      kmCotizados: 0,
      tarifaBaseRd: 0,
      recargoZonaRd: 0,
      subtotalFacturaRd: 0,
      cargoCompaniaRd: 0,
      recargoFacturaRd: 0,
      recargoTransferenciaRd: 0,
      precioViajeRd: 0,
      gananciaRaiEstimadaRd: 0,
      itbisRaiEstimadoRd: 0,
      itbisRd: 0,
      precioConItbisRd: 0,
      modeloTarifa: normalizeModelo(cfg.modeloTarifa),
      cargoKmRd: 0,
      cargoTiempoRd: 0,
      minutosEstimados: 0,
    };
  }

  const kmCotizados = clamp(kmLineaRecta * cfg.factorKmCarretera, 0.1, 500);
  const modelo = normalizeModelo(cfg.modeloTarifa);

  let tarifaBaseRd: number;
  let cargoKmRd = 0;
  let cargoTiempoRd = 0;
  let minutosEstimados = 0;
  let cargoCombustibleRd = 0;

  if (esModeloDinamica(modelo)) {
    tarifaBaseRd = Math.round(cfg.dinamicaBaseRd);
    const cargoKmTabla = Math.round(cargoKmDinamica(kmCotizados, cfg));
    cargoCombustibleRd = cargoCombustibleOperativoRd(kmCotizados, cfg);
    cargoKmRd = Math.max(cargoKmTabla, cargoCombustibleRd);
    minutosEstimados = Math.round(
      minutosEstimadosDinamica(kmCotizados, cfg, numParadas),
    );
    cargoTiempoRd = Math.round(minutosEstimados * cfg.dinamicaPorMinutoRd);
  } else {
    tarifaBaseRd = Math.round(precioBaseCarroReferenciaSync(kmCotizados));
    cargoCombustibleRd = cargoCombustibleOperativoRd(kmCotizados, cfg);
    cargoKmRd = cargoCombustibleRd;
  }

  const nucleo = tarifaBaseRd + cargoKmRd + cargoTiempoRd;
  const paradas = Math.max(1, numParadas);
  const cargoParadasRd = Math.round(paradas * cfg.dinamicaCargoPorParadaRd);
  const nucleoConParadas = nucleo + cargoParadasRd;
  const recargoZonaRd = Math.round(
    nucleoConParadas * (cfg.recargoZonaDificilPorcentaje / 100),
  );
  let costoOperativoRd = nucleoConParadas + recargoZonaRd;
  if (cfg.minimoViajeRd > 0) {
    costoOperativoRd = Math.max(costoOperativoRd, cfg.minimoViajeRd);
  }
  const recargoEmpPct = clamp(
    cfg.recargoEmpresaServicioPorcentaje ?? DEFAULTS.recargoEmpresaServicioPorcentaje,
    0,
    50,
  );
  const recargoEmpresaServicioRd = Math.round(
    costoOperativoRd * (recargoEmpPct / 100),
  );
  const precioBaseServicioRd = costoOperativoRd + recargoEmpresaServicioRd;

  return liquidarPrecioBaseCorporativo(precioBaseServicioRd, cfg, {
    kmLineaRecta,
    kmCotizados,
    tarifaBaseRd,
    recargoZonaRd,
    cargoKmRd,
    cargoTiempoRd,
    cargoCombustibleRd,
    minutosEstimados,
    cargoParadasRd,
    modeloTarifa: esModeloDinamica(modelo) ? "dinamica" : "carro",
    costoOperativoRd,
    recargoEmpresaServicioRd,
    recargoEmpresaServicioPorcentaje: recargoEmpPct,
    costoCombustibleRdPorKm: Math.round(costoCombustibleRdPorKm(cfg) * 100) / 100,
  });
}

export async function writeCorporativoTarifaConfig(

  cfg: CorporativoTarifaConfig,

): Promise<void> {

  await db()

    .collection("config")

    .doc(DOC)

    .set(

      {

        ...cfg,

        updatedAt: FieldValue.serverTimestamp(),

      },

      { merge: true },

    );

  invalidateCorporativoTarifaConfigCache();

}


