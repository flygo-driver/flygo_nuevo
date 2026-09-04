import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Umbrales `config/comision_prepago` (misma fuente que Cloud Functions).
class ComisionPrepagoConfigService {
  ComisionPrepagoConfigService._();

  static const double _defaultMinimoOperativoRd = 200;
  static const double _defaultUmbralPreventivoRd = 250;

  static double minimoOperativoRd = _defaultMinimoOperativoRd;
  static double umbralPreventivoRd = _defaultUmbralPreventivoRd;
  /// Permite aceptar viaje aunque el prepago no cubra toda la comisión (deuda al
  /// finalizar). Por defecto **prepago estricto**: solo se activa si ADM lo pone
  /// explícitamente en `true` en `config/comision_prepago`.
  static bool permitirViajeConPrepagoParcial = false;

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  static bool _started = false;

  static Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('config')
          .doc('comision_prepago')
          .get();
      _apply(snap.data());
    } catch (_) {}
    _sub = FirebaseFirestore.instance
        .collection('config')
        .doc('comision_prepago')
        .snapshots()
        .listen((snap) => _apply(snap.data()));
  }

  static void _apply(Map<String, dynamic>? data) {
    if (data == null) return;
    final min = data['minimoOperativoRd'];
    if (min is num && min.isFinite && min > 0) {
      minimoOperativoRd = min.toDouble();
    }
    final umbral = data['umbralPreventivoRd'];
    if (umbral is num && umbral.isFinite && umbral > 0) {
      umbralPreventivoRd = umbral.toDouble();
    }
    permitirViajeConPrepagoParcial =
        data['permitirViajeConPrepagoParcial'] == true;
  }

  static void disposeService() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
