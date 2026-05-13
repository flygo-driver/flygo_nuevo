import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_google_places_sdk_platform_interface/flutter_google_places_sdk_platform_interface.dart';

class FlutterGooglePlacesSdkWebPlugin extends FlutterGooglePlacesSdkPlatform {
  static void registerWith(Registrar registrar) {
    FlutterGooglePlacesSdkPlatform.instance = FlutterGooglePlacesSdkWebPlugin();
  }

  Never _unsupported() {
    throw UnsupportedError(
      'flutter_google_places_sdk is disabled in web admin build.',
    );
  }

  @override
  Future<void> deinitialize() async => _unsupported();

  @override
  Future<void> initialize(String apiKey, {Locale? locale}) async => _unsupported();

  @override
  Future<bool?> isInitialized() async => _unsupported();

  @override
  Future<void> updateSettings(String apiKey, {Locale? locale}) async => _unsupported();

  @override
  Future<FindAutocompletePredictionsResponse> findAutocompletePredictions(
    String query, {
    List<String>? countries,
    List<String> placeTypesFilter = const [],
    bool? newSessionToken,
    LatLng? origin,
    LatLngBounds? locationBias,
    LatLngBounds? locationRestriction,
  }) async =>
      _unsupported();

  @override
  Future<FetchPlaceResponse> fetchPlace(
    String placeId, {
    required List<PlaceField> fields,
    bool? newSessionToken,
  }) async =>
      _unsupported();

  @override
  Future<FetchPlacePhotoResponse> fetchPlacePhoto(
    PhotoMetadata photoMetadata, {
    int? maxWidth,
    int? maxHeight,
  }) async =>
      _unsupported();
}
