import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
/// Lee `config/comision.porcentaje` y actualiza [PlataformaEconomia] (TTL 60s).
/// Giras por cupos usan % fijo [PlataformaEconomia.comisionGiraPorcentajeFijo] (10%).
class ComisionViajePctService {
  ComisionViajePctService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static DateTime? _lastFetch;
  static const Duration _ttl = Duration(seconds: 60);
  static Timer? _timer;

  static Future<void> refresh({bool force = false}) async {
    if (!force && _lastFetch != null) {
      if (DateTime.now().difference(_lastFetch!) < _ttl) return;
    }
    try {
      final snap = await _db.collection('config').doc('comision').get();
      final data = snap.data();
      final raw = data?['porcentaje'];
      final double p = raw is num ? raw.toDouble() : 20.0;
      final double pct = p.clamp(0.0, 100.0);
      PlataformaEconomia.syncComisionViajePorcentajeFromRemote(pct);
      _lastFetch = DateTime.now();
    } catch (_) {
      const double fallback = 20.0;
      PlataformaEconomia.syncComisionViajePorcentajeFromRemote(fallback);
      _lastFetch = DateTime.now();
    }
  }

  static void startPeriodicRefresh() {
    _timer?.cancel();
    _timer = Timer.periodic(_ttl, (_) => refresh(force: true));
  }

  static void stopPeriodicRefresh() {
    _timer?.cancel();
    _timer = null;
  }

  static double _parsePorcentajeDoc(Map<String, dynamic>? data) {
    final raw = data?['porcentaje'];
    final double p = raw is num ? raw.toDouble() : 20.0;
    return p.clamp(0.0, 100.0);
  }

  /// Stream en vivo de `config/comision.porcentaje` (sincroniza [PlataformaEconomia]).
  static Stream<double> streamPorcentajeVigente() {
    return _db.collection('config').doc('comision').snapshots().map((snap) {
      final p = _parsePorcentajeDoc(snap.data());
      PlataformaEconomia.syncComisionViajePorcentajeFromRemote(p);
      _lastFetch = DateTime.now();
      return p;
    });
  }
}
