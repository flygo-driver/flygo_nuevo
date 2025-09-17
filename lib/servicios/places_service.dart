// lib/servicios/places_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

const String kPlacesApiKeyHardcoded = 'AQUI_TU_API_KEY_DE_PLACES'; // opcional
const String _kApiKeyFromEnv = String.fromEnvironment('GMAPS_API_KEY', defaultValue: '');

String get _apiKey {
  // Prioriza dart-define si viene; si no, usa la hardcoded.
  if (_kApiKeyFromEnv.trim().isNotEmpty) return _kApiKeyFromEnv.trim();
  return kPlacesApiKeyHardcoded.trim();
}

class PlacePrediction {
  final String placeId;
  final String description;
  const PlacePrediction({required this.placeId, required this.description});
}

class PlaceDetails {
  final String placeId;
  final String address;
  final double lat;
  final double lon;
  const PlaceDetails({
    required this.placeId,
    required this.address,
    required this.lat,
    required this.lon,
  });
}

class PlacesService {
  static const _host = 'https://maps.googleapis.com/maps/api/place';

  static Future<List<PlacePrediction>> autocomplete(String input) async {
    final key = _apiKey;
    final q = input.trim();
    if (key.isEmpty || q.length < 2) return const <PlacePrediction>[];

    final uri = Uri.parse(
      '$_host/autocomplete/json?input=${Uri.encodeQueryComponent(q)}'
      '&types=geocode&language=es&components=country:do&key=$key',
    );

    final r = await http.get(uri).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return const <PlacePrediction>[];

    final data = jsonDecode(r.body) as Map;
    final status = (data['status'] ?? '').toString();
    if (status != 'OK' && status != 'ZERO_RESULTS') {
      return const <PlacePrediction>[];
    }
    final preds = (data['predictions'] as List? ?? const []);
    return preds
        .map((p) => PlacePrediction(
              placeId: (p['place_id'] ?? '').toString(),
              description: (p['description'] ?? '').toString(),
            ))
        .where((pp) => pp.placeId.isNotEmpty && pp.description.isNotEmpty)
        .toList(growable: false);
  }

  static Future<PlaceDetails?> details(String placeId) async {
    final key = _apiKey;
    if (key.isEmpty || placeId.trim().isEmpty) return null;

    final uri = Uri.parse(
      '$_host/details/json?place_id=${Uri.encodeQueryComponent(placeId)}'
      '&language=es&key=$key&fields=place_id,formatted_address,geometry',
    );

    final r = await http.get(uri).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;

    final data = jsonDecode(r.body) as Map;
    if ((data['status'] ?? '').toString() != 'OK') return null;

    final res = (data['result'] as Map?);
    if (res == null) return null;
    final loc = ((res['geometry'] as Map?)?['location'] as Map?) ?? const {};
    final lat = (loc['lat'] as num?)?.toDouble();
    final lon = (loc['lng'] as num?)?.toDouble();
    final addr = (res['formatted_address'] ?? '').toString();
    final pid = (res['place_id'] ?? '').toString();

    if (lat == null || lon == null || addr.isEmpty || pid.isEmpty) return null;

    return PlaceDetails(placeId: pid, address: addr, lat: lat, lon: lon);
  }
}
