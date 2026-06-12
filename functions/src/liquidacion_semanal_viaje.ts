type AnyMap = Record<string, unknown>;

/** Deriva categoría desde texto `metodoPago` (variantes legacy). */
export function metodoPagoNormalizado(metodoPago: unknown): string {
  const s = String(metodoPago ?? "").toLowerCase().trim();
  if (s.includes("efectivo")) return "efectivo";
  if (s.includes("transfer")) return "transferencia";
  return "tarjeta";
}

/** Usa `metodoPagoNormalizado` almacenado o lo deriva desde `metodoPago`. */
export function metodoPagoNormalizadoDesde(data: AnyMap): string {
  const stored = String(data.metodoPagoNormalizado ?? "").trim().toLowerCase();
  if (stored === "efectivo" || stored === "transferencia" || stored === "tarjeta") {
    return stored;
  }
  return metodoPagoNormalizado(data.metodoPago);
}

/**
 * Elegibilidad para pago semanal.
 * Fuente de verdad: metodoPagoNormalizado + estadoPago + liquidado.
 * `elegibleLiquidacionSemanal` en Firestore es solo caché auxiliar.
 */
export function esElegibleLiquidacionSemanal(data: AnyMap): boolean {
  if (data.liquidado === true) return false;

  const norm = metodoPagoNormalizadoDesde(data);
  if (norm === "efectivo") return false;
  if (norm !== "transferencia" && norm !== "tarjeta") return false;

  const estadoPago = String(data.estadoPago ?? "").trim().toLowerCase();
  return estadoPago === "verificado";
}

/** Caché auxiliar coherente con [esElegibleLiquidacionSemanal]. */
export function elegibleLiquidacionSemanalCache(data: AnyMap): boolean {
  return esElegibleLiquidacionSemanal(data);
}
