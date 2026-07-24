import 'package:flutter/material.dart';

export 'package:flygo_nuevo/design_system/rai_ds_colors.dart'
    show RaiDsColors;

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/widgets/rai_header_logo.dart';

/// Tokens visuales RAI Driver (dark + verde neón).
abstract final class RaiDriverColors {
  static const Color neon = RaiDsColors.neon;
  static const Color neonSoft = RaiDsColors.neonSoft;
  static const Color bg = RaiDsColors.bg;
  static const Color surface = RaiDsColors.surface;
  static const Color card = RaiDsColors.card;
  static const Color cardElevated = RaiDsColors.cardElevated;
  static const Color border = RaiDsColors.border;
  static const Color textMuted = RaiDsColors.textMuted;

  static const Color purple = RaiDsColors.purple;
  static const Color orange = RaiDsColors.orange;
  static const Color blue = RaiDsColors.blue;
  static const Color teal = RaiDsColors.teal;
}

/// Cabecera de tab sin flecha atrás (navegación por barra inferior).
class RaiDriverTabHeader extends StatelessWidget implements PreferredSizeWidget {
  const RaiDriverTabHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  /// Altura dinámica: respeta letra grande del sistema (sin overflow).
  static double preferredHeight(BuildContext context, {String? subtitle}) {
    final media = MediaQuery.of(context);
    final scaler = media.textScaler;
    const topPad = 6.0;
    const bottomPad = 12.0;
    const logoBlock = 30.0 + 8.0;
    const titleSubtitleGap = 4.0;
    final titleH = scaler.scale(26.0) * 1.1 * 2;
    final subtitleH = subtitle == null
        ? 0.0
        : titleSubtitleGap + scaler.scale(13.0) * 1.3 * 2;
    return media.padding.top + topPad + logoBlock + titleH + subtitleH + bottomPad;
  }

  @override
  Size get preferredSize => const Size.fromHeight(112);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? RaiDriverColors.bg
        : Theme.of(context).colorScheme.surface;
    final titleColor = isDark ? Colors.white : const Color(0xFF111827);
    final subtitleColor =
        isDark ? RaiDriverColors.textMuted : const Color(0xFF6B7280);
    final borderColor = isDark
        ? RaiDriverColors.border
        : const Color(0xFFE5E7EB);

    return Material(
      color: bg,
      elevation: isDark ? 0 : 0.5,
      shadowColor: Colors.black26,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Center(child: RaiDriverBrandMark(compact: true)),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.1,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RaiDriverTabScaffold extends StatelessWidget {
  const RaiDriverTabScaffold({
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
    final headerHeight =
        RaiDriverTabHeader.preferredHeight(context, subtitle: subtitle);
    return Scaffold(
      backgroundColor: isDark
          ? RaiDriverColors.bg
          : RaiDsColors.scaffoldBg(context),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(headerHeight),
        child: RaiDriverTabHeader(title: title, subtitle: subtitle),
      ),
      body: body,
    );
  }
}

class RaiDriverBrandMark extends StatelessWidget {
  const RaiDriverBrandMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return RaiHeaderLogo(
      height: compact ? 30 : 36,
      semanticLabel: 'RAI',
    );
  }
}

enum RaiDriverServiceStatus { activo, pendiente, bloqueado }

class RaiDriverServiceCard extends StatelessWidget {
  const RaiDriverServiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.status,
    this.statusLabel,
    this.enabled = true,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final RaiDriverServiceStatus? status;
  final String? statusLabel;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? RaiDriverColors.card : Colors.white;
    final borderColor =
        isDark ? RaiDriverColors.border : const Color(0xFFE5E7EB);

