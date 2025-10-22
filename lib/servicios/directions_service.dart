import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flygo_nuevo/keys.dart' as app_keys;

/// Resultado de Google Directions listo para UI
class DirectionsResult {
  /// Distancia en kilómetros
  final double km;

  /// Duración en segundos (usa duration_in_traffic si withTraffic=true)
  final int seconds;

  /// Resumen de ruta que da Google (opcional)
  final String? summary;

  /// Puntos de la polyline ya decodificados (para Polyline de GoogleMap)
  final List<LatLng>? path;

  /// Textos listos: "8.4 km", "13 min"
  final String? distanceText;
  final String? durationText;

  const DirectionsResult({
    required this.km,
    required this.seconds,
    this.summary,
    this.path,
    this.distanceText,
    this.durationText,
  });
}

class DirectionsService {
  static const _base = 'https://maps.googleapis.com/maps/api/directions/json';

  /// Calcula ruta en carro. Si [withTraffic]=true usa tráfico en vivo (departure_time=now)
  static Future<DirectionsResult?> drivingDistanceKm({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    bool withTraffic = true,
    String region = 'do',
  }) async {
    try {
      final params = <String, String>{
        'origin': '$originLat,$originLon',
        'destination': '$destLat,$destLon',
        'mode': 'driving',
        'units': 'metric',
        'region': region,
        'key': app_keys.kGooglePlacesApiKey, // 👈 asegura que esta key exista en keys.dart
      };
      if (withTraffic) {
        params['departure_time'] = 'now';
        params['traffic_model'] = 'best_guess';
      }

      final uri = Uri.parse(_base).replace(queryParameters: params);
      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        if (kDebugMode) print('🔴 Directions HTTP ${resp.statusCode}: ${resp.body}');
        return null;
      }

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final status = (data['status'] as String? ?? '');
      if (status != 'OK') {
        // Google a veces devuelve ZERO_RESULTS o OVER_QUERY_LIMIT, etc.
        if (kDebugMode) print('🔴 Directions status=$status, error=${data['error_message']}');
        return null;
      }

      final routes = (data['routes'] as List?) ?? const [];
      if (routes.isEmpty) return null;

      final route0 = routes.first as Map<String, dynamic>;
      final legs = (route0['legs'] as List?) ?? const [];
      if (legs.isEmpty) return null;

      final leg0 = legs.first as Map<String, dynamic>;

      // Distancia/duración numéricas
      final distanceMeters = (leg0['distance'] as Map?)?['value'] as num?;
      final distanceText = (leg0['distance'] as Map?)?['text'] as String?;
      final durationMap = withTraffic
          ? (leg0['duration_in_traffic'] as Map?)
          : (leg0['duration'] as Map?);
      final seconds = (durationMap?['value'] as num?)?.toInt() ?? 0;
      final durationText = (durationMap?['text'] as String?);

      if (distanceMeters == null || distanceMeters <= 0) return null;

      // Polyline
      List<LatLng>? path;
      final enc = (route0['overview_polyline'] as Map?)?['points'] as String?;
      if (enc != null && enc.isNotEmpty) {
        path = decodePolyline(enc);
      }

      return DirectionsResult(
        km: distanceMeters.toDouble() / 1000.0,
        seconds: seconds,
        summary: route0['summary'] as String?,
        path: path,
        distanceText: distanceText,
        durationText: durationText,
      );
    } catch (e, st) {
      if (kDebugMode) {
        print('🔴 Directions exception: $e');
        print(st);
      }
      return null;
    }
  }

  /// Decodifica polyline de Google
  static List<LatLng> decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0, lat = 0, lng = 0;

    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = ((result & 1) == 1) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = ((result & 1) == 1) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
