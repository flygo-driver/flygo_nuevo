import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Ajustes de Phone Auth (reCAPTCHA / Play Integrity).
abstract final class PhoneAuthConfig {
  PhoneAuthConfig._();

  /// Solo QA interno en release: `flutter run --dart-define=QA_PHONE_NO_CAPTCHA=true`
  /// Requiere números de prueba en Firebase Console.
  static const bool qaSinCaptcha = bool.fromEnvironment(
    'QA_PHONE_NO_CAPTCHA',
    defaultValue: false,
  );

  static Future<void> aplicarTrasFirebaseInit() async {
    await _aplicarSettings();
  }

  /// Reaplica antes de cada SMS (el SDK a veces pierde el flag en debug).
  static Future<void> aplicarAntesDeEnviarSms() async {
    await _aplicarSettings();
  }

  static Future<void> _aplicarSettings() async {
    if (kIsWeb) return;
    try {
      // En release/Play NUNCA desactivar verificación (Play Integrity).
      // Solo debug o QA interno con --dart-define=QA_PHONE_NO_CAPTCHA=true.
      final desactivar =
          !kReleaseMode && (kDebugMode || qaSinCaptcha);
      await FirebaseAuth.instance.setSettings(
        appVerificationDisabledForTesting: desactivar,
      );
      if (kDebugMode) {
        debugPrint(
          '[PhoneAuth] appVerificationDisabledForTesting=$desactivar',
        );
      }
    } catch (e) {
      debugPrint('[PhoneAuth] setSettings omitido: $e');
    }
  }
}
