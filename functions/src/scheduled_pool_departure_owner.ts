/**
 * Recordatorio al dueño del pool (agencia/chofer) el día de fechaSalida:
 * iniciar la gira en la app para que salga del catálogo público (pasa a en_ruta).
 * Una notificación por pool por día (campo poolDepartureDayRemindKey = YYYY-MM-DD).
 */
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";

const db = () => getFirestore();
const messaging = () => getMessaging();
const ANDROID_CHANNEL = "rai_driver_notifications";

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

/** Fecha calendario actual en America/Santo_Domingo (YYYY-MM-DD). */
function todayKeySantoDomingo(now: Date): string {
  return now.toLocaleDateString("en-CA", { timeZone: "America/Santo_Domingo" });
}

function boundsForYmdSantoDomingo(ymd: string): { start: Timestamp; end: Timestamp } {
  const start = new Date(`${ymd}T00:00:00-04:00`);
  const end = new Date(`${ymd}T23:59:59.999-04:00`);
  return {
    start: Timestamp.fromDate(start),
    end: Timestamp.fromDate(end),
  };
}

function shouldRemindPool(data: AnyMap, ymd: string): boolean {
  const sent = str(data.poolDepartureDayRemindKey);
  if (sent === ymd) return false;

  const estado = str(data.estado).toLowerCase();
  if (estado === "en_ruta" || estado === "finalizado" || estado === "cancelado") return false;

  return (
    estado === "abierto" ||
    estado === "preconfirmado" ||
    estado === "confirmado" ||
    estado === "lleno" ||
    estado === "activo" ||
    estado === "disponible" ||
    estado === "buscando"
  );
}

export const scheduledNotifyPoolOwnerDepartureDay = onSchedule(
  {
    schedule: "0 8 * * *",
    timeZone: "America/Santo_Domingo",
    memory: "256MiB",
    timeoutSeconds: 120,
  },
  async () => {
    const ymd = todayKeySantoDomingo(new Date());
    const { start, end } = boundsForYmdSantoDomingo(ymd);

    let q: FirebaseFirestore.QuerySnapshot;
    try {
      q = await db()
        .collection("viajes_pool")
        .where("fechaSalida", ">=", start)
        .where("fechaSalida", "<=", end)
        .limit(200)
        .get();
    } catch (e) {
      logger.error("scheduledNotifyPoolOwnerDepartureDay query failed", e);
      return;
    }

    for (const doc of q.docs) {
      const data = doc.data() as AnyMap;
      if (!shouldRemindPool(data, ymd)) continue;

      const owner = str(data.ownerTaxistaId);
      if (!owner) continue;

      const origen = str(data.origenTown) || "Origen";
      const destino = str(data.destino) || "Destino";

      try {
        const tokSnap = await db().collection("push_tokens").doc(owner).get();
        const raw = tokSnap.data()?.tokens;
        const tokens = Array.isArray(raw)
          ? raw.filter((t): t is string => typeof t === "string" && t.length > 10)
          : [];
        if (tokens.length === 0) {
          logger.warn("scheduledNotifyPoolOwnerDepartureDay sin tokens FCM", {
            poolId: doc.id,
            owner,
          });
          continue;
        }

        const title = "Hoy es tu gira por cupos";
        const body = `${origen} → ${destino}. Iniciá el viaje en «Mis viajes por cupos» para que salga del catálogo público.`;

        const res = await messaging().sendEachForMulticast({
          tokens,
          notification: { title, body },
          data: {
            type: "pool_departure_day_reminder",
            poolId: doc.id,
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
          logger.warn("scheduledNotifyPoolOwnerDepartureDay FCM sin entregas", {
            poolId: doc.id,
            failureCount: res.failureCount,
          });
          continue;
        }

        await doc.ref.update({
          poolDepartureDayRemindKey: ymd,
          poolDepartureDayRemindAt: FieldValue.serverTimestamp(),
        });
      } catch (e) {
        logger.error("scheduledNotifyPoolOwnerDepartureDay doc error", {
          poolId: doc.id,
          err: e,
        });
      }
    }
  },
);
