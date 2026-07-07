// lib/servicios/places_service.dart

import 'package:flygo_nuevo/servicios/lugares_service.dart';

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
  /// Delega en [LugaresService] (sin `types: geocode`, variantes y POI locales RD).
  Future<List<PlacePrediction>> autocomplete(
    String input, {
    String? sessionToken,
    double? biasLat,
    double? biasLon,
    int? biasRadiusMeters, // ignorado; LugaresService usa radio amplio RD
  }) async {
    final q = input.trim();
    if (q.isEmpty) return const <PlacePrediction>[];

    String? country;
    for (final c in components) {
      final t = c.trim().toLowerCase();
      if (t.startsWith('country:')) {
        country = t.substring('country:'.length);
        break;
      }
    }

    final preds = await LugaresService.instance.autocompletar(
      q,
      country: country ?? 'DO',
      biasLat: biasLat,
      biasLon: biasLon,
    );

    return preds
        .map(
          (p) => PlacePrediction(
            placeId: p.placeId,
            primary: p.primary,
            secondary: p.secondary,
          ),
        )
        .toList(growable: false);
  }

  // -------------------- DETAILS --------------------
  Future<PlaceDetails?> details(
    String placeId, {
    String? sessionToken,
  }) async {
    final pid = placeId.trim();
    if (pid.isEmpty) return null;

    final det = await LugaresService.instance.detalle(pid);
    if (det == null) return null;

    final addr = (det.address ?? det.displayLabel).trim();
    return PlaceDetails(
      placeId: det.placeId,
      name: det.name.isNotEmpty ? det.name : addr,
      address: addr.isNotEmpty ? addr : det.name,
      latLng: SimpleLatLng(det.lat, det.lon),
    );
  }
}
