import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/design_system/rai_ds_radius.dart';

/// Pestañas segmentadas del pool (AHORA / PROGRAMADOS).
class AppPoolTabBar extends StatelessWidget {
  const AppPoolTabBar({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = RaiDsColors.isDark(context);
    final scaler = MediaQuery.textScalerOf(context);
    final verticalPad = scaler.scale(10.0).clamp(8.0, 16.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: RaiDsColors.cardBg(context),
          borderRadius: BorderRadius.circular(RaiDsRadius.pill),
          border: Border.all(color: RaiDsColors.borderColor(context)),
        ),
        child: Row(
          children: List.generate(labels.length, (i) {
            final selected = i == index;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(vertical: verticalPad),
                  decoration: BoxDecoration(
                    color: selected
                        ? RaiDsColors.neon.withValues(alpha: isDark ? 0.16 : 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(RaiDsRadius.pill),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      height: 1.15,
                      color: selected
                          ? RaiDsColors.neon
                          : RaiDsColors.textSecondary(context),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
