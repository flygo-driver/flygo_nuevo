// lib/servicios/gps_service.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';

class GpsService {
  static Future<bool> isServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  static Future<LocationPermission> checkPermission() =>
      Geolocator.checkPermission();

  static Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  static Future<bool> openLocationSettings() =>
      Geolocator.openLocationSettings();

  static Future<bool> openAppSettings() => Geolocator.openAppSettings();

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
