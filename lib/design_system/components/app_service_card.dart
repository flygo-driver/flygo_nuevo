import 'package:flutter/material.dart';

import 'package:flygo_nuevo/design_system/components/app_badge.dart';
import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/design_system/rai_ds_radius.dart';

enum AppServiceStatus { activo, pendiente, bloqueado }

/// Tarjeta de servicio del conductor (lista Servicios).
class AppServiceCard extends StatelessWidget {
  const AppServiceCard({
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
  final AppServiceStatus? status;
  final String? statusLabel;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = RaiDsColors.isDark(context);
    final badge = switch (status) {
      AppServiceStatus.activo => AppBadge.success(statusLabel ?? 'Activo'),
      AppServiceStatus.pendiente => AppBadge.warning(statusLabel ?? 'Pendiente'),
      AppServiceStatus.bloqueado => AppBadge.danger(statusLabel ?? 'Bloqueado'),
      null => null,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: RaiDsColors.cardBg(context),
        elevation: isDark ? 0 : 0.5,
        shadowColor: Colors.black12,
        borderRadius: BorderRadius.circular(RaiDsRadius.lg),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(RaiDsRadius.lg),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(RaiDsRadius.lg),
              border: Border.all(
                color: enabled
                    ? accent.withValues(alpha: isDark ? 0.35 : 0.28)
                    : RaiDsColors.borderColor(context),
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.16 : 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: enabled ? accent : RaiDsColors.textSecondary(context),
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
                                    ? RaiDsColors.textPrimary(context)
                                    : RaiDsColors.textSecondary(context),
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (badge != null) badge,
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: RaiDsColors.textSecondary(context),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  enabled ? Icons.chevron_right_rounded : Icons.lock_outline,
                  color: enabled
                      ? RaiDsColors.textSecondary(context)
                          .withValues(alpha: 0.75)
                      : RaiDsColors.textSecondary(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
