import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// RAI: pedir viaje / reservar cupos solo con cuenta real (teléfono, Google o correo).
abstract final class ClienteCuentaRealPolicy {
  ClienteCuentaRealPolicy._();

  static const String mensajeRegistroRequerido =
      'Para pedir viaje necesitás registrarte con teléfono, Google o correo.';

  static bool tieneCuentaReal(User? user) {
    if (user == null) return false;
    if (user.isAnonymous) return false;
    if (user.providerData.isEmpty) return false;
    return user.providerData.any(
      (p) =>
          p.providerId == 'phone' ||
          p.providerId == 'google.com' ||
          p.providerId == 'password',
    );
  }

  /// En release bloquea anónimo; en debug permite QA legacy.
  static bool puedePedirViajeOReservar(User? user) {
    if (user == null) return false;
    if (!kReleaseMode && user.isAnonymous) return true;
    return tieneCuentaReal(user);
  }

  static void exigirParaPedirViaje() {
    final user = FirebaseAuth.instance.currentUser;
    if (!puedePedirViajeOReservar(user)) {
      throw ClienteCuentaRealRequeridaException(mensajeRegistroRequerido);
    }
  }
}

class ClienteCuentaRealRequeridaException implements Exception {
  ClienteCuentaRealRequeridaException(this.message);
  final String message;

  @override
  String toString() => message;
}
