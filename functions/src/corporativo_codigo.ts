/**
 * Código de acceso corporativo: uno por período de liquidación (no por viaje).
 */
type AnyMap = Record<string, unknown>;

export function generarCodigoAccesoPeriodo(): string {
  return String(100000 + Math.floor(Math.random() * 900000));
}

export function codigoAccesoDesdePeriodo(periodo: AnyMap | null | undefined): string {
  const raw = String(periodo?.codigoAcceso ?? "").replace(/\D/g, "");
  return raw.length === 6 ? raw : "";
}

export function codigoAccesoPeriodoOGenerar(periodo: AnyMap | null | undefined): string {
  return codigoAccesoDesdePeriodo(periodo) || generarCodigoAccesoPeriodo();
}
