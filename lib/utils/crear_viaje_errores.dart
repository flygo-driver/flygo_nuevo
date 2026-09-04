import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:flygo_nuevo/servicios/cliente_verificacion_identidad_service.dart';

/// Mensajes claros al confirmar un viaje (sin códigos crudos de Functions).
abstract final class CrearViajeErrores {
  CrearViajeErrores._();

  static String traducir(Object error) {
    if (error is ClienteVerificacionIdentidadRequeridaException) {
      return error.message;
    }

    if (error is FirebaseFunctionsException) {
      final msg = (error.message ?? '').trim();
      if (msg.isNotEmpty && !_pareceTecnico(msg)) return msg;
      return _codigoFunctions(error.code);
    }

    if (error is FirebaseException) {
      final msg = (error.message ?? '').trim();
      if (msg.isNotEmpty && !_pareceTecnico(msg)) return msg;
      return _codigoFirebase(error.code);
    }

    if (error is ArgumentError) {
      final msg = error.message?.trim() ?? '';
      if (msg.isNotEmpty) return msg;
    }

    if (error is StateError) {
      return error.message;
    }

    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    if (raw.isEmpty) {
      return 'No se pudo confirmar el viaje. Intenta de nuevo.';
    }
    if (_pareceTecnico(raw)) {
      return 'No se pudo confirmar el viaje. Revisa tu conexión e intenta de nuevo.';
    }
    return raw;
  }

  static bool _pareceTecnico(String s) {
    final l = s.toLowerCase();
    return l.contains('firebase') ||
        l.contains('firestore') ||
        l.contains('cloud_functions') ||
        l.contains('permission-denied') ||
        l.contains('permission to execute') ||
        l.contains('does not have permission') ||
        l == 'internal' ||
        l.contains(' grpc') ||
        l.contains('platformexception');
  }

  static String _codigoFunctions(String code) {
    switch (code) {
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Sin conexión estable. Revisa tu internet e intenta de nuevo.';
      case 'unauthenticated':
        return 'Tu sesión expiró. Cierra la app, inicia sesión y vuelve a intentar.';
      case 'permission-denied':
        return 'No tienes permiso para pedir viaje con esta cuenta.';
      case 'failed-precondition':
        return 'No se puede pedir otro viaje ahora. Revisa si tienes uno activo o un pago pendiente.';
      case 'invalid-argument':
        return 'Faltan datos del viaje. Vuelve a calcular el precio e intenta otra vez.';
      case 'internal':
        return 'El servidor no pudo guardar el viaje. Intenta de nuevo en unos segundos.';
      case 'resource-exhausted':
        return 'Demasiados intentos. Espera un momento e intenta de nuevo.';
      default:
        return 'No se pudo confirmar el viaje ($code). Intenta de nuevo.';
    }
  }

  static String _codigoFirebase(String code) {
    switch (code) {
      case 'permission-denied':
        return 'No tienes permiso para crear el viaje. Cierra sesión y vuelve a entrar.';
      case 'unavailable':
        return 'Sin conexión. Revisa tu internet e intenta de nuevo.';
      default:
        return _codigoFunctions(code);
    }
  }
}
