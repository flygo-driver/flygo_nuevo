import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flygo_nuevo/utils/release_build_flags.dart';

/// Ajustes de Phone Auth (reCAPTCHA / Play Integrity).
abstract final class PhoneAuthConfig {
  PhoneAuthConfig._();

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
      final bool desactivar = kDebugMode ||
          ReleaseBuildFlags.qaPhoneNoCaptchaEnabled;
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
