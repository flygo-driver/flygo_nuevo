/**
 * Recordatorios push a pasajeros con reserva pagada en giras por cupos:
 * 7 días, 3 días y 24 h antes de fechaSalida (America/Santo_Domingo).
 * Idempotencia por reserva: giraRecordatorio7dEn / 3d / 24h.
 */
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";

const db = () => getFirestore();
const messaging = () => getMessaging();
const ANDROID_CHANNEL = "rai_giras_cupos_cliente_v1";

type AnyMap = Record<string, unknown>;
type ReminderTier = "7d" | "3d" | "24h";

const REMINDER_FIELD: Record<ReminderTier, string> = {
  "7d": "giraRecordatorio7dEn",
  "3d": "giraRecordatorio3dEn",
  "24h": "giraRecordatorio24hEn",
};

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function todayKeySantoDomingo(now: Date): string {
  return now.toLocaleDateString("en-CA", { timeZone: "America/Santo_Domingo" });
}

function addCalendarDaysYmd(ymd: string, days: number): string {
  const [y, m, d] = ymd.split("-").map((x) => Number(x));
  const dt = new Date(Date.UTC(y, m - 1, d + days));
  return dt.toISOString().slice(0, 10);
}

function boundsForYmdSantoDomingo(ymd: string): { start: Timestamp; end: Timestamp } {
  const start = new Date(`${ymd}T00:00:00-04:00`);
  const end = new Date(`${ymd}T23:59:59.999-04:00`);
  return {
    start: Timestamp.fromDate(start),
    end: Timestamp.fromDate(end),
  };
}

function poolEstadoActivo(estado: string): boolean {
  const e = estado.toLowerCase();
  return !(
    e === "cancelado" ||
    e === "cancelado_por_admin" ||
    e === "finalizado"
  );
}

function reservaElegibleRecordatorio(res: AnyMap): boolean {
  const est = str(res.estado).toLowerCase();
  if (est === "cancelado") return false;
  return est === "pagado";
}

function tituloCuerpoRecordatorio(
  tier: ReminderTier,
  origen: string,
  destino: string,
  fechaSalida: Timestamp | null,
): { title: string; body: string } {
  const ruta = `${origen} → ${destino}`;
  let cuando = "";
  if (fechaSalida instanceof Timestamp) {
    cuando = fechaSalida
      .toDate()
      .toLocaleString("es-DO", {
        timeZone: "America/Santo_Domingo",
        weekday: "short",
        day: "numeric",
        month: "short",
        hour: "2-digit",
        minute: "2-digit",
      });
  }
  switch (tier) {
    case "7d":
      return {
        title: "Tu gira es en 7 días",
        body: `Recordatorio: ${ruta}${cuando ? ` · salida ${cuando}` : ""}. Revisa tu ticket en la app.`,
      };
    case "3d":
      return {
        title: "Tu gira es en 3 días",
        body: `Faltan 3 días para ${ruta}${cuando ? ` (${cuando})` : ""}. Ten listo tu ticket QR.`,
      };
    default:
      return {
        title: "Mañana es tu gira",
        body: `Salida en ~24 h: ${ruta}${cuando ? ` · ${cuando}` : ""}. Lleva tu código RAI o el QR del ticket.`,
      };
  }
}

async function poolsEnVentana(tier: ReminderTier): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const now = new Date();
  if (tier === "24h") {
    const start = Timestamp.fromDate(new Date(now.getTime() + 20 * 60 * 60 * 1000));
    const end = Timestamp.fromDate(new Date(now.getTime() + 28 * 60 * 60 * 1000));
    const q = await db()
      .collection("viajes_pool")
      .where("fechaSalida", ">=", start)
      .where("fechaSalida", "<=", end)
      .limit(120)
      .get();
    return q.docs;
  }
  const days = tier === "7d" ? 7 : 3;
  const ymd = addCalendarDaysYmd(todayKeySantoDomingo(now), days);
  const { start, end } = boundsForYmdSantoDomingo(ymd);
  const q = await db()
    .collection("viajes_pool")
    .where("fechaSalida", ">=", start)
    .where("fechaSalida", "<=", end)
    .limit(120)
    .get();
  return q.docs;
}

