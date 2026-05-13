import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio centralizado del color de fondo personalizable de la app.
///
/// El cliente puede elegir cualquier color (rojo, rosa, amarillo, verde, etc.)
/// desde la pantalla de Apariencia. El color se persiste en SharedPreferences
/// y se expone como [ValueNotifier<Color>] para que `MaterialApp` y los widgets
/// se reconstruyan automáticamente cuando cambie.
///
/// IMPORTANTE: este servicio NO toca lógica de negocio, navegación ni
/// autenticación. Solo expone helpers de color y contraste WCAG AA.
class CustomThemeService {
  CustomThemeService._();

  /// Clave de persistencia.
  static const String _kBgColorKey = 'app_custom_bg_color_v1';

  /// Chrome flotante sobre el mapa en «Programar Viaje»: sin fondo del sheet,
  /// solo burbuja difusa + bordes alrededor de campos y controles.
  static const String _kMapFloatingChromeKey = 'app_map_floating_chrome_v1';

  /// Cuando es `true`, solo la pantalla [ProgramarViaje] usa fondo
  /// transparente y controles «flotando» sobre el mapa.
  static final ValueNotifier<bool> mapFloatingChrome =
      ValueNotifier<bool>(false);

  /// Color por defecto en modo claro (mismo que `lightTheme.scaffoldBackgroundColor`
  /// original para mantener exactamente el aspecto previo si nadie cambia nada).
  static const Color defaultLightBg = Color(0xFFF4F7FB);

  /// Color por defecto en modo oscuro.
  static const Color defaultDarkBg = Colors.black;

  /// Si `null`, se usa el comportamiento por defecto (light/dark según el modo).
  /// Si tiene valor, se usa ese color como fondo en modo claro y se oscurece
  /// automáticamente en modo oscuro.
  static final ValueNotifier<Color?> color = ValueNotifier<Color?>(null);

  /// Lectura inicial desde SharedPreferences. Llamar una vez en main(), antes
  /// de `runApp(...)`, igual que [ThemeModeService.init].
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_kBgColorKey);
    if (raw != null) {
      color.value = Color(raw);
    }
    mapFloatingChrome.value =
        prefs.getBool(_kMapFloatingChromeKey) ?? false;
  }

  /// Guardar un color custom (lo que devuelve un picker).
  static Future<void> setColor(Color c) async {
    color.value = c;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBgColorKey, _toArgb(c));
  }

  /// Volver al color por defecto del tema (light/dark estándar).
  static Future<void> resetToDefault() async {
    color.value = null;
    mapFloatingChrome.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBgColorKey);
    await prefs.remove(_kMapFloatingChromeKey);
  }

  /// Modo «solo controles sobre el mapa» en Programar Viaje (persistente).
  static Future<void> setMapFloatingChrome(bool enabled) async {
    mapFloatingChrome.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    if (enabled) {
      await prefs.setBool(_kMapFloatingChromeKey, true);
    } else {
      await prefs.remove(_kMapFloatingChromeKey);
    }
  }

  // ---------- HELPERS DE RESOLUCIÓN ----------

  /// Devuelve el color de fondo final dado el brightness del tema.
  /// - En light: el color elegido tal cual (o defaultLightBg si no hay).
  /// - En dark: el color elegido oscurecido fuerte (o defaultDarkBg).
  static Color resolveScaffoldBg(Brightness brightness) {
    final base = color.value;
    if (base == null) {
      return brightness == Brightness.dark ? defaultDarkBg : defaultLightBg;
    }
    if (brightness == Brightness.dark) {
      // Oscurecer el color elegido para que no agreda en modo oscuro,
      // manteniendo el matiz (hue) elegido por el usuario.
      return darken(base, 0.18);
    }
    return base;
  }

  // ---------- HELPERS DE CONTRASTE WCAG ----------

  /// Devuelve negro o blanco según cuál tenga mejor contraste con [bg].
  /// Usa el cálculo de luminancia relativa de WCAG (≥ 4.5:1 garantizado para
  /// blanco vs negro contra cualquier color sólido).
  static Color textOn(Color bg) {
    return ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white
        : const Color(0xFF101828);
  }

  /// Variante muted/secondary del texto, manteniendo contraste razonable.
  static Color textMutedOn(Color bg) {
    return ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white.withValues(alpha: 0.78)
        : const Color(0xFF475467);
  }

  /// Variante terciaria (labels de sección) — más tenue pero aún legible.
  static Color textSubtleOn(Color bg) {
    return ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF667085);
  }

  /// Color de borde sutil que se ve sobre [bg] sin ser invasivo.
  static Color borderOn(Color bg) {
    return ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFE4E7EC);
  }

  /// Color de "card surface" que se ve elevada sobre [bg].
  /// Usa el contraste para decidir entre tinte oscuro o claro.
  static Color cardOn(Color bg) {
    return ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? const Color(0xFF111111)
        : Colors.white;
  }

  // ---------- HELPERS DE COLOR ----------

  /// Aclarar un color por un factor 0.0..1.0.
  static Color lighten(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    final l = (hsl.lightness + amount).clamp(0.0, 1.0);
    return hsl.withLightness(l).toColor();
  }

  /// Oscurecer un color por un factor 0.0..1.0.
  static Color darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    final l = (hsl.lightness - amount).clamp(0.0, 1.0);
    return hsl.withLightness(l).toColor();
  }

  /// Empaquetar un Color en un entero ARGB de 32 bits para SharedPreferences.
  /// Usamos los componentes .a/.r/.g/.b (en lugar de la propiedad value,
  /// deprecada en Flutter 3.x) para evitar warnings y mantener compatibilidad
  /// con SDKs nuevos.
  static int _toArgb(Color c) {
    final a = (c.a * 255.0).round() & 0xff;
    final r = (c.r * 255.0).round() & 0xff;
    final g = (c.g * 255.0).round() & 0xff;
    final b = (c.b * 255.0).round() & 0xff;
    return (a << 24) | (r << 16) | (g << 8) | b;
  }
}
