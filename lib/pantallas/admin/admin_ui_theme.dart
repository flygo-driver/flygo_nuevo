// lib/pantallas/admin/admin_ui_theme.dart
// Solo colores / estilos visuales para modo claro y oscuro en administración.
import 'package:flutter/material.dart';

abstract final class AdminUi {
  AdminUi._();

  static bool light(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  static ColorScheme _cs(BuildContext context) => Theme.of(context).colorScheme;

  static Color scaffold(BuildContext context) {
    if (light(context)) return _cs(context).surface;
    return const Color(0xFF0A0A0A);
  }

  static Color card(BuildContext context) {
    if (light(context)) return _cs(context).surfaceContainerHighest;
    return const Color(0xFF121212);
  }

  static Color dialogSurface(BuildContext context) {
    if (light(context)) return _cs(context).surfaceContainerHigh;
    return const Color(0xFF1E1E1E);
  }

  static Color sheetSurface(BuildContext context) => scaffold(context);

  static Color onCard(BuildContext context) => _cs(context).onSurface;

  static Color secondary(BuildContext context) => _cs(context).onSurfaceVariant;

  static Color muted(BuildContext context) {
    final c = _cs(context).onSurfaceVariant;
    return light(context) ? c : c.withValues(alpha: 0.9);
  }

  static Color borderSubtle(BuildContext context) {
    if (light(context)) {
      return _cs(context).outlineVariant.withValues(alpha: 0.7);
    }
    return Colors.white.withValues(alpha: 0.12);
  }

  static Color inputFill(BuildContext context) {
    if (light(context)) {
      return _cs(context).surfaceContainerHighest.withValues(alpha: 0.9);
    }
    return const Color(0xFF1A1A1A);
  }

  static Color progressAccent(BuildContext context) =>
      light(context) ? const Color(0xFF0F9D58) : Colors.greenAccent;

  static Color accentGreen(BuildContext context) => progressAccent(context);

  static Color appBarFg(BuildContext context) => _cs(context).onSurface;

  static Color iconStandard(BuildContext context) => _cs(context).onSurface;

  static Color tabUnselected(BuildContext context) => secondary(context);

  /// Borde para contenedores informativos (p. ej. banners morados).
  static Color infoBorder(BuildContext context) =>
      light(context) ? Colors.deepPurple.shade200 : Colors.purpleAccent.withValues(alpha: 0.35);

  static Color infoFill(BuildContext context) =>
      light(context) ? Colors.deepPurple.shade50.withValues(alpha: 0.85) : Colors.purple.withValues(alpha: 0.12);

  static TextStyle titleStyle(BuildContext context, {FontWeight? weight}) =>
      TextStyle(color: onCard(context), fontWeight: weight ?? FontWeight.w600);

  static TextStyle bodyStyle(BuildContext context) =>
      TextStyle(color: secondary(context));

  static InputDecorationTheme inputDecorationTheme(BuildContext context) {
    final o = _cs(context).outlineVariant;
    return InputDecorationTheme(
      filled: true,
      fillColor: inputFill(context),
      hintStyle: TextStyle(color: secondary(context).withValues(alpha: 0.85)),
      labelStyle: TextStyle(color: secondary(context)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: o.withValues(alpha: light(context) ? 0.5 : 0.35)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderSubtle(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _cs(context).primary, width: 1.4),
      ),
    );
  }
}
