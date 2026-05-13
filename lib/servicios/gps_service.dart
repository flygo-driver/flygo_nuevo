// lib/servicios/gps_service.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';

class GpsService {
  /// Evita llamadas repetidas a [Geolocator.requestPermission] (p. ej. cada
  /// rebuild del viaje o al volver de segundo plano con el mismo `denied`).
  static DateTime? _lastGeolocatorRequestPermissionAt;

  static Future<bool> isServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  static Future<LocationPermission> checkPermission() =>
      Geolocator.checkPermission();

  static Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  /// Solo si el estado es exactamente [LocationPermission.denied]; no llama
  /// a [Geolocator.requestPermission] más de una vez por [minInterval].
  static Future<LocationPermission> requestPermissionIfDeniedThrottled({
    Duration minInterval = const Duration(seconds: 90),
  }) async {
    final LocationPermission current = await Geolocator.checkPermission();
    if (current != LocationPermission.denied) {
      return current;
    }
    final DateTime now = DateTime.now();
    final DateTime? last = _lastGeolocatorRequestPermissionAt;
    if (last != null && now.difference(last) < minInterval) {
      return current;
    }
    _lastGeolocatorRequestPermissionAt = now;
    return Geolocator.requestPermission();
  }

  static bool permissionUsable(LocationPermission p) =>
      p == LocationPermission.whileInUse || p == LocationPermission.always;

  /// Orden fijo para producción: **primero** GPS del sistema, **después** permiso
  /// de la app. Si el GPS está apagado **no** se llama a [Geolocator.requestPermission]
  /// (evita el diálogo de la app cuando solo hace falta encender ubicación).
  static Future<({bool serviceEnabled, LocationPermission permission})>
      checkServiceThenRequestPermissionIfNeeded({
    Duration minInterval = const Duration(seconds: 90),
  }) async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      final LocationPermission p = await Geolocator.checkPermission();
      return (serviceEnabled: false, permission: p);
    }
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await requestPermissionIfDeniedThrottled(minInterval: minInterval);
    }
    return (serviceEnabled: true, permission: p);
  }

  static Future<bool> openLocationSettings() =>
      Geolocator.openLocationSettings();

  static Future<bool> openAppSettings() => Geolocator.openAppSettings();

  static Future<Position?> obtenerUbicacionActual({
    Duration timeout = const Duration(seconds: 10),
    Duration maxEdadUltima = const Duration(minutes: 2),
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    final snap = await checkServiceThenRequestPermissionIfNeeded();
    if (!snap.serviceEnabled) return null;
    if (!permissionUsable(snap.permission)) return null;

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: timeout,
      );
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && _esReciente(last, maxEdadUltima)) return last;
      return null;
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && _esReciente(last, maxEdadUltima)) return last;
      return null;
    }
  }

  static Stream<Position> streamUbicacion({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilterMeters = 10,
  }) {
    final settings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilterMeters,
    );

    return Geolocator.getPositionStream(locationSettings: settings)
        .where((p) => p.latitude != 0.0 || p.longitude != 0.0);
  }

  static Future<Position?> esperarPrimeraUbicacion({
    Duration timeout = const Duration(seconds: 10),
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilterMeters = 0,
  }) async {
    try {
      return await streamUbicacion(
        accuracy: accuracy,
        distanceFilterMeters: distanceFilterMeters,
      ).first.timeout(timeout);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Position?> ultimaConocidaSiReciente({
    Duration maxEdadUltima = const Duration(minutes: 2),
  }) async {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && _esReciente(last, maxEdadUltima)) return last;
    return null;
  }

  static bool _esReciente(Position p, Duration maxEdad) {
    return DateTime.now().difference(p.timestamp).abs() <= maxEdad;
  }
}
