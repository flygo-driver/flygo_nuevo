import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/custom_theme_service.dart';
import 'package:flygo_nuevo/utils/navegacion_salida_app.dart';

/// Flecha «atrás» con contraste WCAG sobre cualquier fondo (claro/oscuro/Apariencia).
class RaiBackButton extends StatelessWidget {
  const RaiBackButton({
    super.key,
    this.onPressed,
    this.color,
    this.tooltip = 'Atrás',
    this.icon = Icons.arrow_back_rounded,
    this.mostrarFondo = true,
  });

  final VoidCallback? onPressed;
  final Color? color;
  final String tooltip;
  final IconData icon;

  /// Círculo suave detrás del icono (se ve en fondos claros, oscuros y tintados).
  final bool mostrarFondo;

  /// Color legible sobre el fondo real del AppBar / scaffold actual.
  static Color resolveColor(BuildContext context, {Color? superficie}) {
    final ThemeData theme = Theme.of(context);
    final AppBarThemeData appBarTheme = theme.appBarTheme;

    Color bg = superficie ??
        appBarTheme.backgroundColor ??
        theme.scaffoldBackgroundColor;

    // AppBar transparente: usar el fondo del scaffold (Apariencia).
    if (bg.a < 0.08) {
      bg = theme.scaffoldBackgroundColor;
    }

    // Siempre WCAG blanco/negro — no confiar en iconTheme (falla con colores custom).
    return CustomThemeService.textOn(bg);
  }

  @override
  Widget build(BuildContext context) {
    final Color fg = color ?? resolveColor(context);
    final Color chip =
        fg.withValues(alpha: Theme.of(context).brightness == Brightness.dark
            ? 0.18
            : 0.10);

    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed ?? () => intentarSalirAlGate(context),
      style: IconButton.styleFrom(
        foregroundColor: fg,
        backgroundColor: mostrarFondo ? chip : Colors.transparent,
        shape: const CircleBorder(),
      ),
      icon: Icon(icon, color: fg, size: 24),
    );
  }
}

/// AppBar de pestaña del shell con flecha visible en cualquier Apariencia.
PreferredSizeWidget raiShellTabAppBar({
  required BuildContext context,
  required String title,
  required VoidCallback? onBack,
  String backTooltip = 'Atrás',
  bool centerTitle = true,
  Color? backgroundColor,
  double elevation = 0,
  double scrolledUnderElevation = 0,
  List<Widget>? actions,
}) {
  final ThemeData theme = Theme.of(context);
  final Color bg = backgroundColor ??
      theme.appBarTheme.backgroundColor ??
      theme.scaffoldBackgroundColor;
  final Color solid = bg.a < 0.08 ? theme.scaffoldBackgroundColor : bg;
  final Color fg = CustomThemeService.textOn(solid);

  return AppBar(
    title: Text(
      title,
      style: TextStyle(
        color: fg,
        fontWeight: FontWeight.w700,
        fontSize: 18,
      ),
    ),
    centerTitle: centerTitle,
    elevation: elevation,
    scrolledUnderElevation: scrolledUnderElevation,
    backgroundColor: backgroundColor ?? theme.appBarTheme.backgroundColor,
    foregroundColor: fg,
    surfaceTintColor: Colors.transparent,
    iconTheme: IconThemeData(color: fg),
    actionsIconTheme: IconThemeData(color: fg),
    automaticallyImplyLeading: false,
    leadingWidth: onBack == null ? 0 : 56,
    leading: onBack == null
        ? null
        : RaiBackButton(
            tooltip: backTooltip,
            onPressed: onBack,
            color: fg,
          ),
    actions: actions,
  );
}
