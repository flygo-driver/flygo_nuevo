import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/custom_theme_service.dart';

/// Tabs del shell sin depender de InheritedWidget / AppBar (funciona siempre).
class ShellTabController {
  ShellTabController._();

  static final ValueNotifier<int> taxistaIndex = ValueNotifier<int>(0);
  static final ValueNotifier<int> clienteIndex = ValueNotifier<int>(0);

  /// Pestaña interna del pool en Recibir: 0 COMPARTIDOS · 1 AHORA · 2 PROGRAMADOS.
  static final ValueNotifier<int?> taxistaPoolSubTab = ValueNotifier<int?>(null);

  static void taxistaIrARecibir() => taxistaIndex.value = 0;

  /// Sale de Bola Ahorro en Recibir → pestaña AHORA (viajes inmediatos).
  static void taxistaIrAPoolAhora() {
    taxistaIndex.value = 0;
    taxistaPoolSubTab.value = 1;
  }

  static void clienteIrAInicio() => clienteIndex.value = 0;
}

/// Cabecera forzada con flecha grande y contraste WCAG (cualquier Apariencia).
class RaiShellTabHeader extends StatelessWidget implements PreferredSizeWidget {
  const RaiShellTabHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.backTooltip = 'Atrás',
  });

  final String title;
  final VoidCallback onBack;
  final String backTooltip;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final Color bg = Theme.of(context).scaffoldBackgroundColor;
    final Color fg = CustomThemeService.textOn(bg);

    return Material(
      color: bg,
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              const SizedBox(width: 4),
              IconButton(
                tooltip: backTooltip,
                onPressed: onBack,
                iconSize: 28,
                style: IconButton.styleFrom(
                  foregroundColor: fg,
                  backgroundColor: fg.withValues(alpha: 0.14),
                  minimumSize: const Size(48, 48),
                  maximumSize: const Size(48, 48),
                ),
                icon: Icon(Icons.arrow_back_rounded, color: fg, size: 26),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 52),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scaffold de tab con flecha siempre visible encima del contenido.
class RaiShellTabScaffold extends StatelessWidget {
  const RaiShellTabScaffold({
    super.key,
    required this.title,
    required this.onBack,
    required this.body,
    this.backTooltip = 'Atrás',
  });

  final String title;
  final VoidCallback onBack;
  final Widget body;
  final String backTooltip;

  @override
  Widget build(BuildContext context) {
    final Color bg = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: bg,
      appBar: RaiShellTabHeader(
        title: title,
        onBack: onBack,
        backTooltip: backTooltip,
      ),
      body: body,
    );
  }
}
