/**
 * Notificaciones escalonadas corporativas (FCM + historial).
 * SMS/correo: preparado; FCM es canal principal del piloto.
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";

type AnyMap = Record<string, unknown>;

const ANDROID_CHANNEL = "rai_driver_notifications";

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function diaCalendarioRd(ref = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Santo_Domingo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(ref);
}

export async function enviarPushUid(
  uid: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<boolean> {
  const tokSnap = await getFirestore().collection("push_tokens").doc(uid).get();
  const raw = tokSnap.data()?.tokens;
  const tokens = Array.isArray(raw)
    ? raw.filter((t): t is string => typeof t === "string" && t.length > 10)
    : [];
  if (tokens.length === 0) return false;
  try {
    await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: { ...data, click_action: "FLUTTER_NOTIFICATION_CLICK" },
      android: {
        priority: "high",
        notification: { channelId: ANDROID_CHANNEL },
      },
    });
    return true;
  } catch (e) {
    logger.warn("corporativo_notificaciones push", { uid, e });
    return false;
  }
}

export async function registrarHistorialNotificacionCorp(args: {
  empresaId: string;
  plantillaId?: string;
  viajeId?: string;
  uidDestino: string;
  canal: "fcm" | "sms" | "email";
  tipo: string;
  titulo: string;
  cuerpo: string;
  enviado: boolean;
}): Promise<void> {
  const empresaId = str(args.empresaId);
  if (!empresaId) return;
  await getFirestore()
    .collection("empresas_corporativas")
    .doc(empresaId)
    .collection("notificaciones_historial")
    .add({
      plantillaId: args.plantillaId ?? null,
      viajeId: args.viajeId ?? null,
      uidDestino: args.uidDestino,
      canal: args.canal,
      tipo: args.tipo,
      titulo: args.titulo,
      cuerpo: args.cuerpo,
      enviado: args.enviado,
      creadoEn: FieldValue.serverTimestamp(),
    });
}

type Escalon = "120m" | "30m" | "0m" | "confirmar";

const ESCALONES: { id: Escalon; minutos: number; titulo: (h: string) => string; cuerpo: (args: AnyMap) => string }[] = [
  {
    id: "120m",
    minutos: 120,
    titulo: (h) => `Viaje programado hoy a las ${h}`,
    cuerpo: (a) =>
      `${str(a.empresaNombre)} · ${str(a.nombreRuta)}. Recogida ${str(a.horaTxt)} en ${str(a.origen)}.`,
  },
  {
    id: "30m",
    minutos: 30,
    titulo: () => "¡Viaje comienza en 30 min!",
    cuerpo: (a) =>
      `Ve hacia ${str(a.origen)}. Recogida ${str(a.horaTxt)} · ${str(a.empresaNombre)}.`,
  },
  {
    id: "0m",
    minutos: 0,
    titulo: () => "Ya debes estar en el origen",
    cuerpo: (a) =>
      `Hora de recogida ${str(a.horaTxt)}. Confirma en la app o contacta al encargado.`,
  },
  {
    id: "confirmar",
    minutos: -25,
    titulo: () => "Confirma o asignaremos sustituto",
    cuerpo: (a) =>
      `Aún no confirmaste la ruta de hoy (${str(a.horaTxt)}). Toca «Confirmar» en Mis rutas corporativas.`,
  },
];

function parseHora(hora: string): { h: number; m: number } | null {
  const parts = hora.split(":");
  if (parts.length < 2) return null;
  const h = parseInt(parts[0], 10);
  const m = parseInt(parts[1], 10);
  if (!Number.isFinite(h) || !Number.isFinite(m)) return null;
  return { h, m };
}

function recogidaRd(horaStr: string, ref: Date): Date | null {
  const p = parseHora(horaStr);
  if (!p) return null;
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Santo_Domingo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const [y, mo, d] = fmt.format(ref).split("-").map(Number);
  return new Date(Date.UTC(y, mo - 1, d, p.h + 4, p.m, 0));
}

/** Cada 10 min: avisos 2h, 30m, 0m y recordatorio de confirmación. */
export const scheduledCorporativoAvisosEscalonados = onSchedule(
  {
    schedule: "every 10 minutes",
    timeZone: "America/Santo_Domingo",
    memory: "512MiB",
    timeoutSeconds: 300,
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const keyHoy = diaCalendarioRd(now);
    let enviados = 0;

    const empresas = await db
      .collection("empresas_corporativas")
      .where("activa", "==", true)
      .limit(40)
      .get();

    for (const emp of empresas.docs) {
      const empresaId = emp.id;
      const empresaNombre = str(emp.data().nombre) || "Empresa";
      const plantillas = await db
        .collection("empresas_corporativas")
        .doc(empresaId)
        .collection("plantillas_ruta")
        .where("activa", "==", true)
        .where("esFijo", "==", true)
        .limit(20)
        .get();

      for (const pl of plantillas.docs) {
        const d = pl.data() as AnyMap;
        if (d.pausaTotal === true) continue;
        const feriados = Array.isArray(d.diasPausaFeriado)
          ? (d.diasPausaFeriado as string[]).map(str)
          : [];
        if (feriados.includes(keyHoy)) continue;

        const horaStr = str(d.horaRecogidaGrupo) || str(d.horaRecogida) || "07:00";
        const recogida = recogidaRd(horaStr, now);
        if (!recogida) continue;
        const diffMin = (recogida.getTime() - now.getTime()) / 60000;
        const choferUid = str(d.choferPreferidoUid);
        if (!choferUid) continue;

        const horaParsed = parseHora(horaStr)!;
        const horaTxt = `${String(horaParsed.h).padStart(2, "0")}:${String(horaParsed.m).padStart(2, "0")}`;
        const payloadBase: AnyMap = {
          empresaNombre,
          nombreRuta: str(d.nombre) || "Ruta corporativa",
          origen: str(d.origenLabel) || "empresa",
          horaTxt,
        };

        for (const esc of ESCALONES) {
          const ventana = esc.id === "confirmar" ? 5 : 8;
          if (Math.abs(diffMin - esc.minutos) > ventana) continue;

          const notifKey = `ultimaNotifCorp_${esc.id}_${keyHoy}`;
          if (str(d[notifKey]) === "1") continue;

          if (esc.id === "confirmar") {
            const tiempoConf = Math.max(
              15,
              Math.trunc(Number(d.tiempoConfirmacionMin) || 30),
            );
            if (diffMin > -tiempoConf || diffMin < -(tiempoConf + 15)) continue;
            const confirmKey = `choferConfirmado_${keyHoy}`;
            if (str(d[confirmKey]) === choferUid) continue;
          }

          const titulo = esc.titulo(horaTxt);
          const cuerpo = esc.cuerpo(payloadBase);
          const ok = await enviarPushUid(choferUid, titulo, cuerpo, {
            type: `corporativo_aviso_${esc.id}`,
            empresaId,
            plantillaId: pl.id,
            rol: "taxista",
          });

          await registrarHistorialNotificacionCorp({
            empresaId,
            plantillaId: pl.id,
            uidDestino: choferUid,
            canal: "fcm",
            tipo: `aviso_${esc.id}`,
            titulo,
            cuerpo,
            enviado: ok,
          });

          await pl.ref.set(
            { [notifKey]: "1", actualizadoEn: FieldValue.serverTimestamp() },
            { merge: true },
          );
          enviados += 1;
        }
      }
    }

    logger.info("scheduledCorporativoAvisosEscalonados", { enviados, keyHoy });
  },
);
