import 'package:flutter/material.dart';

class RaiAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  /// Cuando [title] está vacío, lectores de pantalla anuncian este texto (no visible).
  final String? titleSemanticsLabel;
  final List<Widget>? actions;
  final bool centerTitle;
  final Widget? leading;
  
  const RaiAppBar({
    Key? key,
    required this.title,
    this.titleSemanticsLabel,
    this.actions,
    this.centerTitle = false,
    this.leading,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return AppBar(
      leading: leading ?? Padding(
        padding: const EdgeInsets.all(8.0),
        child: Image.asset(
          'assets/icon/icono_app_R.png',
          height: 28,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const SizedBox(
            width: 28,
            child: Icon(Icons.error, color: Colors.red, size: 20),
          ),
        ),
      ),
      title: titleWidget,
      centerTitle: centerTitle,
      actions: actions,
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      elevation: 0,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}