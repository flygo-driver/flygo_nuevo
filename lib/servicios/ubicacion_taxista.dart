// lib/servicios/ubicacion_taxista.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/location_permission_service.dart';
import 'package:flygo_nuevo/servicios/solicitud_turismo_repo.dart';
import 'package:flygo_nuevo/utils/rai_geohash.dart';
import 'package:flygo_nuevo/utils/rai_region_operativa.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

/// Publicación de ubicación del taxista en `drivers_location` (mapa cliente en vivo).
class UbicacionTaxista {
  static StreamSubscription<Position>? _subscription;
  static bool _isActive = false;
  static bool _syncUbicacionTurismo = false;
  static String? _uidTurismoSync;
  static double? _ultimaLat;
  static double? _ultimaLon;
  static String? _viajeActivoCache;
  static String? _clienteActivoCache;
  static bool? _disponibleCache;
  static String? _tipoServicioPoolCache;
  static DateTime _ultimaLecturaViajeActivo =
      DateTime.fromMillisecondsSinceEpoch(0);

  /// Activa publicación en `choferes_turismo` (auto-asignación turismo).
  static Future<void> habilitarSyncChoferTurismo(String uid) async {
    _uidTurismoSync = uid;
    _syncUbicacionTurismo =
        await SolicitudTurismoRepo.esChoferTurismoAprobado(uid);
  }

  static void deshabilitarSyncChoferTurismo() {
    _syncUbicacionTurismo = false;
    _uidTurismoSync = null;
  }

  /// Inicia GPS en tiempo real → `taxistas` + `drivers_location` (`tracking: true`).
  static void iniciarActualizacion({bool soloCuandoDisponible = true}) {
    if (_isActive) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 6,
    );

