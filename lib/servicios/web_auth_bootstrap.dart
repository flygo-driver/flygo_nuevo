import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

import 'package:flygo_nuevo/servicios/google_auth.dart';

/// Espera el resultado de Google redirect (web) una sola vez por carga.
abstract final class WebAuthBootstrap {
  WebAuthBootstrap._();

  static Future<bool>? _redirectFuture;
  static bool done = false;
  static bool loggedInAfterRedirect = false;
  static String? lastError;

  static Future<bool> ensureGoogleRedirectHandled() {
    if (!kIsWeb) {
      done = true;
      return Future<bool>.value(false);
    }
    _redirectFuture ??= _run();
    return _redirectFuture!;
  }

  static Future<bool> _run() async {
    try {
      loggedInAfterRedirect = await GoogleAuthService.completeWebRedirectIfAny();
      lastError = null;
    } catch (e) {
      loggedInAfterRedirect = false;
      lastError = e.toString();
      debugPrint('[WebAuthBootstrap] redirect error: $e');
    } finally {
      done = true;
    }
    return loggedInAfterRedirect;
  }
}
