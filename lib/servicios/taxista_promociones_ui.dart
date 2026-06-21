import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Solo lectura: textos y datos de `config/comision` + promos + incentivos taxista.
class TaxistaPromocionesUi {
  TaxistaPromocionesUi._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Stream<double> streamComisionPct() {
    return _db.collection('config').doc('comision').snapshots().map((snap) {
      final raw = snap.data()?['porcentaje'];
      final double p = raw is num ? raw.toDouble() : 20.0;
      return p.clamp(0.0, 100.0);
    });
  }

  static Stream<TaxistaPromoMxKUi?> streamPromoMxK() {
    return _db.collection('config').doc('promociones').snapshots().map((snap) {
      final d = snap.data();
      if (d == null || d.isEmpty) return null;
      return TaxistaPromoMxKUi.fromMap(d);
    });
  }

  static Stream<Map<String, dynamic>?> streamIncentivoConfig() {
    return _db
        .collection('config')
        .doc('comision_incentivos_taxista')
        .snapshots()
        .map((s) => s.data());
  }

  static Stream<Map<String, dynamic>?> streamTaxistaStats(String uid) {
    return _db.collection('taxistas_stats').doc(uid).snapshots().map((s) => s.data());
  }

  static String? currentTaxistaUid() => FirebaseAuth.instance.currentUser?.uid;

  static String pctLabel(double p) =>
      p == p.roundToDouble() ? p.round().toString() : p.toStringAsFixed(1);
}

class TaxistaPromoMxKUi {
  const TaxistaPromoMxKUi({
    required this.activa,
    required this.m,
    required this.k,
    required this.porcentaje,
    required this.modo,
  });

  final bool activa;
  final int m;
  final int k;
  final int porcentaje;
  final String modo;

  factory TaxistaPromoMxKUi.fromMap(Map<String, dynamic> d) {
    int toInt(dynamic v, int fb) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim()) ?? fb;
      return fb;
    }

    return TaxistaPromoMxKUi(
      activa: d['activa'] == true,
      m: toInt(d['m'], 3).clamp(1, 999),
      k: toInt(d['k'], 1).clamp(1, 999),
      porcentaje: toInt(d['porcentaje'], 15).clamp(0, 95),
      modo: (d['modo'] ?? '${toInt(d['m'], 3)}x${toInt(d['k'], 1)}').toString(),
    );
  }

  int get ciclo => m + k;

  String get titulo =>
      activa ? 'Promo clientes $modo · −$porcentaje%' : 'Promo clientes (inactiva)';

  String get explicacionTaxista =>
      activa
          ? 'RAI aplica descuento al precio del pasajero en $m de cada $ciclo viajes '
              '(los otros $k van a precio completo). '
              'Tu comisión RAI es el mismo % vigente sobre lo que paga el cliente: '
              'más descuentos = más pedidos para ti.'
          : 'No hay promo M×K activa para clientes en este momento.';
}

class TaxistaIncentivoComisionUi {
  const TaxistaIncentivoComisionUi({
    required this.programaActivo,
    required this.ventanaLabel,
    required this.viajesCompletados,
    required this.comisionGlobalPct,
    required this.comisionEfectivaPct,
    required this.incentivoActivo,
    required this.escalonEtiqueta,
    required this.proximoViajes,
    required this.proximoPct,
    required this.proximoEtiqueta,
  });

  final bool programaActivo;
  final String ventanaLabel;
  final int viajesCompletados;
  final double comisionGlobalPct;
  final double comisionEfectivaPct;
  final bool incentivoActivo;
  final String escalonEtiqueta;
  final int? proximoViajes;
  final double? proximoPct;
  final String proximoEtiqueta;

  double get progresoFraction {
    if (!programaActivo || proximoViajes == null || proximoViajes! <= 0) {
      return 1.0;
    }
    return (viajesCompletados / proximoViajes!).clamp(0.0, 1.0);
  }

  int? get viajesRestantes {
    if (!programaActivo || proximoViajes == null) return null;
    return (proximoViajes! - viajesCompletados).clamp(0, 9999);
  }

  String get titulo =>
      programaActivo ? 'Tu incentivo por volumen' : 'Incentivo por volumen (inactivo)';

