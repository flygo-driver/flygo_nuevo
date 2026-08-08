import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'package:flygo_nuevo/servicios/negocio_referido_service.dart';

/// Captura `?ref=` desde enlaces QR (`/descarga`, `/login`) en app nativa.
class NegocioReferidoDeepLink {
  NegocioReferidoDeepLink._();

  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;

  static Future<void> install() async {
    if (kIsWeb) return;
    await dispose();
    try {
      final Uri? initial = await _appLinks.getInitialLink();
      if (initial != null) {
        await _procesarUri(initial);
      }
      _sub = _appLinks.uriLinkStream.listen((Uri uri) {
        unawaited(_procesarUri(uri));
      });
    } catch (e) {
      debugPrint('[NegocioReferidoDeepLink] install: $e');
    }
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  static Future<void> _procesarUri(Uri uri) async {
    final String? ref = uri.queryParameters['ref']?.trim() ??
        uri.queryParameters['code']?.trim();
    if (ref == null || ref.isEmpty) return;

    final String path = uri.path.toLowerCase();
    final bool esDescarga = path.contains('descarga');
    final bool esLogin = path.contains('login');
    if (!esDescarga && !esLogin && uri.host.isNotEmpty) {
      // Enlace corto u otro host con ?ref= también vale.
      if (!uri.hasQuery) return;
    }

    await NegocioReferidoService.guardarPendiente(ref);
    debugPrint('[NegocioReferidoDeepLink] ref=$ref path=$path');
  }
}
