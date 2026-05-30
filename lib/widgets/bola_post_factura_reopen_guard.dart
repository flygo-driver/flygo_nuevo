/// Bolas que ya mostraron [FacturaBolaPueblo] en esta ejecución de la app.
///
/// Evita doble factura cuando [BolaPuebloDialogs.confirmarFinalizacionDialog]
/// y [BolaPostFacturaListener] detectan el mismo cierre, o al recrear el shell.
class BolaPostFacturaReopenGuard {
  BolaPostFacturaReopenGuard._();

  static final Set<String> _ids = <String>{};

  static bool shouldSuppressListenerPush(String bolaId) {
    final String id = bolaId.trim();
    return id.isNotEmpty && _ids.contains(id);
  }

  static void markOpened(String bolaId) {
    final String id = bolaId.trim();
    if (id.isNotEmpty) {
      _ids.add(id);
    }
  }
}
