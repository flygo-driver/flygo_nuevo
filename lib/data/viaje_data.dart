// lib/data/viaje_data.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/trip_publish_windows.dart';
import 'package:flygo_nuevo/data/pago_data.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';

class ViajeData {
  // ---------- Firestore ----------
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _viajes =
      _db.collection('viajes');

  // ---------- Estados canónicos (snake_case) ----------
  // Lista usada por taxista en whereIn
  static const List<String> _activosTaxista = <String>[
    'aceptado',
    'en_camino_pickup',
    'a_bordo',
    'en_curso',
  ];

  // ---------- Helpers generales ----------
  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  // Precisión GPS ~6 decimales
  static double _round6(num v) => double.parse(v.toStringAsFixed(6));

  // Solo para dinero
  static double _round2(num v) => double.parse(v.toStringAsFixed(2));

  static DateTime _asDate(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static DateTime _createdOf(Map<String, dynamic> data) {
    final DateTime creadoEn = _asDate(data['creadoEn']);
    if (creadoEn.millisecondsSinceEpoch > 0) return creadoEn;

    final DateTime fechaCreacion = _asDate(data['fechaCreacion']);
    if (fechaCreacion.millisecondsSinceEpoch > 0) return fechaCreacion;

    final DateTime fechaHora = _asDate(data['fechaHora']);
    return (fechaHora.millisecondsSinceEpoch > 0)
        ? fechaHora
        : DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ===== Normalización fuerte de tipos para lat/lon y dinero =====
  static Map<String, dynamic> _normalize(Map<String, dynamic> data) {
    double d(dynamic v) => _asDouble(v);
    double r6(dynamic v) => _round6(_asDouble(v));

    return <String, dynamic>{
      ...data,
      'precio': d(data['precio']),
      'gananciaTaxista': d(data['gananciaTaxista']),
      'comision': d(data['comision']),
      'latCliente': r6(data['latCliente']),
      'lonCliente': r6(data['lonCliente']),
      'latDestino': r6(data['latDestino']),
      'lonDestino': r6(data['lonDestino']),
      'latTaxista': r6(data['latTaxista']),
      'lonTaxista': r6(data['lonTaxista']),
    };
  }

  static int _toCents(num v) => (v * 100).round();
  static double _fromCents(int c) => c / 100.0;
  static int _comision20Cents(int precioCents) =>
      ((precioCents * 20) + 50) ~/ 100;

  static Map<String, int> _partidasCentsDesdePrecio(num precioDbl) {
    final int pCents = _toCents(precioDbl);
    final int cCents = _comision20Cents(pCents);
    final int gCents = pCents - cCents;
    return <String, int>{
      'precio_cents': pCents,
      'comision_cents': cCents,
      'ganancia_cents': gCents,
    };
  }

  // Fuerza estado canónico al ESCRIBIR en DB
  static String _estadoCanon(String estado) => EstadosViaje.normalizar(estado);

  // ===== Helpers de comparación con tolerancia (para evitar parpadeos) =====
  static bool _approxEq(double a, double b, [double eps = 0.0001]) =>
      (a - b).abs() <= eps;

  static bool _viajeIgualAprox(Viaje a, Viaje b) {
    return a.id == b.id &&
        EstadosViaje.normalizar(a.estado) ==
            EstadosViaje.normalizar(b.estado) &&
        _approxEq(a.latTaxista, b.latTaxista) &&
        _approxEq(a.lonTaxista, b.lonTaxista) &&
        _approxEq(a.latCliente, b.latCliente) &&
        _approxEq(a.lonCliente, b.lonCliente) &&
        _approxEq(a.latDestino, b.latDestino) &&
        _approxEq(a.lonDestino, b.lonDestino);
  }

  // ===== Throttle básico para suavizar snapshots ruidosos =====
  static StreamTransformer<T, T> _throttleDistinct<T>(Duration window) {
    Timer? t;
    T? pending;
    bool hasPending = false;
    bool isClosed = false;
    late StreamController<T> ctrl;

    void emitPending() {
      if (hasPending && !isClosed) {
        ctrl.add(pending as T);
        hasPending = false;
      }
    }

    return StreamTransformer<T, T>.fromBind((input) {
      ctrl = StreamController<T>(onCancel: () {
        t?.cancel();
      });

      input.listen(
          (event) {
            if (t == null || !t!.isActive) {
              ctrl.add(event);
              t = Timer(window, () {
                emitPending();
              });
            } else {
              pending = event;
              hasPending = true;
            }
          },
          onError: ctrl.addError,
          onDone: () {
            emitPending();
            isClosed = true;
            ctrl.close();
          });

      return ctrl.stream;
    });
  }

  // ===================================================================
  //                              CREAR
  // ===================================================================
  static Future<void> agregarViaje(Viaje viaje) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('No autenticado');

    final Map<String, int> partidas = _partidasCentsDesdePrecio(viaje.precio);

    final Map<String, dynamic> base = <String, dynamic>{
      ...viaje.toMap(),
      'estado': _estadoCanon(
        (viaje.estado.isNotEmpty) ? viaje.estado : EstadosViaje.pendiente,
      ),
      'aceptado': viaje.aceptado,
      'rechazado': viaje.rechazado,
      'completado': viaje.completado,
      'calificado': viaje.calificado,
      'clienteId': uid,
      'uidCliente': uid,
      'uidTaxista': '',
      'taxistaId': '',
      'precio': _fromCents(partidas['precio_cents']!),
      'gananciaTaxista': _fromCents(partidas['ganancia_cents']!),
      'comision': _fromCents(partidas['comision_cents']!),
      ...partidas,
      'latTaxista': _asDouble(viaje.latTaxista),
      'lonTaxista': _asDouble(viaje.lonTaxista),
      'fechaHora': Timestamp.fromDate(viaje.fechaHora),
      'creadoEn': FieldValue.serverTimestamp(),
      'fechaCreacion': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final DocumentReference<Map<String, dynamic>> doc = await _viajes.add(base);
    await doc.update(<String, dynamic>{
      'id': doc.id,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<String> crearViajeCliente({
    required String origen,
    required String destino,
    required double latCliente,
    required double lonCliente,
    required double latDestino,
    required double lonDestino,
    required double precio,
    required String metodoPago,
  }) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('No autenticado');

    final Map<String, int> partidas = _partidasCentsDesdePrecio(precio);

    final DocumentReference<Map<String, dynamic>> ref = _viajes.doc();
    await ref.set(<String, dynamic>{
      'id': ref.id,
      'clienteId': uid,
      'uidCliente': uid,
      'uidTaxista': '',
      'taxistaId': '',
      'origen': origen,
      'destino': destino,
      'latCliente': _round6(latCliente),
      'lonCliente': _round6(lonCliente),
      'latDestino': _round6(latDestino),
      'lonDestino': _round6(lonDestino),
      'precio': _fromCents(partidas['precio_cents']!),
      'metodoPago': metodoPago,
      'gananciaTaxista': _fromCents(partidas['ganancia_cents']!),
      'comision': _fromCents(partidas['comision_cents']!),
      ...partidas,
      'latTaxista': 0.0,
      'lonTaxista': 0.0,
      'driverLat': 0.0,
      'driverLon': 0.0,
      'estado': _estadoCanon(EstadosViaje.pendiente),
      'aceptado': false,
      'rechazado': false,
      'completado': false,
      'fechaHora': Timestamp.fromDate(DateTime.now()),
      'creadoEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  // --- V2 recomendado (programados/ahora con ventanas) ---
  static Future<String> crearViajeClienteV2({
    required String origen,
    required String destino,
    required double latCliente,
    required double lonCliente,
    required double latDestino,
    required double lonDestino,
    required double precio,
    required String metodoPago,
    String tipoVehiculo = 'Carro',
    bool idaYVuelta = false,
    DateTime? fechaHoraLocal,
  }) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('No autenticado');

    final DateTime now = DateTime.now();
    final DateTime fhLocal = fechaHoraLocal ?? now;
    final bool esAhoraCalc =
        TripPublishWindows.esAhoraPorFechaPickup(fhLocal, now);

    final DateTime publishAtDT = esAhoraCalc
        ? now
        : TripPublishWindows.poolOpensAtForScheduledPickup(fhLocal, now);
    final DateTime acceptAfterDT = esAhoraCalc
        ? now
        : TripPublishWindows.acceptAfterForScheduledPickup(fhLocal, now);
    final DateTime startWindowDT = esAhoraCalc
        ? now
        : TripPublishWindows.startWindowAtForScheduledPickup(fhLocal, now);

    final Map<String, int> partidas = _partidasCentsDesdePrecio(precio);

    final String estadoInicial = (metodoPago.toLowerCase().trim() == 'tarjeta')
        ? EstadosViaje.pendientePago
        : EstadosViaje.pendiente;

    final DocumentReference<Map<String, dynamic>> ref = _viajes.doc();
    await ref.set(<String, dynamic>{
      'id': ref.id,
      'clienteId': uid,
      'uidCliente': uid,
      'uidTaxista': '',
      'taxistaId': '',
      'nombreTaxista': '',
      'telefono': '',
      'placa': '',
      'origen': origen,
      'destino': destino,
      'latCliente': _round6(latCliente),
      'lonCliente': _round6(lonCliente),
      'latDestino': _round6(latDestino),
      'lonDestino': _round6(lonDestino),
      'latOrigen': _round6(latCliente),
      'lonOrigen': _round6(lonCliente),
      'fechaHora': Timestamp.fromDate(fhLocal),
      'estado': _estadoCanon(estadoInicial),
      'aceptado': false,
      'rechazado': false,
      'completado': false,
      'calificado': false,
      'activo': false,
      'esAhora': esAhoraCalc,
      'programado': !esAhoraCalc,
      'acceptAfter': Timestamp.fromDate(acceptAfterDT),
      'startWindowAt': Timestamp.fromDate(startWindowDT),
      'publishAt': Timestamp.fromDate(publishAtDT),
      'precio': _fromCents(partidas['precio_cents']!),
      'metodoPago': metodoPago,
      'tipoVehiculo': tipoVehiculo,
      'idaYVuelta': idaYVuelta,
      'gananciaTaxista': _fromCents(partidas['ganancia_cents']!),
      'comision': _fromCents(partidas['comision_cents']!),
      ...partidas,
      'latTaxista': 0.0,
      'lonTaxista': 0.0,
      'driverLat': 0.0,
      'driverLon': 0.0,
      'reservadoPor': '',
      'reservadoHasta': null,
      'ignoradosPor': <String>[],
      'creadoEn': FieldValue.serverTimestamp(),
      'fechaCreacion': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    });

    try {
      await _db.collection('usuarios').doc(uid).set(<String, dynamic>{
        'siguienteViajeId': ref.id,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}

    return ref.id;
  }

  // ===================================================================
  //                              UPDATE
  // ===================================================================
  static Future<void> actualizarViaje(Viaje viaje) async {
    if (viaje.id.isEmpty) {
      throw Exception('actualizarViaje: id vacío');
    }
    final Map<String, int> partidas = _partidasCentsDesdePrecio(viaje.precio);
    final Map<String, dynamic> data = <String, dynamic>{
      ...viaje.toMap(),
      'estado': _estadoCanon(viaje.estado),
      'precio': _fromCents(partidas['precio_cents']!),
      'gananciaTaxista': _fromCents(partidas['ganancia_cents']!),
      'comision': _fromCents(partidas['comision_cents']!),
      ...partidas,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _viajes.doc(viaje.id).update(data);
  }

  static Future<void> actualizarPosicionTaxista({
    required String uidTaxista,
    required double lat,
    required double lon,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> qs = await _viajes
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('completado', isEqualTo: false)
        .get();

    if (qs.docs.isEmpty) return;

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
        <QueryDocumentSnapshot<Map<String, dynamic>>>[...qs.docs];
    docs.sort((a, b) => _createdOf(b.data()).compareTo(_createdOf(a.data())));
    final DocumentReference<Map<String, dynamic>> ref = docs.first.reference;

    await ref.update(<String, dynamic>{
      'latTaxista': _round6(lat),
      'lonTaxista': _round6(lon),
      'driverLat': _round6(lat),
      'driverLon': _round6(lon),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> actualizarPosicionTaxistaPorViaje({
    required String viajeId,
    required double lat,
    required double lon,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _viajes.doc(viajeId);
    await ref.update(<String, dynamic>{
      'latTaxista': _round6(lat),
      'lonTaxista': _round6(lon),
      'driverLat': _round6(lat),
      'driverLon': _round6(lon),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ===================================================================
  //                              STREAMS
  // ===================================================================
  static Stream<Viaje?> streamEstadoViajePorCliente(String uidCliente) {
    // Priorizamos un único viaje ACTIVO; evitamos cancelados/completados
    const prioridad = <String, int>{
      'en_curso': 100,
      'a_bordo': 90,
      'en_camino_pickup': 80,
      'aceptado': 70,
      'pendiente': 10,
      'pendiente_pago': 9,
    };

    final q = _viajes
        .where(
          Filter.or(
            Filter('uidCliente', isEqualTo: uidCliente),
            Filter('clienteId', isEqualTo: uidCliente),
          ),
        )
        .where('completado', isEqualTo: false);

    return q.snapshots().map((QuerySnapshot<Map<String, dynamic>> snap) {
      if (snap.docs.isEmpty) return null;

      final todos = snap.docs.map((d) {
        final data = _normalize(d.data());
        return Viaje.fromMap(d.id, data);
      }).where((v) {
        final e = EstadosViaje.normalizar(v.estado);
        return EstadosViaje.esActivo(e) && e != EstadosViaje.cancelado;
      }).toList();

      if (todos.isEmpty) return null;

      todos.sort((a, b) {
        final pa = prioridad[EstadosViaje.normalizar(a.estado)] ?? 0;
        final pb = prioridad[EstadosViaje.normalizar(b.estado)] ?? 0;
        if (pa != pb) return pb.compareTo(pa);
        return b.fechaHora.compareTo(a.fechaHora);
      });

      return todos.first;
    })
        // Ignora microcambios por tolerancia en coordenadas/estado
        .distinct((prev, next) {
      if (prev == null && next == null) return true;
      if (prev == null || next == null) return false;
      return _viajeIgualAprox(prev, next);
    })
        // Suaviza frecuencia de emisiones para evitar rebuilds/parpadeos
        .transform(_throttleDistinct(const Duration(milliseconds: 350)));
  }

  static Stream<Viaje?> streamViajeEnCursoPorTaxista(String uidTaxista) {
    return _viajes
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('estado', whereIn: _activosTaxista)
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) {
      if (s.docs.isEmpty) return null;
      final QueryDocumentSnapshot<Map<String, dynamic>> d = s.docs.first;
      return Viaje.fromMap(d.id, _normalize(d.data()));
    });
  }

  // “Seguro” para navegar aunque el estado cambie rápido
  static Stream<Viaje?> streamViajeActivoPorTaxistaSeguro(String uidTaxista) {
    return _viajes
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('completado', isEqualTo: false)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) {
      if (snap.docs.isEmpty) return null;

      final List<Map<String, dynamic>> docs = snap.docs.map((d) {
        final Map<String, dynamic> data = _normalize(d.data());
        final DateTime updatedAt = (d.data()['updatedAt'] is Timestamp)
            ? (d.data()['updatedAt'] as Timestamp).toDate()
            : _createdOf(d.data());
        return <String, dynamic>{
          'id': d.id,
          'data': data,
          'updatedAt': updatedAt
        };
      }).toList();

      docs.sort((a, b) =>
          (b['updatedAt'] as DateTime).compareTo(a['updatedAt'] as DateTime));

      for (final Map<String, dynamic> it in docs) {
        final String estado = EstadosViaje.normalizar(
            (it['data'] as Map<String, dynamic>)['estado']?.toString() ?? '');
        if (EstadosViaje.esActivo(estado)) {
          return Viaje.fromMap(
            it['id'] as String,
            it['data'] as Map<String, dynamic>,
          );
        }
      }

      final Map<String, dynamic> top = docs.first;
      return Viaje.fromMap(
          top['id'] as String, top['data'] as Map<String, dynamic>);
    });
  }

  static Stream<List<Viaje>> streamViajesPorCliente(String uidCliente) {
    return _viajes.where('clienteId', isEqualTo: uidCliente).snapshots().map(
      (QuerySnapshot<Map<String, dynamic>> s) {
        final List<Viaje> list = s.docs
            .map((d) => Viaje.fromMap(d.id, _normalize(d.data())))
            .toList();
        list.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
        return list;
      },
    );
  }

  static Stream<List<Viaje>> streamHistorialCliente(String clienteId) {
    return _viajes
        .where('clienteId', isEqualTo: clienteId)
        .where('completado', isEqualTo: true)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> s) {
      final List<Viaje> list =
          s.docs.map((d) => Viaje.fromMap(d.id, _normalize(d.data()))).toList();
      list.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
      return list;
    });
  }

  static Stream<List<Viaje>> streamHistorialClienteTodosEstados(
      String clienteId) {
    return _viajes.where('clienteId', isEqualTo: clienteId).snapshots().map(
      (QuerySnapshot<Map<String, dynamic>> s) {
        final List<Viaje> list = s.docs
            .map((d) => Viaje.fromMap(d.id, _normalize(d.data())))
            .toList();
        list.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
        return list;
      },
    );
  }

  // ===================================================================
  //                              QUERIES
  // ===================================================================
  static Future<Viaje?> obtenerViajeEnCurso(String emailTaxista) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _viajes
        .where('nombreTaxista', isEqualTo: emailTaxista)
        .where('aceptado', isEqualTo: true)
        .where('completado', isEqualTo: false)
        .get();

    if (snapshot.docs.isEmpty) return null;
    final QueryDocumentSnapshot<Map<String, dynamic>> doc = snapshot.docs.first;
    return Viaje.fromMap(doc.id, _normalize(doc.data()));
  }

  static Future<List<Viaje>> obtenerViajesPorCliente(String clienteId) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot =
        await _viajes.where('clienteId', isEqualTo: clienteId).get();
    final List<Viaje> list = snapshot.docs
        .map((d) => Viaje.fromMap(d.id, _normalize(d.data())))
        .toList();
    list.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
    return list;
  }

  static Future<List<Viaje>> obtenerHistorialCliente(String clienteId) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _viajes
        .where('clienteId', isEqualTo: clienteId)
        .where('completado', isEqualTo: true)
        .get();
    final List<Viaje> list = snapshot.docs
        .map((d) => Viaje.fromMap(d.id, _normalize(d.data())))
        .toList();
    list.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
    return list;
  }

  static Future<List<Viaje>> obtenerHistorialTaxista(
      String emailTaxista) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _viajes
        .where('nombreTaxista', isEqualTo: emailTaxista)
        .where('completado', isEqualTo: true)
        .get();
    final List<Viaje> list = snapshot.docs
        .map((d) => Viaje.fromMap(d.id, _normalize(d.data())))
        .toList();
    list.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
    return list;
  }

  // ===================================================================
  //                         ESTADOS / COMPLETAR
  // ===================================================================
  static Future<void> marcarViajeComoCompletado(Viaje viaje) async {
    await completarViaje(viaje.id);
  }

  static Future<void> completarViaje(String viajeId) async {
    final DocumentReference<Map<String, dynamic>> ref = _viajes.doc(viajeId);

    await _db.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe.');
      final Map<String, dynamic> data = snap.data()!;

      final bool yaCompletado = (data['completado'] == true) ||
          (EstadosViaje.normalizar(data['estado']?.toString() ?? '') ==
              EstadosViaje.completado);
      if (yaCompletado) return;

      final double precioBase =
          _asDouble(data['precioFinal'] ?? data['precio']);

      final int precioCents =
          (data['precio_cents'] as int?) ?? _toCents(precioBase);
      final int comisionCents =
          (data['comision_cents'] as int?) ?? _comision20Cents(precioCents);
      final int gananciaCents =
          (data['ganancia_cents'] as int?) ?? (precioCents - comisionCents);

      // limpiar viajeActivoId del taxista al completar
      final String uidTaxista = (data['uidTaxista'] ?? '').toString();

      tx.update(ref, <String, dynamic>{
        'estado': _estadoCanon(EstadosViaje.completado),
        'completado': true,
        'precioFinal': _fromCents(precioCents),
        'comision': _fromCents(comisionCents),
        'gananciaTaxista': _fromCents(gananciaCents),
        'precio_cents': precioCents,
        'comision_cents': comisionCents,
        'ganancia_cents': gananciaCents,
        'finalizadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      if (uidTaxista.isNotEmpty) {
        final refTax = _db.collection('usuarios').doc(uidTaxista);
        // Las rules exigen poner '' (no delete) y solo esas keys.
        tx.set(
            refTax,
            {
              'viajeActivoId': '',
              'updatedAt': FieldValue.serverTimestamp(),
              'actualizadoEn': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      }
    });

    try {
      final DocumentSnapshot<Map<String, dynamic>> d =
          await _viajes.doc(viajeId).get();
      if (d.exists) {
        final Viaje v = Viaje.fromMap(d.id, _normalize(d.data()!));
        await PagoData.registrarMovimientoPorViaje(v);
      }
    } catch (_) {}
  }

  static Future<void> cancelarViaje(Viaje viaje) async {
    await _viajes.doc(viaje.id).update(<String, dynamic>{
      'aceptado': false,
      'rechazado': true,
      'estado': _estadoCanon(EstadosViaje.cancelado),
      'uidTaxista': '',
      'taxistaId': '',
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    });

    // Limpia viajeActivoId si existía taxista (solo si las reglas lo permiten)
    if (viaje.uidTaxista.isNotEmpty) {
      try {
        await _db.collection('usuarios').doc(viaje.uidTaxista).set({
          'viajeActivoId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  // ---------------- Cancelación por cliente (reglas estrictas) ----------------
  static Future<void> cancelarViajePorCliente({
    required String viajeId,
    required String uidCliente,
    String? motivo,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _viajes.doc(viajeId);

    await _db.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe.');
      final Map<String, dynamic> d = snap.data()!;

      final String ownerA = (d['clienteId'] ?? '').toString();
      final String ownerB = (d['uidCliente'] ?? '').toString();
      if (ownerA != uidCliente && ownerB != uidCliente) {
        throw Exception('No puedes cancelar este viaje.');
      }

      final String estado =
          EstadosViaje.normalizar((d['estado'] ?? '').toString());
      final bool completado = (d['completado'] ?? false) == true;

      if (completado || estado == EstadosViaje.completado) {
        throw Exception('El viaje ya fue completado.');
      }
      if (estado == EstadosViaje.cancelado) {
        return;
      }

      if (EstadosViaje.esEstadoSinCancelacionApp(estado)) {
        throw Exception(EstadosViaje.mensajeNoCancelarViajeTrasAbordarApp);
      }

      // ⬇️ SOLO llaves permitidas por tus rules (changedOnly([...]))
      tx.update(ref, <String, dynamic>{
        'estado': _estadoCanon(EstadosViaje.cancelado),
        'aceptado': false,
        'rechazado': true,
        'activo': false,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        if (motivo != null && motivo.isNotEmpty) 'motivoCancelacion': motivo,
        'canceladoPor': 'cliente',
        'canceladoClienteEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      // ⚠️ NO tocar /usuarios/{uidTaxista} aquí: cliente no es owner -> rules lo bloquearían.
    });
  }

  // ===== NUEVO: Cancelación "siempre" por cliente con limpieza del vínculo =====
  static Future<void> cancelarCualquierEstadoPorClienteTx({
    required String viajeId,
    required String uidCliente,
    String? motivo,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _viajes.doc(viajeId);
    String uidTaxistaParaLimpiar = '';

    await _db.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe.');
      final Map<String, dynamic> d = snap.data()!;

      final String ownerA = (d['clienteId'] ?? '').toString();
      final String ownerB = (d['uidCliente'] ?? '').toString();
      if (ownerA != uidCliente && ownerB != uidCliente) {
        throw Exception('No puedes cancelar este viaje.');
      }

      // Si ya está completado, no hacemos nada
      final bool completado = (d['completado'] ?? false) == true;
      if (completado) return;

      final String estadoTx =
          EstadosViaje.normalizar((d['estado'] ?? '').toString());
      if (EstadosViaje.esEstadoSinCancelacionApp(estadoTx)) {
        throw Exception(EstadosViaje.mensajeNoCancelarViajeTrasAbordarApp);
      }

      uidTaxistaParaLimpiar = (d['uidTaxista'] ?? '').toString();

      tx.update(ref, <String, dynamic>{
        'estado': _estadoCanon(EstadosViaje.cancelado),
        'aceptado': false,
        'rechazado': true,
        'activo': false,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        if (motivo != null && motivo.isNotEmpty) 'motivoCancelacion': motivo,
        'canceladoPor': 'cliente',
        'canceladoClienteEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    });

    // Limpieza del viajeActivoId del taxista (si las rules lo permiten)
    if (uidTaxistaParaLimpiar.isNotEmpty) {
      try {
        await _db.collection('usuarios').doc(uidTaxistaParaLimpiar).set(
          <String, dynamic>{
            'viajeActivoId': '',
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (_) {
        // Si no permite, al menos el viaje quedó cancelado.
      }
    }
  }

  // ===== NUEVO: Cancelar el viaje ACTIVO más reciente de un cliente =====
  static Future<bool> cancelarViajeActivoDeCliente({
    required String uidCliente,
    String? motivo,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> qs = await _viajes
        .where(
          Filter.or(
            Filter('uidCliente', isEqualTo: uidCliente),
            Filter('clienteId', isEqualTo: uidCliente),
          ),
        )
        .where('completado', isEqualTo: false)
        .get();

    if (qs.docs.isEmpty) return false;

    final docs = qs.docs.toList()
      ..sort((a, b) {
        DateTime ua;
        final da = a.data();
        if (da['updatedAt'] is Timestamp) {
          ua = (da['updatedAt'] as Timestamp).toDate();
        } else {
          ua = _createdOf(da);
        }

        DateTime ub;
        final db = b.data();
        if (db['updatedAt'] is Timestamp) {
          ub = (db['updatedAt'] as Timestamp).toDate();
        } else {
          ub = _createdOf(db);
        }
        return ub.compareTo(ua);
      });

    for (final d in docs) {
      final data = d.data();
      final estado = EstadosViaje.normalizar((data['estado'] ?? '').toString());
      final bool esActivo =
          EstadosViaje.esActivo(estado) && estado != EstadosViaje.cancelado;
      if (esActivo) {
        if (EstadosViaje.esEstadoSinCancelacionApp(estado)) {
          return false;
        }
        await cancelarCualquierEstadoPorClienteTx(
          viajeId: d.id,
          uidCliente: uidCliente,
          motivo: motivo,
        );
        return true;
      }
    }

    return false;
  }

  static Future<void> reprogramarViajePorCliente({
    required String viajeId,
    required String uidCliente,
    required DateTime nuevaFechaHora,
    String? motivo,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _viajes.doc(viajeId);

    await _db.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe.');
      final Map<String, dynamic> data = snap.data()!;
      final String ownerA = (data['clienteId'] ?? '').toString();
      final String ownerB = (data['uidCliente'] ?? '').toString();
      if (ownerA != uidCliente && ownerB != uidCliente) {
        throw Exception('No puedes reprogramar este viaje.');
      }

      final String estado =
          EstadosViaje.normalizar((data['estado'] ?? '').toString());
      final bool completado = (data['completado'] ?? false) == true;

      if (completado || estado == EstadosViaje.completado) {
        throw Exception('El viaje completado no se puede reprogramar.');
      }
      if (estado == EstadosViaje.enCurso) {
        throw Exception('El viaje en curso no se puede reprogramar.');
      }

      tx.update(ref, <String, dynamic>{
        'estado': _estadoCanon(EstadosViaje.pendiente),
        'aceptado': false,
        'rechazado': false,
        'uidTaxista': '',
        'taxistaId': '',
        'fechaHora': Timestamp.fromDate(nuevaFechaHora),
        if (motivo != null && motivo.isNotEmpty) 'motivoReprogramacion': motivo,
        'reprogramadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    });
  }

  // ===================================================================
  //                      ACEPTACIÓN / FLUJO TAXISTA
  // ===================================================================
  static Future<void> aceptarViajeTransaccional({
    required String viajeId,
    required String uidTaxista,
    required String nombreTaxista,
  }) async {
    final DocumentReference<Map<String, dynamic>> viajesRef =
        _db.collection('viajes').doc(viajeId);
    final DocumentReference<Map<String, dynamic>> userRef =
        _db.collection('usuarios').doc(uidTaxista);

    await _db.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> viajeSnap =
          await tx.get(viajesRef);
      if (!viajeSnap.exists) throw Exception('El viaje no existe.');
      final Map<String, dynamic> d = viajeSnap.data()!;

      final String estado =
          EstadosViaje.normalizar((d['estado'] ?? '').toString());
      final bool aceptado = (d['aceptado'] ?? false) == true;
      final bool rechazado = (d['rechazado'] ?? false) == true;
      final bool completado = (d['completado'] ?? false) == true;
      final bool yaAsignado = ((d['uidTaxista'] ?? '') as String).isNotEmpty ||
          ((d['taxistaId'] ?? '') as String).isNotEmpty;

      if (estado != EstadosViaje.pendiente ||
          aceptado ||
          rechazado ||
          completado ||
          yaAsignado) {
        throw Exception('Este viaje ya no está disponible.');
      }

      final DocumentSnapshot<Map<String, dynamic>> userSnap =
          await tx.get(userRef);
      if (!userSnap.exists) throw Exception('Taxista no encontrado.');
      final Map<String, dynamic> u = userSnap.data()!;
      final billeSnap =
          await tx.get(_db.collection('billeteras_taxista').doc(uidTaxista));
      if (!PagosTaxistaRepo.taxistaSinBloqueoPrepagoOperativo(
          u, billeSnap.data())) {
        throw Exception(PagosTaxistaRepo.mensajeRecargaTomarViajes);
      }
      final bool disponible = (u['disponible'] ?? false) == true;
      if (!disponible) throw Exception('No disponible para aceptar viajes.');
      final String docsEstado =
          (u['docsEstado'] ?? '').toString().toLowerCase().trim();
      final bool documentosCompletos =
          (u['documentosCompletos'] ?? false) == true;
      final bool aprobado = documentosCompletos ||
          docsEstado == 'aprobado' ||
          docsEstado == 'verificado' ||
          docsEstado == 'ok';
      if (!aprobado) throw Exception('Documentos pendientes.');

      tx.update(viajesRef, <String, dynamic>{
        'taxistaId': uidTaxista,
        'uidTaxista': uidTaxista,
        'nombreTaxista': nombreTaxista,
        'aceptado': true,
        'rechazado': false,
        'estado': _estadoCanon(EstadosViaje.aceptado),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      tx.set(
          userRef,
          <String, dynamic>{
            'viajeActivoId': viajeId,
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    });
  }

  static Future<void> marcarClienteAbordoTx({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _viajes.doc(viajeId);
    await _db.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe.');
      final Map<String, dynamic> d = snap.data()!;
      if ((d['uidTaxista'] ?? '') != uidTaxista) {
        throw Exception('No autorizado');
      }

      final String estadoActual =
          EstadosViaje.normalizar((d['estado'] ?? '').toString());
      final bool completado = (d['completado'] ?? false) == true;
      if (completado ||
          estadoActual == EstadosViaje.completado ||
          estadoActual == EstadosViaje.cancelado) {
        throw Exception('Estado inválido');
      }

      tx.update(ref, <String, dynamic>{
        'estado': _estadoCanon(EstadosViaje.aBordo),
        'pickupConfirmadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> iniciarViajeTx({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _viajes.doc(viajeId);
    await _db.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe.');
      final Map<String, dynamic> d = snap.data()!;
      if ((d['uidTaxista'] ?? '') != uidTaxista) {
        throw Exception('No autorizado');
      }

      final String estadoActual =
          EstadosViaje.normalizar((d['estado'] ?? '').toString());
      if (estadoActual != EstadosViaje.aBordo) {
        throw Exception('Primero marca "Cliente a bordo".');
      }

      tx.update(ref, <String, dynamic>{
        'estado': _estadoCanon(EstadosViaje.enCurso),
        'inicioEnRutaEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> cancelarPorTaxistaYRepublicarTx({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _viajes.doc(viajeId);
    await _db.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Map<String, dynamic>> snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final Map<String, dynamic> d = snap.data()!;
      if ((d['uidTaxista'] ?? '') != uidTaxista) {
        throw Exception('No autorizado');
      }

      final String estadoActual =
          EstadosViaje.normalizar((d['estado'] ?? '').toString());
      final bool permitido = (estadoActual == EstadosViaje.aceptado ||
          estadoActual == EstadosViaje.enCaminoPickup);
      if (!permitido) {
        throw Exception('No se puede cancelar en este estado.');
      }

      DateTime fh;
      final dynamic ts = d['fechaHora'];
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

      tx.update(ref, <String, dynamic>{
        'estado': _estadoCanon(EstadosViaje.pendiente),
        'aceptado': false,
        'rechazado': false,
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
      });

      final refTax = _db.collection('usuarios').doc(uidTaxista);
      tx.set(
          refTax,
          {
            'viajeActivoId': '',
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    });
  }

  // ===================================================================
  //                            GANANCIAS
  // ===================================================================
  static Future<Map<String, dynamic>> calcularGananciasTaxista(
      String emailTaxista) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _viajes
        .where('nombreTaxista', isEqualTo: emailTaxista)
        .where('completado', isEqualTo: true)
        .get();

    double gananciaTotal = 0.0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      gananciaTotal += _asDouble(doc.data()['gananciaTaxista']);
    }

    return <String, dynamic>{
      'ganancia': _round2(gananciaTotal),
      'viajesCompletados': snapshot.docs.length,
    };
  }

  static Future<Map<String, dynamic>> calcularGananciasTaxistaPorUid(
      String uidTaxista) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _viajes
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('completado', isEqualTo: true)
        .get();

    double gananciaTotal = 0.0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in snapshot.docs) {
      gananciaTotal += _asDouble(doc.data()['gananciaTaxista']);
    }

    return <String, dynamic>{
      'ganancia': _round2(gananciaTotal),
      'viajesCompletados': snapshot.docs.length,
    };
  }

  // ===================================================================
  //                           CALIFICACIÓN
  // ===================================================================
  static Future<void> marcarComoCalificado(
    Viaje viaje,
    num calificacion,
    String comentario,
  ) async {
    final double cal = calificacion.toDouble();
    await _viajes.doc(viaje.id).update(<String, dynamic>{
      'calificado': true,
      'calificacion': cal,
      'comentario': comentario,
      'calificadoEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
  }

  /// Persistencia vía Cloud Function [submitTripRating]: Admin SDK, compatible con reglas Firestore.
  static Future<void> calificarViajeSeguro({
    required String viajeId,
    required String uidCliente,
    required num calificacion,
    String? comentario,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Debes iniciar sesión.');
    }
    if (user.uid != uidCliente) {
      throw Exception('Sesión no coincide con el usuario.');
    }

    final HttpsCallable callable = FirebaseFunctions.instanceFor(
      region: 'us-central1',
    ).httpsCallable('submitTripRating');

    try {
      final HttpsCallableResult<dynamic> res = await callable.call(
        <String, dynamic>{
          'viajeId': viajeId,
          'calificacion': calificacion,
          if (comentario != null && comentario.isNotEmpty)
            'comentario': comentario,
        },
      );
      final Object? data = res.data;
      if (data is Map) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(data);
        if (map['ok'] != true) {
          throw Exception(
            map['error']?.toString() ?? 'No se pudo guardar la calificación.',
          );
        }
      }
    } on FirebaseFunctionsException catch (e) {
      final String msg = (e.message ?? '').trim();
      switch (e.code) {
        case 'unauthenticated':
          throw Exception('Debes iniciar sesión.');
        case 'permission-denied':
          throw Exception(
              msg.isNotEmpty ? msg : 'No puedes calificar este viaje.');
        case 'failed-precondition':
          throw Exception(
            msg.isNotEmpty ? msg : 'Solo puedes calificar viajes completados.',
          );
        case 'not-found':
          throw Exception(msg.isNotEmpty ? msg : 'El viaje no existe.');
        case 'invalid-argument':
          throw Exception(msg.isNotEmpty ? msg : 'Datos inválidos.');
        default:
          throw Exception(
            msg.isNotEmpty ? msg : 'Error al guardar calificación (${e.code}).',
          );
      }
    }
  }

  static Future<double> obtenerPromedioTaxista(String uidTaxista) async {
    final DocumentSnapshot<Map<String, dynamic>> u =
        await _db.collection('usuarios').doc(uidTaxista).get();

    final Map<String, dynamic> data = u.data() ?? <String, dynamic>{};

    final double suma = (data['ratingSuma'] is num)
        ? (data['ratingSuma'] as num).toDouble()
        : 0.0;
    final double conteo = (data['ratingConteo'] is num)
        ? (data['ratingConteo'] as num).toDouble()
        : 0.0;

    if (conteo <= 0) return 0.0;
    return _round2(suma / conteo);
  }
}
