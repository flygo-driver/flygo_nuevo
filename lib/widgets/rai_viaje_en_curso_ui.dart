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

  /// Texto seguro en filas angostas (evita RenderFlex overflow).
  static Widget ellipsizedText(
    String text, {
    required TextStyle style,
    int maxLines = 2,
    TextAlign textAlign = TextAlign.start,
  }) {
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
  }

  /// Botón ancho con icono + etiqueta que no desborda en pantallas pequeñas.
  static Widget overflowSafeIconButton({
    required VoidCallback? onPressed,
    required Widget icon,
    required Widget label,
    required ButtonStyle style,
    double iconGap = 8,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: style,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            SizedBox(width: iconGap),
            Flexible(
              child: DefaultTextStyle(
                style: const TextStyle(),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                textAlign: TextAlign.center,
                child: label,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Outlined análogo para filas de acciones del taxista.
  static Widget overflowSafeOutlinedIconButton({
    required VoidCallback? onPressed,
    required Widget icon,
    required Widget label,
    required ButtonStyle style,
    double iconGap = 8,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: style,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          SizedBox(width: iconGap),
          Flexible(
            child: DefaultTextStyle(
              style: const TextStyle(),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              textAlign: TextAlign.center,
              child: label,
            ),
          ),
        ],
      ),
    );
  }
}
