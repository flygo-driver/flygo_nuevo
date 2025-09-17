// lib/servicios/gps_service.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';

class GpsService {
  /// Comprueba si el servicio de ubicación está habilitado en el sistema.
  static Future<bool> isServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  /// Devuelve el estado actual del permiso.
  static Future<LocationPermission> checkPermission() =>
      Geolocator.checkPermission();

  /// Solicita permiso (normalmente lo hacemos desde PermisosService).
  static Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  /// Abre ajustes de ubicación del sistema.
  static Future<bool> openLocationSettings() =>
      Geolocator.openLocationSettings();

  /// Abre ajustes de la app (para permisos denegados para siempre).
  static Future<bool> openAppSettings() => Geolocator.openAppSettings();

  // ---------------------------------------------------------------------------
  // POSICIÓN ACTUAL (con timeout + fallback a última conocida si es reciente)
  // ---------------------------------------------------------------------------
  static Future<Position?> obtenerUbicacionActual({
    Duration timeout = const Duration(seconds: 10),
    Duration maxEdadUltima = const Duration(minutes: 2),
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return null;
    }
    if (perm == LocationPermission.deniedForever) return null;

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

  // ---------------------------------------------------------------------------
  // STREAM EN TIEMPO REAL (para viaje en curso / tracking)
  // ---------------------------------------------------------------------------
  static Stream<Position> streamUbicacion({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilterMeters = 10,
  }) {
    final settings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilterMeters,
    );
    return Geolocator.getPositionStream(
      locationSettings: settings,
    ).where((p) => p.latitude != 0 || p.longitude != 0);
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

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------
  static bool _esReciente(Position p, Duration maxEdad) {
    final ts = p.timestamp;
    return DateTime.now().difference(ts).abs() <= maxEdad;
  }
}
