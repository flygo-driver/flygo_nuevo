import 'package:flutter/material.dart';

/// Puente para limpiar navigators anidados del [ClienteShell] desde servicios.
class ClienteShellNavBridge {
  ClienteShellNavBridge._();

  static void Function()? _popAllTabRoutes;
  static void Function()? _resetInicioTabAlHome;
  static Future<Object?> Function(Widget page)? _pushOnInicioTab;

  static void bind({
    required void Function() popAllTabRoutes,
    void Function()? resetInicioTabAlHome,
    Future<Object?> Function(Widget page)? pushOnInicioTab,
  }) {
    _popAllTabRoutes = popAllTabRoutes;
    _resetInicioTabAlHome = resetInicioTabAlHome;
    _pushOnInicioTab = pushOnInicioTab;
  }

  static void unbind() {
    _popAllTabRoutes = null;
    _resetInicioTabAlHome = null;
    _pushOnInicioTab = null;
  }

  /// Cierra rutas apiladas en cada tab (p. ej. «Conductores en ruta»).
  static void popAllTabRoutes() => _popAllTabRoutes?.call();

  /// Restaura el tab Inicio cuando la reserva programada quedó como única ruta.
  static void resetInicioTabAlHome() => _resetInicioTabAlHome?.call();

  /// Apila una pantalla en el tab Inicio (mantiene la barra inferior del shell).
  static Future<T?> pushOnInicioTab<T>(Widget page) async {
    final Future<Object?> Function(Widget page)? push = _pushOnInicioTab;
    if (push == null) return null;
    final Object? result = await push(page);
    return result is T ? result : null;
  }

  static bool get canPushOnInicioTab => _pushOnInicioTab != null;
}
