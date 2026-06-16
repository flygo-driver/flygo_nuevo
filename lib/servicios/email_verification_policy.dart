import 'package:firebase_auth/firebase_auth.dart';

/// Política de verificación de correo: solo cuentas email/password.
abstract final class EmailVerificationPolicy {
  static bool isGoogleAccount(User user) =>
      user.providerData.any((p) => p.providerId == 'google.com');

  /// Google y anónimos no pasan por pantalla de verificación.
  static bool needsVerification(User? user) {
    if (user == null) return false;
    if (user.isAnonymous) return false;
    if (isGoogleAccount(user)) return false;
    if ((user.email ?? '').trim().isEmpty) return false;
    return !user.emailVerified;
  }
}
