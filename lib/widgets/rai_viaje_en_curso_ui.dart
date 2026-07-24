import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';

/// Tokens visuales compartidos para viaje en curso (solo UI).
abstract final class RaiViajeEnCursoUi {
  static const Color scaffoldBg = RaiDsColors.bg;
  static const Color sheetBg = RaiDsColors.card;
  static const Color sheetBorder = RaiDsColors.border;
  static const Color actionPanelBg = RaiDsColors.cardElevated;
  static const double sheetRadius = 24;
  static const int mapFlex = 5;
  static const int panelFlex = 2;

  static BoxDecoration panelDecoration({double radius = 20}) => BoxDecoration(
        color: actionPanelBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: sheetBorder),
      );

  static BoxDecoration sheetDecoration() => BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(sheetRadius),
        ),
        border: const Border(top: BorderSide(color: sheetBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      );
}
