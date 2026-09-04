/// Enlaces para abrir el detalle de una gira/pool (WhatsApp, App Links, esquema custom).
class PoolShareLink {
  PoolShareLink._();

  static const String scheme = 'raidriver';

  /// Host HTTPS publicado en Firebase Hosting (mismo proyecto que `.firebaserc`).
  static const String httpsHost = 'flygo-rd.web.app';

  /// `https://flygo-rd.web.app/pool?id=<documentId>` — mejor para WhatsApp / vista previa.
  static String httpsOpenUrl(String poolId) {
    final id = poolId.trim();
    if (id.isEmpty) return '';
    return Uri(
      scheme: 'https',
      host: httpsHost,
      path: '/pool',
      queryParameters: <String, String>{'id': id},
    ).toString();
  }

  /// `raidriver://pool?id=<documentId>` — respaldo si el HTTPS no abre la app.
  static String openUrl(String poolId) {
    final id = poolId.trim();
    if (id.isEmpty) return '';
    return Uri(
      scheme: scheme,
      host: 'pool',
      queryParameters: <String, String>{'id': id},
    ).toString();
  }

  static bool _isPoolHttpsHost(String host) {
    final h = host.toLowerCase();
    return h == httpsHost.toLowerCase() || h == 'flygo-rd.firebaseapp.com';
  }

  static String? parsePoolId(Uri uri) {
    final String? fromHttps = _parsePoolIdHttps(uri);
    if (fromHttps != null) return fromHttps;

    if (uri.scheme.toLowerCase() != scheme) return null;
    if (uri.host.toLowerCase() != 'pool') return null;
    final q = uri.queryParameters['id']?.trim();
    if (q != null && q.isNotEmpty) return q;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isNotEmpty) return segs.last;
    return null;
  }

  /// Enlace a giras por cupos sin id concreto (catálogo en app).
  static bool esEnlaceGirasCupos(Uri uri) {
    if (parsePoolId(uri) != null) return false;
    final schemeL = uri.scheme.toLowerCase();
    if (schemeL == scheme && uri.host.toLowerCase() == 'pool') {
      return true;
    }
    if (schemeL == 'https' && _isPoolHttpsHost(uri.host)) {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isEmpty || segs.first.toLowerCase() == 'pool') {
        return true;
      }
    }
    final view = uri.queryParameters['view']?.trim().toLowerCase();
    return view == 'giras' || view == 'cupos';
  }

  /// URL para compartir catálogo giras (sin id de salida).
  static String httpsGirasCuposUrl() {
    return Uri(
      scheme: 'https',
      host: httpsHost,
      path: '/pool',
      queryParameters: const <String, String>{'view': 'giras'},
    ).toString();
  }

  static String? _parsePoolIdHttps(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') return null;
    if (!_isPoolHttpsHost(uri.host)) return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isNotEmpty && segs.first.toLowerCase() == 'pool') {
      final q = uri.queryParameters['id']?.trim();
      if (q != null && q.isNotEmpty) return q;
      if (segs.length >= 2) return segs[1].trim().isEmpty ? null : segs[1];
    }
    return null;
  }

  /// Mensaje listo para WhatsApp, Facebook, Instagram, estados, etc.
  /// El enlace va primero para que las redes muestren vista previa.
  static String mensajeRedesSociales({
    required String textoPromo,
    required String poolId,
  }) {
    final web = httpsOpenUrl(poolId);
    if (web.isEmpty) return textoPromo.trim();
    const play =
        'https://play.google.com/store/apps/details?id=com.flygo.rd2';
    return '''🔗 Reservá cupos aquí (abre RAI o descarga la app):
$web

${textoPromo.trim()}

📲 Sin la app: $play''';
  }

  /// Pie corto para estado de WhatsApp (enlace clicable + vista previa web).
  static String shareFooterCorto(String poolId) {
    final web = httpsOpenUrl(poolId);
    if (web.isEmpty) return '';
    return '''

🔗 Reservá cupos en RAI Pasajero:
$web''';
  }

  /// Pie del mensaje: enlace HTTPS (clicable en WhatsApp) + esquema custom opcional.
  static String shareFooter(String poolId) {
    final web = httpsOpenUrl(poolId);
    final app = openUrl(poolId);
    if (web.isEmpty) return '';
    return '''

🔗 Ver y reservar cupos (RAI Pasajero):
$web

Abrí el enlace con la app RAI Pasajero instalada y vas directo a Giras por cupos.
Respaldo: $app''';
  }
}
