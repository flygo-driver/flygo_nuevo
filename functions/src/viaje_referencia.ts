/**
 * Referencia única por viaje para recaudo Banco Popular (Fase 5).
 * Formato: RAI-V-{slug8}-{checksum2}
 */

const FORMATO = /^RAI-V-[A-Z0-9]{1,8}-[0-9A-F]{2}$/;

function checksum2Hex(viajeId: string): string {
  let sum = 0;
  for (let i = 0; i < viajeId.length; i++) {
    sum = (sum + viajeId.charCodeAt(i)) & 0xff;
  }
  return sum.toString(16).padStart(2, "0").toUpperCase();
}

/** Genera referencia idempotente a partir del id del viaje. */
export function generarReferenciaRecaudoViaje(viajeId: string): string {
  const id = String(viajeId ?? "").trim();
  if (!id) {
    throw new Error("viajeId vacío");
  }
  const slugRaw = (id.length <= 8 ? id : id.slice(0, 8)).toUpperCase();
  const slug = slugRaw.replace(/[^A-Z0-9]/g, "").slice(0, 8) || "V";
  return `RAI-V-${slug}-${checksum2Hex(id)}`;
}

export function esReferenciaRecaudoValida(raw: unknown): boolean {
  const ref = String(raw ?? "").trim().toUpperCase();
  return ref.length > 0 && FORMATO.test(ref);
}
