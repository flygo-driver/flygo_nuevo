import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/custom_theme_service.dart';
import 'package:flygo_nuevo/widgets/rai_back_button.dart';
import 'package:flygo_nuevo/widgets/rai_header_logo.dart';

class RaiAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;

  /// Cuando [title] está vacío, lectores de pantalla anuncian este texto (no visible).
  final String? titleSemanticsLabel;
  final List<Widget>? actions;
  final bool centerTitle;
  final Widget? leading;

  /// En flujos del cliente apilados sobre el shell: atrás en lugar del logo Rai.
  final bool backWhenCanPop;

  /// Pantallas secundarias (Cuenta → Apariencia): flecha si hay ruta anterior.
  final bool showBackWhenCanPop;

  /// P. ej. [TabBar] en la pantalla principal del taxista.
  final PreferredSizeWidget? bottom;

  const RaiAppBar({
    super.key,
    required this.title,
    this.titleSemanticsLabel,
    this.actions,
    this.centerTitle = false,
    this.leading,
    this.backWhenCanPop = false,
    this.showBackWhenCanPop = false,
    this.bottom,
  });

  /// Altura de barra superior que respeta letra grande del sistema.
  static double toolbarHeight(BuildContext context) {
    return MediaQuery.textScalerOf(context)
        .scale(kToolbarHeight)
        .clamp(kToolbarHeight, 80);
  }

  static Size preferredTotalSize(
    BuildContext context, {
    PreferredSizeWidget? bottom,
  }) {
    final bottomH = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(toolbarHeight(context) + bottomH);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppBarThemeData appBarTheme = theme.appBarTheme;
    final Color bg =
        appBarTheme.backgroundColor ?? theme.scaffoldBackgroundColor;
    final Color fg = appBarTheme.foregroundColor ??
        CustomThemeService.textOn(bg);

    final Widget titleWidget;
    if (title.isEmpty) {
      final a11y = titleSemanticsLabel?.trim();
      if (a11y != null && a11y.isNotEmpty) {
        titleWidget = Semantics(
          header: true,
          label: a11y,
          child: const SizedBox.shrink(),
        );
      } else {
        titleWidget = const SizedBox.shrink();
      }
    } else {
      titleWidget = Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: fg,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    Widget? resolvedLeading = leading;
    if (resolvedLeading == null &&
        (backWhenCanPop ||
            (showBackWhenCanPop && Navigator.canPop(context)))) {
      // Contraste WCAG sobre el fondo real (no confiar en appBarTheme.foreground).
      resolvedLeading = RaiBackButton(
        color: RaiBackButton.resolveColor(context, superficie: bg),
      );
    }
    resolvedLeading ??= const SizedBox(
      width: kToolbarHeight,
      height: kToolbarHeight,
      child: Center(
        child: RaiHeaderLogo(height: 30),
      ),
    );

    return AppBar(
      toolbarHeight: RaiAppBar.toolbarHeight(context),
      leading: resolvedLeading,
      automaticallyImplyLeading: false,
      title: titleWidget,
      centerTitle: centerTitle,
      actions: actions,
      backgroundColor: bg,
      foregroundColor: fg,
      iconTheme: IconThemeData(color: fg),
      actionsIconTheme: IconThemeData(color: fg),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: bottom,
    );
  }

  @override
  Size get preferredSize {
    final double bottomH = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(kToolbarHeight + bottomH);
  }
}
