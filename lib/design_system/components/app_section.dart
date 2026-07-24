import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/design_system/rai_ds_typography.dart';

class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.title,
    required this.child,
    this.accent,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Color? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: RaiDsTypography.label(context).copyWith(
                    color: accent ?? RaiDsColors.textSecondary(context),
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        child,
      ],
    );
  }
}
