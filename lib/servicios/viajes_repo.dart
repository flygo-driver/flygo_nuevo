// lib/servicios/viajes_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';

class ViajesRepo {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col => _db.collection('viajes');

  // ==============================================================
  //                           CREATE
  // ==============================================================
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
    required String metodoPago,
    required String tipoVehiculo,
    required bool idaYVuelta,
    String? categoria,
    List<Map<String, dynamic>>? waypoints,
    Map<String, dynamic>? extras,
    double? distanciaKm,
  }) async {
    bool _outOfRange(double lat, double lon) =>
        !(lat.isFinite && lon.isFinite) ||
        lat < -90 || lat > 90 ||
        lon < -180 || lon > 180;

    if (_outOfRange(latOrigen, lonOrigen) || _outOfRange(latDestino, lonDestino)) {
      throw ArgumentError('Coordenadas fuera de rango');
    }
    if (!precio.isFinite || precio <= 0) {
      throw ArgumentError('Precio inválido');
    }

    final int precioCents = (precio * 100).round();
    final int comisionCents = ((precioCents * 20) + 50) ~/ 100;
    final int gananciaCents = precioCents - comisionCents;

    // Ventanas para programados
    const int kAcceptHoursBefore = 2;
    const int kReadyMinutesBefore = 45;

    final DateTime now = DateTime.now();
    final bool esAhora = fechaHora.isBefore(now.add(const Duration(minutes: 15)));

    // Ventanas/flags
    final DateTime acceptAfterDT = esAhora ? now : fechaHora.subtract(const Duration(hours: kAcceptHoursBefore));
    final DateTime startWindowDT = esAhora ? now : fechaHora.subtract(const Duration(minutes: kReadyMinutesBefore));
    // Publica YA para que aparezca en Programados desde su creación
    final DateTime publishAtDT = now;

    List<Map<String, dynamic>>? _sanitize(List<Map<String, dynamic>>? wps) {
      if (wps == null) return null;
      final out = <Map<String, dynamic>>[];
      for (final w in wps) {
        final double? lat = (w['lat'] is num) ? (w['lat'] as num).toDouble() : null;
        final double? lon = (w['lon'] is num) ? (w['lon'] as num).toDouble() : null;
        if (lat == null || lon == null) continue;
        if (_outOfRange(lat, lon)) continue;
        out.add({'lat': lat, 'lon': lon, 'label': (w['label'] ?? '').toString()});
      }
      return out.isEmpty ? null : out;
    }

    final doc = _col.doc();
    final data = <String, dynamic>{
      'id': doc.id,
      'clienteId': uidCliente,
      'uidCliente': uidCliente,

      'uidTaxista': '',
      'taxistaId': '',
      'nombreTaxista': '',
      'telefono': '',
      'placa': '',
      'tipoVehiculo': tipoVehiculo, // preferencia del cliente
      'marca': '',
      'modelo': '',
      'color': '',

      'origen': origen,
      'destino': destino,
      'latCliente': latOrigen,
      'lonCliente': lonOrigen,
      'latOrigen': latOrigen,
      'lonOrigen': lonOrigen,
      'latDestino': latDestino,
      'lonDestino': lonDestino,

      'sentido': idaYVuelta ? 'ida_y_vuelta' : 'solo_ida',
      'idaYVuelta': idaYVuelta,

      'fechaHora': Timestamp.fromDate(fechaHora),
      'acceptAfter': Timestamp.fromDate(acceptAfterDT),
      'publishAt': Timestamp.fromDate(publishAtDT),
      'startWindowAt': Timestamp.fromDate(startWindowDT),
      'programado': !esAhora,
      'esAhora': esAhora,
      'metodoPago': metodoPago,
      'estado': (metodoPago.toLowerCase().trim() == 'tarjeta')
          ? EstadosViaje.pendientePago
          : EstadosViaje.pendiente,
      'aceptado': false,
      'rechazado': false,
      'completado': false,

      // flag que usa la pantalla del taxista para su stream de “en curso”
      'activo': esAhora,
      'ignoradosPor': <String>[],
      'reservadoPor': '',
      'reservadoHasta': null,

      'precio': precioCents / 100.0,
      'comision': comisionCents / 100.0,
      'gananciaTaxista': gananciaCents / 100.0,

      'precio_cents': precioCents,
      'comision_cents': comisionCents,
      'ganancia_cents': gananciaCents,

      'latTaxista': 0.0,
      'lonTaxista': 0.0,
      'driverLat': 0.0,
      'driverLon': 0.0,

      if (categoria != null && categoria.isNotEmpty) 'categoria': categoria,
      if (distanciaKm != null && distanciaKm.isFinite && distanciaKm > 0) 'distanciaKm': distanciaKm,

      'creadoEn': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    final wps = _sanitize(waypoints);
    if (wps != null) data['waypoints'] = wps;
    if (extras != null && extras.isNotEmpty) data['extras'] = extras;

    await doc.set(data);

    // 👉 CLAVE: dejar “viajeActivoId” en el cliente para que su app lo muestre
    await _db.collection('usuarios').doc(uidCliente).set({
      'viajeActivoId': doc.id,
      'siguienteViajeId': '',
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return doc.id;
  }

  // ==============================================================
  //           SANEOS ANTES/DESPUÉS DE ACEPTAR
  // ==============================================================
  static Future<void> ensureTaxistaLibre(String uidTaxista) async {
    final hasActive = await _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('activo', isEqualTo: true)
        .limit(1)
        .get()
        .then((q) => q.docs.isNotEmpty);

    if (!hasActive) {
      await _db.collection('usuarios').doc(uidTaxista).set({
        'viajeActivoId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  static Future<void> ensureSiguienteCoherente(String uidTaxista) async {
    final uRef = _db.collection('usuarios').doc(uidTaxista);
    final u = await uRef.get();
    final m = u.data() ?? {};
    final String nextId = (m['siguienteViajeId'] ?? '').toString();
    if (nextId.isEmpty) return;

    final vRef = _col.doc(nextId);
    final v = await vRef.get();
    if (!v.exists) {
      await uRef.set({'siguienteViajeId': ''}, SetOptions(merge: true));
      return;
    }
    final d = v.data()!;
    final String estado = (d['estado'] ?? '').toString();
    final String uidAsig = (d['uidTaxista'] ?? '').toString();
    final String reservadoPor = (d['reservadoPor'] ?? '').toString();
    final Timestamp? reservadoHasta = d['reservadoHasta'];
    final bool reservaVencida = reservadoHasta != null && reservadoHasta.compareTo(Timestamp.now()) <= 0;

    final ok = (estado == EstadosViaje.pendiente || estado == EstadosViaje.pendientePago)
        && uidAsig.isEmpty && reservadoPor == uidTaxista && !reservaVencida;

    if (!ok) {
      await _db.runTransaction((tx) async {
        tx.update(vRef, {
          'reservadoPor': '',
          'reservadoHasta': null,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp()
        });
        tx.set(uRef, {
          'siguienteViajeId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp()
        }, SetOptions(merge: true));
      });
    }
  }

  static Future<void> _ensureChatForTrip(String viajeId) async {
    final v = await _col.doc(viajeId).get();
    if (!v.exists) return;
    final d = v.data()!;
    final String uidCli = (d['uidCliente'] ?? d['clienteId'] ?? '').toString();
    final String uidTx = (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString();
    if (uidCli.isEmpty || uidTx.isEmpty) return;

    final cRef = _db.collection('chats').doc(viajeId);
    final c = await cRef.get();
    final payload = {
      'participantes': [uidCli, uidTx],
      'viajeId': viajeId,
      'lastMessage': '',
      'lastAt': FieldValue.serverTimestamp(),
      'creadoAt': FieldValue.serverTimestamp(),
    };
    if (!c.exists) {
      await cRef.set(payload);
    }
  }

  // ==============================================================
  //                     CLAIM / RESERVA (ACEPTAR)
  // ==============================================================
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
          (estado == EstadosViaje.pendiente || estado == EstadosViaje.pendientePago);
      if (!estadoPermitido || yaAsignado) return false;

      // Reserva y ventana
      final String reservadoPor = (data['reservadoPor'] ?? '').toString();
      final Timestamp? reservadoHasta = data['reservadoHasta'];
      final bool reservaVigente =
          reservadoPor.isNotEmpty && (reservadoHasta == null || reservadoHasta.compareTo(Timestamp.now()) > 0);
      if (reservaVigente && reservadoPor != uidTaxista) return false;

      final tsAcceptAfter = data['acceptAfter'];
      if (tsAcceptAfter is Timestamp) {
        final DateTime acceptAfter = tsAcceptAfter.toDate();
        if (DateTime.now().isBefore(acceptAfter)) return false;
      }

      final uSnap = await tx.get(uRef);
      final uData = uSnap.data() ?? <String, dynamic>{};
      final String viajeActivoId = (uData['viajeActivoId'] ?? '').toString();
      if (viajeActivoId.isNotEmpty) return false;

      final String _tel   = (telefono.isNotEmpty ? telefono : (uData['telefono'] ?? '')).toString();
      final String _plac  = (placa.isNotEmpty ? placa : (uData['placa'] ?? '')).toString();
      final String _tipo  = (tipoVehiculo.isNotEmpty ? tipoVehiculo : (uData['tipoVehiculo'] ?? '')).toString();
      final String _marca = (uData['marca'] ?? uData['vehiculoMarca'] ?? '').toString();
      final String _modelo= (uData['modelo'] ?? uData['vehiculoModelo'] ?? '').toString();
      final String _color = (uData['color'] ?? uData['vehiculoColor'] ?? '').toString();

      // 👉 uid del cliente del viaje
      final String uidCliente = (data['uidCliente'] ?? data['clienteId'] ?? '').toString();

      tx.update(ref, {
        'uidTaxista': uidTaxista,
        'taxistaId': uidTaxista,
        'nombreTaxista': nombreTaxista,
        'telefono': _tel,
        'placa': _plac,
        'tipoVehiculo': _tipo,
        'marca': _marca,
        'modelo': _modelo,
        'color': _color,
        'estado': EstadosViaje.aceptado,
        'aceptado': true,
        'rechazado': false,
        'activo': true,
        'aceptadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'ignoradosPor': FieldValue.delete(),
        'reservadoPor': '',
        'reservadoHasta': null,
      });

      // 👉 Marcar viaje activo para el CLIENTE
      if (uidCliente.isNotEmpty) {
        tx.set(_db.collection('usuarios').doc(uidCliente), {
          'viajeActivoId': viajeId,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // 👉 Marcar activo para el TAXISTA
      tx.set(uRef, {
        'viajeActivoId': viajeId,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    });

    if (ok) {
      await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: viajeId);
      await _db.collection('usuarios').doc(uidTaxista).set(
        {'siguienteViajeId': '', 'updatedAt': FieldValue.serverTimestamp(), 'actualizadoEn': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      await _ensureChatForTrip(viajeId);
    }
    return ok;
  }

  static Future<String> claimTripWithReason({
    required String viajeId,
    required String uidTaxista,
    required String nombreTaxista,
    String telefono = '',
    String placa = '',
    String tipoVehiculo = '',
  }) async {
    final vRef = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    try {
      await _db.runTransaction((tx) async {
        final vSnap = await tx.get(vRef);
        if (!vSnap.exists) throw 'no-existe';
        final d = vSnap.data()!;

        final String estado = (d['estado'] ?? '').toString();
        final bool estadoPermitido = (estado == EstadosViaje.pendiente || estado == EstadosViaje.pendientePago);
        if (!estadoPermitido) throw 'estado-no-pendiente';

        final bool yaAsignado =
            ((d['uidTaxista'] ?? '') as String).isNotEmpty ||
            ((d['taxistaId'] ?? '') as String).isNotEmpty;
        if (yaAsignado) throw 'ya-asignado';

        // Ventanas
        final now = DateTime.now();
        final tsAA = d['acceptAfter'];
        if (tsAA is Timestamp && now.isBefore(tsAA.toDate())) throw 'acceptAfter-futuro';
        final tsPub = d['publishAt'];
        if (tsPub is Timestamp && tsPub.toDate().isAfter(now)) throw 'publish-futuro';

        // Reserva
        final reservadoPor = (d['reservadoPor'] ?? '').toString();
        DateTime? reservadoHasta;
        final rh = d['reservadoHasta'];
        if (rh is Timestamp) reservadoHasta = rh.toDate();
        final reservaVigente = reservadoPor.isNotEmpty && (reservadoHasta == null || reservadoHasta.isAfter(now));
        if (reservaVigente && reservadoPor != uidTaxista) throw 'reservado-otro';

        // Taxista libre
        final uSnap = await tx.get(uRef);
        final uData = uSnap.data() ?? const <String, dynamic>{};
        final String viajeActivoId = (uData['viajeActivoId'] ?? '').toString();
        if (viajeActivoId.isNotEmpty) throw 'taxista-ocupado';

        final String _tel   = (telefono.isNotEmpty ? telefono : (uData['telefono'] ?? '')).toString();
        final String _plac  = (placa.isNotEmpty ? placa : (uData['placa'] ?? '')).toString();
        final String _tipo  = (tipoVehiculo.isNotEmpty ? tipoVehiculo : (uData['tipoVehiculo'] ?? '')).toString();
        final String _marca = (uData['marca'] ?? uData['vehiculoMarca'] ?? '').toString();
        final String _modelo= (uData['modelo'] ?? uData['vehiculoModelo'] ?? '').toString();
        final String _color = (uData['color'] ?? uData['vehiculoColor'] ?? '').toString();

        final String uidCliente = (d['uidCliente'] ?? d['clienteId'] ?? '').toString();

        tx.update(vRef, {
          'uidTaxista': uidTaxista,
          'taxistaId': uidTaxista,
          'nombreTaxista': nombreTaxista,
          'telefono': _tel,
          'placa': _plac,
          'tipoVehiculo': _tipo,
          'marca': _marca,
          'modelo': _modelo,
          'color': _color,
          'estado': EstadosViaje.aceptado,
          'aceptado': true,
          'rechazado': false,
          'activo': true,
          'aceptadoEn': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
          'reservadoPor': '',
          'reservadoHasta': null,
          'ignoradosPor': FieldValue.delete(),
        });

        // 👉 Cliente ve su viaje activo
        if (uidCliente.isNotEmpty) {
          tx.set(_db.collection('usuarios').doc(uidCliente), {
            'viajeActivoId': vRef.id,
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        // 👉 Taxista activo
        tx.set(uRef, {
          'viajeActivoId': vRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      // fuera de la TX
      await _limpiarOtrosActivosDelTaxista(uidTaxista, exceptoId: viajeId);
      await _db.collection('usuarios').doc(uidTaxista).set(
        {'siguienteViajeId': '', 'updatedAt': FieldValue.serverTimestamp(), 'actualizadoEn': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      await _ensureChatForTrip(viajeId);

      return 'ok';
    } on FirebaseException catch (e) {
      return 'permiso:${e.code}';
    } catch (e) {
      return e.toString();
    }
  }

  static Future<void> reservarComoSiguiente({
    required String viajeId,
    required String uidTaxista,
    int ttlMin = 10,
  }) async {
    final ref = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final d = snap.data()!;

      final String estado = (d['estado'] ?? '').toString();
      final String uidAsignado = (d['uidTaxista'] ?? '').toString();
      final String reservadoPor = (d['reservadoPor'] ?? '').toString();
      final Timestamp? reservadoHasta = d['reservadoHasta'];
      final bool reservaVigente =
          reservadoPor.isNotEmpty && (reservadoHasta == null || reservadoHasta.compareTo(Timestamp.now()) > 0);

      final bool viajeLibre = uidAsignado.isEmpty;
      final bool estadoPermitido = (estado == EstadosViaje.pendiente || estado == EstadosViaje.pendientePago);
      if (!estadoPermitido || !viajeLibre || (reservaVigente && reservadoPor != uidTaxista)) {
        throw StateError('El viaje no está disponible para reservar.');
      }

      final uSnap = await tx.get(uRef);
      final uData = uSnap.data() ?? <String, dynamic>{};
      final String viajeActivoId = (uData['viajeActivoId'] ?? '').toString();
      if (viajeActivoId.isEmpty) {
        throw StateError('Primero debes tener un viaje activo para reservar el siguiente.');
      }

      final String siguienteViajeId = (uData['siguienteViajeId'] ?? '').toString();
      if (siguienteViajeId.isNotEmpty && siguienteViajeId != viajeId) {
        throw StateError('Ya tienes un viaje reservado en cola.');
      }

      final vence = Timestamp.fromDate(DateTime.now().add(Duration(minutes: ttlMin)));

      tx.update(ref, {
        'reservadoPor': uidTaxista,
        'reservadoHasta': vence,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
      tx.set(uRef, {
        'siguienteViajeId': viajeId,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static Future<void> liberarReserva({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');

      final d = snap.data()!;
      final String reservadoPor = (d['reservadoPor'] ?? '').toString();
      if (reservadoPor != uidTaxista) {
        throw StateError('No puedes liberar una reserva que no es tuya.');
      }

      tx.update(ref, {
        'reservadoPor': '',
        'reservadoHasta': null,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      tx.set(uRef, {
        'siguienteViajeId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static Future<String?> promoverReservaAlCompletar({
    required String uidTaxista,
  }) async {
    final uRef = _db.collection('usuarios').doc(uidTaxista);

    return await _db.runTransaction((tx) async {
      final uSnap = await tx.get(uRef);
      final uData = uSnap.data() ?? <String, dynamic>{};
      final String siguienteViajeId = (uData['siguienteViajeId'] ?? '').toString();
      if (siguienteViajeId.isEmpty) return null;

      final vRef = _col.doc(siguienteViajeId);
      final vSnap = await tx.get(vRef);
      if (!vSnap.exists) {
        tx.set(uRef, {
          'siguienteViajeId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return null;
      }

      final v = vSnap.data()!;
      final String estado = (v['estado'] ?? '').toString();
      final String uidAsignado = (v['uidTaxista'] ?? '').toString();
      final String reservadoPor = (v['reservadoPor'] ?? '').toString();
      final Timestamp? reservadoHasta = v['reservadoHasta'];
      final bool reservaVencida = reservadoHasta != null && reservadoHasta.compareTo(Timestamp.now()) <= 0;

      final tsAcceptAfter = v['acceptAfter'];
      if (tsAcceptAfter is Timestamp && DateTime.now().isBefore(tsAcceptAfter.toDate())) {
        return null;
      }

      final bool valido =
          (estado == EstadosViaje.pendiente || estado == EstadosViaje.pendientePago) &&
          uidAsignado.isEmpty &&
          reservadoPor == uidTaxista &&
          !reservaVencida;

      if (!valido) {
        tx.update(vRef, {
          'reservadoPor': '',
          'reservadoHasta': null,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });
        tx.set(uRef, {
          'siguienteViajeId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return null;
      }

      final String nombreTaxista = (uData['nombre'] ?? uData['displayName'] ?? '').toString();
      final String _tel   = (uData['telefono'] ?? '').toString();
      final String _plac  = (uData['placa'] ?? '').toString();
      final String _tipo  = (uData['tipoVehiculo'] ?? '').toString();
      final String _marca = (uData['marca'] ?? uData['vehiculoMarca'] ?? '').toString();
      final String _modelo= (uData['modelo'] ?? uData['vehiculoModelo'] ?? '').toString();
      final String _color = (uData['color'] ?? uData['vehiculoColor'] ?? '').toString();

      // uid del cliente del viaje promovido
      final String uidCliente = (v['uidCliente'] ?? v['clienteId'] ?? '').toString();

      tx.update(vRef, {
        'uidTaxista': uidTaxista,
        'taxistaId': uidTaxista,
        'nombreTaxista': nombreTaxista,
        'telefono': _tel,
        'placa': _plac,
        'tipoVehiculo': _tipo,
        'marca': _marca,
        'modelo': _modelo,
        'color': _color,
        'estado': EstadosViaje.aceptado,
        'aceptado': true,
        'rechazado': false,
        'activo': true,
        'aceptadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'reservadoPor': '',
        'reservadoHasta': null,
        'ignoradosPor': FieldValue.delete(),
      });

      // 👉 Cliente del viaje promovido también ve su viaje activo
      if (uidCliente.isNotEmpty) {
        tx.set(_db.collection('usuarios').doc(uidCliente), {
          'viajeActivoId': siguienteViajeId,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      tx.set(uRef, {
        'siguienteViajeId': '',
        'viajeActivoId': siguienteViajeId,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return siguienteViajeId;
    });
  }

  // ==============================================================
  //                      ACCIONES DE ESTADO
  // ==============================================================
  static Future<void> marcarEnCaminoPickup({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final d = snap.data()!;
      if ((d['uidTaxista'] ?? '') != uidTaxista) throw Exception('No autorizado');
      final String estado = (d['estado'] ?? '').toString();
      if (!EstadosViaje.puedeTransicionar(estado, EstadosViaje.enCaminoPickup)) {
        throw Exception('Estado inválido para en_camino_pickup');
      }
      tx.update(ref, {
        'estado': EstadosViaje.enCaminoPickup,
        'activo': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
    });
  }

  static Future<void> marcarClienteAbordo({
    required String viajeId,
    required String uidTaxista,
  }) async {
    final ref = _col.doc(viajeId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');
      final d = snap.data()!;
      if ((d['uidTaxista'] ?? '') != uidTaxista) throw Exception('No autorizado');
      final String estado = (d['estado'] ?? '').toString();
      if (!EstadosViaje.puedeTransicionar(estado, EstadosViaje.aBordo)) {
        throw Exception('Estado inválido para a_bordo');
      }
      tx.update(ref, {
        'estado': EstadosViaje.aBordo,
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
      if ((d['uidTaxista'] ?? '') != uidTaxista) throw Exception('No autorizado');
      final String estado = (d['estado'] ?? '').toString();
      if (!EstadosViaje.puedeTransicionar(estado, EstadosViaje.enCurso)) {
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
        'estado': EstadosViaje.enCurso,
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
      if ((d['uidTaxista'] ?? '') != uidTaxista) throw Exception('No autorizado');
      final String estado = (d['estado'] ?? '').toString();
      final n = EstadosViaje.normalizar(estado);
      if (n != EstadosViaje.enCurso && n != EstadosViaje.aBordo) {
        throw Exception('Estado inválido para finalizar.');
      }

      // uid cliente para limpiar su activo
      final String uidCliente = (d['uidCliente'] ?? d['clienteId'] ?? '').toString();

      tx.update(ref, {
        'estado': EstadosViaje.completado,
        'completado': true,
        'activo': false,
        'finalizadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      tx.set(uRef, {
        'viajeActivoId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 👉 limpiar activo del CLIENTE también
      if (uidCliente.isNotEmpty) {
        tx.set(_db.collection('usuarios').doc(uidCliente), {
          'viajeActivoId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
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
      if ((d['uidTaxista'] ?? '') != uidTaxista) throw Exception('No autorizado');
      final String estado = (d['estado'] ?? '').toString();
      final estNorm = EstadosViaje.normalizar(estado);
      if (!(estNorm == EstadosViaje.aceptado || estNorm == EstadosViaje.enCaminoPickup)) {
        throw Exception('No se puede cancelar en este estado.');
      }

      // Mantener esAhora según cercanía de la hora
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
      final bool esAhora = !fh.isAfter(DateTime.now().add(const Duration(minutes: 10)));

      tx.update(ref, {
        'estado': EstadosViaje.pendiente,
        'aceptado': false,
        'rechazado': false,
        'activo': false,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        'marca': '',
        'modelo': '',
        'color': '',
        'republicado': true,
        'canceladoPor': 'taxista',
        'canceladoTaxistaEn': FieldValue.serverTimestamp(),
        'esAhora': esAhora,
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'pickupConfirmadoEn': FieldValue.delete(),
        'inicioEnRutaEn': FieldValue.delete(),
        'finalizadoEn': FieldValue.delete(),
        'ignoradosPor': FieldValue.arrayUnion([uidTaxista]),
        'reservadoPor': '',
        'reservadoHasta': null,
      });

      tx.set(uRef, {
        'viajeActivoId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
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
    String uidTaxistaAfter = '';

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('El viaje no existe');

      final d = snap.data()!;
      final String cliente = (d['uidCliente'] ?? d['clienteId']).toString();
      if (cliente != uidCliente) throw Exception('No autorizado');

      final String estado = (d['estado'] ?? '').toString();
      final n = EstadosViaje.normalizar(estado);
      if (n == EstadosViaje.completado || n == EstadosViaje.cancelado) {
        throw Exception('El viaje ya está cerrado.');
      }

      uidTaxistaAfter = (d['uidTaxista'] ?? '').toString();

      tx.update(ref, {
        'estado': EstadosViaje.cancelado,
        'aceptado': false,
        'rechazado': true,
        'activo': false,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        'marca': '',
        'modelo': '',
        'color': '',
        'canceladoPor': 'cliente',
        'motivoCancelacion': (motivo ?? '').trim(),
        'canceladoClienteEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      // 👉 limpiar activo del CLIENTE
      tx.set(_db.collection('usuarios').doc(uidCliente), {
        'viajeActivoId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    if (uidTaxistaAfter.isNotEmpty) {
      try {
        await _db.collection('usuarios').doc(uidTaxistaAfter).set({
          'viajeActivoId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  // ==============================================================
  //                           PING GPS
  // ==============================================================
  static Future<void> pingGps({
    required String viajeId,
    required String uidTaxista,
    double? lat,
    double? lon,
    double? driverLat,
    double? driverLon,
  }) async {
    final ref = _col.doc(viajeId);
    final payload = <String, dynamic>{
      if (lat != null && lon != null) 'latTaxista': lat,
      if (lat != null && lon != null) 'lonTaxista': lon,
      if (driverLat != null && driverLon != null) 'driverLat': driverLat,
      if (driverLat != null && driverLon != null) 'driverLon': driverLon,
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    await _db.runTransaction((tx) async {
      final s = await tx.get(ref);
      if (!s.exists) throw Exception('No existe el viaje');
      final m = s.data()!;
      if ((m['uidTaxista'] ?? '') != uidTaxista) throw Exception('No autorizado');
      tx.update(ref, payload);
    });
  }

  // ==============================================================
  //                           STREAMS
  // ==============================================================
  static Stream<Viaje?> streamEstadoViajePorCliente(String uidCliente) {
    return _col
        .where('uidCliente', isEqualTo: uidCliente)
        .where('estado', whereIn: [
          EstadosViaje.pendiente,
          EstadosViaje.pendientePago,
          'asignado',               // legacy
          EstadosViaje.aceptado,
          EstadosViaje.enCaminoPickup,
          'en_camino_pickup',       // legacy snake
          EstadosViaje.aBordo,
          EstadosViaje.enCurso,
        ])
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .snapshots()
        .map((q) => q.docs.isEmpty ? null : Viaje.fromMap(q.docs.first.id, q.docs.first.data()));
  }

  static Stream<Viaje?> streamViajeEnCursoPorTaxista(String uidTaxista) {
    return _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('activo', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((q) => q.docs.isEmpty ? null : Viaje.fromMap(q.docs.first.id, q.docs.first.data()));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPoolAhora() {
    return _col
        .where('estado', whereIn: [EstadosViaje.pendiente, EstadosViaje.pendientePago])
        .where('uidTaxista', isEqualTo: '')
        .where('esAhora', isEqualTo: true)
        .where('publishAt', isLessThanOrEqualTo: Timestamp.now())
        .snapshots();
  }

  // Programados (visibles desde que publishAt <= now). Ordenados por fechaHora asc.
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPoolProgramados() {
    return _col
        .where('estado', whereIn: [EstadosViaje.pendiente, EstadosViaje.pendientePago])
        .where('uidTaxista', isEqualTo: '')
        .where('esAhora', isEqualTo: false)
        .where('publishAt', isLessThanOrEqualTo: Timestamp.now())
        .orderBy('fechaHora', descending: false)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamProgramadosAceptadosTaxista(String uidTaxista) {
    return _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('estado', isEqualTo: EstadosViaje.aceptado)
        .where('fechaHora', isGreaterThan: Timestamp.now())
        .orderBy('fechaHora', descending: false)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamActivosTaxistaRaw(String uidTaxista) {
    return _col
        .where('uidTaxista', isEqualTo: uidTaxista)
        .where('activo', isEqualTo: true)
        .limit(1)
        .snapshots();
  }

  // ==============================================================
  //                           LIMPIEZA
  // ==============================================================
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
        'estado': EstadosViaje.pendiente,
        'aceptado': false,
        'rechazado': false,
        'activo': false,
        'uidTaxista': '',
        'taxistaId': '',
        'nombreTaxista': '',
        'telefono': '',
        'placa': '',
        'marca': '',
        'modelo': '',
        'color': '',
        'republicado': true,
        'canceladoPor': 'taxista',
        'canceladoTaxistaEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
        'pickupConfirmadoEn': FieldValue.delete(),
        'inicioEnRutaEn': FieldValue.delete(),
        'finalizadoEn': FieldValue.delete(),
        'reservadoPor': '',
        'reservadoHasta': null,
      });
    }
    await batch.commit();
  }
}
