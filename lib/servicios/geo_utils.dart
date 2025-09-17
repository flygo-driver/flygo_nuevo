import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

Future<Position> getPositionConPermiso() async {
  final enabled = await Geolocator.isLocationServiceEnabled();
  if (!enabled) {
    throw Exception('Activa el GPS.');
  }

  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
    throw Exception('Permiso de ubicación denegado.');
  }

  return Geolocator.getCurrentPosition();
}

Future<({double lat, double lon})?> geocodeDireccion(String texto) async {
  try {
    final list = await locationFromAddress(texto);
    if (list.isEmpty) return null;
    return (lat: list.first.latitude, lon: list.first.longitude);
  } catch (_) {
    return null;
  }
}

/// Distancia en km (Haversine)
double distanciaKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return r * c;
}

/// Tarifa simple para pruebas
double precioEstimado(double km) {
  // Bajada RD$120 + RD$38/km; mínimo RD$200
  final p = 120 + km * 38;
  return p < 200 ? 200 : double.parse(p.toStringAsFixed(2));
}
