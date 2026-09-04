import { HttpsError } from "firebase-functions/v2/https";

/** Alineado con lib/legal/terms_data.dart */
const K_TAXISTA_CONTRACT_VERSION = "1.0";
const RENOVACION_DOCUMENTOS_DIAS = 183;

type AnyMap = Record<string, unknown>;

function taxistaDocsEstado(u: AnyMap): string {
  const raw = String(u.docsEstado ?? u.estadoDocumentos ?? "pendiente")
    .trim()
    .toLowerCase();
  return raw || "pendiente";
}

function docsVerificadoEnDate(u: AnyMap): Date | null {
  const v = u.docsVerificadoEn;
  if (v && typeof (v as { toDate?: () => Date }).toDate === "function") {
    return (v as { toDate: () => Date }).toDate();
  }
  return null;
}

/** Paridad con taxistaRequiereRenovacionDocumentos (Dart). */
function taxistaRequiereRenovacionDocumentos(u: AnyMap): boolean {
  if (taxistaDocsEstado(u) !== "aprobado") return false;
  if (u.documentosCompletos !== true) return false;
  const verified = docsVerificadoEnDate(u);
  if (!verified) return false;
  const limit = new Date(verified.getTime());
  limit.setDate(limit.getDate() + RENOVACION_DOCUMENTOS_DIAS);
  return new Date() > limit;
}

/** Paridad con taxistaAprobadoParaOperarPool (Dart). */
export function taxistaAprobadoParaOperarPool(u: AnyMap): boolean {
  if (taxistaDocsEstado(u) !== "aprobado") return false;
  const docsOk = u.documentosCompletos === true || u.puedeRecibirViajes === true;
  if (!docsOk) return false;
  if (taxistaRequiereRenovacionDocumentos(u)) return false;
  return true;
}

/** Paridad con taxistaContratoFirmado (Dart). */
export function taxistaContratoFirmado(u: AnyMap): boolean {
  if (u.contratoTaxistaAceptado !== true) return false;
  return String(u.contratoTaxistaVersion ?? "").trim() === K_TAXISTA_CONTRACT_VERSION;
}

/** Valida elegibilidad para claim pool (aceptarViajeSeguro y rutas equivalentes). */
export function assertTaxistaAptoParaClaimPool(u: AnyMap): void {
  if (u.bloqueado === true) {
    throw new HttpsError("failed-precondition", "bloqueado-admin");
  }
  if (u.registroTaxistaCompleto !== true) {
    throw new HttpsError("failed-precondition", "registro-incompleto");
  }
  if (!taxistaContratoFirmado(u)) {
    throw new HttpsError("failed-precondition", "contrato-no-firmado");
  }
  if (!taxistaAprobadoParaOperarPool(u)) {
    throw new HttpsError("failed-precondition", "documentos-no-aprobados");
  }
}
