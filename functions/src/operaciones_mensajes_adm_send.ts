/**
 * Cliente → operaciones (espera conductor). Admin SDK evita permission-denied
 * si las reglas de Firestore aún no están desplegadas en producción.
 */
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = () => getFirestore();

type AnyMap = Record<string, unknown>;

const MAX_MENSAJE_CHARS = 500;
const MAX_MENSAJES_POR_VIAJE = 12;
const ESPERA_ENTRE_MS = 30_000;

function trimOrEmpty(v: unknown): string {
  return String(v ?? "").trim();
}

function uidClienteDesdeViaje(v: AnyMap): string {
  const u = trimOrEmpty(v.uidCliente);
  if (u) return u;
  const c = trimOrEmpty(v.clienteId);
  if (c) return c;
  return trimOrEmpty(v.uid);
}

function tipoServicioParaAdm(v: AnyMap): string {
  const explicit = trimOrEmpty(v.tipoServicio).toLowerCase();
  if (explicit && explicit !== "normal") return explicit;
  const tv = trimOrEmpty(v.tipoVehiculo || v.tipoVehiculoOriginal).toLowerCase();
  if (tv.includes("motor") || tv.includes("🛵")) return "motor";
  return explicit || "normal";
}

async function verificarRitmoEnvio(viajeId: string, uidCliente: string): Promise<void> {
  const previos = await db()
    .collection("operaciones_mensajes_adm")
    .where("viajeId", "==", viajeId)
    .where("uidCliente", "==", uidCliente)
    .orderBy("createdAt", "desc")
    .limit(MAX_MENSAJES_POR_VIAJE)
    .get();

  if (previos.size >= MAX_MENSAJES_POR_VIAJE) {
    throw new HttpsError(
      "failed-precondition",
      "Ya enviaste varios mensajes en este viaje. Operaciones los está viendo; espera la respuesta.",
    );
  }

  if (previos.empty) return;
  const ts = previos.docs[0].data().createdAt;
  if (!(ts instanceof Timestamp)) return;
  const desde = Date.now() - ts.toMillis();
  if (desde < ESPERA_ENTRE_MS) {
    const faltan = Math.ceil((ESPERA_ENTRE_MS - desde) / 1000);
    throw new HttpsError(
      "failed-precondition",
      `Espera ${faltan} segundos para enviar otro mensaje.`,
    );
  }
}

export const enviarMensajeOperacionesAdm = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = trimOrEmpty(request.auth?.uid);
    if (!uid) {
      throw new HttpsError("unauthenticated", "Inicia sesión para enviar el mensaje.");
    }

    const payload = (request.data ?? {}) as AnyMap;
    const viajeId = trimOrEmpty(payload.viajeId);
    const mensaje = trimOrEmpty(payload.mensaje);
    const origenPantalla = trimOrEmpty(payload.origenPantalla) || "espera_conductor";

    if (!viajeId) {
      throw new HttpsError("invalid-argument", "Viaje inválido.");
    }
    if (!mensaje) {
      throw new HttpsError("invalid-argument", "Escribe un mensaje.");
    }
    if (mensaje.length > MAX_MENSAJE_CHARS) {
      throw new HttpsError("invalid-argument", `Máximo ${MAX_MENSAJE_CHARS} caracteres.`);
    }

    const vSnap = await db().collection("viajes").doc(viajeId).get();
    if (!vSnap.exists) {
      throw new HttpsError("not-found", "El viaje ya no existe.");
    }

    const v = (vSnap.data() ?? {}) as AnyMap;
    const uidCliente = uidClienteDesdeViaje(v);
    if (uidCliente !== uid) {
      throw new HttpsError("permission-denied", "No puedes enviar mensajes en este viaje.");
    }

    const origen = trimOrEmpty(v.origen);
    const destino = trimOrEmpty(v.destino);
    const ruta =
      origen || destino ? `${origen} → ${destino}` : "Viaje RAI";

    let clienteNombre = trimOrEmpty(v.nombreCliente);
    if (!clienteNombre) {
      const uSnap = await db().collection("usuarios").doc(uid).get();
      clienteNombre =
        trimOrEmpty(uSnap.data()?.nombre) ||
        trimOrEmpty(request.auth?.token?.name) ||
        "Cliente RAI";
    }

    await verificarRitmoEnvio(viajeId, uid);

    const ref = await db().collection("operaciones_mensajes_adm").add({
      viajeId,
      uidCliente: uid,
      clienteNombre,
      mensaje,
      ruta,
      tipoServicio: tipoServicioParaAdm(v),
      origenPantalla,
      leidoPorAdm: false,
      createdAt: FieldValue.serverTimestamp(),
    });

    return { ok: true, mensajeId: ref.id };
  },
);
