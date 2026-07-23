/**
 * Constantes operativas corporativas (ventanas, publicación, «Enviar ahora»).
 * Debe coincidir con `lib/utils/corporativo_ventanas_constants.dart`.
 */
export const CORP_MINUTOS_PUBLICAR_ANTES_DEFAULT = 90;
export const CORP_ENVIAR_AHORA_OFFSET_MIN = 20;
export const CORP_VENTANA_TOLERANCIA_MIN = 10;
export const CORP_CONTRATO_VERSION = "1.0";

export function minutosPublicarAntesCorporativo(raw: unknown): number {
  if (typeof raw === "number" && Number.isFinite(raw)) {
    return Math.max(3, Math.trunc(raw));
  }
  return CORP_MINUTOS_PUBLICAR_ANTES_DEFAULT;
}

/** Ms de apertura del pool corporativo (mismo criterio que publicación automática). */
export function corporativoPoolOpensAtMs(
  pickupMs: number,
  nowMs: number,
  minPub = CORP_MINUTOS_PUBLICAR_ANTES_DEFAULT,
): number {
  const leadMs = Math.max(3, Math.trunc(minPub)) * 60_000;
  const t = pickupMs - leadMs;
  return t < nowMs ? nowMs : t;
}
