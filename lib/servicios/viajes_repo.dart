import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';

class ViajesRepo {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('viajes');

  /// Crea un viaje (ahora o programado).
  static Future<String> crearViajePendiente({
    required String uidCliente,
    required String origen,
    required String destino,
    required double latOrigen,
    required double lonOrigen,
    required double latDestino,
    required double lonDestino,
    required DateTime fechaHora,
    required double precio,
    required String metodoPago, // 'Efectivo' | 'Tarjeta' | ...
    required String tipoVehiculo,
    required bool idaYVuelta,

    // opcionales
    String? categoria,
    List<Map<String, dynamic>>? waypoints,
    Map<String, dynamic>? extras,
    double? distanciaKm,
  }) async {
    bool _outOfRange(double lat, double lon) =>
        lat < -90 || lat > 90 || lon < -180 || lon > 180;

    if (_outOfRange(latOrigen, lonOrigen) ||
        _outOfRange(latDestino, lonDestino)) {
      throw ArgumentError('Coordenadas fuera de rango');
    }
    if (precio.isNaN || precio.isInfinite || precio <= 0) {
      throw ArgumentError('Precio inválido');
    }

    // Split 80/20 en centavos
    final int precioCents = (precio * 100).round();
    final int comisionCents = ((precioCents * 20) + 50) ~/ 100;
    final int gananciaCents = precioCents - comisionCents;

    // Parámetros de ventana
    const int kPoolHoursBefore = 5;
    const int kAcceptHoursBefore = 2;
    const int kReadyMinutesBefore = 45;

    final DateTime now = DateTime.now();
    final bool esAhora =
        fechaHora.isBefore(now.add(const Duration(minutes: 15)));

    final DateTime publishDT =
        esAhora ? now : fechaHora.subtract(const Duration(hours: kPoolHoursBefore));
    final DateTime acceptAfterDT =
        esAhora ? now : fechaHora.subtract(const Duration(hours: kAcceptHoursBefore));
    final DateTime startWindowDT =
        esAhora ? now : fechaHora.subtract(const Duration(minutes: kReadyMinutesBefore));

    List<Map<String, dynamic>>? _sanitize(
        List<Map<String, dynamic>>? wps) {
      if (wps == null) return null;
      final out = <Map<String, dynamic>>[];
      for (final w in wps) {
        final double? lat =
            (w['lat'] is num) ? (w['lat'] as num).toDouble() : null;
        final double? lon =
            (w['lon'] is num) ? (w['lon'] as num).toDouble() : null;
        if (lat == null || lon == null) continue;
        if (_outOfRange(lat, lon)) continue;
        out.add(
            {'lat': lat, 'lon': lon, 'label': (w['label'] ?? '').toString()});
      }
      return out.isEmpty ? null : out;
    }

    final doc = _col.doc();
    final data = <String, dynamic>{
      'id': doc.id,
      'clienteId': uidCliente, // compat
      'uidCliente': uidCliente,

      // sin taxista asignado
      'uidTaxista': '',
      'taxistaId': '',
      'nombreTaxista': '',
      'telefono': '',
      'placa': '',
      'tipoVehiculo': tipoVehiculo,
      'marca': '',
      'modelo': '',
      'color': '',

      // trayecto
      'origen': origen,
      'destino': destino,
      'latCliente': latOrigen,
      'lonCliente': lonOrigen,
      'latDestino': latDestino,
      'lonDestino': lonDestino,

      // fechas/estado
      'fechaHora': Timestamp.fromDate(fechaHora),
      'publishAt': Timestamp.fromDate(publishDT),
      'acceptAfter': Timestamp.fromDate(acceptAfterDT),
      'startWindowAt': Timestamp.fromDate(startWindowDT),
      'programado': !esAhora,
      'esAhora': esAhora,
      'metodoPago': metodoPago,
      'estado': (metodoPago.toLowerCase().trim() == 'tarjeta')
          ? 'pendiente_pago'
          : 'pendiente',
      'aceptado': false,
      'rechazado': false,
      'completado': false,
      'activo': false,            // ← usado por el stream del taxista
      'ignoradosPor': <String>[], // ← silencio para quien cancele

      // precios
      'precio': precioCents / 100.0,
      'comision': comisionCents / 100.0,
      'gananciaTaxista': gananciaCents / 100.0,
      'precio_cents': precioCents,
      'comision_cents': comisionCents,
      'ganancia_cents': gananciaCents,

      // tracking taxista
      'latTaxista': 0.0,
      'lonTaxista': 0.0,

      if (categoria != null && categoria.isNotEmpty) 'categoria': categoria,
      if (distanciaKm != null && distanciaKm.isFinite && distanciaKm > 0)
        'distanciaKm': distanciaKm,

      // timestamps
      'creadoEn': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    final wps = _sanitize(waypoints);
    if (wps != null) data['waypoints'] = wps;
    if (extras != null && extras.isNotEmpty) data['extras'] = extras;

    await doc.set(data);
    return doc.id;
  }

  /// Reclamar viaje del pool → `aceptado`
  static Future<bool> claimTrip({
    required String viajeId,
    required String uidTaxista,
    required String nombreTaxista,
    String telefono = '',
    String placa = '',
    String tipoVehiculo = '',
  }) async {
    final ref = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    final bool ok = await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final data = snap.data()!;

      final String estado = (data['estado'] ?? '').toString();
      final bool yaAsignado =
          ((data['uidTaxista'] ?? '') as String).isNotEmpty ||
          ((data['taxistaId'] ?? '') as String).isNotEmpty;

      final bool estadoPermitido =
          (estado == 'pendiente' || estado == 'pendiente_pago');
      if (!estadoPermitido || yaAsignado) return false;

      // Gate de tiempo para programados
      final tsAcceptAfter = data['acceptAfter'];
      if (tsAcceptAfter is Timestamp) {
        final DateTime acceptAfter = tsAcceptAfter.toDate();
        if (DateTime.now().isBefore(acceptAfter)) return false;
      }

      // Verificar que el taxista no tenga viaje activo
      final uSnap = await tx.get(uRef);
      final uData = uSnap.data() ?? <String, dynamic>{};
      final String viajeActivoId = (uData['viajeActivoId'] ?? '').toString();
      if (viajeActivoId.isNotEmpty) return false;

      final String _tel =
          (telefono.isNotEmpty ? telefono : (uData['telefono'] ?? ''))
              .toString();
      final String _plac =
          (placa.isNotEmpty ? placa : (uData['placa'] ?? '')).toString();
      final String _tipo = (tipoVehiculo.isNotEmpty
              ? tipoVehiculo
              : (uData['tipoVehiculo'] ?? ''))
          .toString();

      // Asignar viaje
      tx.update(ref, {
        'uidTaxista': uidTaxista,
        'taxistaId': uidTaxista,
        'nombreTaxista': nombreTaxista,
        'telefono': _tel,
        'placa': _plac,
        'tipoVehiculo': _tipo,
        'estado': 'aceptado',
        'aceptado': true,
        'rechazado': false,
        'activo': true, // ← pasa a activo
        'aceptadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      // Bloquear al taxista con este viaje
      tx.set(uRef, {
        'viajeActivoId': viajeId,
        'actualizadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    });

    if (ok) {
      await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: viajeId);
    }
    return ok;
  }

  /* ==================== ACCIONES DE ESTADO ==================== */

  static Future<void> marcarClienteAbordo({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final d = snap.data()!;
      if ((d['uidTaxista'] ?? '') != uidTaxista) {
        throw Exception('No autorizado');
      }
      final String estado = (d['estado'] ?? '').toString();
      if (estado != 'aceptado') {
        throw Exception('Estado inválido para marcar a bordo');
      }
      tx.update(ref, {
        'estado': 'a_bordo',
        'activo': true,
        'pickupConfirmadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    });

    await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: viajeId);
  }

  static Future<void> iniciarViaje({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final d = snap.data()!;
      if ((d['uidTaxista'] ?? '') != uidTaxista) {
        throw Exception('No autorizado');
      }
      final String estado = (d['estado'] ?? '').toString();
      if (estado != 'a_bordo') {
        throw Exception('Primero marca "Cliente a bordo".');
      }
      final bool esAhora = (d['esAhora'] == true);
      final tsStart = d['startWindowAt'];
      if (!esAhora && tsStart is Timestamp) {
        if (DateTime.now().isBefore(tsStart.toDate())) {
          throw Exception('Aún no está en ventana de inicio.');
        }
      }
      tx.update(ref, {
        'estado': 'en_curso',
        'activo': true,
        'inicioEnRutaEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    });

    await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: viajeId);
  }

  static Future<void> completarViajePorTaxista({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final d = snap.data()!;
      if ((d['uidTaxista'] ?? '') != uidTaxista) {
        throw Exception('No autorizado');
      }
      final String estado = (d['estado'] ?? '').toString();
      if (estado != 'en_curso' && estado != 'a_bordo') {
        throw Exception('Estado inválido para finalizar.');
      }

      tx.update(ref, {
        'estado': 'completado',
        'completado': true,
        'activo': false,
        'finalizadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      // liberar viajeActivoId del taxista
      tx.set(uRef, {
        'viajeActivoId': '',
        'actualizadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    await _limpiarOtrosActivosDelTaxista(uidTaxista);
  }

  static Future<void> cancelarPorTaxista({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');

      final d = snap.data()!;
      if ((d['uidTaxista'] ?? '') != uidTaxista) {
        throw Exception('No autorizado');
      }
      final String estado = (d['estado'] ?? '').toString();
      if (!(estado == 'aceptado' ||
          estado == 'enCaminoPickup' ||
          estado == 'en_camino_pickup')) {
        throw Exception('No se puede cancelar en este estado.');
      }

      // Recalcular esAhora por consistencia
      DateTime fh;
      final ts = d['fechaHora'];
      if (ts is Timestamp) {
        fh = ts.toDate();
      } else if (ts is DateTime) {
        fh = ts;
      } else if (ts is String) {
        fh = DateTime.tryParse(ts) ?? DateTime.now();
      } else {
        fh = DateTime.now();
      }
      final bool esAhora =
          !fh.isAfter(DateTime.now().add(const Duration(minutes: 10)));

      tx.update(ref, {
        'estado': 'pendiente',
        'aceptado': false,
        'rechazado': false,
        'activo': false,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        'republicado': true,
        'canceladoPor': 'taxista',
        'canceladoTaxistaEn': FieldValue.serverTimestamp(),
        'esAhora': esAhora,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        // Limpia timestamps de estados previos por si acaso
        'pickupConfirmadoEn': FieldValue.delete(),
        'inicioEnRutaEn': FieldValue.delete(),
        'finalizadoEn': FieldValue.delete(),
        'ignoradosPor': FieldValue.arrayUnion([uidTaxista]), // ← clave
      });

      // liberar bloqueo
      tx.set(uRef, {
        'viajeActivoId': '',
        'actualizadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    await _limpiarOtrosActivosDelTaxista(uidTaxista);
  }

  static Future<void> cancelarPorCliente({
    required String viajeId,
    required String uidCliente,
    String? motivo,
  }) async {
    final ref = _col.doc(viajeId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');

      final d = snap.data()!;
      final String cliente =
          (d['uidCliente'] ?? d['clienteId']).toString();
      if (cliente != uidCliente) {
        throw Exception('No autorizado');
      }
      final String estado = (d['estado'] ?? '').toString();
      if (estado == 'completado' || estado == 'cancelado') {
        throw Exception('El viaje ya está cerrado.');
      }

      // si había taxista, también liberar su bloqueo
      final String uidTaxista = (d['uidTaxista'] ?? '').toString();

      tx.update(ref, {
        'estado': 'cancelado',
        'aceptado': false,
        'rechazado': true,
        'activo': false,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        'canceladoPor': 'cliente',
        'motivoCancelacion': (motivo ?? '').trim(),
        'canceladoClienteEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      if (uidTaxista.isNotEmpty) {
        final uRef = _db.collection('usuarios').doc(uidTaxista);
        tx.set(uRef, {
          'viajeActivoId': '',
          'actualizadoEn': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  /* ==================== STREAMS ==================== */

  /// Activo para taxista (usamos booleano `activo`) → 1 doc
  static Stream<Viaje?> streamViajeEnCursoPorTaxista(String uidTaxista) {
    return _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('activo', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((q) {
      if (q.docs.isEmpty) return null;
      final d = q.docs.first;
      return Viaje.fromMap(d.id, d.data());
    });
  }

  /// Estado actual para cliente (pendiente / pendiente_pago / aceptado / a_bordo / en_curso).
  static Stream<Viaje?> streamEstadoViajePorCliente(String uidCliente) {
    return _col
        .where('uidCliente', isEqualTo: uidCliente)
        .where('estado',
            whereIn: ['pendiente', 'pendiente_pago', 'aceptado', 'a_bordo', 'en_curso'])
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .snapshots()
        .map((q) {
      if (q.docs.isEmpty) return null;
      final d = q.docs.first;
      return Viaje.fromMap(d.id, d.data());
    });
  }

  /* ==================== POOL / LISTADOS ==================== */

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPoolAhora() {
    return _col
        .where('estado', whereIn: ['pendiente', 'pendiente_pago'])
        .where('uidTaxista', isEqualTo: '')
        .where('publishAt', isLessThanOrEqualTo: Timestamp.now())
        .where('esAhora', isEqualTo: true)
        .orderBy('publishAt', descending: false)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPoolProgramados() {
    return _col
        .where('estado', whereIn: ['pendiente', 'pendiente_pago'])
        .where('uidTaxista', isEqualTo: '')
        .where('publishAt', isLessThanOrEqualTo: Timestamp.now())
        .where('esAhora', isEqualTo: false)
        .orderBy('publishAt', descending: false)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamProgramadosAceptadosTaxista(
    String uidTaxista,
  ) {
    return _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('estado', isEqualTo: 'aceptado')
        .where('fechaHora', isGreaterThan: Timestamp.now())
        .orderBy('fechaHora', descending: false)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamActivosTaxistaRaw(
    String uidTaxista,
  ) {
    return _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('activo', isEqualTo: true)
        .limit(1)
        .snapshots();
  }

  /* ==================== LIMPIEZA DEFENSIVA ==================== */

  static Future<void> _limpiarOtrosActivosDelTaxista(
    String uidTaxista, {
    String? exceptoId,
  }) async {
    final qs = await _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('activo', isEqualTo: true)
        .get();

    if (qs.docs.isEmpty) return;

    final batch = _db.batch();
    for (final d in qs.docs) {
      if (exceptoId != null && d.id == exceptoId) continue;
      batch.update(d.reference, {
        'estado': 'pendiente',
        'aceptado': false,
        'rechazado': false,
        'activo': false,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        // limpia timestamps de estados previos
        'pickupConfirmadoEn': FieldValue.delete(),
        'inicioEnRutaEn': FieldValue.delete(),
        'finalizadoEn': FieldValue.delete(),
      });
    }
    await batch.commit();
  }
}
