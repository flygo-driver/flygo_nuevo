import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/design_system/rai_ds_radius.dart';

class AppBadge extends StatelessWidget {
  const AppBadge._({
    required this.label,
    required this.bg,
    required this.fg,
  });

  final String label;
  final Color bg;
  final Color fg;

  factory AppBadge.success(String label) => AppBadge._(
        label: label,
        bg: RaiDsColors.neon.withValues(alpha: 0.15),
        fg: RaiDsColors.neon,
      );

  factory AppBadge.warning(String label) => AppBadge._(
        label: label,
        bg: RaiDsColors.orange.withValues(alpha: 0.15),
        fg: RaiDsColors.orange,
      );

  factory AppBadge.danger(String label) => AppBadge._(
        label: label,
        bg: Colors.redAccent.withValues(alpha: 0.15),
        fg: Colors.redAccent,
      );

  factory AppBadge.neutral(String label) => AppBadge._(
        label: label,
        bg: RaiDsColors.border,
        fg: RaiDsColors.textMuted,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(RaiDsRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class AppTag extends StatelessWidget {
  const AppTag({
    super.key,
    required this.label,
    this.color = RaiDsColors.neon,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(RaiDsRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