  String get resumenPct {
    final global = TaxistaPromocionesUi.pctLabel(comisionGlobalPct);
    final efectiva = TaxistaPromocionesUi.pctLabel(comisionEfectivaPct);
    if (incentivoActivo) {
      return '$efectiva% RAI ahora · base $global%';
    }
    return '$global% RAI (comisión global)';
  }

  static TaxistaIncentivoComisionUi fromFirestore({
    Map<String, dynamic>? cfg,
    Map<String, dynamic>? stats,
    required double globalPct,
  }) {
    int toInt(dynamic v, int fb) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim()) ?? fb;
      return fb;
    }

    double toDouble(dynamic v, double fb) {
      if (v is num) return v.toDouble();
      if (v is String) {
        return double.tryParse(v.trim().replaceAll(',', '.')) ?? fb;
      }
      return fb;
    }

    final ventana = (cfg?['ventana'] ?? 'semana').toString().trim().toLowerCase();
    final ventanaLabel = ventana == 'mes' ? 'este mes' : 'esta semana';

    final rawEsc = cfg?['escalones'];
    final bool tieneEscalones = rawEsc is List && rawEsc.isNotEmpty;
    final bool programaActivo = cfg?['activo'] == true && tieneEscalones;

    EscalonUi? activoEsc;
    EscalonUi? proximoEsc;
    if (tieneEscalones) {
      final parsed = <EscalonUi>[];
      for (final item in rawEsc) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        parsed.add(
          EscalonUi(
            viajesMinimos: toInt(m['viajesMinimos'], 0),
            comisionPct: toDouble(m['comisionPct'], 20).clamp(0.0, 100.0),
            etiqueta: (m['etiqueta'] ?? '').toString(),
          ),
        );
      }
      parsed.sort((a, b) => a.viajesMinimos.compareTo(b.viajesMinimos));
      final viajesTmp = toInt(stats?['viajesCompletadosVentana'], 0).clamp(0, 9999);
      for (final e in parsed) {
        if (viajesTmp >= e.viajesMinimos) activoEsc = e;
      }
      for (final e in parsed) {
        if (e.viajesMinimos > viajesTmp) {
          proximoEsc = e;
          break;
        }
      }
    }

    final viajes = toInt(stats?['viajesCompletadosVentana'], 0).clamp(0, 9999);
    final pctStats = toDouble(stats?['comisionPctActual'], globalPct).clamp(0.0, 100.0);
    final pctGlobalStats = toDouble(stats?['comisionPctGlobal'], globalPct).clamp(0.0, 100.0);
    final global = pctGlobalStats > 0 ? pctGlobalStats : globalPct;
    final efectiva = pctStats > 0 ? pctStats : global;
    final incentivoActivo = stats?['comisionIncentivoActivo'] == true && efectiva < global;

    final proxViajesStats = stats?['proximoEscalonViajes'];
    final proxPctStats = stats?['proximoEscalonPct'];
    final proxEtiquetaStats = (stats?['proximoEscalonEtiqueta'] ?? '').toString();

    return TaxistaIncentivoComisionUi(
      programaActivo: programaActivo,
      ventanaLabel: ventanaLabel,
      viajesCompletados: viajes,
      comisionGlobalPct: global,
      comisionEfectivaPct: efectiva,
      incentivoActivo: incentivoActivo ||
          (programaActivo && activoEsc != null && activoEsc.comisionPct < global),
      escalonEtiqueta: (stats?['escalonActivoEtiqueta'] ?? activoEsc?.etiqueta ?? '')
          .toString(),
      proximoViajes: proxViajesStats is num
          ? proxViajesStats.toInt()
          : proximoEsc?.viajesMinimos,
      proximoPct: proxPctStats is num
          ? proxPctStats.toDouble()
          : proximoEsc?.comisionPct,
      proximoEtiqueta: proxEtiquetaStats.isNotEmpty
          ? proxEtiquetaStats
          : (proximoEsc?.etiqueta ?? ''),
    );
  }
}

class EscalonUi {
  const EscalonUi({
    required this.viajesMinimos,
    required this.comisionPct,
    required this.etiqueta,
  });

  final int viajesMinimos;
  final double comisionPct;
  final String etiqueta;
}
