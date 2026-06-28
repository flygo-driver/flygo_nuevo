import 'package:flutter/material.dart';

/// Marca el área del [ClienteShell] donde el banner global ya está visible.
/// [RaiUbicacionClienteBanner] dentro de este scope no se repite.
class RaiUbicacionBannerScope extends InheritedWidget {
  const RaiUbicacionBannerScope({super.key, required super.child});

  static bool isDescendant(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<RaiUbicacionBannerScope>() !=
      null;

  @override
  bool updateShouldNotify(RaiUbicacionBannerScope oldWidget) => false;
}
