// lib/servicios/places_api.dart
import 'package:flygo_nuevo/servicios/places_service.dart';
import 'package:flygo_nuevo/keys.dart' as app_keys;

class PlacesApi {
  static PlacesService? _shared;

  static PlacesService get _s => _shared ??= PlacesService(
        app_keys.kGooglePlacesApiKey,
        language: 'es',
        components: const ['country:do'],
      );

  /// Opcional: reconfigurar idioma/components en runtime.
  static void configure({
    String? apiKey,
    String language = 'es',
    List<String> components = const ['country:do'],
  }) {
    _shared = PlacesService(
      apiKey ?? app_keys.kGooglePlacesApiKey,
      language: language,
      components: components,
    );
  }

  /// Autocomplete con sessionToken y sesgo opcionales.
  static Future<List<PlacePrediction>> autocomplete(
    String input, {
    String? sessionToken,
    double? biasLat,
    double? biasLon,
    int? biasRadiusMeters,
  }) {
    return _s.autocomplete(
      input,
      sessionToken: sessionToken,
      biasLat: biasLat,
      biasLon: biasLon,
      biasRadiusMeters: biasRadiusMeters,
    );
  }

  /// Details con sessionToken opcional.
  static Future<PlaceDetails?> details(
    String placeId, {
    String? sessionToken,
  }) async {
    try {
      return await _s.details(placeId, sessionToken: sessionToken);
    } catch (_) {
      return null;
    }
  }
}
