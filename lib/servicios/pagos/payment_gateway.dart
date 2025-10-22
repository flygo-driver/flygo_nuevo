// lib/servicios/pagos/payment_gateway.dart
// Contrato del gateway de pagos + implementación Mock (dev) y Blaze (prod).

import 'package:cloud_functions/cloud_functions.dart';

/// =====================
/// CONTRATO
/// =====================
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

/// =====================
/// MOCK (desarrollo)
/// =====================
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
    await Future<void>.delayed(const Duration(milliseconds: 120));
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

/// =====================
/// BLAZE (producción)
/// =====================
/// Llama a Cloud Functions onCall:
///  - blaze_authorizePayment
///  - blaze_capturePayment
///  - blaze_cancelPayment
///
/// Si usas región distinta, crea la instancia así:
///   final _fx = FirebaseFunctions.instanceFor(region: 'us-central1');
class BlazePaymentGateway implements PaymentGateway {
  BlazePaymentGateway({FirebaseFunctions? functions})
      : _fx = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _fx;

  @override
  String get providerId => 'plan_blaze';

  @override
  String buildPaymentIntentId(String viajeId) => 'blz_$viajeId';

  @override
  Future<void> autorizarPago({
    required String viajeId,
    required String clienteId,
    required String paymentMethodId,
    required double montoDop,
  }) async {
    final callable = _fx.httpsCallable('blaze_authorizePayment');
    final payload = {
      'viajeId': viajeId,
      'clienteId': clienteId,
      'paymentMethodId': paymentMethodId,
      'amount': double.parse(montoDop.toStringAsFixed(2)),
      'paymentIntentId': buildPaymentIntentId(viajeId),
    };
    final res = await callable.call(payload);
    final ok = (res.data is Map) ? (res.data['ok'] == true) : true;
    if (!ok) {
      final msg = (res.data is Map) ? (res.data['error'] ?? 'Error autorizar') : 'Error autorizar';
      throw Exception(msg.toString());
    }
  }

  @override
  Future<void> capturarPago({
    required String viajeId,
    required String paymentIntentId,
    required double montoFinalDop,
  }) async {
    final callable = _fx.httpsCallable('blaze_capturePayment');
    final payload = {
      'viajeId': viajeId,
      'paymentIntentId': paymentIntentId,
      'amount': double.parse(montoFinalDop.toStringAsFixed(2)),
    };
    final res = await callable.call(payload);
    final ok = (res.data is Map) ? (res.data['ok'] == true) : true;
    if (!ok) {
      final msg = (res.data is Map) ? (res.data['error'] ?? 'Error capturar') : 'Error capturar';
      throw Exception(msg.toString());
    }
  }

  @override
  Future<void> cancelarPago({
    required String viajeId,
    required String paymentIntentId,
  }) async {
    final callable = _fx.httpsCallable('blaze_cancelPayment');
    final payload = {
      'viajeId': viajeId,
      'paymentIntentId': paymentIntentId,
    };
    final res = await callable.call(payload);
    final ok = (res.data is Map) ? (res.data['ok'] == true) : true;
    if (!ok) {
      final msg = (res.data is Map) ? (res.data['error'] ?? 'Error cancelar') : 'Error cancelar';
      throw Exception(msg.toString());
    }
  }
}
