/**
 * Publica config/tarifas_tramos en Firestore (flygo-rd).
 * Uso: gcloud auth application-default login  (o GOOGLE_APPLICATION_CREDENTIALS)
 *      cd functions && node ../scripts/seed_tarifas_tramos.mjs
 */
import admin from "firebase-admin";

const data = {
  activo: true,
  tramosKm: [40, 80, 140],
  minimoLargaDistanciaRd: 1200,
  promoAplicaSoloTramoLocal: true,
  distanciaMaximaCotizableKm: 800,
  version: 1,
  porVehiculo: {
    Carro: { porKmPorTramo: [25, 45, 60, 72] },
    Jeepeta: { porKmPorTramo: [30, 50, 65, 80] },
    Minivan: { porKmPorTramo: [32, 52, 68, 82] },
    "Minibús": { porKmPorTramo: [35, 55, 70, 85] },
    AutobusGuagua: { porKmPorTramo: [45, 65, 80, 95] },
    motor: { porKmPorTramo: [12, 22, 35, 42] },
    carro: { porKmPorTramo: [25, 45, 60, 72] },
    jeepeta: { porKmPorTramo: [30, 50, 65, 80] },
    minivan: { porKmPorTramo: [35, 55, 70, 85] },
    bus: { porKmPorTramo: [45, 65, 80, 95] },
  },
};

admin.initializeApp({ projectId: "flygo-rd" });
await admin.firestore().doc("config/tarifas_tramos").set(data, { merge: true });
console.log("OK config/tarifas_tramos", JSON.stringify(data, null, 2));
process.exit(0);
