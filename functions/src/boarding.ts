import * as functions from "firebase-functions/v2";
import * as admin from "firebase-admin";

const db = admin.firestore();

// Genera un PIN de abordaje
export const issueBoardingPin = functions.https.onCall(async (request) => {
  const { viajeId } = request.data;
  if (!viajeId) throw new functions.https.HttpsError("invalid-argument", "Falta viajeId");

  const pin = Math.floor(1000 + Math.random() * 9000).toString();
  await db.collection("viajes").doc(viajeId).update({
    boardingPin: pin,
    boardingPinExpira: Date.now() + 10 * 60 * 1000, // 10 minutos
  });

  return { pin };
});

// Confirma el PIN al abordar
export const confirmBoarding = functions.https.onCall(async (request) => {
  const { viajeId, pin } = request.data;
  const snap = await db.collection("viajes").doc(viajeId).get();
  if (!snap.exists) throw new functions.https.HttpsError("not-found", "Viaje no existe");

  const data = snap.data()!;
  if (data.boardingPin !== pin) throw new functions.https.HttpsError("permission-denied", "PIN incorrecto");

  await snap.ref.update({ estado: "a_bordo" });
  return { ok: true };
});
