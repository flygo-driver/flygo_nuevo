import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/servicios/configuracion_globals_service.dart';

/// Lee `config/comision.porcentaje` y actualiza [PlataformaEconomia] (TTL 60s).
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
      PlataformaEconomia.syncComisionViajePorcentajeFromRemote(p.clamp(0.0, 100.0));
      await ConfiguracionGlobalsService.refreshGiraComision(force: true);
      _lastFetch = DateTime.now();
    } catch (_) {
      PlataformaEconomia.syncComisionViajePorcentajeFromRemote(20.0);
      PlataformaEconomia.syncComisionGiraPorcentajeFromRemote(10.0);
      await ConfiguracionGlobalsService.refreshGiraComision(force: true);
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
}
