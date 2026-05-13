import * as functions from "firebase-functions/v2";

/**
 * Legacy deshabilitado: antes, al pasar a `estado === completado`, escribía en
 * `billeteras/{uid}/movimientos` y `empresa/comisiones/movimientos` con 80/20 fijo
 * sobre `precio`, duplicando y desalineando la lógica real de comisión/prepago.
 *
 * Fuente de verdad del cierre financiero: `finalizarViajeSeguro` (finance.ts) →
 * `billeteras_taxista`, asientos en `pagos`, `pagoDetalle`, `settlement`, etc.
 *
 * Se conserva el export y el trigger para que un `firebase deploy` solo actualice
 * la función (no hace falta borrarla a mano en GCP).
 */
export const onViajeCompleted = functions.firestore.onDocumentUpdated(
  "viajes/{viajeId}",
  async () => {
    // Intencionalmente vacío: no escribir en Firestore desde aquí.
  },
);
