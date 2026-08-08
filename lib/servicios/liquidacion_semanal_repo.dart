import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../modelo/liquidacion_semanal.dart';
import '../modelo/resumen_por_liquidar_taxista.dart';
import '../utils/liquidacion_semanal_viaje.dart';
import '../utils/periodo_iso_semana.dart';

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

  static Stream<List<LiquidacionSemanal>> streamPagadasAdmin() {
    return _col
        .where('estado', isEqualTo: 'pagado')
        .orderBy('periodoFin', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => LiquidacionSemanal.fromMap(d.id, d.data()))
            .toList(growable: false));
  }

  static Future<List<LiquidacionSemanalLinea>> fetchLineas(
    String liquidacionId,
  ) async {
    if (liquidacionId.trim().isEmpty) return const <LiquidacionSemanalLinea>[];
    final snap = await _col
        .doc(liquidacionId)
        .collection('lineas')
        .get();
    final list = snap.docs
        .map(
          (d) => LiquidacionSemanalLinea.fromMap(d.id, d.data()),
        )
        .toList(growable: false);
    list.sort((a, b) {
      final ta = a.finalizadoEn ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.finalizadoEn ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return list;
  }

  /// Datos de viaje para auditoría (cliente, ruta) por IDs de línea.
  static Future<Map<String, Map<String, dynamic>>> fetchViajesResumen(
    Iterable<String> viajeIds,
  ) async {
    final ids = viajeIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const <String, Map<String, dynamic>>{};
    final out = <String, Map<String, dynamic>>{};
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      final snaps = await Future.wait(
        chunk.map((id) => _db.collection('viajes').doc(id).get()),
      );
      for (final s in snaps) {
        if (!s.exists) continue;
        final d = s.data() ?? <String, dynamic>{};
        out[s.id] = <String, dynamic>{
          'clienteNombre': (d['nombreCliente'] ?? d['clienteNombre'] ?? '')
              .toString(),
          'origen': (d['origen'] ?? d['origenNombre'] ?? '').toString(),
          'destino': (d['destino'] ?? d['destinoNombre'] ?? '').toString(),
          'metodoPago': (d['metodoPago'] ?? '').toString(),
          'estadoPago': (d['estadoPago'] ?? '').toString(),
        };
      }
    }
    return out;
  }

  static Future<CuentaDestinoSnapshot?> fetchCuentaActualTaxista(
    String uidTaxista,
  ) async {
    if (uidTaxista.trim().isEmpty) return null;
    final snap = await _db.collection('usuarios').doc(uidTaxista).get();
    if (!snap.exists) return null;
    final d = snap.data() ?? <String, dynamic>{};
    return CuentaDestinoSnapshot.fromMap(<String, dynamic>{
      'banco': d['banco'] ?? d['bancoTaxista'],
      'numeroCuenta': d['numeroCuenta'] ?? d['numeroCuentaTaxista'],
      'tipoCuenta': d['tipoCuenta'] ?? d['tipoCuentaTaxista'],
      'titular': d['titularCuenta'] ??
          d['titularCuentaTaxista'] ??
          d['nombre'],
      'ci': d['ci'] ?? d['ciTaxista'] ?? d['cedula'],
    });
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

  static Future<GenerarLiquidacionResult> generarParaTaxista({
    required String uidTaxista,
    String? periodo,
  }) async {
    final res = await FirebaseFunctions.instance
        .httpsCallable('generarLiquidacionSemanalTaxista')
        .call(<String, dynamic>{
      'uidTaxista': uidTaxista,
      if (periodo != null && periodo.trim().isNotEmpty) 'periodo': periodo,
    });
    final data = res.data;
    if (data is! Map) {
      return const GenerarLiquidacionResult(ok: false, mensaje: 'Respuesta inválida');
    }
    final map = Map<String, dynamic>.from(data);
    return GenerarLiquidacionResult(
      ok: map['ok'] == true,
      liquidacionId: (map['liquidacionId'] ?? '').toString(),
      skipped: (map['skipped'] ?? '').toString(),
    );
  }

  static Stream<List<ResumenPorLiquidarTaxista>> streamResumenPorLiquidar() {
    return _db
        .collection('viajes')
        .where('estadoPago', isEqualTo: 'verificado')
        .where('completado', isEqualTo: true)
        .limit(800)
        .snapshots()
        .map(_resumenDesdeViajesSnap);
  }

  static List<ResumenPorLiquidarTaxista> _resumenDesdeViajesSnap(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final porUid = <String, List<ViajePendienteLiquidacion>>{};

    for (final doc in snap.docs) {
      final data = doc.data();
      if (!LiquidacionSemanalViaje.esElegible(data)) continue;

      final metodo = LiquidacionSemanalViaje.metodoPagoNormalizadoDesde(data);
      if (metodo != 'transferencia' && metodo != 'tarjeta') continue;

      final uid =
          (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString().trim();
      if (uid.isEmpty) continue;

      final nombre = (data['nombreTaxista'] ?? data['nombre'] ?? 'Sin nombre')
          .toString()
          .trim();
      final fin = (data['finalizadoEn'] as Timestamp?)?.toDate();
      final periodo = fin != null
          ? PeriodoIsoSemana.desdeFechaUtc(fin.toUtc()).etiqueta
          : '';

      porUid.putIfAbsent(uid, () => <ViajePendienteLiquidacion>[]).add(
            ViajePendienteLiquidacion(
              viajeId: doc.id,
              uidTaxista: uid,
              nombreTaxista: nombre,
              metodo: metodo,
              precioCents: _centsFromViaje(data, 'precio_cents', 'precio'),
              comisionCents:
                  _centsFromViaje(data, 'comision_cents', 'comision'),
              gananciaCents:
                  _centsFromViaje(data, 'ganancia_cents', 'gananciaTaxista'),
              finalizadoEn: fin,
              periodoIso: periodo,
            ),
          );
    }

    final list = porUid.entries
        .map((e) {
          final nombre = e.value.isNotEmpty
              ? e.value.first.nombreTaxista
              : 'Sin nombre';
          return ResumenPorLiquidarTaxista.fromViajes(
            uidTaxista: e.key,
            nombreTaxista: nombre,
            viajes: e.value,
          );
        })
        .toList(growable: false);
    list.sort((a, b) => b.totalNetoCents.compareTo(a.totalNetoCents));
    return list;
  }

  static Future<List<ResumenPorLiquidarTaxista>> fetchResumenPorLiquidar() async {
    final snap = await _db
        .collection('viajes')
        .where('estadoPago', isEqualTo: 'verificado')
        .where('completado', isEqualTo: true)
        .limit(800)
        .get();
    return _resumenDesdeViajesSnap(snap);
  }

  static int _centsFromViaje(
    Map<String, dynamic> data,
    String fieldCents,
    String fieldRd,
  ) {
    final c = data[fieldCents];
    if (c is num) return c.round();
    final n = data[fieldRd];
    if (n is num) return (n * 100).round();
    return 0;
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

class GenerarLiquidacionResult {
  final bool ok;
  final String liquidacionId;
  final String skipped;
  final String mensaje;

  const GenerarLiquidacionResult({
    this.ok = false,
    this.liquidacionId = '',
    this.skipped = '',
    this.mensaje = '',
  });

  String get mensajeUsuario {
    if (mensaje.isNotEmpty) return mensaje;
    if (!ok) return 'No se pudo generar el lote';
    if (skipped == 'sin_viajes_elegibles') {
      return 'No hay viajes elegibles en ese período para este chofer';
    }
    if (skipped.startsWith('estado_')) {
      return 'Ya existe un lote ${skipped.replaceFirst('estado_', '')} para ese período';
    }
    if (liquidacionId.isNotEmpty) {
      return 'Lote generado: $liquidacionId';
    }
    return 'Lote generado';
  }
}
