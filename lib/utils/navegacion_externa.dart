import 'package:flygo_nuevo/servicios/navegacion_externa_launcher.dart';

/// Abre Google Maps con ruta (opcionalmente desde un origen).
Future<void> abrirGoogleMaps({
  double? oLat,
  double? oLon,
  required double dLat,
  required double dLon,
}) async {
  if (!NavegacionExternaLauncher.coordsValidas(dLat, dLon)) return;
  if (oLat != null &&
      oLon != null &&
      NavegacionExternaLauncher.coordsValidas(oLat, oLon)) {
    await NavegacionExternaLauncher.abrirGoogleMapsRutaConParadas(
      origenLat: oLat,
      origenLon: oLon,
      destinoLat: dLat,
      destinoLon: dLon,
    );
    return;
  }
  await NavegacionExternaLauncher.abrirGoogleMapsDestino(dLat, dLon);
}

/// Abre Waze directo al destino (solo con GPS válido).
Future<void> abrirWaze({required double dLat, required double dLon}) async {
  await NavegacionExternaLauncher.abrirWazeDestino(dLat, dLon);
}
