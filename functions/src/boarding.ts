import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const db = () => getFirestore();

// Genera un PIN de abordaje
export const issueBoardingPin = onCall(async (request) => {
  const { viajeId } = request.data;
  if (!viajeId) throw new HttpsError("invalid-argument", "Falta viajeId");

  const pin = Math.floor(1000 + Math.random() * 9000).toString();
  await db().collection("viajes").doc(viajeId).update({
    boardingPin: pin,
    boardingPinExpira: Date.now() + 10 * 60 * 1000, // 10 minutos
  });

  return { pin };
});

// Confirma el PIN al abordar
export const confirmBoarding = onCall(async (request) => {
  const { viajeId, pin } = request.data;
  const snap = await db().collection("viajes").doc(viajeId).get();
  if (!snap.exists) throw new HttpsError("not-found", "Viaje no existe");

  const data = snap.data()!;
  if (data.boardingPin !== pin) throw new HttpsError("permission-denied", "PIN incorrecto");

  await snap.ref.update({ estado: "a_bordo" });
  return { ok: true };
});
