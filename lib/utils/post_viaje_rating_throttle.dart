import 'package:shared_preferences/shared_preferences.dart';

/// Limita cuánto se insiste con la pantalla de **calificación** post-viaje
/// (estilo Uber: no spamear en cada carrera).
///
/// El resumen de viaje (totales, transferencia) **no** se ve afectado; solo
/// el paso de estrellas/comentario.
class PostViajeRatingThrottle {
  PostViajeRatingThrottle._();

  static const String _kLastPromptMs = 'post_viaje_rating_last_prompt_ms';
  static const String _kTripsSincePrompt = 'post_viaje_rating_trips_since_prompt';

  /// Volver a pedir calificación si pasaron al menos estos días desde la última vez
  /// que se **mostró** el paso (aunque el usuario omitiera).
  static const int minDiasEntrePrompts = 5;

  /// O bien, cada tantos viajes completados sin haber visto el prompt de calificación.
  static const int minViajesEntrePrompts = 4;

  static Future<bool> shouldShowRatingPrompt() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final int? lastMs = p.getInt(_kLastPromptMs);
    final int viajes = p.getInt(_kTripsSincePrompt) ?? 0;

    if (lastMs == null) {
      return true;
    }
    final double dias =
        (DateTime.now().millisecondsSinceEpoch - lastMs) / 86400000.0;
    if (dias + 1e-9 >= minDiasEntrePrompts) {
      return true;
    }
    if (viajes >= minViajesEntrePrompts) {
      return true;
    }
    return false;
  }

  /// Llamar cuando el cliente **ve** el paso de calificación (al pulsar Continuar en resumen).
  static Future<void> recordPromptShown() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setInt(
        _kLastPromptMs, DateTime.now().millisecondsSinceEpoch);
    await p.setInt(_kTripsSincePrompt, 0);
  }

  /// Un viaje terminó y **no** mostramos calificación (throttle): sube el contador.
  static Future<void> recordViajeSinPromptCalificacion() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final int n = p.getInt(_kTripsSincePrompt) ?? 0;
    await p.setInt(_kTripsSincePrompt, n + 1);
  }
}
