import 'package:flutter/material.dart';

/// Puente para limpiar navigators anidados del [ClienteShell] desde servicios.
class ClienteShellNavBridge {
  ClienteShellNavBridge._();

  static void Function()? _popAllTabRoutes;
  static Future<Object?> Function(Widget page)? _pushOnInicioTab;

  static void bind({
    required void Function() popAllTabRoutes,
    Future<Object?> Function(Widget page)? pushOnInicioTab,
  }) {
    _popAllTabRoutes = popAllTabRoutes;
    _pushOnInicioTab = pushOnInicioTab;
  }

  static void unbind() {
    _popAllTabRoutes = null;
    _pushOnInicioTab = null;
  }

  /// Cierra rutas apiladas en cada tab (p. ej. «Conductores en ruta»).
  static void popAllTabRoutes() => _popAllTabRoutes?.call();

  /// Apila una pantalla en el tab Inicio (mantiene la barra inferior del shell).
  static Future<T?> pushOnInicioTab<T>(Widget page) async {
    final Future<Object?> Function(Widget page)? push = _pushOnInicioTab;
    if (push == null) return null;
    final Object? result = await push(page);
    return result is T ? result : null;
  }

  static bool get canPushOnInicioTab => _pushOnInicioTab != null;
}
