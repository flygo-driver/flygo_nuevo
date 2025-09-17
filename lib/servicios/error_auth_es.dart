// lib/servicios/error_auth_es.dart
import 'package:firebase_auth/firebase_auth.dart';

String errorAuthEs(Object e) {
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

  return 'Ocurrió un error inesperado.';
}
