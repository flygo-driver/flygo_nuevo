// lib/servicios/places_service.dart
import 'dart:convert';
import 'dart:io';

class SimpleLatLng {
  final double latitude;
  final double longitude;
  const SimpleLatLng(this.latitude, this.longitude);
}

class PlacePrediction {
  final String placeId;
  final String primary;
  final String? secondary;

  const PlacePrediction({
    required this.placeId,
    required this.primary,
    this.secondary,
  });

  String get fullDescription =>
      (secondary != null && secondary!.trim().isNotEmpty)
          ? '$primary, ${secondary!.trim()}'
          : primary;
}

class PlaceDetails {
  final String placeId;
  final String name;
  final String address; // nunca nula
  final SimpleLatLng latLng;

  const PlaceDetails({
    required this.placeId,
    required this.name,
    required this.address,
    required this.latLng,
  });
}

class PlacesService {
  final String apiKey;
  final String language;

  /// p.ej. ['country:do']
  final List<String> components;

  PlacesService(
    this.apiKey, {
    this.language = 'es',
    this.components = const <String>[],
  });

  // -------------------- AUTOCOMPLETE --------------------
  Future<List<PlacePrediction>> autocomplete(
    String input, {
    String? sessionToken,
    double? biasLat,
    double? biasLon,
    int? biasRadiusMeters, // p.ej. 30000
  }) async {
    final q = input.trim();
    if (q.isEmpty) return const <PlacePrediction>[];

    final params = <String, String>{
      'input': q,
      'key': apiKey,
      'language': language,
      'types': 'geocode', // direcciones/lugares físicos
    };
    if (sessionToken != null && sessionToken.trim().isNotEmpty) {
      params['sessiontoken'] = sessionToken;
    }
    if (components.isNotEmpty) {
      params['components'] = components.join('|'); // p.ej. country:do
    }
    if (biasLat != null && biasLon != null) {
      params['location'] =
          '${biasLat.toStringAsFixed(6)},${biasLon.toStringAsFixed(6)}';
      params['radius'] = '${biasRadiusMeters ?? 30000}';
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      params,
    );

    try {
      final json = await _getJson(uri);
      if (json == null) return const <PlacePrediction>[];

      final status = (json['status'] ?? '').toString();
      if (status != 'OK' && status != 'ZERO_RESULTS') {
        return const <PlacePrediction>[];
      }

      final List preds = (json['predictions'] as List?) ?? const [];
      return preds
          .map((e) {
            final m = (e as Map).cast<String, dynamic>();
            final placeId = (m['place_id'] ?? '').toString();
            final desc = (m['description'] ?? '').toString();

            String primary = desc;
            String? secondary;

            final sf =
                (m['structured_formatting'] as Map?)?.cast<String, dynamic>();
            final mainText = sf?['main_text']?.toString();
            final secText = sf?['secondary_text']?.toString();
            if ((mainText ?? '').trim().isNotEmpty) {
              primary = mainText!.trim();
              secondary =
                  (secText ?? '').trim().isEmpty ? null : secText!.trim();
            } else {
              final parts = desc.split(',').map((s) => s.trim()).toList();
              if (parts.length > 1) {
                primary = parts.first;
                secondary = parts.sublist(1).join(', ');
              }
            }

            return PlacePrediction(
              placeId: placeId.isNotEmpty ? placeId : desc,
              primary: primary.isNotEmpty ? primary : desc,
              secondary:
                  (secondary ?? '').trim().isEmpty ? null : secondary!.trim(),
            );
          })
          .cast<PlacePrediction>()
          .toList(growable: false);
    } catch (_) {
      return const <PlacePrediction>[];
    }
  }

  // -------------------- DETAILS --------------------
  Future<PlaceDetails?> details(
    String placeId, {
    String? sessionToken,
  }) async {
    final pid = placeId.trim();
    if (pid.isEmpty) return null;

    final params = <String, String>{
      'place_id': pid,
      'fields': 'name,formatted_address,geometry',
      'language': language,
      'key': apiKey,
    };
    if (sessionToken != null && sessionToken.trim().isNotEmpty) {
      params['sessiontoken'] = sessionToken;
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      params,
    );

    try {
      final json = await _getJson(uri);
      if (json == null) return null;

      final status = (json['status'] ?? '').toString();
      if (status != 'OK') return null;

      final result = (json['result'] as Map?)?.cast<String, dynamic>();
      if (result == null) return null;

      final name = (result['name'] ?? '').toString().trim();
      final addr = (result['formatted_address'] ?? '').toString().trim();

      final geom = (result['geometry'] as Map?)?.cast<String, dynamic>();
      final loc = (geom?['location'] as Map?)?.cast<String, dynamic>();
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lng = (loc?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      final address = addr.isNotEmpty ? addr : name;

      return PlaceDetails(
        placeId: pid,
        name: name.isNotEmpty ? name : address,
        address: address,
        latLng: SimpleLatLng(lat, lng),
      );
    } catch (_) {
      return null;
    }
  }

  // -------------------- HTTP helper --------------------
  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }
}
