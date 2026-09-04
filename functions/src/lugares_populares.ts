/**
 * Aprende destinos/orígenes frecuentes de viajes FlyGo por región (estilo Uber).
 * Solo Admin SDK escribe; clientes leen para mejorar autocomplete.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

const db = () => getFirestore();

type TipoLugar = "destino" | "origen";

function numCoord(v: unknown): number | null {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function str(v: unknown): string {
  return String(v ?? "").trim();
}

/** Misma lógica que RaiRegionOperativa (Dart). */
export function resolverRegionRd(lat: number, lon: number): string {
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return "rd_otros";
  if (lat < 17.47 || lat > 19.98 || lon < -72.05 || lon > -68.32) return "rd_otros";

  if (lon >= -68.72 && lat >= 18.12 && lat <= 19.35) return "rd_este";
  if (lat >= 19.05 && lat <= 19.55 && lon >= -69.95 && lon <= -69.15) return "rd_samana";
  if (lat >= 18.4 && lat <= 19.05 && lon >= -69.6 && lon <= -68.85) return "rd_san_pedro";
  if (lat >= 18.35 && lat <= 18.68 && lon >= -70.12 && lon <= -69.62) return "rd_metro";
  if (lat >= 18.18 && lat <= 18.42 && lon >= -70.55 && lon <= -69.95) return "rd_valdesia";
  if (lat >= 19.38 && lat <= 19.58 && lon >= -70.92 && lon <= -70.55) return "rd_santiago";
  if (lat >= 19.35 && lat <= 19.95 && lon >= -72.05 && lon <= -71.15) return "rd_noroeste";
  if (lat >= 19.5 && lat <= 19.95 && lon >= -71.25 && lon <= -70.35) return "rd_norte";
  if (lat <= 18.28 && lon >= -72.05 && lon <= -68.9) return "rd_sur";
  if (lat >= 18.75 && lat <= 19.45 && lon >= -71.15 && lon <= -70.15) return "rd_cibao";
  return "rd_otros";
}

function docId(
  region: string,
  tipo: TipoLugar,
  lat: number,
  lon: number,
  placeId?: string,
): string {
  const pid = str(placeId);
  if (pid.length >= 8 && !pid.startsWith("geocoded:") && !pid.startsWith("recent:")) {
    const safe = pid.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 96);
    return `${region}_${tipo}_${safe}`;
  }
  return `${region}_${tipo}_${lat.toFixed(4)}_${lon.toFixed(4)}`;
}

async function incrementLugar(params: {
  region: string;
  tipo: TipoLugar;
  label: string;
  lat: number;
  lon: number;
  placeId?: string;
}): Promise<void> {
  const label = str(params.label);
  if (label.length < 2) return;
  if (Math.abs(params.lat) < 1e-5 && Math.abs(params.lon) < 1e-5) return;

  const id = docId(params.region, params.tipo, params.lat, params.lon, params.placeId);
  await db()
    .collection("lugares_populares_flygo")
    .doc(id)
    .set(
      {
        region: params.region,
        tipo: params.tipo,
        label,
        lat: params.lat,
        lon: params.lon,
        placeId: str(params.placeId),
        count: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}

async function registrarDesdeViaje(data: FirebaseFirestore.DocumentData): Promise<void> {
  const destino = str(data.destino);
  const origen = str(data.origen);
  const latD = numCoord(data.latDestino);
  const lonD = numCoord(data.lonDestino);
  const latO = numCoord(data.latOrigen) ?? numCoord(data.latCliente);
  const lonO = numCoord(data.lonOrigen) ?? numCoord(data.lonCliente);

  if (destino && latD != null && lonD != null) {
    await incrementLugar({
      region: resolverRegionRd(latD, lonD),
      tipo: "destino",
      label: destino,
      lat: latD,
      lon: lonD,
      placeId: str(data.placeIdDestino) || str(data.destinoPlaceId) || undefined,
    });
  }

  if (origen && latO != null && lonO != null) {
    await incrementLugar({
      region: resolverRegionRd(latO, lonO),
      tipo: "origen",
      label: origen,
      lat: latO,
      lon: lonO,
      placeId: str(data.placeIdOrigen) || str(data.origenPlaceId) || undefined,
    });
  }
}

/** Cada viaje nuevo alimenta el ranking de lugares por zona. */
export const onViajeLugaresPopulares = onDocumentCreated(
  "viajes/{viajeId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    try {
      await registrarDesdeViaje(data);
    } catch (e) {
      console.error("[onViajeLugaresPopulares]", e);
    }
  },
);

/** Cuando el usuario confirma origen/destino en el mapa (antes del viaje). */
export const registrarLugarPopularSeleccion = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }

    const label = str(request.data?.label);
    const lat = numCoord(request.data?.lat);
    const lon = numCoord(request.data?.lon);
    const tipoRaw = str(request.data?.tipo).toLowerCase();
    const tipo: TipoLugar = tipoRaw === "origen" ? "origen" : "destino";

    if (label.length < 2 || lat == null || lon == null) {
      throw new HttpsError("invalid-argument", "Datos incompletos");
    }

    try {
      await incrementLugar({
        region: resolverRegionRd(lat, lon),
        tipo,
        label,
        lat,
        lon,
        placeId: str(request.data?.placeId) || undefined,
      });
      return { ok: true };
    } catch (e) {
      console.error("[registrarLugarPopularSeleccion]", e);
      throw new HttpsError("internal", "No se pudo registrar");
    }
  },
);
