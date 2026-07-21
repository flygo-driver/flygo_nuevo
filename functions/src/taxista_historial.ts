/**
 * Chofer: ocultar viajes completados y ya pagados de su historial local.
 * No borra el documento `viajes/{id}` (empresa / admin / facturación lo conservan).
 */
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = () => getFirestore();

function str(v: unknown): string {
  return String(v ?? "").trim();
}

function esChoferDelViaje(v: Record<string, unknown>, uid: string): boolean {
  return str(v.uidTaxista) === uid || str(v.taxistaId) === uid;
}

/** Viaje cerrado y con pago al chofer confirmado en sistema. */
export function choferViajePagadoParaOcultar(v: Record<string, unknown>): boolean {
  if (v.liquidado === true) return true;
  const ep = str(v.estadoPago).toLowerCase();
  if (ep === "pagado" || ep === "verificado" || ep === "liquidado") return true;
  if (v.pagoATaxistaPendiente === false || v.pagoTaxistaPendiente === false) {
    return true;
  }
  if (v.corporativoChoferPagadoEn != null) return true;
  return false;
}

/**
 * Oculta un viaje del historial del chofer (subcolección privada).
 * Requiere viaje completado y marcado como pagado/liquidado.
 */
export const taxistaOcultarViajeHistorial = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }

  const viajeId = str(request.data?.viajeId);
  if (!viajeId) {
    throw new HttpsError("invalid-argument", "Falta viajeId.");
  }

  const vSnap = await db().collection("viajes").doc(viajeId).get();
  if (!vSnap.exists) {
    throw new HttpsError("not-found", "Viaje no encontrado.");
  }
  const v = (vSnap.data() ?? {}) as Record<string, unknown>;

  if (!esChoferDelViaje(v, uid)) {
    throw new HttpsError("permission-denied", "Este viaje no es tuyo.");
  }
  if (v.completado !== true) {
    throw new HttpsError(
      "failed-precondition",
      "Solo podés quitar viajes ya completados.",
    );
  }
  if (!choferViajePagadoParaOcultar(v)) {
    throw new HttpsError(
      "failed-precondition",
      "Este viaje aún no figura como pagado. "
        + "Cuando RAI liquide tu pago podrás quitarlo del historial.",
    );
  }

  await db()
    .collection("usuarios")
    .doc(uid)
    .collection("historial_viajes_ocultos")
    .doc(viajeId)
    .set({
      viajeId,
      ocultoEn: FieldValue.serverTimestamp(),
      empresaCorporativaId: str(v.corporativoEmpresaId) || null,
      corporativo: v.corporativo === true || str(v.categoria) === "corporativo",
    });

  return { ok: true, viajeId };
});
