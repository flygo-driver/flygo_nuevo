import 'package:cloud_functions/cloud_functions.dart';

/// Cliente → Cloud Functions AZUL (Fase 6 cableado).
class AzulPaymentService {
  AzulPaymentService._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<AzulPaymentSessionResult> createSession({
    required String viajeId,
  }) async {
    try {
      final res = await _fn.httpsCallable('azulCreatePaymentSession').call(
        <String, dynamic>{'viajeId': viajeId},
      );
      return AzulPaymentSessionResult.fromMap(
        Map<String, dynamic>.from(res.data as Map),
      );
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition' &&
          (e.message ?? '').contains('AZUL_NOT_CONFIGURED')) {
        return AzulPaymentSessionResult.notConfigured(
          message: e.message ?? 'AZUL no configurado',
        );
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> verifyPayment({
    required String viajeId,
  }) async {
    final res = await _fn.httpsCallable('azulVerifyPayment').call(
      <String, dynamic>{'viajeId': viajeId},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }
}

class AzulPaymentSessionResult {
  const AzulPaymentSessionResult({
    required this.ok,
    this.omitido = false,
    this.notConfigured = false,
    this.viajeId,
    this.paymentPageUrl,
    this.message,
    this.useStub = false,
  });

  final bool ok;
  final bool omitido;
  final bool notConfigured;
  final String? viajeId;
  final String? paymentPageUrl;
  final String? message;
  final bool useStub;

  factory AzulPaymentSessionResult.fromMap(Map<String, dynamic> m) {
    return AzulPaymentSessionResult(
      ok: m['ok'] == true,
      omitido: m['omitido'] == true,
      viajeId: m['viajeId']?.toString(),
      paymentPageUrl: m['paymentPageUrl']?.toString(),
      message: m['message']?.toString(),
      useStub: m['useStub'] == true,
    );
  }

  factory AzulPaymentSessionResult.notConfigured({required String message}) {
    return AzulPaymentSessionResult(
      ok: false,
      notConfigured: true,
      message: message,
    );
  }
}
