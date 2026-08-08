import 'package:cloud_functions/cloud_functions.dart';

import 'package:flygo_nuevo/utils/pago_tarjeta_cliente_gate.dart';

/// Cliente → Cloud Functions AZUL (Fase 6 cableado).
class AzulPaymentService {
  AzulPaymentService._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<AzulPaymentSessionResult> createSession({
    required String viajeId,
  }) async {
    if (!PagoTarjetaClienteGate.cobroHabilitado) {
      return AzulPaymentSessionResult.notConfigured(
        message: PagoTarjetaClienteGate.mensaje,
      );
    }
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

  static Future<AzulPaymentSessionResult> createRecargaTaxistaSession({
    required double montoRd,
  }) async {
    try {
      final res = await _fn.httpsCallable('azulCreateRecargaTaxistaSession').call(
        <String, dynamic>{'montoRd': montoRd},
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

  /// Marca que el cliente abrió AZUL para este viaje (retorno / resume).
  static void registrarViajePagoEnCurso(String viajeId) {
    final id = viajeId.trim();
    if (id.isEmpty) return;
    _viajePagoEnCursoId = id;
    _recargaPagoEnCursoId = null;
  }

  static void limpiarViajePagoEnCurso([String? viajeId]) {
    final id = viajeId?.trim();
    if (id == null || id.isEmpty || _viajePagoEnCursoId == id) {
      _viajePagoEnCursoId = null;
    }
  }

  static String? get viajePagoEnCursoId => _viajePagoEnCursoId;

  static String? _viajePagoEnCursoId;

  /// Taxista abrió AZUL para recarga prepago (retorno / resume → Mis pagos).
  static void registrarRecargaPagoEnCurso(String recargaId) {
    final id = recargaId.trim();
    if (id.isEmpty) return;
    _recargaPagoEnCursoId = id;
    _viajePagoEnCursoId = null;
  }

  static void limpiarRecargaPagoEnCurso([String? recargaId]) {
    final id = recargaId?.trim();
    if (id == null || id.isEmpty || _recargaPagoEnCursoId == id) {
      _recargaPagoEnCursoId = null;
    }
  }

  static String? get recargaPagoEnCursoId => _recargaPagoEnCursoId;

  static String? _recargaPagoEnCursoId;

  /// Reconcilia recarga prepago taxista al volver de AZUL (acredita + desbloqueo).
  static Future<Map<String, dynamic>> verifyRecargaTaxista({
    required String recargaId,
  }) async {
    final res = await _fn.httpsCallable('azulVerifyRecargaTaxista').call(
      <String, dynamic>{'recargaId': recargaId},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Tarjeta sin cobrar → el cliente pasa a pagar en efectivo al conductor.
  static Future<void> cambiarTarjetaAEfectivo({
    required String viajeId,
  }) async {
    await _fn.httpsCallable('cambiarTarjetaAEfectivoViaje').call(
      <String, dynamic>{'viajeId': viajeId},
    );
  }
}

class AzulPaymentSessionResult {
  const AzulPaymentSessionResult({
    required this.ok,
    this.omitido = false,
    this.notConfigured = false,
    this.viajeId,
    this.recargaId,
    this.paymentPageUrl,
    this.paymentLaunchUrl,
    this.message,
    this.useStub = false,
  });

  final bool ok;
  final bool omitido;
  final bool notConfigured;
  final String? viajeId;
  final String? recargaId;
  final String? paymentPageUrl;
  final String? paymentLaunchUrl;
  final String? message;
  final bool useStub;

  /// URL para abrir el pago (preferir launch sobre page legacy).
  String? get launchUrl {
    final launch = paymentLaunchUrl?.trim();
    if (launch != null && launch.isNotEmpty) return launch;
    final page = paymentPageUrl?.trim();
    if (page != null && page.isNotEmpty) return page;
    return null;
  }

  factory AzulPaymentSessionResult.fromMap(Map<String, dynamic> m) {
    return AzulPaymentSessionResult(
      ok: m['ok'] == true,
      omitido: m['omitido'] == true,
      viajeId: m['viajeId']?.toString(),
      recargaId: m['recargaId']?.toString(),
      paymentPageUrl: m['paymentPageUrl']?.toString(),
      paymentLaunchUrl: m['paymentLaunchUrl']?.toString(),
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
