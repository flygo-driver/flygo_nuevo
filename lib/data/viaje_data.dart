// lib/data/viaje_data.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/data/pago_data.dart';

class ViajeData {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final CollectionReference<Map<String, dynamic>> _viajes =
      _db.collection('viajes');

  // Estados activos que hacen que el viaje "exista" para cliente y taxista.
  static const List<String> _activosCliente = [
    'pendiente',
    'aceptado',
    'a_bordo',
    'en_curso'
  ];
  static const List<String> _activosTaxista = [
    'aceptado',
    'a_bordo',
    'en_curso'
  ];

  // ----------------------- Helpers generales -----------------------
  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

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
    final creadoEn = _asDate(data['creadoEn']);
    if (creadoEn.millisecondsSinceEpoch > 0) return creadoEn;

    final fechaCreacion = _asDate(data['fechaCreacion']);
    if (fechaCreacion.millisecondsSinceEpoch > 0) return fechaCreacion;

    final fechaHora = _asDate(data['fechaHora']);
    return fechaHora.millisecondsSinceEpoch > 0
        ? fechaHora
        : DateTime.fromMillisecondsSinceEpoch(0);
  }

  static Map<String, dynamic> _normalize(Map<String, dynamic> data) {
    return {
      ...data,
      'precio': _asDouble(data['precio']),
      'gananciaTaxista': _asDouble(data['gananciaTaxista']),
      'comision': _asDouble(data['comision']),
      'latCliente': _asDouble(data['latCliente']),
      'lonCliente': _asDouble(data['lonCliente']),
      'latDestino': _asDouble(data['latDestino']),
      'lonDestino': _asDouble(data['lonDestino']),
      'latTaxista': _asDouble(data['latTaxista']),
      'lonTaxista': _asDouble(data['lonTaxista']),
    };
  }

  static int _toCents(num v) => (v * 100).round();
  static double _fromCents(int c) => c / 100.0;
  static int _comision20Cents(int precioCents) =>
      ((precioCents * 20) + 50) ~/ 100;

  static Map<String, int> _partidasCentsDesdePrecio(num precioDbl) {
    final pCents = _toCents(precioDbl);
    final cCents = _comision20Cents(pCents);
    final gCents = pCents - cCents;
    return {
      'precio_cents': pCents,
      'comision_cents': cCents,
      'ganancia_cents': gCents,
    };
  }

  // ----------------------- Helpers de cancelación -----------------------
  static const List<String> _motivosProtegidos = [
    'vehículo no coincide',
    'vehiculo no coincide',
    'seguridad',
    'conductor pidió cancelar',
    'conductor pidio cancelar',
    'retraso excesivo',
    'retraso',
  ];

  static bool _esMotivoProtegido(String? motivo) {
    final m = motivo?.toLowerCase().trim() ?? '';
    if (m.isEmpty) return false;
    return _motivosProtegidos.any((x) => m.contains(x));
  }

  static int _minsDesdeTs(dynamic ts) {
    if (ts is Timestamp) return DateTime.now().difference(ts.toDate()).inMinutes;
    if (ts is DateTime) return DateTime.now().difference(ts).inMinutes;
    return 0;
  }

  // --------------------- Crear ---------------------
  static Future<void> agregarViaje(Viaje viaje) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('No autenticado');

    final partidas = _partidasCentsDesdePrecio(viaje.precio);

    final Map<String, dynamic> base = {
      ...viaje.toMap(),
      'estado': (viaje.estado.isNotEmpty)
          ? viaje.estado
          : EstadosViaje.pendiente,
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

    final doc = await _viajes.add(base);
    await doc.update({'id': doc.id, 'updatedAt': FieldValue.serverTimestamp()});
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('No autenticado');

    final partidas = _partidasCentsDesdePrecio(precio);

    final ref = _viajes.doc();
    await ref.set({
      'id': ref.id,
      'clienteId': uid,
      'uidCliente': uid,
      'uidTaxista': '',
      'taxistaId': '',
      'origen': origen,
      'destino': destino,
      'latCliente': latCliente,
      'lonCliente': lonCliente,
      'latDestino': latDestino,
      'lonDestino': lonDestino,
      'precio': _fromCents(partidas['precio_cents']!),
      'metodoPago': metodoPago,
      'gananciaTaxista': _fromCents(partidas['ganancia_cents']!),
      'comision': _fromCents(partidas['comision_cents']!),
      ...partidas,
      'latTaxista': 0.0,
      'lonTaxista': 0.0,
      'estado': EstadosViaje.pendiente,
      'aceptado': false,
      'rechazado': false,
      'completado': false,
      'fechaHora': Timestamp.fromDate(DateTime.now()),
      'creadoEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  // --------------------- Update ---------------------
  static Future<void> actualizarViaje(Viaje viaje) async {
    if (viaje.id.isEmpty) {
      throw Exception('actualizarViaje: id vacío');
    }
    final partidas = _partidasCentsDesdePrecio(viaje.precio);
    final data = {
      ...viaje.toMap(),
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
    final qs = await _viajes
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('completado', isEqualTo: false)
        .get();

    if (qs.docs.isEmpty) return;

    final docs = [...qs.docs];
    docs.sort((a, b) => _createdOf(b.data()).compareTo(_createdOf(a.data())));
    final ref = docs.first.reference;

    await ref.update({
      'latTaxista': _round2(lat),
      'lonTaxista': _round2(lon),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> actualizarPosicionTaxistaPorViaje({
    required String viajeId,
    required double lat,
    required double lon,
  }) async {
    final ref = _viajes.doc(viajeId);
    await ref.update({
      'latTaxista': _round2(lat),
      'lonTaxista': _round2(lon),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // --------------------- Streams ---------------------
  static Stream<Viaje?> streamEstadoViajePorCliente(String uidCliente) {
    return _viajes
        .where('uidCliente', isEqualTo: uidCliente)
        .where('estado', whereIn: _activosCliente)
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isEmpty
            ? null
            : Viaje.fromMap(
                s.docs.first.id, _normalize(s.docs.first.data())));
  }

  static Stream<Viaje?> streamViajeEnCursoPorTaxista(String uidTaxista) {
    return _viajes
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('estado', whereIn: _activosTaxista)
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isEmpty
            ? null
            : Viaje.fromMap(
                s.docs.first.id, _normalize(s.docs.first.data())));
  }

  static Stream<List<Viaje>> streamViajesPorCliente(String uidCliente) {
    return _viajes
        .where('clienteId', isEqualTo: uidCliente)
        .snapshots()
        .map((s) {
      final list = s.docs
          .map((d) => Viaje.fromMap(d.id, _normalize(d.data())))
          .toList();
      list.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
      return list;
    });
  }

  static Stream<List<Viaje>> streamHistorialCliente(String clienteId) {
    return _viajes
        .where('clienteId', isEqualTo: clienteId)
        .where('completado', isEqualTo: true)
        .snapshots()
        .map((s) {
      final list = s.docs
          .map((d) => Viaje.fromMap(d.id, _normalize(d.data())))
          .toList();
      list.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
      return list;
    });
  }

  static Stream<List<Viaje>> streamHistorialClienteTodosEstados(
    String clienteId,
  ) {
    return _viajes
        .where('clienteId', isEqualTo: clienteId)
        .snapshots()
        .map((s) {
      final list = s.docs
          .map((d) => Viaje.fromMap(d.id, _normalize(d.data())))
          .toList();
      list.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
      return list;
    });
  }

  // --------------------- Consultas ---------------------
  static Future<Viaje?> obtenerViajeEnCurso(String emailTaxista) async {
    final snapshot = await _viajes
        .where('nombreTaxista', isEqualTo: emailTaxista)
        .where('aceptado', isEqualTo: true)
        .where('completado', isEqualTo: false)
        .get();

    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return Viaje.fromMap(doc.id, _normalize(doc.data()));
  }

  static Future<List<Viaje>> obtenerViajesPorCliente(String clienteId) async {
    final snapshot =
        await _viajes.where('clienteId', isEqualTo: clienteId).get();
    final list = snapshot.docs
        .map((d) => Viaje.fromMap(d.id, _normalize(d.data())))
        .toList();
    list.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
    return list;
  }

  static Future<List<Viaje>> obtenerHistorialCliente(String clienteId) async {
    final snapshot = await _viajes
        .where('clienteId', isEqualTo: clienteId)
        .where('completado', isEqualTo: true)
        .get();
    final list = snapshot.docs
        .map((d) => Viaje.fromMap(d.id, _normalize(d.data())))
        .toList();
    list.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
    return list;
  }

  static Future<List<Viaje>> obtenerHistorialTaxista(String emailTaxista) async {
    final snapshot = await _viajes
        .where('nombreTaxista', isEqualTo: emailTaxista)
        .where('completado', isEqualTo: true)
        .get();
    final list = snapshot.docs
        .map((d) => Viaje.fromMap(d.id, _normalize(d.data())))
        .toList();
    list.sort((a, b) => b.fechaHora.compareTo(a.fechaHora));
    return list;
  }

  // --------------------- Estados / completar ---------------------
  static Future<void> marcarViajeComoCompletado(Viaje viaje) async {
    await completarViaje(viaje.id);
  }

  static Future<void> completarViaje(String viajeId) async {
    final ref = _viajes.doc(viajeId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe.');
      final data = snap.data() as Map<String, dynamic>;

      final bool yaCompletado =
          (data['completado'] ?? false) == true ||
              (data['estado']?.toString() == EstadosViaje.completado);
      if (yaCompletado) return;

      final double precioBase = _asDouble(
        data['precioFinal'] ?? data['precio'],
      );

      final int precioCents =
          (data['precio_cents'] as int?) ?? _toCents(precioBase);
      final int comisionCents =
          (data['comision_cents'] as int?) ?? _comision20Cents(precioCents);
      final int gananciaCents =
          (data['ganancia_cents'] as int?) ?? (precioCents - comisionCents);

      tx.update(ref, {
        'estado': EstadosViaje.completado,
        'completado': true,
        'precioFinal': _fromCents(precioCents),
        'comision': _fromCents(comisionCents),
        'gananciaTaxista': _fromCents(gananciaCents),
        'precio_cents': precioCents,
        'comision_cents': comisionCents,
        'ganancia_cents': gananciaCents,
        'finalizadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    // Registrar movimiento de billetera (80/20)
    try {
      final d = await _viajes.doc(viajeId).get();
      if (d.exists) {
        final v = Viaje.fromMap(d.id, _normalize(d.data()!));
        await PagoData.registrarMovimientoPorViaje(v);
      }
    } catch (_) {}
  }

  static Future<void> cancelarViaje(Viaje viaje) async {
    await _viajes.doc(viaje.id).update({
      'aceptado': false,
      'rechazado': true,
      'estado': EstadosViaje.cancelado,
      'uidTaxista': '',
      'taxistaId': '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // --------------------- Cancelación por cliente (PRO) ---------------------
  static Future<void> cancelarViajePorCliente({
    required String viajeId,
    required String uidCliente,
    String? motivo,
  }) async {
    final ref = _viajes.doc(viajeId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe.');
      final Map<String, dynamic> d = snap.data() as Map<String, dynamic>;

      // Autorización
      final String clienteId = (d['clienteId'] ?? '').toString();
      if (clienteId != uidCliente) {
        throw Exception('No puedes cancelar este viaje.');
      }

      // Estado actual
      final String estado = (d['estado'] ?? '').toString();
      final bool completado = (d['completado'] ?? false) == true;

      if (completado || estado == EstadosViaje.completado) {
        throw Exception('El viaje ya fue completado.');
      }
      if (estado == EstadosViaje.cancelado) {
        return; // idempotente
      }

      // Reglas (notar que las reglas de seguridad actuales NO permiten guardar fees aquí)
      final DateTime fh = _asDate(d['fechaHora']);
      final bool esProgramadoFuturo =
          fh.isAfter(DateTime.now().add(const Duration(minutes: 15)));

      final bool protegido = _esMotivoProtegido(motivo);
      // int feeCents = 0; // si quieres persistir fee, añade las claves a las reglas

      if (estado == EstadosViaje.pendiente) {
        // feeCents = 0;
      } else if (estado == EstadosViaje.aceptado) {
        final int mins = _minsDesdeTs(d['aceptadoEn']);
        final bool dentroDeGracia = mins <= 2;
        if (esProgramadoFuturo || protegido || dentroDeGracia) {
          // feeCents = 0;
        } else {
          // feeCents = 50 * 100;
        }
      } else if (estado == EstadosViaje.aBordo) {
        if (!protegido) {
          throw Exception(
              'No puedes cancelar en este estado. Si hay problema de seguridad o el vehículo no coincide, selecciona ese motivo.');
        }
        // feeCents = 0;
      } else if (estado == EstadosViaje.enCurso) {
        throw Exception(
            'El viaje ya inició. Solicita una finalización anticipada con el conductor.');
      }

      tx.update(ref, {
        'estado': EstadosViaje.cancelado,
        'aceptado': false,
        'rechazado': true,
        'uidTaxista': '',
        'taxistaId': '',
        if (motivo != null && motivo.isNotEmpty) 'motivoCancelacion': motivo,
        'canceladoPor': 'cliente',
        'canceladoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Para guardar fee/cancelacionProtegida añade esas claves a changedOnly[] en tus reglas.
    });
  }

  static Future<void> reprogramarViajePorCliente({
    required String viajeId,
    required String uidCliente,
    required DateTime nuevaFechaHora,
    String? motivo,
  }) async {
    final ref = _viajes.doc(viajeId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe.');
      final Map<String, dynamic> data = snap.data() as Map<String, dynamic>;
      if ((data['clienteId'] ?? '') != uidCliente) {
        throw Exception('No puedes reprogramar este viaje.');
      }

      final String estado = (data['estado'] ?? '').toString();
      final bool completado = (data['completado'] ?? false) == true;

      if (completado || estado == EstadosViaje.completado) {
        throw Exception('El viaje completado no se puede reprogramar.');
      }
      if (estado == EstadosViaje.enCurso) {
        throw Exception('El viaje en curso no se puede reprogramar.');
      }

      tx.update(ref, {
        'estado': EstadosViaje.pendiente,
        'aceptado': false,
        'rechazado': false,
        'uidTaxista': '',
        'taxistaId': '',
        'fechaHora': Timestamp.fromDate(nuevaFechaHora),
        if (motivo != null && motivo.isNotEmpty) 'motivoReprogramacion': motivo,
        'reprogramadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // --------------------- Aceptación / flujo del taxista ---------------------
  static Future<void> aceptarViajeTransaccional({
    required String viajeId,
    required String uidTaxista,
    required String nombreTaxista,
  }) async {
    final viajesRef = _db.collection('viajes').doc(viajeId);
    final userRef = _db.collection('usuarios').doc(uidTaxista);

    await _db.runTransaction((tx) async {
      final viajeSnap = await tx.get(viajesRef);
      if (!viajeSnap.exists) throw Exception('El viaje no existe.');
      final d = viajeSnap.data()!;
      final estado = (d['estado'] ?? '').toString();
      final aceptado = (d['aceptado'] ?? false) == true;
      final rechazado = (d['rechazado'] ?? false) == true;
      final completado = (d['completado'] ?? false) == true;
      final yaAsignado =
          ((d['uidTaxista'] ?? '') as String).isNotEmpty ||
              ((d['taxistaId'] ?? '') as String).isNotEmpty;

      if (estado != EstadosViaje.pendiente ||
          aceptado ||
          rechazado ||
          completado ||
          yaAsignado) {
        throw Exception('Este viaje ya no está disponible.');
      }

      final userSnap = await tx.get(userRef);
      if (!userSnap.exists) throw Exception('Taxista no encontrado.');
      final u = userSnap.data()!;
      final disponible = (u['disponible'] ?? false) == true;
      if (!disponible) throw Exception('No disponible para aceptar viajes.');
      final docsEstado =
          (u['docsEstado'] ?? '').toString().toLowerCase().trim();
      final documentosCompletos = (u['documentosCompletos'] ?? false) == true;
      final aprobado = documentosCompletos ||
          docsEstado == 'aprobado' ||
          docsEstado == 'verificado' ||
          docsEstado == 'ok';
      if (!aprobado) throw Exception('Documentos pendientes.');

      // ⚠ IMPORTANTE: no escribir 'aceptadoEn' aquí porque tus reglas actuales no lo permiten.
      tx.update(viajesRef, {
        'taxistaId': uidTaxista,
        'uidTaxista': uidTaxista,
        'nombreTaxista': nombreTaxista,
        'aceptado': true,
        'rechazado': false,
        'estado': EstadosViaje.aceptado,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> marcarClienteAbordoTx({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _viajes.doc(viajeId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe.');
      final Map<String, dynamic> d = snap.data() as Map<String, dynamic>;
      if ((d['uidTaxista'] ?? '') != uidTaxista) {
        throw Exception('No autorizado');
      }

      final String estadoActual = (d['estado'] ?? '').toString();
      final bool completado = (d['completado'] ?? false) == true;
      if (completado ||
          estadoActual == EstadosViaje.completado ||
          estadoActual == EstadosViaje.cancelado) {
        throw Exception('Estado inválido');
      }

      tx.update(ref, {
        'estado': EstadosViaje.aBordo,
        'pickupConfirmadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> iniciarViajeTx({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _viajes.doc(viajeId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe.');
      final Map<String, dynamic> d = snap.data() as Map<String, dynamic>;
      if ((d['uidTaxista'] ?? '') != uidTaxista) {
        throw Exception('No autorizado');
      }

      final String estadoActual = (d['estado'] ?? '').toString();
      if (estadoActual != EstadosViaje.aBordo) {
        throw Exception('Primero marca "Cliente a bordo".');
      }

      tx.update(ref, {
        'estado': EstadosViaje.enCurso,
        'inicioEnRutaEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> cancelarPorTaxistaYRepublicarTx({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _viajes.doc(viajeId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final d = snap.data()!;
      if ((d['uidTaxista'] ?? '') != uidTaxista) {
        throw Exception('No autorizado');
      }

      final estadoActual = (d['estado'] ?? '').toString();
      final permitido = (estadoActual == EstadosViaje.aceptado);
      if (!permitido) {
        throw Exception('No se puede cancelar en este estado.');
      }

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
      final esAhora =
          !fh.isAfter(DateTime.now().add(const Duration(minutes: 10)));

      tx.update(ref, {
        'estado': EstadosViaje.pendiente,
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
      });
    });
  }

  // --------------------- Ganancias ---------------------
  static Future<Map<String, dynamic>> calcularGananciasTaxista(
    String emailTaxista,
  ) async {
    final snapshot = await _viajes
        .where('nombreTaxista', isEqualTo: emailTaxista)
        .where('completado', isEqualTo: true)
        .get();

    double gananciaTotal = 0.0;
    for (final doc in snapshot.docs) {
      gananciaTotal += _asDouble(doc.data()['gananciaTaxista']);
    }

    return {
      'ganancia': _round2(gananciaTotal),
      'viajesCompletados': snapshot.docs.length,
    };
  }

  static Future<Map<String, dynamic>> calcularGananciasTaxistaPorUid(
    String uidTaxista,
  ) async {
    final snapshot = await _viajes
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('completado', isEqualTo: true)
        .get();

    double gananciaTotal = 0.0;
    for (final doc in snapshot.docs) {
      gananciaTotal += _asDouble(doc.data()['gananciaTaxista']);
    }

    return {
      'ganancia': _round2(gananciaTotal),
      'viajesCompletados': snapshot.docs.length,
    };
  }

  // --------------------- Calificación ---------------------
  static Future<void> marcarComoCalificado(
    Viaje viaje,
    num calificacion,
    String comentario,
  ) async {
    final double cal = calificacion.toDouble();
    await _viajes.doc(viaje.id).update({
      'calificado': true,
      'calificacion': cal,
      'comentario': comentario,
      'calificadoEn': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> calificarViajeSeguro({
    required String viajeId,
    required String uidCliente,
    required num calificacion,
    String? comentario,
  }) async {
    final refViaje = _viajes.doc(viajeId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(refViaje);
      if (!snap.exists) throw Exception('El viaje no existe.');
      final Map<String, dynamic> data = snap.data() as Map<String, dynamic>;

      final String clienteId = (data['clienteId'] ?? '').toString();
      if (clienteId != uidCliente) {
        throw Exception('No puedes calificar este viaje.');
      }

      final bool completado = (data['completado'] ?? false) == true;
      if (!completado) {
        throw Exception('Solo puedes calificar viajes completados.');
      }

      final bool yaCalificado = (data['calificado'] ?? false) == true;
      if (yaCalificado) return;

      final double cal = calificacion.toDouble();

      tx.update(refViaje, {
        'calificado': true,
        'calificacion': cal,
        if (comentario != null && comentario.isNotEmpty)
          'comentario': comentario,
        'calificadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final String uidTaxista = (data['uidTaxista'] ?? '').toString();
      if (uidTaxista.isNotEmpty) {
        final refTaxista = _db.collection('usuarios').doc(uidTaxista);
        tx.set(refTaxista, {
          'ratingSuma': FieldValue.increment(cal),
          'ratingConteo': FieldValue.increment(1),
        }, SetOptions(merge: true));
      }
    });
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
