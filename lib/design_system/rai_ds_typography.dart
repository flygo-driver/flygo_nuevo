import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';

/// Tipografía Inter con jerarquía premium.
abstract final class RaiDsTypography {
  static TextStyle display(BuildContext context) => GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        height: 1.05,
        color: Colors.white,
      );

  static TextStyle title(BuildContext context) => GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.15,
        color: Colors.white,
      );

  static TextStyle subtitle(BuildContext context) => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: RaiDsColors.textMuted,
      );

  static TextStyle body(BuildContext context) => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.4,
        color: Colors.white.withValues(alpha: 0.92),
      );

  static TextStyle caption(BuildContext context) => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: RaiDsColors.textMuted,
      );

  static TextStyle label(BuildContext context) => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: RaiDsColors.textMuted,
      );

  static TextTheme textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: false).textTheme
        : ThemeData.light(useMaterial3: false).textTheme;
    return GoogleFonts.interTextTheme(base);
  }
}
