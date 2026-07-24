import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Historial del chofer: ocultar viajes pagados sin borrar el doc `viajes`.
abstract final class TaxistaHistorialRepo {
  TaxistaHistorialRepo._();

  static final _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _ocultos(String uid) =>
      _db
          .collection('usuarios')
          .doc(uid.trim())
          .collection('historial_viajes_ocultos');

  /// IDs de viajes que el chofer quitó de su historial.
  static Future<Set<String>> idsOcultos(String uid) async {
    final id = uid.trim();
    if (id.isEmpty) return <String>{};
    try {
      final snap = await _ocultos(id).limit(500).get();
      return snap.docs.map((d) => d.id).toSet();
    } catch (e) {
      debugPrint('[TaxistaHistorialRepo] idsOcultos: $e');
      return <String>{};
    }
  }

  /// Quita el viaje del historial del chofer (solo si ya está pagado/liquidado).
  static Future<void> ocultarViaje({
    required String uid,
    required String viajeId,
  }) async {
    final id = viajeId.trim();
    if (id.isEmpty) throw 'Viaje inválido.';
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('taxistaOcultarViajeHistorial')
          .call(<String, dynamic>{'viajeId': id});
      final ok = res.data is Map && (res.data as Map)['ok'] == true;
      if (!ok) {
        throw 'No se pudo quitar el viaje del historial.';
      }
    } on FirebaseFunctionsException catch (e) {
      throw e.message ??
          'No se pudo quitar el viaje. Reintentá cuando figure como pagado.';
    }
  }

  static bool viajePagadoParaOcultar(Map<String, dynamic> d) {
    if (d['liquidado'] == true) return true;
    final ep = (d['estadoPago'] ?? '').toString().trim().toLowerCase();
    if (ep == 'pagado' || ep == 'verificado' || ep == 'liquidado') {
      return true;
    }
    if (d['pagoATaxistaPendiente'] == false ||
        d['pagoTaxistaPendiente'] == false) {
      return true;
    }
    if (d['corporativoChoferPagadoEn'] != null) return true;
    return false;
  }
}
