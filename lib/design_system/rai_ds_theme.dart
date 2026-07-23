import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/design_system/rai_ds_typography.dart';

/// Colores adaptativos según tema del sistema / app.
extension RaiDsAdaptive on BuildContext {
  bool get isRaiDark => Theme.of(this).brightness == Brightness.dark;

  Color get raiBg =>
      isRaiDark ? RaiDsColors.bg : const Color(0xFFF4F4F5);

  Color get raiSurface =>
      isRaiDark ? RaiDsColors.surface : Colors.white;

  Color get raiCard =>
      isRaiDark ? RaiDsColors.card : Colors.white;

  Color get raiCardElevated =>
      isRaiDark ? RaiDsColors.cardElevated : const Color(0xFFFAFAFA);

  Color get raiBorder =>
      isRaiDark ? RaiDsColors.border : const Color(0xFFE4E4E7);

  Color get raiTextPrimary =>
      isRaiDark ? Colors.white : const Color(0xFF111827);

  Color get raiTextSecondary =>
      isRaiDark ? Colors.white.withValues(alpha: 0.88) : const Color(0xFF374151);

  Color get raiTextMuted =>
      isRaiDark ? RaiDsColors.textMuted : const Color(0xFF6B7280);

  Color get raiChevron =>
      isRaiDark ? Colors.white.withValues(alpha: 0.35) : Colors.black26;

  /// True cuando el usuario tiene letra grande (accesibilidad).
  bool get raiLargeText =>
      MediaQuery.textScalerOf(this).scale(14) / 14 >= 1.1;
}

/// Tema oscuro premium RAI Driver.
abstract final class RaiDsTheme {
  static ThemeData dark({Color? scaffoldOverride}) {
    const neon = RaiDsColors.neon;
    final bg = scaffoldOverride ?? RaiDsColors.bg;

    return ThemeData(
      useMaterial3: false,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Inter',
      colorScheme: const ColorScheme.dark(
        primary: neon,
        secondary: neon,
        surface: RaiDsColors.card,
        onSurface: Colors.white,
        outline: RaiDsColors.border,
      ),
      dividerColor: RaiDsColors.border,
      textTheme: RaiDsTypography.textTheme(Brightness.dark).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: RaiDsColors.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: RaiDsColors.card,
        indicatorColor: neon.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? neon : RaiDsColors.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? neon : RaiDsColors.textMuted,
            size: 22,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: neon,
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RaiDsColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: RaiDsColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: RaiDsColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: neon, width: 1.4),
        ),
        hintStyle: const TextStyle(color: RaiDsColors.textMuted),
      ),
    );
  }
}
