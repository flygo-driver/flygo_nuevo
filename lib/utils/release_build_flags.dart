import 'package:flutter/foundation.dart';

/// Flags de desarrollo / QA. En builds de Play Store ([kReleaseMode]) quedan
/// siempre desactivados aunque alguien pase `--dart-define` por error.
abstract final class ReleaseBuildFlags {
  ReleaseBuildFlags._();

  static const bool _simCasaDefine = bool.fromEnvironment(
    'FLYGO_SIM_CASA',
    defaultValue: false,
  );

  static const bool _useEmulatorsDefine = bool.fromEnvironment(
    'USE_EMULATORS',
    defaultValue: false,
  );

  static const bool _qaPhoneNoCaptchaDefine = bool.fromEnvironment(
    'QA_PHONE_NO_CAPTCHA',
    defaultValue: false,
  );

  /// Bypass GPS / distancia (solo debug o profile con define explícito).
  static bool get simCasaEnabled =>
      !kReleaseMode && (kDebugMode || _simCasaDefine);

  /// Firebase emulators (nunca en release de Play Store).
  static bool get useEmulatorsEnabled =>
      !kReleaseMode && _useEmulatorsDefine;

  /// Phone Auth sin captcha (solo QA interno, nunca Play Store).
  static bool get qaPhoneNoCaptchaEnabled =>
      !kReleaseMode && _qaPhoneNoCaptchaDefine;
}
