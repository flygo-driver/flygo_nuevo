/**
 * Notifica a operaciones cuando un cliente escribe en operaciones_mensajes_adm
 * (espera de conductor en viaje normal / motor).
 */
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";

import { sendMail } from "./mail.js";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();
const messaging = () => getMessaging();

const ANDROID_CHANNEL = "rai_driver_notifications";

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function tipoServicioParaAdm(raw: AnyMap): string {
  const explicit = str(raw.tipoServicio).toLowerCase();
  if (explicit && explicit !== "normal") return explicit;
  const tv = str(raw.tipoVehiculo || raw.tipoVehiculoOriginal).toLowerCase();
  if (tv.includes("motor") || tv.includes("🛵")) return "motor";
  return explicit || "normal";
}

function etiquetaChoferEspera(tipoServicio: string): string {
  return tipoServicio.toLowerCase() === "motor" ? "motorista" : "conductor";
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

/** Avisos por cliente y hora antes de dejar de despertar a todo el equipo. */
const MAX_AVISOS_POR_CLIENTE_HORA = 4;

/**
 * Un mensaje despierta a ~80 admins con push y correo. Si el mismo cliente
 * insiste, el mensaje se guarda igual pero deja de disparar el operativo.
 */
async function debeAvisarAOperaciones(
  uidCliente: string,
  msgId: string,
): Promise<boolean> {
  if (!uidCliente) return true;
  try {
    const desde = Timestamp.fromMillis(Date.now() - 60 * 60 * 1000);
    const snap = await db()
      .collection("operaciones_mensajes_adm")
      .where("uidCliente", "==", uidCliente)
      .where("createdAt", ">=", desde)
      .limit(MAX_AVISOS_POR_CLIENTE_HORA + 1)
      .get();
    const previos = snap.docs.filter((d) => d.id !== msgId).length;
    if (previos >= MAX_AVISOS_POR_CLIENTE_HORA) {
      logger.info("[OPS_MSG_ADM] aviso omitido por ritmo", {
        uidCliente,
        previos,
      });
      return false;
    }
    return true;
  } catch (e) {
    // Ante duda, avisar: perder un mensaje real es peor que un push de más.
    logger.warn("[OPS_MSG_ADM] no se pudo medir el ritmo", { err: String(e) });
    return true;
  }
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
    logger.info("[OPS_MSG_ADM] sin admins para push");
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
      logger.warn("[OPS_MSG_ADM] push admin falló", { uid, err: String(e) });
    }
  }
  logger.info(`[OPS_MSG_ADM] push admins ok=${ok} fail=${fail}`);
}

export const onOperacionesMensajeAdmCreatedNotify = onDocumentCreated(
  {
    document: "operaciones_mensajes_adm/{msgId}",
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const msgId = str(event.params.msgId);
    const data = (snap.data() ?? {}) as AnyMap;
    const viajeId = str(data.viajeId);
    const mensaje = str(data.mensaje);
    const clienteNombre = str(data.clienteNombre) || "Cliente RAI";
    const ruta = str(data.ruta) || "Viaje RAI";
    const uidCliente = str(data.uidCliente);
    const tipoServicio = tipoServicioParaAdm(data);
    const choferLabel = etiquetaChoferEspera(tipoServicio);

    if (!mensaje || !viajeId) {
      logger.info("[OPS_MSG_ADM] skip: mensaje o viajeId vacío");
      return;
    }

    const refCorta = viajeId.length > 8 ? viajeId.slice(0, 8) : viajeId;
    const titulo = `Cliente esperando ${choferLabel} (#${refCorta})`;
    const cuerpo = preview(mensaje);
    const textoAlerta = `${clienteNombre} · ${ruta}\n\n${mensaje}`;

    if (!(await debeAvisarAOperaciones(uidCliente, msgId))) return;

    await db()
      .collection("admin_alertas")
      .add({
        tipo: "cliente_espera_conductor_mensaje",
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
          tipoServicio,
          origenPantalla: str(data.origenPantalla),
        },
        createdAt: FieldValue.serverTimestamp(),
      });

    await pushAdmins(titulo, cuerpo, {
      type: "cliente_espera_conductor_mensaje",
      viajeId,
      mensajeId: msgId,
    });

    await sendMail({
      subject: `[RAI Operaciones] ${titulo}`,
      text: [
        "Nuevo mensaje de cliente esperando chofer.",
        "",
        `Viaje: #${refCorta}`,
        `Cliente: ${clienteNombre}`,
        `Ruta: ${ruta}`,
        `Servicio: ${tipoServicio}`,
        "",
        mensaje,
        "",
        "Revisa en la app admin: Alertas operativas.",
      ].join("\n"),
    });

    logger.info("[OPS_MSG_ADM] alerta + push + mail best-effort", {
      msgId,
      viajeId,
    });
  },
);

/** El cliente se enteró de que operaciones le contestó. */
export const onOperacionesMensajeAdmRespuestaNotify = onDocumentUpdated(
  {
    document: "operaciones_mensajes_adm/{msgId}",
    region: "us-central1",
  },
  async (event) => {
    const antes = (event.data?.before?.data() ?? {}) as AnyMap;
    const despues = (event.data?.after?.data() ?? {}) as AnyMap;

    const respuesta = str(despues.respuesta);
    if (!respuesta) return;
    if (respuesta === str(antes.respuesta)) return;

    const uidCliente = str(despues.uidCliente);
    if (!uidCliente) return;

    const tokens = await tokensForUser(uidCliente);
    if (tokens.length === 0) {
      logger.info("[OPS_MSG_ADM] cliente sin tokens para la respuesta", {
        uidCliente,
      });
      return;
    }

    try {
      await messaging().sendEachForMulticast({
        tokens,
        notification: {
          title: "Operaciones RAI te respondió",
          body: preview(respuesta, 140),
        },
        data: {
          type: "operaciones_respuesta_cliente",
          viajeId: str(despues.viajeId),
          mensajeId: str(event.params.msgId),
          click_action: "FLUTTER_NOTIFICATION_CLICK",
        },
        android: {
          notification: { channelId: ANDROID_CHANNEL, sound: "default" },
        },
        apns: { payload: { aps: { sound: "default" } } },
      });
    } catch (e) {
      logger.warn("[OPS_MSG_ADM] push respuesta falló", { err: String(e) });
    }
  },
);
