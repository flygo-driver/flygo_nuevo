import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Locale;
import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart'
    as sdk;

import 'package:flygo_nuevo/keys.dart' as app_keys;
import 'package:flygo_nuevo/servicios/google_places_sdk_adapter.dart';

GooglePlacesSdkAdapter createGooglePlacesSdkAdapter() =>
    GooglePlacesSdkAdapterMobile();

/// SDK nativo de Google Places (mismo motor que Google Maps). Solo móvil.
class GooglePlacesSdkAdapterMobile extends GooglePlacesSdkAdapter {
  GooglePlacesSdkAdapterMobile();

  sdk.FlutterGooglePlacesSdk? _client;
  bool _sdkSessionAbierta = false;

  @override
  bool get disponible =>
      !kIsWeb && app_keys.kGooglePlacesApiKey.trim().isNotEmpty;

  sdk.FlutterGooglePlacesSdk get _sdk {
    return _client ??= sdk.FlutterGooglePlacesSdk(
      app_keys.kGooglePlacesApiKey,
      locale: const Locale('es'),
    );
  }

  @override
  void cerrarSesion() {
    _sdkSessionAbierta = false;
  }

  static const sdk.LatLngBounds _boundsRd = sdk.LatLngBounds(
    southwest: sdk.LatLng(lat: 17.47, lng: -72.05),
    northeast: sdk.LatLng(lat: 19.95, lng: -68.32),
  );

  static sdk.LatLngBounds _boundsCercanos(double lat, double lon, {double km = 120}) {
    final dLat = km / 111.0;
    final dLon = km / (111.0 * math.cos(lat * math.pi / 180).abs().clamp(0.2, 1.0));
    return sdk.LatLngBounds(
      southwest: sdk.LatLng(lat: lat - dLat, lng: lon - dLon),
      northeast: sdk.LatLng(lat: lat + dLat, lng: lon + dLon),
    );
  }

  @override
  Future<List<GooglePlacesSdkPrediction>> autocompletar({
    required String query,
    double? biasLat,
    double? biasLon,
    bool sinSesgoUbicacion = false,
    bool sesgoCercano = false,
  }) async {
    if (!disponible) return const [];
    final q = query.trim();
    if (q.isEmpty) return const [];

    try {
      final bool nuevaSesion = !_sdkSessionAbierta;
      final sdk.LatLng? origin = (biasLat != null && biasLon != null)
          ? sdk.LatLng(lat: biasLat, lng: biasLon)
          : null;

      sdk.LatLngBounds? locationBias;
      if (!sinSesgoUbicacion) {
        if (sesgoCercano && biasLat != null && biasLon != null) {
          locationBias = _boundsCercanos(biasLat, biasLon);
        } else {
          locationBias = _boundsRd;
        }
      }

      final sdk.FindAutocompletePredictionsResponse res =
          await _sdk.findAutocompletePredictions(
        q,
        countries: const ['DO'],
        placeTypesFilter: const [],
        newSessionToken: nuevaSesion,
        origin: origin,
        locationBias: locationBias,
      );
      _sdkSessionAbierta = true;

      return res.predictions
          .map(
            (p) => GooglePlacesSdkPrediction(
              placeId: p.placeId,
              primary: p.primaryText,
              secondary: p.secondaryText.trim().isEmpty
                  ? null
                  : p.secondaryText.trim(),
              distanceMeters: p.distanceMeters,
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<GooglePlacesSdkDetalle?> detalle(String placeId) async {
    if (!disponible) return null;
    var pid = placeId.trim();
    if (pid.startsWith('places/')) {
      pid = pid.substring('places/'.length);
    }
    if (pid.isEmpty || pid.startsWith('local:') || pid.startsWith('geocoded:')) {
      return null;
    }

    try {
      final sdk.FetchPlaceResponse res = await _sdk.fetchPlace(
        pid,
        fields: const [
          sdk.PlaceField.Id,
          sdk.PlaceField.Name,
          sdk.PlaceField.Address,
          sdk.PlaceField.Location,
        ],
      );
      cerrarSesion();

      final sdk.Place? place = res.place;
      if (place == null) return null;

      final double? lat = place.latLng?.lat;
      final double? lon = place.latLng?.lng;
      if (lat == null || lon == null) return null;

      final String name = (place.name ?? '').trim();
      final String address = (place.address ?? '').trim();

      return GooglePlacesSdkDetalle(
        placeId: pid,
        name: name.isNotEmpty ? name : address,
        address: address.isNotEmpty ? address : null,
        lat: lat,
        lon: lon,
      );
    } catch (_) {
      return null;
    }
  }
}
