import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Admin — Fase 3/4: extracto Popular y conciliación banco ↔ viaje (solo callables CF).
class ConciliacionBancoRepo {
  ConciliacionBancoRepo._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static CollectionReference<Map<String, dynamic>> get _conciliaciones =>
      FirebaseFirestore.instance.collection('conciliaciones');

  static Stream<List<Map<String, dynamic>>> streamPropuestas({int limit = 50}) {
    return _conciliaciones
        .where('estado', isEqualTo: 'propuesta')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
              .toList(growable: false),
        );
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
