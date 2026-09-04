import 'google_places_sdk_adapter.dart';

GooglePlacesSdkAdapter createGooglePlacesSdkAdapter() =>
    GooglePlacesSdkAdapterStub();

class GooglePlacesSdkAdapterStub extends GooglePlacesSdkAdapter {
  GooglePlacesSdkAdapterStub();

  @override
  bool get disponible => false;

  @override
  void cerrarSesion() {}

  @override
  Future<List<GooglePlacesSdkPrediction>> autocompletar({
    required String query,
    double? biasLat,
    double? biasLon,
    bool sinSesgoUbicacion = false,
    bool sesgoCercano = false,
  }) async =>
      const [];

  @override
  Future<GooglePlacesSdkDetalle?> detalle(String placeId) async => null;
}
