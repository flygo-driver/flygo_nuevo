import 'metodo_pago_viaje.dart';

/// Viajes elegibles para liquidación semanal ACH (recaudo digital).
///
/// Fuente de verdad: [metodoPagoNormalizado], [estadoPago] y [liquidado].
/// El campo `elegibleLiquidacionSemanal` en Firestore es solo caché auxiliar.
class LiquidacionSemanalViaje {
  LiquidacionSemanalViaje._();

  /// Normaliza `metodoPagoNormalizado` almacenado o deriva desde `metodoPago`.
  static String metodoPagoNormalizadoDesde(Map<String, dynamic> data) {
    final stored = (data['metodoPagoNormalizado'] as String?)?.trim().toLowerCase();
    if (stored == 'efectivo' ||
        stored == 'transferencia' ||
        stored == 'tarjeta') {
      return stored!;
    }
    return MetodoPagoViaje.asientoCategoria(data['metodoPago']?.toString());
  }

  /// `true` solo si transferencia/tarjeta verificada y no liquidada.
  static bool esElegible(Map<String, dynamic> data) {
    if (data['liquidado'] == true) return false;

    final norm = metodoPagoNormalizadoDesde(data);
    if (norm == 'efectivo') return false;
    if (norm != 'transferencia' && norm != 'tarjeta') return false;

    final estadoPago =
        (data['estadoPago'] ?? '').toString().trim().toLowerCase();
    return estadoPago == 'verificado';
  }

  /// Caché auxiliar coherente con [esElegible] (no usar como autoridad).
  static bool elegibleCacheDesde(Map<String, dynamic> data) => esElegible(data);
}
