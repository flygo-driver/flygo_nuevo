import 'package:cloud_functions/cloud_functions.dart';

/// Admin — Fase 3/4: extracto Popular y conciliación banco ↔ viaje (callables CF).
class ConciliacionBancoRepo {
  ConciliacionBancoRepo._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<List<Map<String, dynamic>>> _listarPropuestas({
    int limit = 50,
  }) async {
    final res = await _fn.httpsCallable('listarConciliacionesPropuestas').call(
      <String, dynamic>{'limit': limit},
    );
    final data = Map<String, dynamic>.from(res.data as Map);
    final raw = data['conciliaciones'];
    if (raw is! List) return const [];
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  /// Lista vía Cloud Function (Admin SDK) para evitar permission-denied en cliente.
  static Stream<List<Map<String, dynamic>>> streamPropuestas({int limit = 50}) {
    return Stream.periodic(const Duration(seconds: 10)).asyncMap((_) async {
      return _listarPropuestas(limit: limit);
    }).startWith(_listarPropuestas(limit: limit));
  }

  static Future<Map<String, dynamic>> proponerAutomaticas({int limit = 30}) async {
    final res = await _fn.httpsCallable('proponerConciliacionesAutomaticas').call(
      <String, dynamic>{'limit': limit},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>> importarExtractoCsv({
    required String csv,
    String cuentaRaiUltimos4 = '',
  }) async {
    final res = await _fn.httpsCallable('importarExtractoPopular').call(
      <String, dynamic>{
        'csv': csv,
        if (cuentaRaiUltimos4.trim().isNotEmpty)
          'cuentaRaiUltimos4': cuentaRaiUltimos4.trim(),
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<void> confirmar({
    required String conciliacionId,
    String notaAdmin = '',
  }) async {
    await _fn.httpsCallable('confirmarConciliacion').call(
      <String, dynamic>{
        'conciliacionId': conciliacionId,
        'notaAdmin': notaAdmin,
      },
    );
  }

  static Future<void> rechazar({
    required String conciliacionId,
    required String notaAdmin,
  }) async {
    await _fn.httpsCallable('rechazarConciliacion').call(
      <String, dynamic>{
        'conciliacionId': conciliacionId,
        'notaAdmin': notaAdmin,
      },
    );
  }
}

extension<T> on Stream<T> {
  Stream<T> startWith(Future<T> first) async* {
    yield await first;
    yield* this;
  }
}
