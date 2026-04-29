import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Centraliza el reporte de errores en producción (Crashlytics).
/// No afecta esquema/datos; solo agrega trazabilidad.
class ErrorReporting {
  const ErrorReporting._();

  static Future<void> reportError(
    Object error, {
    StackTrace? stack,
    String context = '',
  }) async {
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack ?? StackTrace.current,
        reason: context,
      );
    } catch (_) {
      // Si Crashlytics falla, no queremos romper el flujo.
    }
  }
}