    Color? badgeBg;
    Color? badgeFg;
    if (status != null) {
      switch (status!) {
        case RaiDriverServiceStatus.activo:
          badgeBg = RaiDriverColors.neon.withValues(alpha: 0.15);
          badgeFg = RaiDriverColors.neon;
        case RaiDriverServiceStatus.pendiente:
          badgeBg = RaiDriverColors.orange.withValues(alpha: 0.18);
          badgeFg = RaiDriverColors.orange;
        case RaiDriverServiceStatus.bloqueado:
          badgeBg = Colors.red.withValues(alpha: 0.15);
          badgeFg = Colors.redAccent;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: enabled
                    ? accent.withValues(alpha: isDark ? 0.35 : 0.25)
                    : borderColor,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: enabled ? accent : RaiDriverColors.textMuted,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: enabled
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : RaiDriverColors.textMuted,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (status != null && statusLabel != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                statusLabel!,
                                style: TextStyle(
                                  color: badgeFg,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? RaiDriverColors.textMuted
                              : Colors.black54,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  enabled ? Icons.chevron_right_rounded : Icons.lock_outline,
                  color: enabled
                      ? (isDark ? Colors.white38 : Colors.black38)
                      : RaiDriverColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RaiDriverHubCard extends StatelessWidget {
  const RaiDriverHubCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.badge,
    this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Widget? badge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? RaiDriverColors.card : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: accent.withValues(alpha: isDark ? 0.35 : 0.25),
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? RaiDriverColors.textMuted
                              : Colors.black54,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge != null) ...[
                  badge!,
                  const SizedBox(width: 6),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RaiDriverSectionTitle extends StatelessWidget {
  const RaiDriverSectionTitle(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Text(
        label.toUpperCase(),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color ?? (isDark ? RaiDriverColors.textMuted : Colors.black45),
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class RaiDriverWalletCard extends StatelessWidget {
  const RaiDriverWalletCard({
    super.key,
    required this.label,
    required this.amount,
    this.detail,
    this.warning = false,
    this.onTap,
    this.expanded = false,
    this.onToggleExpand,
  });

  final String label;
  final String amount;
  final String? detail;
  final bool warning;
  final VoidCallback? onTap;
  final bool expanded;
  final VoidCallback? onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = warning ? Colors.redAccent : RaiDriverColors.neon;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: isDark ? RaiDriverColors.cardElevated : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onToggleExpand ?? onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: accent.withValues(alpha: isDark ? 0.45 : 0.35),
              ),
              gradient: isDark
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        RaiDriverColors.cardElevated,
                        accent.withValues(alpha: 0.08),
                      ],
                    )
                  : null,
            ),
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    warning
                        ? Icons.warning_amber_rounded
                        : Icons.account_balance_wallet_rounded,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: isDark
                              ? RaiDriverColors.textMuted
                              : Colors.black54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        amount,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (expanded && detail != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          detail!,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white70
                                : Colors.black54,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onToggleExpand != null)
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: isDark ? Colors.white38 : Colors.black26,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RaiDriverPoolTabBar extends StatelessWidget {
  const RaiDriverPoolTabBar({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaler = MediaQuery.textScalerOf(context);
    final verticalPad = scaler.scale(10.0).clamp(8.0, 16.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark ? RaiDriverColors.card : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? RaiDriverColors.border : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          children: List.generate(labels.length, (i) {
            final selected = i == index;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(vertical: verticalPad),
                  decoration: BoxDecoration(
                    color: selected
                        ? (isDark
                            ? RaiDriverColors.neon.withValues(alpha: 0.18)
                            : const Color(0xFFD1FAE5))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: selected
                        ? Border.all(
                            color: RaiDriverColors.neon.withValues(alpha: 0.5),
                          )
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? (isDark
                              ? RaiDriverColors.neon
                              : const Color(0xFF047857))
                          : (isDark
                              ? RaiDriverColors.textMuted
                              : Colors.black54),
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 11.5,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class RaiDriverAlertBanner extends StatelessWidget {
  const RaiDriverAlertBanner({
    super.key,
    required this.message,
    required this.icon,
    this.color = RaiDriverColors.orange,
    this.onTap,
  });

  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Material(
        color: color.withValues(alpha: isDark ? 0.12 : 0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : const Color(0xFF374151),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
