import 'package:firebase_auth/firebase_auth.dart';

/// Política de verificación de correo: solo cuentas email/password.
abstract final class EmailVerificationPolicy {
  static bool isGoogleAccount(User user) =>
      user.providerData.any((p) => p.providerId == 'google.com');

  /// Tras login/registro con contraseña válida, mismo acceso que Google (sin pantalla bloqueante).
  /// El enlace de verificación se envía al registrarse; no impide entrar a la app.
  static bool needsVerification(User? user) => false;
}
