import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';

class AppBottomBarItem {
  const AppBottomBarItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Barra inferior premium con indicador animado.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<AppBottomBarItem> items;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: RaiDsColors.card,
        border: Border(top: BorderSide(color: RaiDsColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(8, 8, 8, bottom > 0 ? 4 : 8),
      child: Row(
        children: List.generate(items.length, (i) {
          final item = items[i];
          final selected = i == currentIndex;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? RaiDsColors.neon.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: RaiDsColors.neon.withValues(alpha: 0.38),
                            blurRadius: 18,
                            spreadRadius: -2,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        selected ? item.selectedIcon : item.icon,
                        key: ValueKey<bool>(selected),
                        size: 22,
                        color: selected ? RaiDsColors.neon : RaiDsColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 180),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color:
                            selected ? RaiDsColors.neon : RaiDsColors.textMuted,
                      ),
                      child: Text(item.label),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Ítems predefinidos taxista (Phosphor + Material).
abstract final class AppBottomBarTaxista {
  static List<AppBottomBarItem> items() => [
        AppBottomBarItem(
          label: 'Inicio',
          icon: PhosphorIconsRegular.house,
          selectedIcon: PhosphorIconsFill.house,
        ),
        AppBottomBarItem(
          label: 'Viajes',
          icon: PhosphorIconsRegular.car,
          selectedIcon: PhosphorIconsFill.car,
        ),
        AppBottomBarItem(
          label: 'Servicios',
          icon: PhosphorIconsRegular.squaresFour,
          selectedIcon: PhosphorIconsFill.squaresFour,
        ),
        AppBottomBarItem(
          label: 'Trabajo',
          icon: PhosphorIconsRegular.chartBar,
          selectedIcon: PhosphorIconsFill.chartBar,
        ),
        AppBottomBarItem(
          label: 'Cuenta',
          icon: PhosphorIconsRegular.user,
          selectedIcon: PhosphorIconsFill.user,
        ),
      ];
}

abstract final class AppBottomBarCliente {
  static List<AppBottomBarItem> items() => [
        AppBottomBarItem(
          label: 'Inicio',
          icon: PhosphorIconsRegular.house,
          selectedIcon: PhosphorIconsFill.house,
        ),
        AppBottomBarItem(
          label: 'Mis viajes',
          icon: PhosphorIconsRegular.mapTrifold,
          selectedIcon: PhosphorIconsFill.mapTrifold,
        ),
        AppBottomBarItem(
          label: 'Experiencias',
          icon: PhosphorIconsRegular.sparkle,
          selectedIcon: PhosphorIconsFill.sparkle,
        ),
        AppBottomBarItem(
          label: 'Cuenta',
          icon: PhosphorIconsRegular.user,
          selectedIcon: PhosphorIconsFill.user,
        ),
      ];
}
