/**
 * Push FCM al recibir mensajes en chats de viaje + aviso de intento de llamada/WhatsApp.
 *
 * Tokens: `push_tokens/{uid}.tokens[]` (y fallback `usuarios/{uid}.pushToken`).
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
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

function uidClienteDesdeViaje(d: Record<string, unknown>): string {
  const u = str(d.uidCliente);
  if (u) return u;
  const c = str(d.clienteId);
  if (c) return c;
  return str(d.uid);
}

function uidTaxistaDesdeViaje(d: Record<string, unknown>): string {
  const u = str(d.uidTaxista);
  if (u) return u;
  return str(d.taxistaId);
}

function esParticipanteViajeDoc(d: Record<string, unknown>, uid: string): boolean {
  if (!uid) return false;
  return (
    uid === uidClienteDesdeViaje(d) ||
    uid === uidTaxistaDesdeViaje(d) ||
    uid === str(d.corporativoChoferAsignadoUid) ||
    uid === str(d.corporativoChoferPreferidoUid)
  );
}

/** Asegura chats/{viajeId} con Admin SDK (evita permission-denied en cliente). */
export const ensureChatViajeDoc = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = str(request.auth?.uid);
    if (!uid) {
      throw new HttpsError("unauthenticated", "Inicia sesión para usar el chat.");
    }
    const viajeId = str((request.data as Record<string, unknown> | undefined)?.viajeId);
    if (!viajeId) {
      throw new HttpsError("invalid-argument", "Viaje inválido.");
    }

    const vSnap = await db().collection("viajes").doc(viajeId).get();
    if (!vSnap.exists) {
      throw new HttpsError("not-found", "Viaje no encontrado.");
    }
    const vd = (vSnap.data() ?? {}) as Record<string, unknown>;
    if (!esParticipanteViajeDoc(vd, uid)) {
      throw new HttpsError("permission-denied", "No participás en este viaje.");
    }

    const participantes = new Set<string>();
    const uidCli = uidClienteDesdeViaje(vd);
    const uidTx = uidTaxistaDesdeViaje(vd);
    if (uidCli) participantes.add(uidCli);
    if (uidTx) participantes.add(uidTx);
    participantes.add(uid);

    if (participantes.size < 2) {
      throw new HttpsError(
        "failed-precondition",
        "Aún no hay conductor asignado para chatear.",
      );
    }

    const chatRef = db().collection("chats").doc(viajeId);
    const cSnap = await chatRef.get();
    if (!cSnap.exists) {
      await chatRef.set({
        participantes: [...participantes],
        viajeId,
        lastMessage: "",
        lastAt: FieldValue.serverTimestamp(),
        creadoAt: FieldValue.serverTimestamp(),
      });
      logger.info("[CHAT] ensureChatViajeDoc created", { viajeId, uid });
      return { ok: true, viajeId, created: true };
    }

    const raw = cSnap.data()?.participantes;
    const existentes = Array.isArray(raw)
      ? raw.map((x) => str(x)).filter((x) => x.length > 0)
      : [];
    const merged = new Set<string>([...existentes, ...participantes]);
    await chatRef.set(
      {
        participantes: [...merged],
        viajeId,
        lastAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    logger.info("[CHAT] ensureChatViajeDoc merged", { viajeId, uid });
    return { ok: true, viajeId, created: false };
  },
);

/** Destinatario: viaje (chatId == viajeId) o chat con participantes. */
async function resolveRecipientUid(
  chatId: string,
  senderUid: string,
): Promise<string | null> {
  const vSnap = await db().collection("viajes").doc(chatId).get();
  if (vSnap.exists) {
    const d = vSnap.data() ?? {};
    const cliente = uidClienteDesdeViaje(d);
    const taxista = uidTaxistaDesdeViaje(d);
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
  const cliente = uidClienteDesdeViaje(vd);
  const taxista = uidTaxistaDesdeViaje(vd);
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
