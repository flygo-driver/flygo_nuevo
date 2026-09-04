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

  /// Cliente paga a cuenta RAI (tarjeta / transfer conciliada): liquidación semanal.
  static bool viajeRecaudoEnCuentaRai(Map<String, dynamic> viajeData) {
    final String ref =
        (viajeData['referenciaRecaudo'] ?? '').toString().trim();
    final String dest =
        (viajeData['recaudoDestino'] ?? '').toString().trim().toLowerCase();
    return ref.isNotEmpty || dest == 'rai';
  }

  /// AZUL capturó el cobro (solo servidor / webhook escribe estos campos).
  static bool tarjetaPagadoVerificado(Map<String, dynamic> data) {
    final ep =
        (data['estadoPago'] ?? '').toString().trim().toLowerCase();
    final ps = (data['payment'] is Map)
        ? (data['payment'] as Map)['status']?.toString().trim().toLowerCase()
        : '';
    return ep == 'verificado' || ps == 'captured';
  }

  /// Intento de cobro rechazado por AZUL/banco (sin fondos, declinada, etc.).
  static bool tarjetaPagoFallido(Map<String, dynamic> data) {
    if (tarjetaPagadoVerificado(data)) return false;
    final ps = (data['payment'] is Map)
        ? (data['payment'] as Map)['status']?.toString().trim().toLowerCase()
        : '';
    return ps == 'failed';
  }

  static String? tarjetaUltimoErrorAzul(Map<String, dynamic> data) {
    if (data['payment'] is! Map) return null;
    final err = (data['payment'] as Map)['azulLastError']?.toString().trim();
    if (err == null || err.isEmpty) return null;
    return err;
  }

  /// Cliente cambió de tarjeta a efectivo (callable servidor).
  static bool cambioDesdeTarjetaAEfectivo(Map<String, dynamic> data) {
    if (!esEfectivo(data['metodoPago']?.toString())) return false;
    final anterior =
        (data['metodoPagoAnterior'] ?? '').toString().toLowerCase().trim();
    if (anterior.contains('tarjeta') || anterior.contains('card')) return true;
    return data['tarjetaCambioEfectivoEn'] != null;
  }

  /// Tarjeta sin cobrar: pendiente o rechazada (ofrecer efectivo).
  static bool tarjetaPendienteOCobroFallido(Map<String, dynamic> data) {
    if (!esTarjeta(data['metodoPago']?.toString())) return false;
    return !tarjetaPagadoVerificado(data);
  }

  /// Cliente debe pagar o regularizar antes de seguir (bloqueo estricto en factura).
  static bool cobroClienteBloqueaApp(Map<String, dynamic> data) {
    if (tarjetaPagadoVerificado(data)) return false;
    if (impagoRegistrado(data)) return false;
    // Efectivo (incl. cambio desde tarjeta): cobro en mano; no bloquear por flags
    // de tarjeta pendiente que el servidor pudo dejar al cerrar el viaje.
    if (esEfectivo(data['metodoPago']?.toString())) return false;
    final estado =
        (data['cobroClienteEstado'] ?? '').toString().trim().toLowerCase();
    if (estado == 'pagado' || estado == 'regularizado') return false;
    if (data['cobroClientePendiente'] == true) return true;
    if (esTarjeta(data['metodoPago']?.toString()) &&
        !tarjetaPagadoVerificado(data)) {
      return true;
    }
    return false;
  }

  static bool impagoRegistrado(Map<String, dynamic> data) {
    return (data['cobroClienteEstado'] ?? '')
            .toString()
            .trim()
            .toLowerCase() ==
        'impago_registrado';
  }

  static double cobroClienteMontoRd(Map<String, dynamic> data) {
    final v = data['cobroClienteMontoRd'];
    if (v is num) return v.toDouble();
    final precio = data['precio'];
    if (precio is num) return precio.toDouble();
    return 0;
  }
}
