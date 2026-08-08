import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';

/// Configuración de comisiones RAI (`config/comision`).
class ComisionConfigMetodos {
  final double efectivo;
  final double transferencia;
  final double tarjeta;

  const ComisionConfigMetodos({
    this.efectivo = 10,
    this.transferencia = 15,
    this.tarjeta = 15,
  });

  static ComisionConfigMetodos fromMap(Map<String, dynamic>? data) {
    double read(String key, double fallback) {
      final raw = data?[key];
      if (raw is! num || !raw.isFinite) return fallback;
      return raw.toDouble().clamp(0.0, 100.0);
    }

    return ComisionConfigMetodos(
      efectivo: read('porcentaje', 10),
      transferencia: read('porcentajeTransferencia', 15),
      tarjeta: read('porcentajeTarjeta', 15),
    );
  }

  void applyToPlataformaEconomia() {
    PlataformaEconomia.syncComisionesMetodoFromRemote(
      efectivo: efectivo,
      transferencia: transferencia,
      tarjeta: tarjeta,
    );
  }
}

/// Lee `config/comision` y actualiza [PlataformaEconomia] (TTL 60s).
class ComisionViajePctService {
  ComisionViajePctService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static DateTime? _lastFetch;
  static const Duration _ttl = Duration(seconds: 60);
  static Timer? _timer;

  static ComisionConfigMetodos _applyDoc(Map<String, dynamic>? data) {
    final cfg = ComisionConfigMetodos.fromMap(data);
    cfg.applyToPlataformaEconomia();
    return cfg;
  }

  static Future<ComisionConfigMetodos> refresh({bool force = false}) async {
    if (!force && _lastFetch != null) {
      if (DateTime.now().difference(_lastFetch!) < _ttl) {
        return ComisionConfigMetodos(
          efectivo: PlataformaEconomia.comisionViajePorcentaje,
          transferencia: PlataformaEconomia.comisionTransferenciaPorcentaje,
          tarjeta: PlataformaEconomia.comisionTarjetaPorcentaje,
        );
      }
    }
    try {
      final snap = await _db.collection('config').doc('comision').get();
      final cfg = _applyDoc(snap.data());
      _lastFetch = DateTime.now();
      return cfg;
    } catch (_) {
      const cfg = ComisionConfigMetodos();
      cfg.applyToPlataformaEconomia();
      _lastFetch = DateTime.now();
      return cfg;
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

  /// Stream en vivo de `config/comision.porcentaje` (efectivo).
  static Stream<double> streamPorcentajeVigente() {
    return streamComisionesPorMetodo().map((c) => c.efectivo);
  }

  /// Stream con los tres % por método.
  static Stream<ComisionConfigMetodos> streamComisionesPorMetodo() {
    return _db.collection('config').doc('comision').snapshots().map((snap) {
      final cfg = _applyDoc(snap.data());
      _lastFetch = DateTime.now();
      return cfg;
    });
  }
}
