/// Puente para limpiar navigators anidados del [ClienteShell] desde servicios.
class ClienteShellNavBridge {
  ClienteShellNavBridge._();

  static void Function()? _popAllTabRoutes;

  static void bind({required void Function() popAllTabRoutes}) {
    _popAllTabRoutes = popAllTabRoutes;
  }

  static void unbind() {
    _popAllTabRoutes = null;
  }

  /// Cierra rutas apiladas en cada tab (p. ej. «Conductores en ruta»).
  static void popAllTabRoutes() => _popAllTabRoutes?.call();
}
