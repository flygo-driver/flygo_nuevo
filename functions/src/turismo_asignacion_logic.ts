/**
 * Lógica pura de auto-asignación turismo / liberación al pool (paridad Dart).
 */

export type AnyMap = Record<string, unknown>;

export const CANAL_TURISMO_POOL = "turismo_pool";

export function choferEstadoOperativo(estadoRaw: unknown): boolean {
  const e = String(estadoRaw ?? "").trim().toLowerCase();
  return e === "aprobado" || e === "activo";
}

export function normalizarEstadoViaje(raw: unknown): string {
  const s = String(raw ?? "").trim().toLowerCase();
  if (s === "pendiente_admin" || s === "pendienteadmin") return "pendiente_admin";
  if (s === "pendiente_pago" || s === "pendientepago") return "pendiente_pago";
  if (s === "en_camino_pickup" || s === "encamino_pickup") return "en_camino_pickup";
  if (s === "en_curso" || s === "encurso") return "en_curso";
  return s;
}

export function estadoPermiteAutoAsignacionTurismo(vData: AnyMap): boolean {
  if (String(vData.tipoServicio ?? "").trim() !== "turismo") return false;
  const uidTx = String(vData.uidTaxista ?? vData.taxistaId ?? "").trim();
  if (uidTx) return false;
  const canal = String(vData.canalAsignacion ?? "admin").trim();
  if (canal !== "admin") return false;
  const estado = String(vData.estado ?? "").trim();
  if (estado === "pendiente_admin") return true;
  return normalizarEstadoViaje(estado) === "pendiente" && vData.republicado === true;
}

export function estadoPermiteLiberarAlPool(vData: AnyMap): boolean {
  const estadoRaw = String(vData.estado ?? "").trim();
  const estadoNorm = normalizarEstadoViaje(estadoRaw);
  return (
    estadoRaw === "pendiente_admin" ||
    estadoNorm === "pendiente" ||
    estadoNorm === "pendiente_pago"
  );
}

