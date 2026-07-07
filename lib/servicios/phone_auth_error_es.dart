import 'package:firebase_auth/firebase_auth.dart';

/// Mensajes claros para SMS / teléfono (producción y pruebas reales).
String phoneAuthErrorEs(Object e, {String entradaRol = 'cliente'}) {
  final esConductor = entradaRol.trim().toLowerCase() == 'taxista';
  final perfil = esConductor ? 'conductor' : 'pasajero';

  if (e is FirebaseAuthException) {
    if (e.code == 'role-mismatch') {
      return e.message ??
          'Esta cuenta no corresponde al perfil de $perfil en RAI.';
    }

    if (e.code == 'captcha-check-failed' ||
        e.code == 'invalid-app-credential') {
      return _mensajeCaptchaOAppCredential(e.code);
    }

    final desdeTexto = _mensajeDesdeTextoCrudo(e.message, omitirCaptcha: true);
    if (desdeTexto != null) return desdeTexto;

    switch (e.code) {
      case 'invalid-phone-number':
        return 'Número inválido. Usa 809, 829 o 849 (10 dígitos).';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera 30–60 minutos o entrá con Google.';
      case 'quota-exceeded':
        return 'Límite de SMS alcanzado. Espera un rato, probá otro número o usá Google.';
      case 'captcha-check-failed':
        return _mensajeCaptchaOAppCredential(e.code);
      case 'invalid-app-credential':
        return _mensajeCaptchaOAppCredential(e.code);
      case 'invalid-verification-code':
        return 'Código incorrecto. Revisá el SMS o pedí uno nuevo.';
      case 'session-expired':
        return 'El código expiró. Tocá «Cambiar número» y pedí un SMS nuevo.';
      case 'operation-in-progress':
        return 'Ya estamos enviando un SMS. Esperá unos segundos.';
      case 'account-exists-with-different-credential':
        return 'Este teléfono ya está con otra cuenta. Entrá con Google o el correo que usaste antes.';
      case 'credential-already-in-use':
        return 'Este teléfono ya está vinculado a otra cuenta.';
      case 'network-request-failed':
        return 'Sin conexión. Verificá internet e intentá de nuevo.';
      case 'internal-error':
      case 'unknown':
        return 'Servicio SMS temporalmente saturado. Esperá 30–60 min, probá otro número o usá Google.';
      default:
        return e.message ?? 'No se pudo verificar el teléfono. Probá Google.';
    }
  }

  final desdeTexto = _mensajeDesdeTextoCrudo(e.toString(), omitirCaptcha: true);
  if (desdeTexto != null) return desdeTexto;

  return 'No se pudo verificar el teléfono. Probá Google o esperá unos minutos.';
}

String _mensajeCaptchaOAppCredential(String code) {
  if (code == 'invalid-app-credential') {
    return 'SMS no autorizado en esta versión de la app. '
        'Actualizá la app desde Play Store o entrá con Google.';
  }
  return 'Google no completó la verificación (reCAPTCHA).\n\n'
      '1. Si ves pantalla en blanco → tocá Atrás del teléfono.\n'
      '2. Actualizá «Android System WebView» en Play Store.\n'
      '3. Reintentá o tocá «Continuar con Google» abajo.';
}

String? _mensajeDesdeTextoCrudo(String? raw, {bool omitirCaptcha = false}) {
  if (raw == null || raw.trim().isEmpty) return null;
  final l = raw.toLowerCase();

  if (_contieneError39(l)) {
    return 'Demasiados intentos con este número (límite Firebase). '
        'Esperá 30–60 minutos, probá otro teléfono o entrá con Google.';
  }
  if (l.contains('quota') || l.contains('quotaexceeded')) {
    return 'Límite de SMS alcanzado. Esperá un rato o usá Google.';
  }
  if (!omitirCaptcha && l.contains('captcha')) {
    return _mensajeCaptchaOAppCredential('captcha-check-failed');
  }
  if (l.contains('invalid app credential') || l.contains('app credential')) {
    return 'SMS no autorizado en esta app. Contactá soporte RAI.';
  }
  return null;
}

bool _contieneError39(String lower) {
  if (!lower.contains('39')) return false;
  return lower.contains('error code') ||
      lower.contains('code:39') ||
      lower.contains('code 39') ||
      lower.contains('backenderror') ||
      lower.contains('17499') ||
      lower.contains('17028');
}

/// Normaliza códigos crudos del SDK Android/iOS (p. ej. error 39).
String normalizarCodigoPhoneAuth(String code, String? message) {
  final blob = '${code.trim()} ${message ?? ''}'.toLowerCase();
  if (_contieneError39(blob)) return 'quota-exceeded';
  if (blob.contains('too-many') || blob.contains('blocked all requests')) {
    return 'too-many-requests';
  }
  if (blob.contains('invalid app credential')) return 'invalid-app-credential';
  if (blob.contains('captcha')) return 'captcha-check-failed';
  return code.trim().isEmpty ? 'unknown' : code;
}
