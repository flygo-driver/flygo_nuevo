// lib/keys.dart
// Claves y nombre de marca (RAI Driver).
// Android Play: com.flygo.rd2 → Firebase flygo-rd (google-services.json en android/app).
//
// Release duro: puedes inyectar claves sin tocar el repo:
//   flutter build appbundle --dart-define=GOOGLE_PLACES_API_KEY=... --dart-define=GOOGLE_MAPS_API_KEY=...
// La clave de Maps en Android también debe coincidir en:
//   android/app/src/main/res/values/strings.xml → google_maps_api_key

/// Nombre visible: launcher, título de ventana / MaterialApp, tiendas.
const String kAppDisplayName = 'RAI Driver';

class AppKeys {
  /// Cliente OAuth Web del proyecto flygo-rd (client_type 3 en google-services.json).
  static const String googleOAuthWebClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_WEB_CLIENT_ID',
    defaultValue:
        '237301602510-csi76vsfun9vp4rv2e2818jach4dk28s.apps.googleusercontent.com',
  );

  /// API Key: Places, Geocoding, Directions (REST desde Dart).
  static const String googlePlacesApiKey = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY',
    defaultValue: 'AIzaSyAPMeBX8oZCGJsb8iurATEWjePNTUn0ECs',
  );

  /// Misma clave que Maps SDK (manifest meta-data); por si algún código Dart la necesita.
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyDp-DhgbYE70S0PrpuXzbdZ41Ojs-hKh0w',
  );
}

const String kGooglePlacesApiKey = AppKeys.googlePlacesApiKey;
const String kGoogleMapsApiKey = AppKeys.googleMapsApiKey;
