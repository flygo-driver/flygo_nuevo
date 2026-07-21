import 'package:cloud_functions/cloud_functions.dart';

/// Callables Fase A corporativo (notificaciones, código, sustituto).
abstract final class CorporativoFaseAService {
  CorporativoFaseAService._();

  static final _fn = FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<int> reenviarCodigoATodos(String empresaId) async {
    final res = await _fn
        .httpsCallable('encargadoReenviarCodigoCorporativo')
        .call({'empresaId': empresaId});
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['enviados'] as num?)?.toInt() ?? 0;
  }

  static Future<void> asignarSustitutoManual({
    required String empresaId,
    required String plantillaId,
    required String choferUid,
  }) async {
    await _fn.httpsCallable('encargadoAsignarSustitutoCorporativo').call({
      'empresaId': empresaId,
      'plantillaId': plantillaId,
      'choferUid': choferUid,
    });
  }

  static Future<Map<String, dynamic>> asignarSustitutoUrgenteAdmin({
    required String empresaId,
    required String plantillaId,
  }) async {
    final res = await _fn.httpsCallable('adminAsignarSustitutoUrgenteCorp').call({
      'empresaId': empresaId,
      'plantillaId': plantillaId,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<void> taxistaSolicitarCodigo(String viajeId) async {
    await _fn.httpsCallable('taxistaSolicitarCodigoCorporativo').call({
      'viajeId': viajeId.trim(),
    });
  }

  static Future<void> encargadoEnviarCodigo({
    required String viajeId,
    bool generarCodigoRespaldo = false,
  }) async {
    await _fn.httpsCallable('encargadoEnviarCodigoCorporativo').call({
      'viajeId': viajeId.trim(),
      'generarCodigoRespaldo': generarCodigoRespaldo,
    });
  }
}
