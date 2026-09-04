import 'google_places_sdk_adapter_stub.dart'
    if (dart.library.io) 'google_places_sdk_adapter_mobile.dart';

/// Resultado ligero del SDK (evita import circular con [LugaresService]).
class GooglePlacesSdkPrediction {
  const GooglePlacesSdkPrediction({
    required this.placeId,
    required this.primary,
    this.secondary,
    this.distanceMeters,
  });

  final String placeId;
  final String primary;
  final String? secondary;
  final int? distanceMeters;
}

class GooglePlacesSdkDetalle {
  const GooglePlacesSdkDetalle({
    required this.placeId,
    required this.name,
    this.address,
    required this.lat,
    required this.lon,
  });

  final String placeId;
  final String name;
  final String? address;
  final double lat;
  final double lon;
}

/// Autocomplete y detalles vía SDK nativo (móvil) o no-op (web).
abstract class GooglePlacesSdkAdapter {
  GooglePlacesSdkAdapter();

  static final GooglePlacesSdkAdapter instance = createGooglePlacesSdkAdapter();

  bool get disponible;

  void cerrarSesion();

  Future<List<GooglePlacesSdkPrediction>> autocompletar({
    required String query,
    double? biasLat,
    double? biasLon,
    bool sinSesgoUbicacion = false,
    /// Sesgo circular alrededor de [biasLat]/[biasLon] (mapa / GPS), no solo RD entero.
    bool sesgoCercano = false,
  });

  Future<GooglePlacesSdkDetalle?> detalle(String placeId);
}
