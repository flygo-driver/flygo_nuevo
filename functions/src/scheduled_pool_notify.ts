/**
 * Aviso al cliente cuando su viaje programado entra en ventana de pool (publishAt).
 * Corre cada 5 min; usa FCM con tokens en push_tokens/{uid}.
 */
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";

const db = () => getFirestore();
const messaging = () => getMessaging();

const ANDROID_CHANNEL = "rai_driver_notifications";

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function shouldSkipTrip(data: Record<string, unknown>): boolean {
  if (data.poolOpeningPushSent === true) return true;

  const taxista = str(data.uidTaxista) || str(data.taxistaId);
  if (taxista.length > 0) return true;

  const canal = str(data.canalAsignacion) || "pool";
  if (canal === "admin") return true;

  const tipo = str(data.tipoServicio) || "normal";
  // Turismo solo por admin: no aviso de pool hasta que exista pool turístico.
  if (tipo === "turismo" && canal !== "turismo_pool") return true;

  const estado = str(data.estado).toLowerCase();
  if (estado !== "pendiente" && estado !== "pendiente_pago") return true;

  return false;
}

export const scheduledNotifyClienteViajeProgramadoEnPool = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "America/Santo_Domingo",
    memory: "256MiB",
    timeoutSeconds: 120,
  },
  async () => {
    const now = Timestamp.now();
    let q: FirebaseFirestore.QuerySnapshot;
    try {
      q = await db()
        .collection("viajes")
        .where("estado", "in", ["pendiente", "pendiente_pago"])
        .where("programado", "==", true)
        .where("publishAt", "<=", now)
        .orderBy("publishAt", "desc")
        .limit(40)
        .get();
    } catch (e) {
      logger.error("scheduledNotifyClienteViajeProgramadoEnPool query failed", e);
      return;
    }

    for (const doc of q.docs) {
      const data = doc.data();
      if (shouldSkipTrip(data)) continue;

      const pub = data.publishAt;
      if (!(pub instanceof Timestamp)) continue;
      if (pub.toMillis() > now.toMillis()) continue;

      const uid = str(data.uidCliente) || str(data.clienteId);
      if (!uid) continue;

      const tipoServicio = str(data.tipoServicio) || "normal";

      try {
        const tokSnap = await db().collection("push_tokens").doc(uid).get();
        const raw = tokSnap.data()?.tokens;
        const tokens = Array.isArray(raw)
          ? raw.filter((t): t is string => typeof t === "string" && t.length > 10)
          : [];
        if (tokens.length === 0) continue;

        const origen = str(data.origen) || "Origen";
        const destino = str(data.destino) || "Destino";
        const title = "Tu viaje ya está en búsqueda de conductor";
        const body =
          tipoServicio === "turismo"
            ? `${origen} → ${destino}. Los conductores de turismo habilitados ya pueden ver tu viaje.`
            : `${origen} → ${destino}. Los conductores cercanos pueden aceptarlo ahora.`;

        const res = await messaging().sendEachForMulticast({
          tokens,
          notification: { title, body },
          data: {
            type: "scheduled_trip_pool_open",
            viajeId: doc.id,
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
          android: {
            notification: {
              channelId: ANDROID_CHANNEL,
              sound: "default",
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
              },
            },
          },
        });

        if (res.successCount < 1) {
          logger.warn("FCM no entregó ningún mensaje", {
            viajeId: doc.id,
            failureCount: res.failureCount,
          });
          continue;
        }

        await doc.ref.update({
          poolOpeningPushSent: true,
          poolOpeningPushSentAt: FieldValue.serverTimestamp(),
        });
      } catch (e) {
        logger.error("scheduledNotifyClienteViajeProgramadoEnPool doc error", {
          viajeId: doc.id,
          err: e,
        });
      }
    }
  },
);
