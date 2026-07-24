import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/admin/admin_ui_theme.dart';
import 'package:flygo_nuevo/widgets/admin_drawer.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import 'package:flygo_nuevo/widgets/rai_header_logo.dart';

/// AppBar estándar del panel admin: menú + logo + título + guía de uso opcional.
class AdminAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AdminAppBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
    this.guiaId,
  });

  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  /// Si se indica, muestra franja «cómo se usa» + botón de ayuda.
  final String? guiaId;

  @override
  Size get preferredSize {
    final double guiaH = (guiaId != null && AdminGuiaCatalogo.of(guiaId) != null)
        ? 40
        : 0;
    final double bottomH = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(kToolbarHeight + guiaH + bottomH);
  }

  @override
  Widget build(BuildContext context) {
    final hasGuia =
        guiaId != null && AdminGuiaCatalogo.of(guiaId) != null;
    return AppBar(
      backgroundColor: AdminUi.scaffold(context),
      foregroundColor: AdminUi.appBarFg(context),
      iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
      actionsIconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.menu),
        tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
        onPressed: () => AdminDrawer.openMenu(context),
      ),
      title: Row(
        children: [
          const RaiHeaderLogo(height: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: AdminUi.onCard(context),
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        if (hasGuia)
          IconButton(
            tooltip: 'Cómo se usa esta pantalla',
            icon: const Icon(Icons.help_outline),
            onPressed: () =>
                AdminGuiaCatalogo.mostrarDialogo(context, guiaId!),
          ),
        ...?actions,
      ],
      bottom: hasGuia
          ? AdminGuiaBar(guiaId: guiaId!, extra: bottom)
          : bottom,
    );
  }
}
