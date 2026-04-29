/**
 * Única fuente de verdad para ventanas de viajes programados (pool de conductores).
 * Duplicado en app: lib/utils/trip_publish_windows.dart — si cambias aquí, actualiza allí.
 */
/** Misma ventana que Flutter `trip_publish_windows.dart` (estilo Uber: ~45 min antes de recogida). */
export const POOL_LEAD_MINUTES_PROGRAMADO = 45;
export const READY_MINUTES_BEFORE_PICKUP = 45;
export const AHORA_THRESHOLD_MINUTES = 15;

/** Ms desde epoch: apertura del pool (mismo criterio que Flutter poolOpensAtForScheduledPickup). */
export function poolOpensAtMsForScheduledPickup(pickupMs: number, nowMs: number): number {
  const t = pickupMs - POOL_LEAD_MINUTES_PROGRAMADO * 60_000;
  return t < nowMs ? nowMs : t;
}

export function startWindowAtMsForScheduledPickup(pickupMs: number, nowMs: number): number {
  const t = pickupMs - READY_MINUTES_BEFORE_PICKUP * 60_000;
  return t < nowMs ? nowMs : t;
}
