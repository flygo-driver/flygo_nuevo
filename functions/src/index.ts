import * as admin from "firebase-admin";
import { setGlobalOptions } from "firebase-functions/v2";

admin.initializeApp();
setGlobalOptions({ region: "us-central1", maxInstances: 10 });

// Exporta tus módulos
export * from "./wallet.js";
export * from "./boarding.js";
