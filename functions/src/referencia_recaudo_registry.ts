/**
 * Reserva atómica referenciaRecaudo ↔ viajeId (evita colisión entre viajes).
 */
import { FieldValue, getFirestore, type DocumentReference } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import { generarReferenciaRecaudoViaje } from "./viaje_referencia.js";

type AnyMap = Record<string, unknown>;

const db = () => getFirestore();

const MAX_INTENTOS = 6;

class ReferenciaRecaudoColisionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ReferenciaRecaudoColisionError";
  }
}

/**
 * Asigna referenciaRecaudo única en viaje + registro referencias_recaudo/{ref}.
 * Idempotente si el mismo viajeId re-ejecuta el trigger.
 */
export async function asignarReferenciaRecaudoUnicaEnViaje(
  viajeRef: DocumentReference,
  viajeId: string,
): Promise<string> {
  for (let intento = 0; intento < MAX_INTENTOS; intento++) {
    const seed = intento === 0 ? viajeId : `${viajeId}#${intento}`;
    const referenciaRecaudo = generarReferenciaRecaudoViaje(seed);
    const regRef = db().collection("referencias_recaudo").doc(referenciaRecaudo);

    try {
      await db().runTransaction(async (tx) => {
        const regSnap = await tx.get(regRef);
        if (regSnap.exists) {
          const other = String((regSnap.data() as AnyMap | undefined)?.viajeId ?? "").trim();
          if (other && other !== viajeId) {
            throw new ReferenciaRecaudoColisionError(referenciaRecaudo);
          }
        } else {
          tx.set(regRef, {
            viajeId,
            referenciaRecaudo,
            createdAt: FieldValue.serverTimestamp(),
          });
        }

        tx.set(
          viajeRef,
          {
            referenciaRecaudo,
            recaudoDestino: "rai",
            updatedAt: FieldValue.serverTimestamp(),
            actualizadoEn: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      });

      if (intento > 0) {
        logger.warn("[asignarReferenciaRecaudoUnicaEnViaje] colisión resuelta con retry", {
          viajeId,
          intento,
          referenciaRecaudo,
        });
      }
      return referenciaRecaudo;
    } catch (e) {
      if (e instanceof ReferenciaRecaudoColisionError && intento < MAX_INTENTOS - 1) {
        continue;
      }
      throw e;
    }
  }

  throw new Error(`No se pudo reservar referenciaRecaudo única para viaje ${viajeId}`);
}
