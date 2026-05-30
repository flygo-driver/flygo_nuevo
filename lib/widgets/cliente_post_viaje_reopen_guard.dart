/// Viajes que ya abrieron [PostViajeClienteFlow] en esta ejecución de la app.
///
/// Sin esto, al volver al inicio con [NavigationService.clearAndGo] se crea un
/// [ClienteShell] nuevo, el listener pierde `_ultimoViajeOfrecido` y el mismo
/// snapshot de Firestore vuelve a hacer `push` del post‑viaje (usuario atrapado).
class ClientePostViajeReopenGuard {
  ClientePostViajeReopenGuard._();

  static final Set<String> _ids = <String>{};

  static bool shouldSuppressListenerPush(String viajeId) {
    final String id = viajeId.trim();
    return id.isNotEmpty && _ids.contains(id);
  }

  static void markOpened(String viajeId) {
    final String id = viajeId.trim();
    if (id.isNotEmpty) {
      _ids.add(id);
    }
  }
}
