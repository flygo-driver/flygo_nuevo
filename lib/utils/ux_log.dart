// lib/utils/ux_log.dart
// Logs de diagnóstico UX/rendimiento (no datos sensibles del usuario).
//
// ignore_for_file: avoid_print

import 'package:flutter/foundation.dart';

const String kUxLogPrefix = '[RAI_UX]';

void uxLog(String area, String message, [Object? error]) {
  if (kDebugMode) {
    if (error != null) {
      print('$kUxLogPrefix $area: $message → $error');
    } else {
      print('$kUxLogPrefix $area: $message');
    }
  }
}

bool firebaseFunctionsCodeIsTransient(String code) {
  final c = code.toLowerCase().trim();
  return c == 'unavailable' ||
      c == 'deadline-exceeded' ||
      c == 'internal' ||
      c == 'resource-exhausted' ||
      c == 'aborted';
}
