/**
 * Monitoreo de viajes corporativos sin finalizar (alerta ADM).
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";

type AnyMap = Record<string, unknown>;

function str(v: unknown): string {
  return String(v ?? "").trim();
}

/** Cada 30 min: viajes corp en_curso > 6 h sin completar → alerta admin. */
export const scheduledCorporativoViajesSinFinalizar = onSchedule(
  {
    schedule: "every 30 minutes",
    timeZone: "America/Santo_Domingo",
    memory: "256MiB",
    timeoutSeconds: 180,
  },
  async () => {
    const db = getFirestore();
    const now = Date.now();
    const umbralMs = 6 * 60 * 60 * 1000;
    let alertas = 0;

    const snap = await db
      .collection("viajes")
      .where("corporativo", "==", true)
      .where("estado", "==", "en_curso")
      .where("activo", "==", true)
      .limit(30)
      .get();

    for (const doc of snap.docs) {
      const d = doc.data() as AnyMap;
      const inicio = d.inicioViaje ?? d.viajeIniciadoEn ?? d.codigoVerificadoEn;
      const ts =
        inicio && typeof (inicio as { toDate?: () => Date }).toDate === "function"
          ? (inicio as { toDate: () => Date }).toDate().getTime()
          : 0;
      if (!ts || now - ts < umbralMs) continue;

      const alertKey = `alertaSinFinalizar_${doc.id}`;
      if (str(d[alertKey]) === "1") continue;

      await db.collection("alertas_admin").add({
        tipo: "corporativo_viaje_sin_finalizar",
        viajeId: doc.id,
        empresaId: str(d.corporativoEmpresaId),
        uidTaxista: str(d.uidTaxista ?? d.taxistaId),
        titulo: "Viaje corporativo sin finalizar",
        mensaje:
          `Viaje ${doc.id} lleva más de 6 h en curso. ` +
          `Revisar GPS y contactar al chofer.`,
        leida: false,
        creadoEn: FieldValue.serverTimestamp(),
      });

      await doc.ref.set(
        { [alertKey]: "1", actualizadoEn: FieldValue.serverTimestamp() },
        { merge: true },
      );
      alertas += 1;
    }

    logger.info("scheduledCorporativoViajesSinFinalizar", { alertas });
  },
);
