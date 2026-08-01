/**
 * Secretos AZUL (Firebase Secret Manager).
 *
 * Configurar en producción / staging:
 *   firebase functions:secrets:set AZUL_STORE_ID
 *   firebase functions:secrets:set AZUL_AUTH_KEY
 *
 * Emulador local: functions/.secret.local (no commitear).
 */
import { defineSecret } from "firebase-functions/params";

export const azulStoreIdSecret = defineSecret("AZUL_STORE_ID");
export const azulAuthKeySecret = defineSecret("AZUL_AUTH_KEY");

/** Pasar a `secrets:` en cada export AZUL que lea credenciales. */
export const azulRuntimeSecrets = [azulStoreIdSecret, azulAuthKeySecret];

export function getAzulAuthKey(): string {
  return String(process.env.AZUL_AUTH_KEY ?? "").trim();
}

export function getAzulMerchantName(): string {
  const name = String(process.env.AZUL_MERCHANT_NAME ?? "OPEN ASK SERVICE SRL").trim();
  return name || "OPEN ASK SERVICE SRL";
}
