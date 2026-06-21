/**
 * Notifica a operaciones cuando un cliente escribe en turismo_mensajes_adm.
 * Aislado: no modifica asignación, pool ni alertas horarias existentes.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

import { sendMail } from "./mail.js";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();
const messaging = () => getMessaging();

const ANDROID_CHANNEL = "rai_driver_notifications";

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function preview(text: string, max = 160): string {
  const t = text.trim();
  if (t.length <= max) return t;
  return `${t.slice(0, max - 1)}…`;
}

async function adminUids(): Promise<string[]> {
  const [adm, admLegacy] = await Promise.all([
    db().collection("usuarios").where("rol", "==", "admin").limit(80).get(),
    db().collection("usuarios").where("rol", "==", "administrador").limit(80).get(),
  ]);
  const out = new Set<string>();
  for (const snap of [adm, admLegacy]) {
    for (const doc of snap.docs) {
      const uid = doc.id.trim();
      if (uid) out.add(uid);
    }
  }
  return [...out];
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

async function pushAdmins(
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<void> {
  const uids = await adminUids();
  if (uids.length === 0) {
    logger.info("[TURISMO_MSG_ADM] sin admins para push");
    return;
  }

  let ok = 0;
  let fail = 0;
  for (const uid of uids) {
    const tokens = await tokensForUser(uid);
    if (tokens.length === 0) continue;
    try {
      const res = await messaging().sendEachForMulticast({
        tokens,
        notification: { title, body },
        data: {
          ...data,
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          notification: { channelId: ANDROID_CHANNEL, sound: "default" },
        },
        apns: {
          payload: { aps: { sound: "default", badge: 1 } },
        },
      });
      ok += res.successCount;
      fail += res.failureCount;
    } catch (e) {
      logger.warn("[TURISMO_MSG_ADM] push admin falló", { uid, err: String(e) });
    }
  }
  logger.info(`[TURISMO_MSG_ADM] push admins ok=${ok} fail=${fail}`);
}

export const onTurismoMensajeAdmCreatedNotify = onDocumentCreated(
  {
    document: "turismo_mensajes_adm/{msgId}",
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const msgId = str(event.params.msgId);
    const data = (snap.data() ?? {}) as AnyMap;
    const viajeId = str(data.viajeId);
    const mensaje = str(data.mensaje);
    const clienteNombre = str(data.clienteNombre) || "Cliente turismo";
    const ruta = str(data.ruta) || "Viaje turismo";
    const uidCliente = str(data.uidCliente);

    if (!mensaje || !viajeId) {
      logger.info("[TURISMO_MSG_ADM] skip: mensaje o viajeId vacío");
      return;
    }

    const refCorta = viajeId.length > 8 ? viajeId.slice(0, 8) : viajeId;
    const titulo = `Turismo · mensaje cliente (#${refCorta})`;
    const cuerpo = preview(mensaje);
    const textoAlerta = `${clienteNombre} · ${ruta}\n\n${mensaje}`;

    await db()
      .collection("admin_alertas")
      .add({
        tipo: "turismo_mensaje_cliente",
        titulo,
        mensaje: textoAlerta,
        severidad: "warning",
        leida: false,
        metadata: {
          viajeId,
          mensajeId: msgId,
          uidCliente,
          ruta,
          clienteNombre,
          origenPantalla: str(data.origenPantalla),
        },
        createdAt: FieldValue.serverTimestamp(),
      });

    await pushAdmins(titulo, cuerpo, {
      type: "turismo_mensaje_cliente",
      viajeId,
      mensajeId: msgId,
    });

    await sendMail({
      subject: `[RAI Turismo] ${titulo}`,
      text: [
        "Nuevo mensaje de cliente turismo (panel Control turismo).",
        "",
        `Viaje: #${refCorta}`,
        `Cliente: ${clienteNombre}`,
        `Ruta: ${ruta}`,
        "",
        mensaje,
        "",
        "Revisa en la app admin: Control turismo → Mensajes.",
      ].join("\n"),
    });

    logger.info("[TURISMO_MSG_ADM] alerta + push + mail best-effort", {
      msgId,
      viajeId,
    });
  },
);
