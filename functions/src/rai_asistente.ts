/**
 * Asistente RAI para clientes — Gemini (capa gratuita de Google AI Studio).
 *
 * Configuración (producción):
 *   firebase functions:secrets:set GEMINI_API_KEY
 * o variable GEMINI_API_KEY en el entorno de despliegue.
 *
 * Si no hay clave, la app usa conocimiento local embebido (sin costo).
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const geminiApiKey = defineSecret("GEMINI_API_KEY");

const DAILY_LIMIT = 50;
const MODEL = "gemini-2.0-flash-lite";

const SYSTEM_PROMPT = `
Eres RAI, el asistente oficial de la app móvil RAI Driver (República Dominicana).
Responde SIEMPRE en español dominicano, claro, amable y breve (máximo 120 palabras en "reply").

CONOCIMIENTO DE LA APP (no inventes funciones que no existen):
- RAI Driver conecta clientes con conductores (taxi/carro, motor/moto, turismo, BOLA pueblo a pueblo, viajes programados y pools/giras).
- Viaje AHORA: origen = GPS del cliente; el cliente elige destino y ve precio antes de confirmar.
- Viaje PROGRAMADO: puede elegir origen y destino con anticipación.
- Motor: pantalla estilo mapa; solo destino; origen automático por GPS.
- Turismo: destinos turísticos; puede haber asignación automática o pool turístico.
- Pagos: efectivo o transferencia al conductor; la app registra total y comisiones.
- Sin internet: puede verse un precio ESTIMADO (referencia); NO se puede confirmar viaje hasta volver la conexión.
- Soporte humano: correo, teléfono y WhatsApp desde menú Soporte.
- Perfil cliente (opcional para pedir viajes): nombre (mín. 2 letras) y teléfono (mín. 7 dígitos) en Cuenta → Configuración de perfil. Foto opcional.
- Si recibes CONTEXTO_PERFIL del usuario, indica con precisión qué falta (nombre, teléfono, foto recomendada). Sugiere open_perfil si falta algo importante.
- NO puedes confirmar viajes, cambiar tarifas, asignar conductores ni acceder a cuentas ajenas.

DIRECCIONES COMPLEJAS EN RD:
- Si el usuario describe un lugar impreciso, normaliza búsquedas cortas para Google Places (sector, calle, referencia, ciudad).
- Devuelve addressQuery (principal) y addressQueries (2-4 variantes: sector, ciudad, referencia, RD).
- Ejemplo: "colmado de la esquina en Los Mina" → addressQuery: "Los Minas Santo Domingo"
- Aeropuertos: SDQ (Las Américas), PUJ (Punta Cana), STI (Cibao), POP (Puerto Plata).

ACCIONES SUGERIDAS (campo suggestedAction, solo uno):
- none — solo información
- open_motor — quiere pedir motor/moto ya
- open_taxi — taxi/carro ahora o programar
- open_turismo — viaje turístico
- open_soporte — problema, reclamo, emergencia humana
- open_mis_viajes — historial o viaje en curso
- open_perfil — completar nombre, teléfono o foto de perfil

FORMATO DE RESPUESTA: un único objeto JSON válido, sin markdown, sin texto extra:
{
  "reply": "texto para el usuario",
  "addressQuery": "búsqueda principal o null",
  "addressQueries": ["variante1", "variante2"],
  "suggestedAction": "none|open_motor|open_taxi|open_turismo|open_soporte|open_mis_viajes|open_perfil"
}
`.trim();

type HistoryItem = { role?: string; text?: string };
type AssistantPayload = {
  reply: string;
  addressQuery: string | null;
  addressQueries: string[];
  suggestedAction: string;
};

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function todayKey(): string {
  return new Date().toISOString().slice(0, 10);
}

function esSolicitudViaje(action: string): boolean {
  return action === "open_taxi" || action === "open_motor" || action === "open_turismo";
}

async function logAsistenteMensaje(params: {
  uid: string;
  message: string;
  reply: string;
  suggestedAction: string;
  addressQuery: string | null;
  source: string;
}): Promise<void> {
  try {
    await getFirestore().collection("rai_asistente_mensajes").add({
      uid: params.uid,
      message: params.message.slice(0, 1200),
      reply: params.reply.slice(0, 2000),
      suggestedAction: params.suggestedAction,
      addressQuery: params.addressQuery,
      source: params.source,
      solicitaViaje: esSolicitudViaje(params.suggestedAction),
      day: todayKey(),
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    logger.warn("[RAI_ASISTENTE] log mensaje", e);
  }
}

async function assertDailyQuota(uid: string): Promise<void> {
  const ref = getFirestore().collection("rai_asistente_usage").doc(uid);
  const day = todayKey();
  await getFirestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() ?? {};
    const storedDay = str(data.day);
    let count = typeof data.count === "number" ? data.count : 0;
    if (storedDay !== day) count = 0;
    if (count >= DAILY_LIMIT) {
      throw new HttpsError(
        "resource-exhausted",
        "Límite diario del asistente alcanzado. Usa soporte humano o intenta mañana.",
      );
    }
    tx.set(
      ref,
      {
        day,
        count: count + 1,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
}

function buildGeminiContents(
  message: string,
  history: HistoryItem[],
): { role: string; parts: { text: string }[] }[] {
  const contents: { role: string; parts: { text: string }[] }[] = [];
  for (const h of history.slice(-8)) {
    const text = str(h.text);
    if (!text) continue;
    const role = str(h.role).toLowerCase() === "assistant" ? "model" : "user";
    contents.push({ role, parts: [{ text }] });
  }
  contents.push({ role: "user", parts: [{ text: message }] });
  return contents;
}

function parseAssistantJson(raw: string): AssistantPayload | null {
  const trimmed = raw.trim();
  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    const obj = JSON.parse(trimmed.slice(start, end + 1)) as Record<string, unknown>;
    const reply = str(obj.reply);
    if (!reply) return null;
    const aq = str(obj.addressQuery);
    const action = str(obj.suggestedAction) || "none";
    const queriesRaw = obj.addressQueries;
    const addressQueries: string[] = [];
    if (Array.isArray(queriesRaw)) {
      for (const item of queriesRaw) {
        const s = str(item);
        if (s.length >= 2 && !addressQueries.includes(s)) addressQueries.push(s);
      }
    }
    if (aq.length >= 2 && !addressQueries.includes(aq)) {
      addressQueries.unshift(aq);
    }
    const allowed = new Set([
      "none",
      "open_motor",
      "open_taxi",
      "open_turismo",
      "open_soporte",
      "open_mis_viajes",
      "open_perfil",
    ]);
    return {
      reply,
      addressQuery: aq.length > 0 ? aq : null,
      addressQueries,
      suggestedAction: allowed.has(action) ? action : "none",
    };
  } catch {
    return null;
  }
}

async function callGemini(
  apiKey: string,
  message: string,
  history: HistoryItem[],
  profileContext?: Record<string, unknown>,
): Promise<AssistantPayload | null> {
  let systemText = SYSTEM_PROMPT;
  if (profileContext && Object.keys(profileContext).length > 0) {
    systemText += `\n\nCONTEXTO_PERFIL_USUARIO (datos reales de su cuenta, no inventes otros):\n${JSON.stringify(profileContext)}`;
  }

  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${encodeURIComponent(apiKey)}`;

  const body = {
    systemInstruction: { parts: [{ text: systemText }] },
    contents: buildGeminiContents(message, history),
    generationConfig: {
      temperature: 0.35,
      maxOutputTokens: 512,
      responseMimeType: "application/json",
    },
  };

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const errText = await res.text();
    logger.warn("[RAI_ASISTENTE] Gemini HTTP", res.status, errText.slice(0, 400));
    return null;
  }

  const json = (await res.json()) as {
    candidates?: { content?: { parts?: { text?: string }[] } }[];
  };
  const text = str(json.candidates?.[0]?.content?.parts?.[0]?.text);
  if (!text) return null;
  return parseAssistantJson(text);
}

export const raiAsistenteCliente = onCall(
  {
    region: "us-central1",
    secrets: [geminiApiKey],
    maxInstances: 8,
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
    }

    const message = str(request.data?.message);
    if (message.length < 2) {
      throw new HttpsError("invalid-argument", "Escribe un mensaje.");
    }
    if (message.length > 1200) {
      throw new HttpsError("invalid-argument", "Mensaje demasiado largo.");
    }

    const history = Array.isArray(request.data?.history)
      ? (request.data.history as HistoryItem[])
      : [];

    const profileContext =
      request.data?.profileContext &&
      typeof request.data.profileContext === "object"
        ? (request.data.profileContext as Record<string, unknown>)
        : undefined;

    await assertDailyQuota(request.auth.uid);

    const apiKey = geminiApiKey.value().trim();
    if (!apiKey) {
      return {
        source: "cloud_no_key",
        useLocalFallback: true,
      };
    }

    try {
      const parsed = await callGemini(apiKey, message, history, profileContext);
      if (!parsed) {
        return { source: "cloud_error", useLocalFallback: true };
      }
      await logAsistenteMensaje({
        uid: request.auth.uid,
        message,
        reply: parsed.reply,
        suggestedAction: parsed.suggestedAction,
        addressQuery: parsed.addressQuery,
        source: "gemini",
      });
      return {
        source: "gemini",
        useLocalFallback: false,
        reply: parsed.reply,
        addressQuery: parsed.addressQuery,
        addressQueries: parsed.addressQueries,
        suggestedAction: parsed.suggestedAction,
      };
    } catch (e) {
      logger.error("[RAI_ASISTENTE] error", e);
      return { source: "cloud_error", useLocalFallback: true };
    }
  },
);
