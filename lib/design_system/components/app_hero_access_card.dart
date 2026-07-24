import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/components/app_hero_vehicle_glyph.dart';
import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/design_system/rai_ds_theme.dart';

/// Tarjeta hero grande para el inicio (Viajes Ahora, Programados, Servicios).
class AppHeroAccessCard extends StatefulWidget {
  const AppHeroAccessCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    this.onTap,
    this.heroTag,
    this.showVehicleGlyph = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final String? heroTag;

  /// Auto vectorial sin PNG (solo en Viajes Ahora).
  final bool showVehicleGlyph;

  @override
  State<AppHeroAccessCard> createState() => _AppHeroAccessCardState();
}

class _AppHeroAccessCardState extends State<AppHeroAccessCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isRaiDark;
    final largeText = context.raiLargeText;
    final showGlyph = widget.showVehicleGlyph && !largeText;
    final showIconBox = !showGlyph;

    final card = AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          borderRadius: BorderRadius.circular(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 112),
            child: Ink(
              decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark
                    ? RaiDsColors.border
                    : widget.accent.withValues(alpha: 0.22),
                width: 1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        RaiDsColors.card,
                        widget.accent.withValues(alpha: 0.14),
                        RaiDsColors.bg,
                      ]
                    : [
                        Colors.white,
                        widget.accent.withValues(alpha: 0.1),
                        const Color(0xFFF9FAFB),
                      ],
                stops: const [0.0, 0.55, 1.0],
              ),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: widget.accent.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (showGlyph)
                  Positioned(
                    right: 8,
                    bottom: 10,
                    child: IgnorePointer(
                      child: AppHeroVehicleGlyph(
                        color: widget.accent,
                        width: 100,
                        height: 56,
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    showGlyph ? 100 : 16,
                    16,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: largeText ? 3 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.raiTextPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.subtitle,
                              maxLines: largeText ? 4 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.raiTextMuted,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (showIconBox) ...[
                        const SizedBox(width: 10),
                        Container(
                          width: largeText ? 44 : 52,
                          height: largeText ? 44 : 52,
                          decoration: BoxDecoration(
                            color: widget.accent.withValues(
                              alpha: isDark ? 0.16 : 0.12,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: widget.accent.withValues(
                                alpha: isDark ? 0.35 : 0.28,
                              ),
                            ),
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.accent,
                            size: largeText ? 22 : 26,
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: context.raiChevron,
                        size: largeText ? 24 : 28,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );

    if (widget.heroTag == null) return card;
    return Hero(tag: widget.heroTag!, child: card);
  }
}
