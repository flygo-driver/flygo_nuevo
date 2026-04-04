import * as functions from "firebase-functions/v2";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const db = () => getFirestore();

// Cuando un viaje se completa -> acreditamos billetera
export const onViajeCompleted = functions.firestore.onDocumentUpdated(
  "viajes/{viajeId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.estado !== "completado" && after.estado === "completado") {
      const uidTaxista = after.uidTaxista;
      const monto = after.precio || 0;
      const ganancia = monto * 0.8;
      const comision = monto * 0.2;

      await db().collection("billeteras").doc(uidTaxista).collection("movimientos").add({
        tipo: "ingreso",
        monto: ganancia,
        viajeId: event.params.viajeId,
        createdAt: FieldValue.serverTimestamp(),
      });

      await db().collection("empresa").doc("comisiones").collection("movimientos").add({
        tipo: "comision",
        monto: comision,
        viajeId: event.params.viajeId,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  }
);
