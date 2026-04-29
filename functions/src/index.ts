import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

initializeApp();
setGlobalOptions({ region: "us-central1", maxInstances: 10 });

// Misma superficie que producción (flygo-rd): desplegar siempre desde flygo_nuevo/functions
export * from "./wallet.js";
export * from "./boarding.js";
export * from "./finance.js";
export * from "./pool_finance.js";
export * from "./scheduled_pool_notify.js";
export * from "./scheduled_pool_departure_owner.js";
export * from "./scheduled_pool_reservations_cleanup.js";
export * from "./trip_rating.js";
export * from "./cliente_fidelidad_stats.js";
export * from "./bola_pueblo.js";
