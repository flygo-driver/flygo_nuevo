// lib/servicios/directions_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'keys.dart';

class DirectionsResult {
  final double km; // distancia en kilómetros (carretera)
  final int seconds; // duración en segundos (con tráfico si se pide)
  final String? summary;

  const DirectionsResult({
    required this.km,
    required this.seconds,
    this.summary,
  });
}

class DirectionsService {
  static const _base = 'https://maps.googleapis.com/maps/api/directions/json';

  /// Distancia "driving". Si [withTraffic] es true, usa tráfico en tiempo real.
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
        'key': kGooglePlacesApiKey, // misma key que Places/Maps
        // 'alternatives': 'false', // opcional (por defecto no rompe nada)
      };
      if (withTraffic) {
        params['departure_time'] = 'now';
        params['traffic_model'] = 'best_guess';
      }

      final uri = Uri.parse(_base).replace(queryParameters: params);
      final resp = await http.get(uri);

      if (resp.statusCode != 200) {
        if (kDebugMode) {
          print('🔴 Directions HTTP ${resp.statusCode}: ${resp.body}');
        }
        return null;
      }

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';
      if (status != 'OK') {
        if (kDebugMode) {
          print('🔴 Directions status=$status, error=${data['error_message']}');
        }
        return null;
      }

      final routes = (data['routes'] as List?) ?? const [];
      if (routes.isEmpty) return null;
      final route0 = routes.first as Map<String, dynamic>;
      final legs = (route0['legs'] as List?) ?? const [];
      if (legs.isEmpty) return null;
      final leg0 = legs.first as Map<String, dynamic>;

      final distanceMeters =
          (leg0['distance'] as Map<String, dynamic>?)?['value'] as num?;
      final durationMap =
          (withTraffic ? leg0['duration_in_traffic'] : leg0['duration'])
              as Map<String, dynamic>?;
      final seconds = (durationMap?['value'] as num?)?.toInt() ?? 0;

      if (distanceMeters == null || distanceMeters <= 0) return null;

      return DirectionsResult(
        km: distanceMeters.toDouble() / 1000.0,
        seconds: seconds,
        summary: route0['summary'] as String?,
      );
    } catch (e, st) {
      if (kDebugMode) {
        print('🔴 Directions exception: $e');
        print(st);
      }
      return null;
    }
  }
}
