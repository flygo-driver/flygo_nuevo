import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';

/// Tokens visuales para pantalla de documentos (solo UI).
abstract final class RaiDocsUi {
  static const Color scaffoldBg = RaiDsColors.bg;
  static const Color cardBg = RaiDsColors.card;
  static const Color previewBg = RaiDsColors.cardElevated;

  static BoxDecoration bannerDecoration(Color accent) => BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      );

  static BoxDecoration docItemDecoration() => BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RaiDsColors.border),
      );

  static BoxDecoration statusChipDecoration(Color accent) => BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(24),
      );
}

/// Banner informativo reutilizable en documentos.
class RaiDocsInfoBanner extends StatelessWidget {
  const RaiDocsInfoBanner({
    super.key,
    required this.message,
    required this.accent,
    this.icon = Icons.info_outline_rounded,
  });

  final String message;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: RaiDocsUi.bannerDecoration(accent),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: RaiDsColors.textMuted,
                height: 1.35,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
