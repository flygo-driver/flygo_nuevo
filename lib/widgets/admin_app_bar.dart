import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/admin/admin_ui_theme.dart';
import 'package:flygo_nuevo/widgets/rai_header_logo.dart';

/// AppBar estándar del panel admin: menú lateral + logo RAI + título de pantalla.
class AdminAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AdminAppBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
  });

  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize {
    final double bottomH = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(kToolbarHeight + bottomH);
  }

  @override
  Widget build(BuildContext context) {
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
        onPressed: () => Scaffold.of(context).openDrawer(),
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
      actions: actions,
      bottom: bottom,
    );
  }
}
