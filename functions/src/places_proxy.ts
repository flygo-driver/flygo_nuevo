/**
 * Proxy Google Places para web/laptop (el navegador no puede llamar
 * maps.googleapis.com/place/* por CORS). Móvil sigue usando REST directo.
 */
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function placesApiKey(): string {
  const fromEnv = str(process.env.GOOGLE_PLACES_API_KEY);
  if (fromEnv) return fromEnv;
  // Misma clave que la app móvil (ya expuesta en cliente). Web la usa solo vía Functions.
  return "AIzaSyAPMeBX8oZCGJsb8iurATEWjePNTUn0ECs";
}

async function googlePlacesGet(
  path: string,
  params: Record<string, string>,
): Promise<AnyMap> {
  const key = placesApiKey();
  if (!key) {
    throw new HttpsError("failed-precondition", "Falta GOOGLE_PLACES_API_KEY");
  }
  const qs = new URLSearchParams({ ...params, key, language: "es" });
  const url = `https://maps.googleapis.com${path}?${qs.toString()}`;
  const res = await fetch(url);
  if (!res.ok) {
    logger.warn("places proxy http", { status: res.status, path });
    throw new HttpsError("unavailable", "Google Places no respondió");
  }
  return (await res.json()) as AnyMap;
}

function normalizeCountryCode(raw: unknown): string {
  const c = str(raw).toLowerCase();
  if (!c) return "do";
  if (
    c === "do" ||
    c === "rd" ||
    c.includes("dominic") ||
    c.includes("república") ||
    c.includes("republica")
  ) {
    return "do";
  }
  return c.length === 2 ? c : "do";
}

/** Autocomplete estilo Google (calles, POI, barrios en RD). */
export const placesAutocomplete = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }
    const input = str(request.data?.input);
    if (input.length < 1) {
      return { status: "OK", predictions: [] as AnyMap[] };
    }

    const params: Record<string, string> = { input };
    const country = normalizeCountryCode(request.data?.country);
    params.components = `country:${country}`;

    const sessiontoken = str(request.data?.sessiontoken);
    if (sessiontoken) params.sessiontoken = sessiontoken;

    const biasLat = Number(request.data?.biasLat);
    const biasLon = Number(request.data?.biasLon);
    if (Number.isFinite(biasLat) && Number.isFinite(biasLon)) {
      params.location = `${biasLat},${biasLon}`;
      params.radius = "150000";
      params.origin = `${biasLat},${biasLon}`;
    } else {
      params.location = "18.7357,-70.1627";
      params.radius = "180000";
    }

    try {
      const json = await googlePlacesGet(
        "/maps/api/place/autocomplete/json",
        params,
      );
      const status = str(json.status) || "UNKNOWN";
      const list = Array.isArray(json.predictions) ? json.predictions : [];
      return { status, predictions: list };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("placesAutocomplete", e);
      throw new HttpsError("internal", "Error en autocomplete");
    }
  },
);

/** Place Details (coords + dirección formateada). */
export const placesDetails = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }
    const placeId = str(request.data?.placeId);
    if (!placeId) {
      throw new HttpsError("invalid-argument", "Falta placeId");
    }

    const params: Record<string, string> = {
      place_id: placeId,
      fields: "name,formatted_address,geometry,address_components",
    };
    const sessiontoken = str(request.data?.sessiontoken);
    if (sessiontoken) params.sessiontoken = sessiontoken;

    try {
      const json = await googlePlacesGet(
        "/maps/api/place/details/json",
        params,
      );
      return {
        status: str(json.status) || "UNKNOWN",
        result: (json.result as AnyMap) ?? null,
      };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("placesDetails", e);
      throw new HttpsError("internal", "Error en place details");
    }
  },
);

/** Reverse geocoding (cualquier punto del mapa → dirección Google). */
export const placesReverseGeocode = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }
    const lat = Number(request.data?.lat);
    const lon = Number(request.data?.lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
      throw new HttpsError("invalid-argument", "Faltan coordenadas");
    }

    const params: Record<string, string> = {
      latlng: `${lat},${lon}`,
      language: "es",
    };

    try {
      const json = await googlePlacesGet("/maps/api/geocode/json", params);
      return {
        status: str(json.status) || "UNKNOWN",
        results: Array.isArray(json.results) ? json.results : [],
      };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("placesReverseGeocode", e);
      throw new HttpsError("internal", "Error en reverse geocode");
    }
  },
);

/** Find Place From Text — fallback de geocoding en web/laptop. */
export const placesFindFromText = onCall(
  { region: "us-central1", cors: true },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "No autenticado");
    }
    const input = str(request.data?.input);
    if (input.length < 1) {
      return { status: "ZERO_RESULTS", candidates: [] as AnyMap[] };
    }

    const params: Record<string, string> = {
      input,
      inputtype: "textquery",
      fields: "place_id,name,formatted_address,geometry",
    };
    const country = normalizeCountryCode(request.data?.country);
    const biasLat = Number(request.data?.biasLat);
    const biasLon = Number(request.data?.biasLon);
    if (Number.isFinite(biasLat) && Number.isFinite(biasLon)) {
      params.locationbias = `circle:120000@${biasLat},${biasLon}`;
    } else {
      // Sesgo centro RD (Santo Domingo) para resultados locales.
      params.locationbias = "circle:180000@18.7357,-70.1627";
    }
    if (country) {
      params.region = country;
    }

    try {
      const json = await googlePlacesGet(
        "/maps/api/place/findplacefromtext/json",
        params,
      );
      return {
        status: str(json.status) || "UNKNOWN",
        candidates: Array.isArray(json.candidates) ? json.candidates : [],
      };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("placesFindFromText", e);
      throw new HttpsError("internal", "Error en find place");
    }
  },
);
