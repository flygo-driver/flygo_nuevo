import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/rai_ds_typography.dart';
import 'package:flygo_nuevo/widgets/rai_driver_ui.dart';

export 'rai_driver_ui.dart' show
    RaiDriverHubCard,
    RaiDriverServiceCard,
    RaiDriverSectionTitle,
    RaiDriverServiceStatus;

/// Tokens visuales RAI Cliente (misma línea que RAI Driver).
abstract final class RaiClienteColors {
  static const Color neon = RaiDriverColors.neon;
  static const Color bg = RaiDriverColors.bg;
  static const Color card = RaiDriverColors.card;
  static const Color textMuted = RaiDriverColors.textMuted;
  static const Color purple = RaiDriverColors.purple;
  static const Color orange = RaiDriverColors.orange;
  static const Color blue = RaiDriverColors.blue;
  static const Color teal = RaiDriverColors.teal;
}

class RaiClienteBrandMark extends StatelessWidget {
  const RaiClienteBrandMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double size = compact ? 14 : 18;
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
        children: const [
          TextSpan(text: 'RAI ', style: TextStyle(color: Colors.white)),
          TextSpan(
            text: 'CLIENTE',
            style: TextStyle(color: RaiClienteColors.neon),
          ),
        ],
      ),
    );
  }
}

class RaiClienteTabHeader extends StatelessWidget implements PreferredSizeWidget {
  const RaiClienteTabHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Size get preferredSize => Size.fromHeight(
        subtitle == null ? kToolbarHeight + 8 : kToolbarHeight + 28,
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        isDark ? RaiClienteColors.bg : Theme.of(context).scaffoldBackgroundColor;

    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RaiClienteBrandMark(compact: true),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.05,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: isDark
                        ? RaiClienteColors.textMuted
                        : Colors.black54,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class RaiClienteTabScaffold extends StatelessWidget {
  const RaiClienteTabScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? RaiClienteColors.bg
          : Theme.of(context).scaffoldBackgroundColor,
      appBar: RaiClienteTabHeader(title: title, subtitle: subtitle),
      body: body,
    );
  }
}

/// Cabecera de sección en inicio cliente (respeta tema claro/oscuro).
class ClienteHomeSectionHeader extends StatelessWidget {
  const ClienteHomeSectionHeader({
    super.key,
    required this.title,
    this.accent,
    this.isDark = true,
  });

  final String title;
  final Color? accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color labelColor = accent ??
        (isDark ? RaiClienteColors.textMuted : Theme.of(context).hintColor);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Text(
        title.toUpperCase(),
        style: isDark
            ? RaiDsTypography.label(context).copyWith(color: labelColor)
            : TextStyle(
                color: labelColor,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 1.1,
              ),
      ),
    );
  }
}
