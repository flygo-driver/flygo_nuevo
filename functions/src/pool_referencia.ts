/**
 * Referencia única por reserva pool (gira por cupos) — recaudo cuenta RAI.
 * Formato: RAI-P-{slugPool8}-{slugRes8}-{checksum2}
 */

const FORMATO = /^RAI-P-[A-Z0-9]{1,8}-[A-Z0-9]{1,8}-[0-9A-F]{2}$/;

function slug8(id: string): string {
  const raw = (id.length <= 8 ? id : id.slice(0, 8)).toUpperCase();
  return raw.replace(/[^A-Z0-9]/g, "").slice(0, 8) || "P";
}

function checksum2Hex(seed: string): string {
  let sum = 0;
  for (let i = 0; i < seed.length; i++) {
    sum = (sum + seed.charCodeAt(i)) & 0xff;
  }
  return sum.toString(16).padStart(2, "0").toUpperCase();
}

/** Idempotente: misma pareja poolId + reservaId → misma referencia. */
export function generarReferenciaRecaudoPool(poolId: string, reservaId: string): string {
  const p = String(poolId ?? "").trim();
  const r = String(reservaId ?? "").trim();
  if (!p || !r) {
    throw new Error("poolId o reservaId vacío");
  }
  const seed = `${p}:${r}`;
  return `RAI-P-${slug8(p)}-${slug8(r)}-${checksum2Hex(seed)}`;
}

export function esReferenciaRecaudoPoolValida(raw: unknown): boolean {
  const ref = String(raw ?? "").trim().toUpperCase();
  return ref.length > 0 && FORMATO.test(ref);
}
