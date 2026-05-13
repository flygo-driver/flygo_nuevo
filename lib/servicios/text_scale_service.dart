import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio centralizado del factor de escala de texto de la app (tipo inDrive).
///
/// El cliente puede hacer las letras más grandes o más pequeñas desde la
/// pantalla de Apariencia. El factor se persiste en SharedPreferences y se
/// aplica globalmente vía [MediaQuery.textScaler] en `MaterialApp.builder`.
///
/// El rango está acotado a [minFactor]..[maxFactor] (0.85 a 1.30) para
/// prevenir overflow en widgets existentes, sin tocar nada del UI ya hecho.
class TextScaleService {
  TextScaleService._();

  /// Clave de persistencia.
  static const String _kKey = 'app_text_scale_factor_v1';

  /// Límites seguros para evitar overflow en cards y botones existentes.
  static const double minFactor = 0.85;
  static const double maxFactor = 1.30;
  static const double defaultFactor = 1.0;

  /// Factor actual. 1.0 = tamaño normal de Flutter (sin escalado).
  static final ValueNotifier<double> factor =
      ValueNotifier<double>(defaultFactor);

  /// Lectura inicial desde SharedPreferences. Llamar una vez en main(), antes
  /// de `runApp(...)`, igual que [ThemeModeService.init].
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getDouble(_kKey);
    if (raw != null) {
      factor.value = _clamp(raw);
    }
  }

  /// Guardar un nuevo factor (lo que devuelve un slider o un botón preset).
  static Future<void> setFactor(double next) async {
    final clamped = _clamp(next);
    factor.value = clamped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kKey, clamped);
  }

  /// Volver al tamaño por defecto.
  static Future<void> resetToDefault() async {
    factor.value = defaultFactor;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }

  /// Etiqueta legible (Pequeño / Normal / Grande / Muy grande) para mostrar
  /// al usuario en la UI.
  static String labelFor(double f) {
    if (f <= 0.92) return 'Pequeño';
    if (f >= 1.22) return 'Muy grande';
    if (f >= 1.08) return 'Grande';
    return 'Normal';
  }

  static double _clamp(double v) {
    if (v.isNaN) return defaultFactor;
    return v.clamp(minFactor, maxFactor);
  }
}
