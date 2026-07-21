/**
 * Avisos de vencimiento del código de verificación corporativo (3d, 1d, día 0).
 */
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  enviarPushUid,
  registrarHistorialNotificacionCorp,
} from "./corporativo_notificaciones.js";
import { evaluarVigenciaCodigoCorporativo } from "./corporativo_periodo.js";

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function parseTs(v: unknown): Date | null {
  if (v instanceof Timestamp) return v.toDate();
  const d = new Date(str(v));
  return Number.isFinite(d.getTime()) ? d : null;
}

function diasHastaFin(fin: Date, now: Date): number {
  const ms = fin.getTime() - now.getTime();
  return Math.ceil(ms / 86400000);
}

const AVISOS: {
  id: string;
  diasRestantes: number;
  titulo: string;
  cuerpo: string;
}[] = [
  {
    id: "codigo_3d",
    diasRestantes: 3,
    titulo: "Código de verificación vence en 3 días",
    cuerpo:
      "El código de verificación vence en 3 días. Realice su pago para renovarlo.",
  },
  {
    id: "codigo_1d",
    diasRestantes: 1,
    titulo: "Mañana vence su código",
    cuerpo: "Mañana vence su código. Pague para continuar usando el servicio.",
  },
  {
    id: "codigo_0d",
    diasRestantes: 0,
    titulo: "Su código ha expirado",
    cuerpo: "Su código ha expirado. Realice su pago para generar uno nuevo.",
  },
];

/** Diario 8:00 RD: avisos de vencimiento del código de período. */
export const scheduledCorporativoAvisosCodigoVencimiento = onSchedule(
  {
    schedule: "0 8 * * *",
    timeZone: "America/Santo_Domingo",
    memory: "256MiB",
    timeoutSeconds: 180,
  },
  async () => {
    const db = getFirestore();
    const now = new Date();
    let enviados = 0;

    const empresas = await db
      .collection("empresas_corporativas")
      .where("activa", "==", true)
      .limit(60)
      .get();

    for (const emp of empresas.docs) {
      const ed = emp.data() as AnyMap;
      const periodo = (ed.periodoActual ?? {}) as AnyMap;
      const fin = parseTs(periodo.fin);
      if (!fin) continue;

      const vig = evaluarVigenciaCodigoCorporativo(periodo, now);
      const dias = diasHastaFin(fin, now);
      const encargados = Array.isArray(ed.encargadoUids)
        ? (ed.encargadoUids as string[]).map(str).filter(Boolean)
        : [];
      if (encargados.length === 0) continue;

      for (const aviso of AVISOS) {
        const match =
          aviso.diasRestantes === 0
            ? !vig.vigente || dias <= 0
            : dias === aviso.diasRestantes;
        if (!match) continue;

        const key = `ultimaNotifCodigo_${aviso.id}_${fin.toISOString().slice(0, 10)}`;
        if (str(ed[key]) === "1") continue;

        for (const uid of encargados) {
          const ok = await enviarPushUid(uid, aviso.titulo, aviso.cuerpo, {
            type: aviso.id,
            empresaId: emp.id,
            rol: "encargado",
          });
          await registrarHistorialNotificacionCorp({
            empresaId: emp.id,
            uidDestino: uid,
            canal: "fcm",
            tipo: aviso.id,
            titulo: aviso.titulo,
            cuerpo: aviso.cuerpo,
            enviado: ok,
          });
          if (ok) enviados += 1;
        }

        await emp.ref.set(
          { [key]: "1", actualizadoEn: FieldValue.serverTimestamp() },
          { merge: true },
        );
      }
    }

    logger.info("scheduledCorporativoAvisosCodigoVencimiento", { enviados });
  },
);
