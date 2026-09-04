import test from "node:test";
import assert from "node:assert/strict";
import {
  AHORA_THRESHOLD_MINUTES,
  POOL_LEAD_MINUTES_PROGRAMADO,
  poolOpensAtMsForScheduledPickup,
  startWindowAtMsForScheduledPickup,
} from "../lib/trip_publish_windows.js";

test("poolOpensAtMsForScheduledPickup — mañana abre T-45 min", () => {
  const nowMs = Date.UTC(2026, 7, 12, 14, 0, 0);
  const pickupMs = Date.UTC(2026, 7, 13, 14, 0, 0);
  const opensMs = poolOpensAtMsForScheduledPickup(pickupMs, nowMs);
  const expected = pickupMs - POOL_LEAD_MINUTES_PROGRAMADO * 60_000;
  assert.equal(opensMs, expected);
  assert.ok(opensMs > nowMs);
});

test("poolOpensAtMsForScheduledPickup — pickup pasado abre ahora", () => {
  const nowMs = Date.UTC(2026, 7, 13, 15, 0, 0);
  const pickupMs = Date.UTC(2026, 7, 13, 14, 0, 0);
  assert.equal(poolOpensAtMsForScheduledPickup(pickupMs, nowMs), nowMs);
});

test("startWindowAtMsForScheduledPickup — misma ventana 45 min", () => {
  const nowMs = Date.UTC(2026, 7, 12, 10, 0, 0);
  const pickupMs = Date.UTC(2026, 7, 14, 8, 30, 0);
  const startMs = startWindowAtMsForScheduledPickup(pickupMs, nowMs);
  const expected = pickupMs - POOL_LEAD_MINUTES_PROGRAMADO * 60_000;
  assert.equal(startMs, expected);
});

test("constantes alineadas Flutter ↔ servidor", () => {
  assert.equal(POOL_LEAD_MINUTES_PROGRAMADO, 45);
  assert.equal(AHORA_THRESHOLD_MINUTES, 15);
});