async function enviarRecordatorioReserva(opts: {
  tier: ReminderTier;
  poolId: string;
  pool: AnyMap;
  reservaId: string;
  res: AnyMap;
  resRef: FirebaseFirestore.DocumentReference;
}): Promise<boolean> {
  const { tier, poolId, pool, reservaId, res, resRef } = opts;
  const field = REMINDER_FIELD[tier];
  if (res[field]) return false;

  const uid = str(res.uidCliente);
  if (!uid) return false;

  const tokSnap = await db().collection("push_tokens").doc(uid).get();
  const raw = tokSnap.data()?.tokens;
  const tokens = Array.isArray(raw)
    ? raw.filter((t): t is string => typeof t === "string" && t.length > 10)
    : [];
  if (tokens.length === 0) {
    logger.warn("[giraRecordatorio] sin FCM", { tier, poolId, reservaId, uid });
    return false;
  }

  const origen = str(pool.origenTown) || "Origen";
  const destino = str(pool.destino) || "Destino";
  const fechaSalida = pool.fechaSalida instanceof Timestamp ? pool.fechaSalida : null;
  const { title, body } = tituloCuerpoRecordatorio(tier, origen, destino, fechaSalida);

  const fcmRes = await messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: {
      type: `gira_cupos_recordatorio_${tier}`,
      poolId,
      reservaId,
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
    android: {
      notification: {
        channelId: ANDROID_CHANNEL,
        sound: "default",
      },
    },
    apns: { payload: { aps: { sound: "default" } } },
  });

  if (fcmRes.successCount < 1) {
    logger.warn("[giraRecordatorio] FCM sin entregas", {
      tier,
      poolId,
      reservaId,
      failureCount: fcmRes.failureCount,
    });
    return false;
  }

  await resRef.update({
    [field]: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return true;
}

async function procesarTier(tier: ReminderTier): Promise<number> {
  let sent = 0;
  let poolDocs: FirebaseFirestore.QueryDocumentSnapshot[];
  try {
    poolDocs = await poolsEnVentana(tier);
  } catch (e) {
    logger.error("[giraRecordatorio] query pools failed", { tier, err: e });
    return 0;
  }

  for (const poolDoc of poolDocs) {
    const pool = poolDoc.data() as AnyMap;
    if (!poolEstadoActivo(str(pool.estado))) continue;

    let resSnap: FirebaseFirestore.QuerySnapshot;
    try {
      resSnap = await poolDoc.ref
        .collection("reservas")
        .where("estado", "==", "pagado")
        .limit(80)
        .get();
    } catch (e) {
      logger.warn("[giraRecordatorio] reservas query", { poolId: poolDoc.id, err: e });
      continue;
    }

    for (const resDoc of resSnap.docs) {
      const res = resDoc.data() as AnyMap;
      if (!reservaElegibleRecordatorio(res)) continue;
      try {
        const ok = await enviarRecordatorioReserva({
          tier,
          poolId: poolDoc.id,
          pool,
          reservaId: resDoc.id,
          res,
          resRef: resDoc.ref,
        });
        if (ok) sent += 1;
      } catch (e) {
        logger.error("[giraRecordatorio] reserva error", {
          tier,
          poolId: poolDoc.id,
          reservaId: resDoc.id,
          err: e,
        });
      }
    }
  }
  return sent;
}

export const scheduledNotifyGiraCuposClienteRecordatorios = onSchedule(
  {
    schedule: "every 2 hours",
    timeZone: "America/Santo_Domingo",
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    const n24 = await procesarTier("24h");
    const n7 = await procesarTier("7d");
    const n3 = await procesarTier("3d");
    logger.info("[giraRecordatorio] done", { n24, n7, n3 });
  },
);
