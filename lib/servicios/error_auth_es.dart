// lib/servicios/error_auth_es.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

String errorAuthEs(Object e) {
  if (e is FirebaseFunctionsException) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permiso denegado.';
      case 'unauthenticated':
        return 'Sesión expirada. Vuelve a iniciar sesión.';
      case 'unavailable':
        return 'Servicio en la nube no disponible. La app intentará el modo local.';
      case 'failed-precondition':
        return (e.message ?? '').trim().isNotEmpty
            ? e.message!.trim()
            : 'No se puede completar en este estado del viaje.';
      case 'not-found':
        return 'No se encontró el viaje.';
      case 'invalid-argument':
        return (e.message ?? '').trim().isNotEmpty
            ? e.message!.trim()
            : 'Datos inválidos.';
      default:
        return (e.message ?? '').trim().isNotEmpty
            ? e.message!.trim()
            : 'Error de servidor (${e.code}).';
    }
  }

  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Ese correo ya está registrado.';
      case 'invalid-email':
        return 'Correo inválido.';
      case 'user-disabled':
        return 'Cuenta deshabilitada.';
      case 'user-not-found':
        return 'No existe una cuenta con ese correo.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Contraseña incorrecta.';
      case 'too-many-requests':
        return 'Demasiados intentos. Intenta más tarde.';
      case 'operation-not-allowed':
        return 'Método de acceso no habilitado.';
    }
  }

  // FirebaseException también está disponible vía firebase_auth.
  if (e is FirebaseException) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permiso denegado.';
      case 'unavailable':
        return 'Servicio temporalmente no disponible.';
      case 'cancelled':
        return 'Operación cancelada.';
      case 'deadline-exceeded':
        return 'Tiempo de espera agotado.';
      default:
        return 'Error de servidor (${e.code}).';
    }
  }

  final String msg = _exceptionMessage(e).trim();
  if (msg.isNotEmpty) return msg;
  return 'Ocurrió un error inesperado.';
}

String _exceptionMessage(Object e) {
  if (e is Exception) {
    final raw = e.toString();
    const prefix = 'Exception: ';
    if (raw.startsWith(prefix)) return raw.substring(prefix.length);
    return raw;
  }
  return e.toString();
}
