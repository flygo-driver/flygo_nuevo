import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';

class WalletService {
  WalletService._(); // evita instancias

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------- Helpers ----------
  static DateTime _asDate(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime _firstRelevantDate(Map<String, dynamic> data) {
    final f1 = _asDate(data['finalizadoEn']);
    if (f1.millisecondsSinceEpoch > 0) return f1;
    final f2 = _asDate(data['fechaHora']);
    if (f2.millisecondsSinceEpoch > 0) return f2;
    final f3 = _asDate(data['creadoEn']);
    return f3;
  }

  static bool _esCompletado(Map<String, dynamic> data) {
    final estado = (data['estado'] as String?) ?? '';
    final completoBool = (data['completado'] as bool?) ?? false;
    return EstadosViaje.esCompletado(estado) || completoBool == true;
  }

  static int _gananciaCentsOf(Map<String, dynamic> data) {
    final gc = data['ganancia_cents'];
    if (gc is int) return gc;
    final num? g = data['gananciaTaxista'] as num?;
    return g == null ? 0 : (g * 100).round();
  }

  static int _comisionCentsOf(Map<String, dynamic> data) {
    final cc = data['comision_cents'];
    if (cc is int) return cc;
    final num? c = data['comision'] as num?;
    return c == null ? 0 : (c * 100).round();
  }

  static bool _pasaRango(
    Map<String, dynamic> data,
    DateTime? desde,
    DateTime? hasta,
  ) {
    if (desde == null && hasta == null) return true;
    final t = _firstRelevantDate(data);
    if (desde != null && t.isBefore(desde)) return false;
    if (hasta != null && t.isAfter(hasta)) return false;
    return true;
  }

  // ===================== TAXISTA =====================

  /// Ganancia del taxista en CENTAVOS (tiempo real).
  static Stream<int> streamGananciaCents(String uidTaxista) {
    if (uidTaxista.trim().isEmpty) return Stream<int>.value(0);
    return _db
        .collection('viajes')
        .where('uidTaxista', isEqualTo: uidTaxista)
        .snapshots()
        .map((qs) {
      var sum = 0;
      for (final d in qs.docs) {
        final data = d.data();
        if (!_esCompletado(data)) continue;
        sum += _gananciaCentsOf(data);
      }
      return sum;
    });
  }

  /// Ganancia del taxista en moneda (double, RD$).
  static Stream<double> streamGananciaMoneda(String uidTaxista) {
    return streamGananciaCents(uidTaxista).map((cents) => cents / 100.0);
  }

  /// Ganancia del taxista con filtro de fechas.
  static Stream<int> streamGananciaCentsRango(
    String uidTaxista, {
    DateTime? desde,
    DateTime? hasta,
  }) {
    if (uidTaxista.trim().isEmpty) return Stream<int>.value(0);
    return _db
        .collection('viajes')
        .where('uidTaxista', isEqualTo: uidTaxista)
        .snapshots()
        .map((qs) {
      var sum = 0;
      for (final d in qs.docs) {
        final data = d.data();
        if (!_esCompletado(data)) continue;
        if (!_pasaRango(data, desde, hasta)) continue;
        sum += _gananciaCentsOf(data);
      }
      return sum;
    });
  }

  /// Comisión que generó un taxista (CENTAVOS).
  static Stream<int> streamComisionCentsPorTaxista(String uidTaxista) {
    if (uidTaxista.trim().isEmpty) return Stream<int>.value(0);
    return _db
        .collection('viajes')
        .where('uidTaxista', isEqualTo: uidTaxista)
        .snapshots()
        .map((qs) {
      var sum = 0;
      for (final d in qs.docs) {
        final data = d.data();
        if (!_esCompletado(data)) continue;
        sum += _comisionCentsOf(data);
      }
      return sum;
    });
  }

  /// Resumen en tiempo real para el taxista (conteos + sumas).
  static Stream<Map<String, int>> streamResumenTaxista(String uidTaxista) {
    if (uidTaxista.trim().isEmpty) {
      return Stream<Map<String, int>>.value({
        'ganancia_cents': 0,
        'comision_cents': 0,
        'viajes_completados': 0,
      });
    }

    return _db
        .collection('viajes')
        .where('uidTaxista', isEqualTo: uidTaxista)
        .snapshots()
        .map((qs) {
      var gan = 0;
      var com = 0;
      var cnt = 0;
      for (final d in qs.docs) {
        final data = d.data();
        if (!_esCompletado(data)) continue;
        gan += _gananciaCentsOf(data);
        com += _comisionCentsOf(data);
        cnt++;
      }
      return {
        'ganancia_cents': gan,
        'comision_cents': com,
        'viajes_completados': cnt,
      };
    });
  }

  // ---------- Queries (Future) por taxista ----------
  static Future<int> totalGananciaCents(
    String uidTaxista, {
    DateTime? desde,
    DateTime? hasta,
  }) async {
    if (uidTaxista.trim().isEmpty) return 0;

    final qs = await _db
        .collection('viajes')
        .where('uidTaxista', isEqualTo: uidTaxista)
        .get();

    var sum = 0;
    for (final d in qs.docs) {
      final data = d.data();
      if (!_esCompletado(data)) continue;
      if (!_pasaRango(data, desde, hasta)) continue;
      sum += _gananciaCentsOf(data);
    }
    return sum;
  }

  static Future<double> totalGananciaMoneda(
    String uidTaxista, {
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final cents = await totalGananciaCents(uidTaxista, desde: desde, hasta: hasta);
    return cents / 100.0;
  }

  static Future<int> totalComisionCentsPorTaxista(
    String uidTaxista, {
    DateTime? desde,
    DateTime? hasta,
  }) async {
    if (uidTaxista.trim().isEmpty) return 0;

    final qs = await _db
        .collection('viajes')
        .where('uidTaxista', isEqualTo: uidTaxista)
        .get();

    var sum = 0;
    for (final d in qs.docs) {
      final data = d.data();
      if (!_esCompletado(data)) continue;
      if (!_pasaRango(data, desde, hasta)) continue;
      sum += _comisionCentsOf(data);
    }
    return sum;
  }

  // ===================== ADMIN / PLATAFORMA =====================

  static Stream<int> streamComisionCentsGlobal() {
    return _db
        .collection('viajes')
        .where('estado', isEqualTo: EstadosViaje.completado)
        .snapshots()
        .map((qs) {
      var sum = 0;
      for (final d in qs.docs) {
        sum += _comisionCentsOf(d.data());
      }
      return sum;
    });
  }

  static Stream<int> streamGananciaCentsGlobal() {
    return _db
        .collection('viajes')
        .where('estado', isEqualTo: EstadosViaje.completado)
        .snapshots()
        .map((qs) {
      var sum = 0;
      for (final d in qs.docs) {
        sum += _gananciaCentsOf(d.data());
      }
      return sum;
    });
  }

  static Stream<int> streamComisionCentsGlobalPorRango({
    required DateTime desde,
    required DateTime hasta,
  }) {
    final tsDesde = Timestamp.fromDate(desde);
    final tsHasta = Timestamp.fromDate(hasta);
    return _db
        .collection('viajes')
        .where('estado', isEqualTo: EstadosViaje.completado)
        .where('finalizadoEn', isGreaterThanOrEqualTo: tsDesde)
        .where('finalizadoEn', isLessThanOrEqualTo: tsHasta)
        .snapshots()
        .map((qs) {
      var sum = 0;
      for (final d in qs.docs) {
        sum += _comisionCentsOf(d.data());
      }
      return sum;
    });
  }

  static Stream<int> streamGananciaCentsGlobalPorRango({
    required DateTime desde,
    required DateTime hasta,
  }) {
    final tsDesde = Timestamp.fromDate(desde);
    final tsHasta = Timestamp.fromDate(hasta);
    return _db
        .collection('viajes')
        .where('estado', isEqualTo: EstadosViaje.completado)
        .where('finalizadoEn', isGreaterThanOrEqualTo: tsDesde)
        .where('finalizadoEn', isLessThanOrEqualTo: tsHasta)
        .snapshots()
        .map((qs) {
      var sum = 0;
      for (final d in qs.docs) {
        sum += _gananciaCentsOf(d.data());
      }
      return sum;
    });
  }

  static Stream<Map<String, int>> streamResumenGlobal() {
    return _db
        .collection('viajes')
        .where('estado', isEqualTo: EstadosViaje.completado)
        .snapshots()
        .map((qs) {
      var com = 0, gan = 0, cnt = 0;
      for (final d in qs.docs) {
        final data = d.data();
        com += _comisionCentsOf(data);
        gan += _gananciaCentsOf(data);
        cnt++;
      }
      return {
        'comision_cents': com,
        'ganancia_cents': gan,
        'viajes_completados': cnt,
      };
    });
  }

  static Future<int> totalComisionCentsGlobal({
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final qs = await _db
        .collection('viajes')
        .where('estado', isEqualTo: EstadosViaje.completado)
        .get();

    var sum = 0;
    for (final d in qs.docs) {
      final data = d.data();
      if (!_pasaRango(data, desde, hasta)) continue;
      sum += _comisionCentsOf(data);
    }
    return sum;
  }

  static Future<int> totalGananciaCentsGlobal({
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final qs = await _db
        .collection('viajes')
        .where('estado', isEqualTo: EstadosViaje.completado)
        .get();

    var sum = 0;
    for (final d in qs.docs) {
      final data = d.data();
      if (!_pasaRango(data, desde, hasta)) continue;
      sum += _gananciaCentsOf(data);
    }
    return sum;
  }
}
