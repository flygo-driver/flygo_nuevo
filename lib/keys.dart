// lib/keys.dart
// Claves y nombre de marca (RAI Driver).
// Android Play: com.flygo.rd2 → Firebase flygo-rd (google-services.json en android/app).

/// Nombre visible: launcher, título de ventana / MaterialApp, tiendas.
const String kAppDisplayName = 'RAI Driver';

class AppKeys {
  /// Cliente OAuth Web del proyecto flygo-rd (client_type 3 en google-services.json).
  static const String googleOAuthWebClientId =
      '237301602510-csi76vsfun9vp4rv2e2818jach4dk28s.apps.googleusercontent.com';

  // 🔑 API Key para Places, Geocoding, Directions (la que usas en código)
  static const String googlePlacesApiKey = 'AIzaSyAPMeBX8oZCGJsb8iurATEWjePNTUn0ECs';
  
  // 🔑 API Key para Google Maps (AndroidManifest)
  static const String googleMapsApiKey = 'AIzaSyDp-DhgbYE70S0PrpuXzbdZ41Ojs-hKh0w';
}

const String kGooglePlacesApiKey = AppKeys.googlePlacesApiKey;
const String kGoogleMapsApiKey = AppKeys.googleMapsApiKey;