export function toDateFromUnknown(v: unknown): Date | null {
  if (v && typeof v === "object" && typeof (v as { toDate?: unknown }).toDate === "function") {
    try {
      return (v as { toDate: () => Date }).toDate();
    } catch {
      return null;
    }
  }
  if (v instanceof Date) return v;
  if (typeof v === "number" && Number.isFinite(v)) return new Date(v);
  if (typeof v === "string") {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

export function ventanaPublicacionYAceptacionOk(
  vData: AnyMap,
  now: Date,
  omitirVentanaPublicacion = false,
): boolean {
  if (omitirVentanaPublicacion) return true;
  const acceptAfter = toDateFromUnknown(vData.acceptAfter);
  if (acceptAfter && now < acceptAfter) return false;
  const publishAt = toDateFromUnknown(vData.publishAt);
  if (publishAt && publishAt > now) return false;
  return true;
}

export function pasajerosRequeridos(vData: AnyMap): number {
  const ex = vData.extras;
  if (ex && typeof ex === "object") {
    const map = ex as AnyMap;
    const p = map.pasajeros ?? map.numPasajeros;
    if (p != null) {
      const n = Number.parseInt(String(p), 10);
      if (Number.isFinite(n) && n > 0) return Math.min(60, Math.max(1, n));
    }
  }
  return 1;
}

const CATEGORIAS_DESTINO_TURISMO = new Set([
  "AEROPUERTO",
  "MUELLE",
  "ZONA_COLONIAL",
  "CIUDAD",
  "PLAYA",
  "RESORT",
  "HOTEL",
  "TOUR",
  "PARQUE",
  "MONTANA",
  "CASCADA",
  "LAGO",
  "MUSEO",
  "ATRACCION",
]);

export function esCategoriaDestinoTurismo(raw: unknown): boolean {
  const u = String(raw ?? "").trim().toUpperCase();
  return u.length > 0 && CATEGORIAS_DESTINO_TURISMO.has(u);
}

function codigoVehiculoDesdeCampoDoc(raw: unknown): string | null {
  const t = String(raw ?? "").trim();
  if (!t || t.includes("🏝️")) return null;
  const c = normalizarCodigoTipoTurismo(t, t);
  return c || null;
}

function codigoVehiculoDesdeCotizacionDesglose(vData: AnyMap): string | null {
  const ex = vData.extras;
  if (!ex || typeof ex !== "object") return null;
  const desg = (ex as AnyMap).cotizacionDesglose;
  if (!desg || typeof desg !== "object") return null;
  const clave = String((desg as AnyMap).claveVehiculo ?? "").trim();
  if (!clave) return null;
  return normalizarCodigoTipoTurismo(clave, clave);
}

export function normalizarCodigoTipoTurismo(
  subtipo: unknown,
  tipoVehiculoDoc?: unknown,
): string {
  const from = (raw: unknown): string => {
    const t = String(raw ?? "").trim().toLowerCase();
    if (!t) return "";
    if (t.includes("jeepeta")) return "jeepeta";
    if (t.includes("minivan") || t.includes("minib")) return "minivan";
    if (t.includes("bus") || t.includes("guagua") || t.includes("autobús") || t.includes("autobus")) {
      return "bus";
    }
    if (t.includes("carro")) return "carro";
    if (t === "carro" || t === "jeepeta" || t === "minivan" || t === "bus") return t;
    if (t === "viaje_multi" || t === "ciudad" || t === "interior") return "carro";
    return "";
  };

  const a = from(subtipo);
  if (a) return a;
  const b = from(tipoVehiculoDoc);
  if (b) return b;
  return "carro";
}

export function subtipoTurismoRequeridoDesdeViaje(vData: AnyMap): string {
  const subtipo = String(vData.subtipoTurismo ?? "").trim();
  const tipoOrig = String(vData.tipoVehiculoOriginal ?? "").trim();
  const tipoVeh = String(vData.tipoVehiculo ?? "").trim();

  if (subtipo && !esCategoriaDestinoTurismo(subtipo)) {
    const desdeSubtipo = codigoVehiculoDesdeCampoDoc(subtipo);
    if (desdeSubtipo) return desdeSubtipo;
  }

  const desdeOriginal = codigoVehiculoDesdeCampoDoc(tipoOrig);
  if (desdeOriginal) return desdeOriginal;

  const desdeDesglose = codigoVehiculoDesdeCotizacionDesglose(vData);
  if (desdeDesglose) return desdeDesglose;

  const desdeTipoDoc = codigoVehiculoDesdeCampoDoc(tipoVeh);
  if (desdeTipoDoc) return desdeTipoDoc;

  return "carro";
}

export function capacidadPorTipoVehiculo(tipo: string): number {
  switch (tipo.toLowerCase()) {
    case "jeepeta":
      return 6;
    case "minivan":
      return 8;
    case "bus":
      return 25;
    case "carro":
    default:
      return 4;
  }
}

export function capacidadDesdeVehiculoMap(v: AnyMap, tipoFallback: string): number {
  const c = v.capacidad ?? v.capacidadPasajeros;
  if (typeof c === "number" && Number.isFinite(c)) {
    return Math.min(60, Math.max(1, Math.round(c)));
  }
  if (c != null) {
    const p = Number.parseInt(String(c), 10);
    if (Number.isFinite(p)) return Math.min(60, Math.max(1, p));
  }
  const t = String(v.tipo ?? tipoFallback);
  return capacidadPorTipoVehiculo(t);
}

export function vehiculoQueCoincide(
  vehiculos: unknown,
  tipoReq: string,
): AnyMap | null {
  const t = normalizarCodigoTipoTurismo(tipoReq, tipoReq);
  if (!Array.isArray(vehiculos)) return null;
  for (const v of vehiculos) {
    if (!v || typeof v !== "object") continue;
    const map = v as AnyMap;
    const vt = normalizarCodigoTipoTurismo(map.tipo, map.tipoLabel);
    if (vt === t) return map;
  }
  return null;
}

function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function distanciaKmHastaOrigen(
  chofer: AnyMap,
  latO: number,
  lonO: number,
): number | null {
  let lat: number | null = null;
  let lon: number | null = null;
  const u = chofer.ultimaUbicacion;
  if (u && typeof u === "object") {
    const geo = u as { latitude?: unknown; longitude?: unknown };
    if (typeof geo.latitude === "number" && typeof geo.longitude === "number") {
      lat = geo.latitude;
      lon = geo.longitude;
    }
  }
  if (lat == null || lon == null) {
    const ubic = chofer.ubicacion;
    if (ubic && typeof ubic === "object") {
      const m = ubic as AnyMap;
      const la = m.lat;
      const lo = m.lon;
      if (typeof la === "number" && typeof lo === "number") {
        lat = la;
        lon = lo;
      }
    }
  }
  if (lat == null || lon == null) return null;
  return haversineKm(latO, lonO, lat, lon);
}

export type ChoferCandidatoSort = {
  id: string;
  data: AnyMap;
  distanciaKm: number | null;
};

export function ordenarCandidatosPorDistancia(
  candidatos: ChoferCandidatoSort[],
): ChoferCandidatoSort[] {
  return [...candidatos].sort((a, b) => {
    if (a.distanciaKm == null && b.distanciaKm == null) return 0;
    if (a.distanciaKm == null) return 1;
    if (b.distanciaKm == null) return -1;
    return a.distanciaKm - b.distanciaKm;
  });
}

export function filtrarCandidatoTurismo(args: {
  choferData: AnyMap;
  subtipoTurismo: string;
  pasajeros: number;
  latO: number;
  lonO: number;
  radioKm: number;
}): { ok: boolean; vehiculo: AnyMap | null; distanciaKm: number | null } {
  if (!choferEstadoOperativo(args.choferData.estado)) {
    return { ok: false, vehiculo: null, distanciaKm: null };
  }
  if (args.choferData.disponible !== true) {
    return { ok: false, vehiculo: null, distanciaKm: null };
  }
  const veh = vehiculoQueCoincide(args.choferData.vehiculos, args.subtipoTurismo);
  if (!veh) return { ok: false, vehiculo: null, distanciaKm: null };
  const subtipoNorm = normalizarCodigoTipoTurismo(
    args.subtipoTurismo,
    args.subtipoTurismo,
  );
  if (capacidadDesdeVehiculoMap(veh, subtipoNorm) < args.pasajeros) {
    return { ok: false, vehiculo: null, distanciaKm: null };
  }
  const dk = distanciaKmHastaOrigen(args.choferData, args.latO, args.lonO);
  if (dk != null && dk > args.radioKm) {
    return { ok: false, vehiculo: null, distanciaKm: dk };
  }
  return { ok: true, vehiculo: veh, distanciaKm: dk };
}
