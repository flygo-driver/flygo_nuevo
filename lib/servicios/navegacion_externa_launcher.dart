import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Lanzamiento Waze / Google Maps (intents + fallbacks web/geo) compartido
/// entre taxista en curso, detalle de viaje, etc.
class NavegacionExternaLauncher {
  NavegacionExternaLauncher._();

  static String fmtCoord(double v) => v.toStringAsFixed(6);

  static Future<bool> tryLaunch(
    Uri uri, {
    bool preferExternalApp = true,
  }) async {
    try {
      final ok1 = await launchUrl(
        uri,
        mode: preferExternalApp
            ? LaunchMode.externalApplication
            : LaunchMode.platformDefault,
      );
      if (ok1) return true;

      final ok2 = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (ok2) return true;

      if (uri.scheme.startsWith('http')) {
        final ok3 = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok3) return true;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[nav_ext] launch fail: $e');
      }
    }
    return false;
  }

  static Future<void> abrirGoogleMapsDestino(double lat, double lon) async {
    final String la = fmtCoord(lat);
    final String lo = fmtCoord(lon);
    final googleIntent = Uri(
      scheme: 'google.navigation',
      queryParameters: <String, String>{'q': '$la,$lo', 'mode': 'd'},
    );
    final geoQuery = Uri.parse('geo:0,0?q=$la,$lo');
    final googleWeb = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$la,$lo&travelmode=driving',
    );

    if (await tryLaunch(googleIntent)) return;
    if (await tryLaunch(geoQuery)) return;
    await tryLaunch(googleWeb, preferExternalApp: false);
  }

  static Future<void> abrirGoogleMapsDireccion(String direccion) async {
    final q = Uri.encodeComponent(direccion);
    final geoQuery = Uri.parse('geo:0,0?q=$q');
    final web = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');

    if (await tryLaunch(geoQuery)) return;
    await tryLaunch(web, preferExternalApp: false);
  }

  static Future<void> abrirWazeDestino(double lat, double lon) async {
    final String la = fmtCoord(lat);
    final String lo = fmtCoord(lon);
    final wazeDeep = Uri.parse('waze://?ll=$la,$lo&navigate=yes');
    final wazeWeb = Uri.parse('https://waze.com/ul?ll=$la,$lo&navigate=yes');

    if (await tryLaunch(wazeDeep)) return;
    if (await tryLaunch(wazeWeb, preferExternalApp: false)) return;

    await abrirGoogleMapsDestino(lat, lon);
  }

  static Future<void> abrirWazeBusqueda(String query) async {
    final q = Uri.encodeComponent(query);
    final wazeDeep = Uri.parse('waze://?q=$q&navigate=yes');
    final wazeWeb = Uri.parse('https://waze.com/ul?q=$q&navigate=yes');

    if (await tryLaunch(wazeDeep)) return;
    if (await tryLaunch(wazeWeb, preferExternalApp: false)) return;

    await abrirGoogleMapsDireccion(query);
  }
}
