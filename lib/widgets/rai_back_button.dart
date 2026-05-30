import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/custom_theme_service.dart';
import 'package:flygo_nuevo/utils/navegacion_salida_app.dart';

/// Flecha «atrás» con color legible sobre cualquier fondo (Apariencia claro/oscuro).
class RaiBackButton extends StatelessWidget {
  const RaiBackButton({
    super.key,
    this.onPressed,
    this.color,
    this.tooltip = 'Atrás',
    this.icon = Icons.arrow_back_rounded,
  });

  final VoidCallback? onPressed;
  final Color? color;
  final String tooltip;
  final IconData icon;

  /// Color de iconos de navegación sobre el fondo actual del scaffold/app bar.
  static Color resolveColor(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppBarThemeData appBarTheme = theme.appBarTheme;
    final Color bg =
        appBarTheme.backgroundColor ?? theme.scaffoldBackgroundColor;
    return appBarTheme.foregroundColor ??
        appBarTheme.iconTheme?.color ??
        theme.iconTheme.color ??
        CustomThemeService.textOn(bg);
  }

  @override
  Widget build(BuildContext context) {
    final Color fg = color ?? resolveColor(context);
    return IconButton(
      icon: Icon(icon, color: fg),
      tooltip: tooltip,
      onPressed: onPressed ?? () => intentarSalirAlGate(context),
    );
  }
}
