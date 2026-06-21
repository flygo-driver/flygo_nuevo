import 'package:flutter/material.dart';

/// Paleta verano / tropical para giras por cupos — legible en claro, oscuro y cualquier primary.
class PoolGiraTropicalTheme {
  PoolGiraTropicalTheme._();

  static PoolGiraTropicalColors of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = Color.lerp(cs.primary, const Color(0xFF00C9A7), 0.35)!;

    return PoolGiraTropicalColors(
      sunset: const Color(0xFFFF7A45),
      coral: const Color(0xFFFF5E62),
      ocean: const Color(0xFF00C9A7),
      lagoon: const Color(0xFF5BC0BE),
      sand: const Color(0xFFFFE08A),
      palm: const Color(0xFF34D399),
      accent: accent,
      heroGradient: [
        const Color(0xFFFF8A5B).withValues(alpha: isDark ? 0.35 : 0.28),
        const Color(0xFFFFC75F).withValues(alpha: isDark ? 0.22 : 0.18),
        const Color(0xFF00C9A7).withValues(alpha: isDark ? 0.45 : 0.38),
      ],
      overlayBottom: [
        Colors.transparent,
        Colors.black.withValues(alpha: isDark ? 0.35 : 0.28),
        Colors.black.withValues(alpha: isDark ? 0.88 : 0.82),
      ],
      cardFill: isDark
          ? Color.lerp(cs.surfaceContainerHigh, const Color(0xFF0F766E), 0.12)!
          : Color.lerp(cs.surface, const Color(0xFFE0F2FE), 0.55)!,
      cardBorder: Color.lerp(accent, const Color(0xFFFFB347), 0.35)!
          .withValues(alpha: isDark ? 0.55 : 0.45),
      chipFill: accent.withValues(alpha: isDark ? 0.28 : 0.16),
      chipBorder: accent.withValues(alpha: isDark ? 0.65 : 0.5),
      shadow: accent.withValues(alpha: isDark ? 0.35 : 0.22),
    );
  }
}

class PoolGiraTropicalColors {
  const PoolGiraTropicalColors({
    required this.sunset,
    required this.coral,
    required this.ocean,
    required this.lagoon,
    required this.sand,
    required this.palm,
    required this.accent,
    required this.heroGradient,
    required this.overlayBottom,
    required this.cardFill,
    required this.cardBorder,
    required this.chipFill,
    required this.chipBorder,
    required this.shadow,
  });

  final Color sunset;
  final Color coral;
  final Color ocean;
  final Color lagoon;
  final Color sand;
  final Color palm;
  final Color accent;
  final List<Color> heroGradient;
  final List<Color> overlayBottom;
  final Color cardFill;
  final Color cardBorder;
  final Color chipFill;
  final Color chipBorder;
  final Color shadow;

  LinearGradient get frameGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [sunset, sand, ocean],
      );
}
