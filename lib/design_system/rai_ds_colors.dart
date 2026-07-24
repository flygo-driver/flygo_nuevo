import 'package:flutter/material.dart';

/// Paleta RAI Driver (dark premium).
abstract final class RaiDsColors {
  static const Color bg = Color(0xFF090909);
  static const Color surface = Color(0xFF0D0D0D);
  static const Color card = Color(0xFF141414);
  static const Color cardElevated = Color(0xFF1A1A1A);
  static const Color border = Color(0xFF242424);

  static const Color neon = Color(0xFF00E676);
  static const Color neonSoft = Color(0xFF69F0AE);
  static const Color textMuted = Color(0xFF9CA3AF);

  static const Color purple = Color(0xFF8B5CF6);
  static const Color orange = Color(0xFFF59E0B);
  static const Color blue = Color(0xFF3B82F6);
  static const Color teal = Color(0xFF14B8A6);
  static const Color gold = Color(0xFFEAB308);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Fondo de pantallas conductor (tabs shell).
  static Color scaffoldBg(BuildContext context) => isDark(context)
      ? bg
      : const Color(0xFFF3F6FA);

  static Color cardBg(BuildContext context) =>
      isDark(context) ? card : Colors.white;

  static Color cardElevatedBg(BuildContext context) =>
      isDark(context) ? cardElevated : Colors.white;

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF111827);

  static Color textSecondary(BuildContext context) =>
      isDark(context) ? textMuted : const Color(0xFF6B7280);

  static Color borderColor(BuildContext context) =>
      isDark(context) ? border : const Color(0xFFE5E7EB);
}
