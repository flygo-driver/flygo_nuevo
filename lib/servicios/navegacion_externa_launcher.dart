import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Lanzamiento Waze / Google Maps (intents + fallbacks web/geo) compartido
/// entre taxista en curso, detalle de viaje, etc.
class NavegacionExternaLauncher {
  NavegacionExternaLauncher._();

  static String fmtCoord(double v) => v.toStringAsFixed(6);

  /// En laptop/web: solo HTTPS y pestaña nueva.
  /// Los schemes `google.navigation:` / `geo:` / `waze://` dejan la app en blanco
  /// (navegan la misma pestaña a una URL inválida).
  static Future<bool> tryLaunch(
    Uri uri, {
    bool preferExternalApp = true,
  }) async {
    try {
      if (kIsWeb) {
        if (uri.scheme != 'http' && uri.scheme != 'https') {
          return false;
        }
        final ok = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank',
        );
        return ok;
      }

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
    final googleWeb = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$la,$lo&travelmode=driving',
    );

    if (kIsWeb) {
      await tryLaunch(googleWeb);
      return;
    }

    final googleIntent = Uri(
      scheme: 'google.navigation',
      queryParameters: <String, String>{'q': '$la,$lo', 'mode': 'd'},
    );
    final geoQuery = Uri.parse('geo:0,0?q=$la,$lo');

    if (await tryLaunch(googleIntent)) return;
    if (await tryLaunch(geoQuery)) return;
    await tryLaunch(googleWeb, preferExternalApp: false);
  }

  static Future<void> abrirGoogleMapsDireccion(String direccion) async {
    final q = Uri.encodeComponent(direccion);
    final web = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');

    if (kIsWeb) {
      await tryLaunch(web);
      return;
    }

    final geoQuery = Uri.parse('geo:0,0?q=$q');
    if (await tryLaunch(geoQuery)) return;
    await tryLaunch(web, preferExternalApp: false);
  }

  static Future<void> abrirWazeDestino(double lat, double lon) async {
    final String la = fmtCoord(lat);
    final String lo = fmtCoord(lon);
    final wazeWeb = Uri.parse('https://waze.com/ul?ll=$la,$lo&navigate=yes');

    if (kIsWeb) {
      if (await tryLaunch(wazeWeb)) return;
      await abrirGoogleMapsDestino(lat, lon);
      return;
    }

    final wazeDeep = Uri.parse('waze://?ll=$la,$lo&navigate=yes');
    if (await tryLaunch(wazeDeep)) return;
    if (await tryLaunch(wazeWeb, preferExternalApp: false)) return;
    await abrirGoogleMapsDestino(lat, lon);
  }

  /// Google Maps URL: máx. 9 paradas intermedias entre origen y destino.
  static const int maxParadasIntermediasGoogleMaps = 9;

  /// Ruta con origen, paradas intermedias y destino (Google Maps; Waze solo admite un destino).
  static Future<void> abrirGoogleMapsRutaConParadas({
    required double origenLat,
    required double origenLon,
    required double destinoLat,
    required double destinoLon,
    List<({double lat, double lon})> paradas = const [],
  }) async {
    var paradasUsar = paradas;
    if (paradas.length > maxParadasIntermediasGoogleMaps) {
      paradasUsar = paradas.sublist(0, maxParadasIntermediasGoogleMaps);
      if (kDebugMode) {
        debugPrint(
          '[nav_ext] Maps: ${paradas.length} paradas → usando las primeras '
          '$maxParadasIntermediasGoogleMaps (límite Google)',
        );
      }
    }
    final String o = '${fmtCoord(origenLat)},${fmtCoord(origenLon)}';
    final String d = '${fmtCoord(destinoLat)},${fmtCoord(destinoLon)}';
    final String wp = paradasUsar
        .map((p) => '${fmtCoord(p.lat)},${fmtCoord(p.lon)}')
        .join('|');
    final Uri mapsDir = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=$o'
      '&destination=$d'
      '${wp.isNotEmpty ? '&waypoints=$wp' : ''}'
      '&travelmode=driving',
    );
    if (await tryLaunch(mapsDir, preferExternalApp: false)) return;
    if (!kIsWeb && await tryLaunch(mapsDir, preferExternalApp: true)) return;
    if (kIsWeb && await tryLaunch(mapsDir, preferExternalApp: true)) return;
    try {
      if (await launchUrl(mapsDir, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {}
    await abrirGoogleMapsDestino(destinoLat, destinoLon);
  }

  static Future<void> abrirWazeBusqueda(String query) async {
    final q = Uri.encodeComponent(query);
    final wazeWeb = Uri.parse('https://waze.com/ul?q=$q&navigate=yes');

    if (kIsWeb) {
      if (await tryLaunch(wazeWeb)) return;
      await abrirGoogleMapsDireccion(query);
      return;
    }

    final wazeDeep = Uri.parse('waze://?q=$q&navigate=yes');
    if (await tryLaunch(wazeDeep)) return;
    if (await tryLaunch(wazeWeb, preferExternalApp: false)) return;
    await abrirGoogleMapsDireccion(query);
  }

  /// Abre un enlace guardado (p. ej. ruta corporativa en Google Maps / Waze).
  static Future<bool> abrirEnlaceNavegacion(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    if (kIsWeb && uri.scheme != 'http' && uri.scheme != 'https') {
      return false;
    }
  final bool esMapsHttps = uri.scheme == 'https' &&
      (uri.host.contains('google.') ||
          uri.host.contains('maps.') ||
          uri.host.contains('waze.com'));
    if (await tryLaunch(uri, preferExternalApp: esMapsHttps ? false : true)) {
      return true;
    }
    if (!kIsWeb && esMapsHttps) {
      return tryLaunch(uri, preferExternalApp: true);
    }
    return false;
  }
}
