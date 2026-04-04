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

  /// Pie del mensaje: enlace HTTPS (clicable en WhatsApp) + esquema custom opcional.
  static String shareFooter(String poolId) {
    final web = httpsOpenUrl(poolId);
    final app = openUrl(poolId);
    if (web.isEmpty) return '';
    return '''

🔗 Ver esta gira en RAI Driver:
$web

(Con la app instalada suele abrirse directo al detalle. Si no: $app)''';
  }
}
