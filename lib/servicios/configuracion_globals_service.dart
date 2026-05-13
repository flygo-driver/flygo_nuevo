import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';

/// Umbrales de cancelación “abusiva” en giras (pruebas en calle vía `configuracion_globals/pruebas`).
class GiraAbusoRemote {
  const GiraAbusoRemote({
    required this.ratioMax,
    required this.minCreadas,
    required this.disabled,
  });

  /// Ratio máximo canceladas/creadas (ej. 0.5 = 50 %).
  final double ratioMax;
  final int minCreadas;
  final bool disabled;
}

/// Lee `configuracion_globals/app.comision_gira_porcentaje` (0.10 = 10 % o 10 = 10 %).
class ConfiguracionGlobalsService {
  ConfiguracionGlobalsService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static DateTime? _lastFetch;
  static const Duration _ttl = Duration(seconds: 60);
  static Timer? _timer;

  static double _normalizeGiraPct(num raw) {
    double v = raw.toDouble();
    if (v > 0 && v <= 1.001) v *= 100;
    return v.clamp(0.0, 100.0);
  }

  static Future<void> refreshGiraComision({bool force = false}) async {
    if (!force && _lastFetch != null) {
      if (DateTime.now().difference(_lastFetch!) < _ttl) return;
    }
    try {
      final snap =
          await _db.collection('configuracion_globals').doc('app').get();
      final raw = snap.data()?['comision_gira_porcentaje'];
      final double g = raw is num ? _normalizeGiraPct(raw) : 10.0;
      PlataformaEconomia.syncComisionGiraPorcentajeFromRemote(g);
      _lastFetch = DateTime.now();
    } catch (_) {
      PlataformaEconomia.syncComisionGiraPorcentajeFromRemote(10.0);
      _lastFetch = DateTime.now();
    }
  }

  static void startPeriodicRefresh() {
    _timer?.cancel();
    _timer = Timer.periodic(_ttl, (_) => refreshGiraComision(force: true));
  }

  static void stopPeriodicRefresh() {
    _timer?.cancel();
    _timer = null;
  }

  /// `configuracion_globals/pruebas`: `abuse_threshold` (0.5 o 50 = 50 %), `abuse_min_creadas`, `abuse_disabled`.
  static Future<GiraAbusoRemote> fetchGiraAbusoUmbral() async {
    try {
      final snap =
          await _db.collection('configuracion_globals').doc('pruebas').get();
      final d = snap.data() ?? <String, dynamic>{};
      if (d['abuse_disabled'] == true || d['gira_abuse_disabled'] == true) {
        return const GiraAbusoRemote(
          ratioMax: 1.0,
          minCreadas: 999999,
          disabled: true,
        );
      }
      final raw = d['abuse_threshold'];
      double ratio = 0.5;
      if (raw is num) {
        ratio = raw.toDouble();
        if (ratio > 1.001 && ratio <= 100) ratio = ratio / 100.0;
      }
      ratio = ratio.clamp(0.01, 0.99);
      final minRaw = d['abuse_min_creadas'];
      int minC = 3;
      if (minRaw is int) {
        minC = minRaw;
      } else if (minRaw is num) {
        minC = minRaw.toInt();
      }
      minC = minC.clamp(1, 100);
      return GiraAbusoRemote(ratioMax: ratio, minCreadas: minC, disabled: false);
    } catch (_) {
      return const GiraAbusoRemote(ratioMax: 0.5, minCreadas: 3, disabled: false);
    }
  }
}