    _subscription = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
      (Position pos) async {
        await _publicarPosicionTaxista(
          uid: user.uid,
          pos: pos,
          soloCuandoDisponible: soloCuandoDisponible,
        );

        if (_syncUbicacionTurismo && _uidTurismoSync == user.uid) {
          unawaited(
            SolicitudTurismoRepo.sincronizarUbicacionChofer(
              uid: user.uid,
              lat: pos.latitude,
              lon: pos.longitude,
            ),
          );
        }
      },
      onError: (_) async {
        await ocultarDelMapaCliente(uid: user.uid);
      },
    );

    _isActive = true;
  }

  /// Ping desde viaje activo (GPS de navegación) — mantiene `drivers_location` al día.
  static Future<void> publicarPingDesdeViajeActivo({
    required String uid,
    required double lat,
    required double lon,
    required String viajeId,
    String? clienteId,
    double? heading,
  }) async {
    final Position pos = Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: heading ?? -1,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    _viajeActivoCache = viajeId;
    _clienteActivoCache = clienteId;
    await _publicarPosicionTaxista(
      uid: uid,
      pos: pos,
      soloCuandoDisponible: true,
      viajeIdForzado: viajeId,
      clienteIdForzado: clienteId,
    );
  }

  static Future<void> _publicarPosicionTaxista({
    required String uid,
    required Position pos,
    required bool soloCuandoDisponible,
    String? viajeIdForzado,
    String? clienteIdForzado,
  }) async {
    await FirebaseFirestore.instance.collection('taxistas').doc(uid).set({
      'ubicacion': GeoPoint(pos.latitude, pos.longitude),
      'ultimaActualizacion': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    String? viajeActivoId = viajeIdForzado;
    String? clienteId = clienteIdForzado;
    bool disponible = _disponibleCache ?? false;

    if (soloCuandoDisponible &&
        viajeActivoId == null &&
        DateTime.now().difference(_ultimaLecturaViajeActivo) >
            const Duration(seconds: 12)) {
      final DocumentSnapshot<Map<String, dynamic>> userDoc =
          await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      final Map<String, dynamic>? userData = userDoc.data();
      viajeActivoId = (userData?['viajeActivoId'] as String?)?.trim();
      if (viajeActivoId != null && viajeActivoId.isEmpty) {
        viajeActivoId = null;
      }
      disponible = userData?['disponible'] == true;
      _tipoServicioPoolCache =
          ViajePoolTaxistaGate.poolModoConductorDesdeUsuario(userData);
      _viajeActivoCache = viajeActivoId;
      _disponibleCache = disponible;
      _ultimaLecturaViajeActivo = DateTime.now();

      if (viajeActivoId != null && clienteId == null) {
        final DocumentSnapshot<Map<String, dynamic>> vDoc =
            await FirebaseFirestore.instance
                .collection('viajes')
                .doc(viajeActivoId)
                .get();
        clienteId = (vDoc.data()?['uidCliente'] ?? vDoc.data()?['clienteId'])
            ?.toString()
            .trim();
        if (clienteId != null && clienteId.isEmpty) clienteId = null;
        _clienteActivoCache = clienteId;
      }
    } else {
      viajeActivoId ??= _viajeActivoCache;
      clienteId ??= _clienteActivoCache;
      disponible = _disponibleCache ?? false;
    }

    final bool tieneViajeActivo = viajeActivoId != null && viajeActivoId.isNotEmpty;
    if (!tieneViajeActivo && !disponible) {
      await ocultarDelMapaCliente(uid: uid);
      return;
    }
    final double? bearing = _resolverBearing(pos);

    final Map<String, dynamic> payload = <String, dynamic>{
      'location': GeoPoint(pos.latitude, pos.longitude),
      'geohash': RaiGeohash.encode(pos.latitude, pos.longitude, precision: 7),
      'region': RaiRegionOperativa.resolver(pos.latitude, pos.longitude),
      'tracking': true,
      'online': !tieneViajeActivo,
      'disponible': disponible,
      'updatedAt': FieldValue.serverTimestamp(),
      if (bearing != null) 'heading': bearing,
      if (_tipoServicioPoolCache == TaxistaPoolModoConductor.motor)
        'tipoServicio': TaxistaPoolModoConductor.motor,
    };

    if (tieneViajeActivo) {
      payload['viajeId'] = viajeActivoId;
      if (clienteId != null && clienteId.isNotEmpty) {
        payload['clienteId'] = clienteId;
      }
    } else {
      payload['viajeId'] = FieldValue.delete();
      payload['clienteId'] = FieldValue.delete();
      _viajeActivoCache = null;
      _clienteActivoCache = null;
    }

    await FirebaseFirestore.instance
        .collection('drivers_location')
        .doc(uid)
        .set(payload, SetOptions(merge: true));

    _ultimaLat = pos.latitude;
    _ultimaLon = pos.longitude;
  }

  static double? _resolverBearing(Position pos) {
    if (pos.heading.isFinite && pos.heading >= 0 && pos.heading <= 360) {
      return pos.heading;
    }
    if (_ultimaLat != null && _ultimaLon != null) {
      final double d = Geolocator.distanceBetween(
        _ultimaLat!,
        _ultimaLon!,
        pos.latitude,
        pos.longitude,
      );
      if (d >= 4) {
        return Geolocator.bearingBetween(
          _ultimaLat!,
          _ultimaLon!,
          pos.latitude,
          pos.longitude,
        );
      }
    }
    return null;
  }

  /// Detiene GPS y oculta al taxista del mapa cliente.
  static Future<void> detenerActualizacion() async {
    if (_subscription != null) {
      await _subscription!.cancel();
      _subscription = null;
    }
    _isActive = false;
    _viajeActivoCache = null;
    _clienteActivoCache = null;
    _disponibleCache = null;
    _tipoServicioPoolCache = null;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await ocultarDelMapaCliente(uid: user.uid);
    }
  }

  /// Oculta al taxista del mapa cliente sin detener el GPS (p. ej. no disponible / GPS off).
  static Future<void> ocultarDelMapaCliente({String? uid}) async {
    final String? id = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (id == null) return;

    final bool enViaje =
        _viajeActivoCache != null && _viajeActivoCache!.trim().isNotEmpty;
    if (enViaje) {
      await FirebaseFirestore.instance.collection('drivers_location').doc(id).set(
        <String, dynamic>{
          'online': false,
          'disponible': false,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('drivers_location').doc(id).set(
      <String, dynamic>{
        'online': false,
        'tracking': false,
        'disponible': false,
        'viajeId': FieldValue.delete(),
        'clienteId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Fuerza releer `disponible` / viaje activo en el próximo ping GPS.
  static void refrescarEstadoOperativo() {
    _ultimaLecturaViajeActivo = DateTime.fromMillisecondsSinceEpoch(0);
    _tipoServicioPoolCache = null;
  }

  static Future<void> marcarNoDisponible() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('drivers_location')
          .doc(user.uid)
          .set({
        'online': false,
        'disponible': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  static Future<void> marcarDisponible() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('drivers_location')
          .doc(user.uid)
          .set({
        'online': true,
        'tracking': true,
        'disponible': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  static Future<Position> obtenerUbicacionActual() async {
    final snap = await GpsService.readServiceAndPermissionStabilizedNoRequest();
    if (!snap.serviceEnabled) {
      throw Exception('Servicios de ubicación desactivados');
    }

    var permission = snap.permission;
    if (permission == LocationPermission.denied) {
      if (await LocationPermissionService.taxistaUbicacionListaAntes()) {
        permission = await GpsService.waitUntilPermissionUsable(
          timeout: const Duration(seconds: 2),
        );
      }
      if (!GpsService.permissionUsable(permission)) {
        throw Exception('Permisos de ubicación denegados');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Permisos de ubicación denegados permanentemente');
    }

    return Geolocator.getCurrentPosition();
  }

  static Stream<Position> obtenerStreamUbicacion() {
    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 8,
    );
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}
