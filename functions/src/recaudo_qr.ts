/**
 * Fase 5c — QR recaudo Popular (stub cableado; reemplazar payload por API banco).
 */
import { FieldValue, type DocumentReference } from "firebase-admin/firestore";

import { getFinanceConfig } from "./finance.js";
import { precioCentsViaje } from "./conciliacion.js";

type AnyMap = Record<string, unknown>;

/** Cuenta RAI por defecto (misma que recarga; override futuro en config/empresa). */
export const RAI_CUENTA_RECAUDO_DEFAULT = {
  titular: "Open ASK Service SRL",
  banco: "Banco Popular",
  tipoCuenta: "Cuenta Corriente",
  numeroCuenta: "816104582",
  rnc: "1320-11767",
};

/**
 * Payload QR interno v1 (placeholder hasta API Popular/AZUL/Toke).
 * Formato legible: reemplazar por string EMV o URL del banco sin cambiar campos Firestore.
 */
export function buildQrRecaudoPayloadStub(input: {
  referenciaRecaudo: string;
  montoCents: number;
  viajeId: string;
  cuenta?: Partial<typeof RAI_CUENTA_RECAUDO_DEFAULT>;
}): { payload: string; tipo: string; version: string } {
  const c = { ...RAI_CUENTA_RECAUDO_DEFAULT, ...input.cuenta };
  const montoRd = (Math.max(0, input.montoCents) / 100).toFixed(2);
  const payload = [
    "RAI-RECAUDO",
    "v=1",
    `ref=${input.referenciaRecaudo}`,
    `amt=${montoRd}`,
    "cur=DOP",
    `acct=${c.numeroCuenta}`,
    `bn=${c.banco}`,
    `rnc=${c.rnc}`,
    `vid=${input.viajeId.slice(0, 12)}`,
  ].join("|");
  return { payload, tipo: "popular_stub_v1", version: "1" };
}

/** Escribe metadata QR en viaje (solo Admin SDK). */
export async function asignarQrRecaudoEnViaje(
  viajeRef: DocumentReference,
  viajeId: string,
  data: AnyMap,
  referenciaRecaudo: string,
): Promise<void> {
  const cfg = await getFinanceConfig();
  if (!cfg.transferenciaRecaudoEnCuentaRai) return;

  const ref = String(referenciaRecaudo ?? "").trim();
  if (!ref) return;

  const refViaje = String(data.referenciaRecaudo ?? "").trim();
  if (refViaje && refViaje !== ref) return;
  if (refViaje === ref && String(data.qrRecaudoPayload ?? "").trim()) return;

  const montoCents = precioCentsViaje(data);
  const built = buildQrRecaudoPayloadStub({
    referenciaRecaudo: ref,
    montoCents,
    viajeId,
  });

  await viajeRef.set(
    {
      qrRecaudoPayload: built.payload,
      qrRecaudoTipo: built.tipo,
      qrRecaudoVersion: built.version,
      qrRecaudoGeneradoEn: FieldValue.serverTimestamp(),
      qrRecaudoEstado: "pendiente_api_banco",
      updatedAt: FieldValue.serverTimestamp(),
      actualizadoEn: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}
