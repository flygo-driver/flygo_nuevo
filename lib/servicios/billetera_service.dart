// lib/servicios/billetera_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../modelo/liquidacion.dart';
import '../utils/calculos/estados.dart';

/// Servicio de Billetera (cliente)
/// - Calcula exacto en centavos.
/// - Compatibilidad total con tu UI actual.
/// - Si agregas las Cloud Functions de abajo, tendrás además los totales en
///   /billeteras/{uid}, pero este servicio sigue funcionando sin ellas.
class BilleteraService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _viajes =
      _db.collection('viajes');
  static final CollectionReference<Map<String, dynamic>> _liquidas =
      _db.collection('liquidaciones');

  static const List<String> _retirosActivos = ['pendiente', 'aprobado'];

  // ===================== Helpers =====================

  static bool _esCompletado(Map<String, dynamic> data) {
    final estado = (data['estado'] as String?) ?? '';
    final completadoBool = (data['completado'] as bool?) ?? false;
    return EstadosViaje.esCompletado(estado) || completadoBool == true;
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

  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      final s = v.replaceAll(RegExp(r'[^0-9\.\-]'), '');
      return double.tryParse(s) ?? 0.0;
    }
    return 0.0;
  }

  // ===================== Futures (compat) =====================

  /// Saldo = SUM(ganancia viajes completados del UID) – SUM(liquidaciones {pendiente, aprobado})
  static Future<double> calcularSaldoDisponible(String uidTaxista) async {
    if (uidTaxista.trim().isEmpty) return 0.0;

    final QuerySnapshot<Map<String, dynamic>> vSnap =
        await _viajes.where('uidTaxista', isEqualTo: uidTaxista).get();

    int totalGanadoCents = 0;
    for (final d in vSnap.docs) {
      final data = d.data();
      if (!_esCompletado(data)) continue;
      totalGanadoCents += _gananciaCentsOf(data);
    }

    final QuerySnapshot<Map<String, dynamic>> lSnap = await _liquidas
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('estado', whereIn: _retirosActivos)
        .get();

    int totalSolicitadoCents = 0;
    for (final d in lSnap.docs) {
      totalSolicitadoCents += (_asDouble(d.data()['monto']) * 100).round();
    }

    final saldoCents = totalGanadoCents - totalSolicitadoCents;
    return (saldoCents <= 0) ? 0.0 : (saldoCents / 100.0);
  }

  /// Resumen estático (compat)
  static Future<ResumenCalculado> calcularResumenTaxista(
      String uidTaxista) async {
    if (uidTaxista.trim().isEmpty) {
      return const ResumenCalculado(
        gananciaTotal: 0,
        comisionTotal: 0,
        viajesCompletados: 0,
      );
    }

    final QuerySnapshot<Map<String, dynamic>> vSnap =
        await _viajes.where('uidTaxista', isEqualTo: uidTaxista).get();

    int gananciaCents = 0;
    int comisionCents = 0;
    int cnt = 0;

    for (final d in vSnap.docs) {
      final data = d.data();
      if (!_esCompletado(data)) continue;
      gananciaCents += _gananciaCentsOf(data);
      comisionCents += _comisionCentsOf(data);
      cnt++;
    }

    return ResumenCalculado(
      gananciaTotal: gananciaCents / 100.0,
      comisionTotal: comisionCents / 100.0,
      viajesCompletados: cnt,
    );
  }

  // ===================== Streams (tiempo real) =====================

  static Stream<List<Liquidacion>> streamLiquidacionesPorTaxista(
      String uidTaxista) {
    if (uidTaxista.trim().isEmpty) {
      return Stream.value(const <Liquidacion>[]);
    }
    return _liquidas
        .where('uidTaxista', isEqualTo: uidTaxista)
        .snapshots()
        .map((s) {
      final list =
          s.docs.map((d) => Liquidacion.fromMap(d.id, d.data())).toList();
      list.sort((a, b) {
        final ta = a.solicitadoEn?.millisecondsSinceEpoch ?? 0;
        final tb = b.solicitadoEn?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });
      return list;
    });
  }

  static Stream<double> streamSaldoDisponible(String uidTaxista) {
    if (uidTaxista.trim().isEmpty) return Stream.value(0.0);

    final Stream<int> sViajes = _viajes
        .where('uidTaxista', isEqualTo: uidTaxista)
        .snapshots()
        .map((qs) {
      int totalGanado = 0;
      for (final d in qs.docs) {
        final data = d.data();
        if (!_esCompletado(data)) continue;
        totalGanado += _gananciaCentsOf(data);
      }
      return totalGanado;
    });

    final Stream<int> sLiq = _liquidas
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('estado', whereIn: _retirosActivos)
        .snapshots()
        .map((qs) {
      int total = 0;
      for (final d in qs.docs) {
        total += (_asDouble(d.data()['monto']) * 100).round();
      }
      return total;
    });

    return Stream<double>.multi((controller) {
      int? ganadoCents;
      int? solicitadoCents;
      late final StreamSubscription<int> subViajes;
      late final StreamSubscription<int> subLiq;

      void emitIfReady() {
        if (ganadoCents == null || solicitadoCents == null) return;
        final saldoCents = ganadoCents! - solicitadoCents!;
        controller.add(saldoCents <= 0 ? 0.0 : (saldoCents / 100.0));
      }

      subViajes = sViajes.listen((v) {
        ganadoCents = v;
        emitIfReady();
      }, onError: controller.addError);

      subLiq = sLiq.listen((v) {
        solicitadoCents = v;
        emitIfReady();
      }, onError: controller.addError);

      controller
        ..onCancel = () {
          subViajes.cancel();
          subLiq.cancel();
        }
        ..onPause = () {
          subViajes.pause();
          subLiq.pause();
        }
        ..onResume = () {
          subViajes.resume();
          subLiq.resume();
        };
    });
  }

  static Stream<ResumenCalculado> streamResumenTaxistaLive(String uidTaxista) {
    if (uidTaxista.trim().isEmpty) {
      return Stream.value(const ResumenCalculado(
        gananciaTotal: 0.0,
        comisionTotal: 0.0,
        viajesCompletados: 0,
      ));
    }

    return _viajes
        .where('uidTaxista', isEqualTo: uidTaxista)
        .snapshots()
        .map((qs) {
      int ganC = 0, comC = 0, cnt = 0;
      for (final d in qs.docs) {
        final data = d.data();
        if (!_esCompletado(data)) continue;
        ganC += _gananciaCentsOf(data);
        comC += _comisionCentsOf(data);
        cnt++;
      }
      return ResumenCalculado(
        gananciaTotal: ganC / 100.0,
        comisionTotal: comC / 100.0,
        viajesCompletados: cnt,
      );
    });
  }

  static Stream<ResumenBilleteraLive> streamResumenBilletera(
      String uidTaxista) {
    if (uidTaxista.trim().isEmpty) {
      return Stream.value(const ResumenBilleteraLive(
        saldoDisponible: 0,
        gananciaTotal: 0,
        comisionTotal: 0,
        viajesCompletados: 0,
      ));
    }

    final Stream<(int, int, int)> sViajes = _viajes
        .where('uidTaxista', isEqualTo: uidTaxista)
        .snapshots()
        .map((qs) {
      int ganC = 0, comC = 0, cnt = 0;
      for (final d in qs.docs) {
        final data = d.data();
        if (!_esCompletado(data)) continue;
        ganC += _gananciaCentsOf(data);
        comC += _comisionCentsOf(data);
        cnt++;
      }
      return (ganC, comC, cnt);
    });

    final Stream<int> sLiq = _liquidas
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('estado', whereIn: _retirosActivos)
        .snapshots()
        .map((qs) {
      int total = 0;
      for (final d in qs.docs) {
        total += (_asDouble(d.data()['monto']) * 100).round();
      }
      return total;
    });

    return Stream<ResumenBilleteraLive>.multi((controller) {
      (int, int, int)? viajes; // (ganC, comC, cnt)
      int? liq; // solicitadoCents
      late final StreamSubscription<(int, int, int)> subViajes;
      late final StreamSubscription<int> subLiq;

      void emitIfReady() {
        if (viajes == null || liq == null) return;
        final ganC = viajes!.$1;
        final comC = viajes!.$2;
        final cnt = viajes!.$3;
        final saldoC = ganC - liq!;
        controller.add(ResumenBilleteraLive(
          saldoDisponible: (saldoC <= 0) ? 0.0 : (saldoC / 100.0),
          gananciaTotal: ganC / 100.0,
          comisionTotal: comC / 100.0,
          viajesCompletados: cnt,
        ));
      }

      subViajes = sViajes.listen((v) {
        viajes = v;
        emitIfReady();
      }, onError: controller.addError);

      subLiq = sLiq.listen((v) {
        liq = v;
        emitIfReady();
      }, onError: controller.addError);

      controller
        ..onCancel = () {
          subViajes.cancel();
          subLiq.cancel();
        }
        ..onPause = () {
          subViajes.pause();
          subLiq.pause();
        }
        ..onResume = () {
          subViajes.resume();
          subLiq.resume();
        };
    });
  }

  // ===================== Acciones =====================

  static Future<void> solicitarRetiro({
    required String uidTaxista,
    required double monto,
    String? requestId,
  }) async {
    if (uidTaxista.trim().isEmpty) {
      throw Exception('UID vacío.');
    }
    if (monto <= 0) {
      throw Exception('El monto debe ser mayor a 0.');
    }

    final int montoCents = (monto * 100).round();
    final String rid = (requestId ?? '').trim();
    final DocumentReference<Map<String, dynamic>> ref =
        rid.isEmpty ? _liquidas.doc() : _liquidas.doc(rid);

    final existing = await ref.get();
    if (existing.exists) {
      return;
    }

    // Deduplicación defensiva por doble click/reintento inmediato.
    final recientes = await _liquidas
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('estado', isEqualTo: 'pendiente')
        .where('monto_cents', isEqualTo: montoCents)
        .limit(1)
        .get();
    if (recientes.docs.isNotEmpty) {
      return;
    }

    final saldo = await calcularSaldoDisponible(uidTaxista);
    if (monto > saldo) {
      throw Exception('Monto mayor al saldo disponible.');
    }

    await ref.set({
      'id': ref.id,
      'uidTaxista': uidTaxista,
      'monto': double.parse(monto.toStringAsFixed(2)),
      'monto_cents': montoCents,
      'estado': 'pendiente',
      'solicitadoEn': FieldValue.serverTimestamp(),
      'resueltoEn': null,
      'requestId': rid.isEmpty ? ref.id : rid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class ResumenCalculado {
  final double gananciaTotal;
  final double comisionTotal;
  final int viajesCompletados;

  const ResumenCalculado({
    required this.gananciaTotal,
    required this.comisionTotal,
    required this.viajesCompletados,
  });
}

class ResumenBilleteraLive {
  final double saldoDisponible;
  final double gananciaTotal;
  final double comisionTotal;
  final int viajesCompletados;

  const ResumenBilleteraLive({
    required this.saldoDisponible,
    required this.gananciaTotal,
    required this.comisionTotal,
    required this.viajesCompletados,
  });
}
