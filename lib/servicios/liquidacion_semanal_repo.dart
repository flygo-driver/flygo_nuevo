import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../modelo/liquidacion_semanal.dart';

class LiquidacionSemanalRepo {
  LiquidacionSemanalRepo._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('liquidaciones_semanales');

  static Stream<List<LiquidacionSemanal>> streamPorTaxista(String uidTaxista) {
    if (uidTaxista.trim().isEmpty) {
      return Stream.value(const <LiquidacionSemanal>[]);
    }
    return _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .orderBy('periodoFin', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => LiquidacionSemanal.fromMap(d.id, d.data()))
            .toList(growable: false));
  }

  static Stream<List<LiquidacionSemanal>> streamPendientesAdmin() {
    return _col
        .where('estado', whereIn: ['borrador', 'pendiente_pago'])
        .orderBy('periodoFin', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => LiquidacionSemanal.fromMap(d.id, d.data()))
            .toList(growable: false));
  }

  static Future<void> aprobarLiquidacion({
    required String liquidacionId,
    String? notaAdmin,
    String? referenciaAch,
  }) async {
    final idemKey =
        'aprobar_liq_${liquidacionId}_${DateTime.now().millisecondsSinceEpoch}';
    await FirebaseFunctions.instance
        .httpsCallable('aprobarLiquidacionSemanal')
        .call(<String, dynamic>{
      'liquidacionId': liquidacionId,
      'notaAdmin': notaAdmin ?? '',
      'referenciaAch': referenciaAch ?? '',
      'idempotencyKey': idemKey,
    });
  }

  static Future<void> cancelarLiquidacion({
    required String liquidacionId,
    required String motivo,
  }) async {
    await FirebaseFunctions.instance
        .httpsCallable('cancelarLiquidacionSemanal')
        .call(<String, dynamic>{
      'liquidacionId': liquidacionId,
      'motivo': motivo,
    });
  }

  static Future<void> generarParaTaxista({
    required String uidTaxista,
    String? periodo,
  }) async {
    await FirebaseFunctions.instance
        .httpsCallable('generarLiquidacionSemanalTaxista')
        .call(<String, dynamic>{
      'uidTaxista': uidTaxista,
      if (periodo != null && periodo.trim().isNotEmpty) 'periodo': periodo,
    });
  }

  static Future<List<LiquidacionSemanal>> listarTaxistaViaCf(
    String uidTaxista,
  ) async {
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('obtenerLiquidacionSemanalTaxista')
          .call(<String, dynamic>{'uidTaxista': uidTaxista});
      final data = res.data;
      if (data is! Map) return const <LiquidacionSemanal>[];
      final list = data['liquidaciones'];
      if (list is! List) return const <LiquidacionSemanal>[];
      return list
          .whereType<Map>()
          .map((m) {
            final id = (m['id'] ?? '').toString();
            final map = Map<String, dynamic>.from(m);
            map.remove('id');
            return LiquidacionSemanal.fromMap(id, map);
          })
          .toList(growable: false);
    } catch (e) {
      debugPrint('obtenerLiquidacionSemanalTaxista: $e');
      return const <LiquidacionSemanal>[];
    }
  }
}
