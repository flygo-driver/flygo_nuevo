// lib/utils/metodo_pago_viaje.dart
//
// Una sola definición de “efectivo vs transferencia vs otro”, alineada con
// [ViajesRepo.completarViajePorTaxista] (pool, motor, turismo, normal).

/// Clasificación del texto `metodoPago` guardado en `viajes`.
class MetodoPagoViaje {
  MetodoPagoViaje._();

  static String _norm(String? raw) =>
      (raw ?? '').toString().toLowerCase().trim();

  /// Coincide con el cierre contable en [ViajesRepo.completarViajePorTaxista].
  static bool esEfectivo(String? metodoPago) =>
      _norm(metodoPago).contains('efectivo');

  /// Transferencia bancaria (excluye etiquetas que solo digan “efectivo”).
  static bool esTransferencia(String? metodoPago) {
    final String s = _norm(metodoPago);
    if (s.contains('efectivo')) return false;
    return s.contains('transfer');
  }

  static bool esTarjeta(String? metodoPago) {
    final String s = _norm(metodoPago);
    if (s.contains('efectivo')) return false;
    if (s.contains('transfer')) return false;
    return s.contains('tarjeta') || s.contains('card');
  }

  /// Valores de asiento / informes internos.
  static String asientoCategoria(String? metodoPago) {
    if (esEfectivo(metodoPago)) return 'efectivo';
    if (esTransferencia(metodoPago)) return 'transferencia';
    return 'tarjeta';
  }

  /// Etiquetas para el documento del viaje (capitalización fija).
  static String etiquetaDocumento(String? metodoPago) {
    if (esEfectivo(metodoPago)) return 'Efectivo';
    if (esTransferencia(metodoPago)) return 'Transferencia';
    return 'Tarjeta';
  }
}
