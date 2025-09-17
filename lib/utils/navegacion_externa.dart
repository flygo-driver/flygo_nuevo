import 'package:url_launcher/url_launcher.dart';

/// Abre Google Maps con ruta (opcionalmente desde un origen).
Future<void> abrirGoogleMaps({
  double? oLat,
  double? oLon,
  required double dLat,
  required double dLon,
}) async {
  final hasOrigin = oLat != null && oLon != null;
  final url = Uri.parse(
    'https://www.google.com/maps/dir/?api=1'
    '${hasOrigin ? '&origin=$oLat,$oLon' : ''}'
    '&destination=$dLat,$dLon&travelmode=driving',
  );
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

/// Abre Waze directo al destino.
Future<void> abrirWaze({required double dLat, required double dLon}) async {
  final url = Uri.parse('https://waze.com/ul?ll=$dLat,$dLon&navigate=yes');
  await launchUrl(url, mode: LaunchMode.externalApplication);
}
