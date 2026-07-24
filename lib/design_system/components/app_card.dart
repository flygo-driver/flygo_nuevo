import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/design_system/rai_ds_radius.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.accent,
    this.radius = RaiDsRadius.xl,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? accent;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = RaiDsColors.isDark(context);
    final borderColor =
        accent?.withValues(alpha: isDark ? 0.35 : 0.25) ??
            RaiDsColors.borderColor(context);
    final content = Container(
      decoration: BoxDecoration(
        color: RaiDsColors.cardBg(context),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      padding: padding,
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );
  }
}
