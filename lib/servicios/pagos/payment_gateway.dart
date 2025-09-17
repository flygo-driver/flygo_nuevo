// lib/servicios/pagos/payment_gateway.dart
// Contrato del gateway de pagos + implementación Mock para desarrollo.

abstract class PaymentGateway {
  /// Identificador del proveedor (p.ej. 'stripe', 'adyen', 'mock', etc.)
  String get providerId;

  /// Construye un ID de intent/intención de pago a partir del viaje.
  String buildPaymentIntentId(String viajeId);

  /// Autoriza el pago del cliente (NO captura).
  Future<void> autorizarPago({
    required String viajeId,
    required String clienteId,
    required String paymentMethodId,
    required double montoDop,
  });

  /// Captura el pago previamente autorizado.
  Future<void> capturarPago({
    required String viajeId,
    required String paymentIntentId,
    required double montoFinalDop,
  });

  /// Cancela/void de la autorización.
  Future<void> cancelarPago({
    required String viajeId,
    required String paymentIntentId,
  });
}

/// Implementación Mock para desarrollo y pruebas locales.
/// No hace llamadas externas; solo simula latencias pequeñas.
class MockPaymentGateway implements PaymentGateway {
  @override
  String get providerId => 'mock';

  @override
  String buildPaymentIntentId(String viajeId) => 'pi_mock_$viajeId';

  @override
  Future<void> autorizarPago({
    required String viajeId,
    required String clienteId,
    required String paymentMethodId,
    required double montoDop,
  }) async {
    // Simula latencia del proveedor
    await Future<void>.delayed(const Duration(milliseconds: 120));
    // Aquí podrías validar formatos o lanzar excepciones simuladas si quieres.
  }

  @override
  Future<void> capturarPago({
    required String viajeId,
    required String paymentIntentId,
    required double montoFinalDop,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  @override
  Future<void> cancelarPago({
    required String viajeId,
    required String paymentIntentId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
}
