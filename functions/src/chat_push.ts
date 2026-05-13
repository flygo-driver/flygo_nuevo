/**
 * Push FCM al recibir mensajes en chats de viaje + aviso de intento de llamada/WhatsApp.
 *
 * Tokens: `push_tokens/{uid}.tokens[]` (y fallback `usuarios/{uid}.pushToken`).
 */
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = () => getFirestore();
const messaging = () => getMessaging();

const ANDROID_CHANNEL = "rai_driver_notifications";

function str(v: unknown): string {
  return String(v ?? "").trim();
}

async function tokensForUser(uid: string): Promise<string[]> {
  const tokSnap = await db().collection("push_tokens").doc(uid).get();
  const raw = tokSnap.data()?.tokens;
  const fromArr = Array.isArray(raw)
    ? raw.filter((t): t is string => typeof t === "string" && t.length > 12)
    : [];
  if (fromArr.length > 0) return [...new Set(fromArr)];
  const uSnap = await db().collection("usuarios").doc(uid).get();
  const single = str(uSnap.data()?.pushToken);
  return single.length > 12 ? [single] : [];
}

async function sendToTokens(
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  if (tokens.length === 0) {
    logger.info("[CHAT_NOTIFICACION] sin tokens FCM");
    return;
  }
  const message = {
    tokens,
    notification: { title, body },
    data,
    android: {
      notification: { channelId: ANDROID_CHANNEL, sound: "default" },
    },
    apns: {
      payload: {
        aps: { sound: "default", badge: 1 },
      },
    },
  };
  const res = await messaging().sendEachForMulticast(message);
  logger.info(
    `[CHAT_NOTIFICACION] FCM multicast ok=${res.successCount} fail=${res.failureCount}`,
  );
}

/** Destinatario: viaje (chatId == viajeId) o chat con participantes. */
async function resolveRecipientUid(
  chatId: string,
  senderUid: string,
): Promise<string | null> {
  const vSnap = await db().collection("viajes").doc(chatId).get();
  if (vSnap.exists) {
    const d = vSnap.data() ?? {};
    const cliente = str(d.uidCliente) || str(d.clienteId);
    const taxista = str(d.uidTaxista) || str(d.taxistaId);
    const ids = [cliente, taxista].filter((x) => x.length > 0);
    for (const id of ids) {
      if (id !== senderUid) return id;
    }
    return null;
  }
  const cSnap = await db().collection("chats").doc(chatId).get();
  const part = cSnap.data()?.participantes;
  if (!Array.isArray(part)) return null;
  const others = part
    .map((x) => str(x))
    .filter((x) => x.length > 0 && x !== senderUid);
  return others[0] ?? null;
}

export const onChatMensajeCreatedPush = onDocumentCreated(
  {
    document: "chats/{chatId}/mensajes/{msgId}",
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const chatId = str(event.params.chatId);
    const data = snap.data();
    const de = str(data?.de);
    const texto = str(data?.texto);
    if (!de || !texto) {
      logger.info("[CHAT_NOTIFICACION] skip: sin de/texto");
      return;
    }
    const dest = await resolveRecipientUid(chatId, de);
    if (!dest) {
      logger.info("[CHAT_NOTIFICACION] skip: sin destinatario", { chatId, de });
      return;
    }
    const tokens = await tokensForUser(dest);
    const preview = texto.length > 140 ? `${texto.slice(0, 137)}…` : texto;
    logger.info(`[CHAT_NOTIFICACION] onCreate push → ${dest} tokens=${tokens.length}`);
    await sendToTokens(tokens, "Mensaje en tu viaje RAI", preview, {
      type: "trip_chat_message",
      viajeId: chatId,
      senderUid: de,
    });
  },
);

export const notifyViajeComunicacionIntento = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "No autenticado");
  const viajeId = str(request.data?.viajeId);
  const tipoRaw = str(request.data?.tipo).toLowerCase();
  const tipo = tipoRaw === "whatsapp" ? "whatsapp" : "llamada";
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const vSnap = await db().collection("viajes").doc(viajeId).get();
  if (!vSnap.exists) throw new HttpsError("not-found", "Viaje no existe");
  const vd = vSnap.data() ?? {};
  const cliente = str(vd.uidCliente) || str(vd.clienteId);
  const taxista = str(vd.uidTaxista) || str(vd.taxistaId);
  let dest = "";
  if (uid === cliente) dest = taxista;
  else if (uid === taxista) dest = cliente;
  else {
    throw new HttpsError("permission-denied", "No participás en este viaje");
  }
  if (!dest) {
    logger.info("[CHAT_NOTIFICACION] notifyIntento: sin contraparte aún", { viajeId });
    return { ok: true, skipped: true };
  }

  const tokens = await tokensForUser(dest);
  const title =
    tipo === "whatsapp"
      ? "WhatsApp · viaje RAI"
      : "Intento de llamada · viaje RAI";
  const body =
    tipo === "whatsapp"
      ? "Te escribirán por WhatsApp desde el viaje en curso."
      : "Abrieron el marcador para llamarte desde el viaje en curso.";
  logger.info(`[CHAT_NOTIFICACION] notifyIntento tipo=${tipo} → ${dest}`);
  await sendToTokens(tokens, title, body, {
    type: "trip_call_attempt",
    viajeId,
    senderUid: uid,
    comm: tipo,
  });
  return { ok: true };
});
