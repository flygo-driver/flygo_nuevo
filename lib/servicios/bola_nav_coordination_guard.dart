/// Coordina navegación Bola Ahorro entre shell, tablero y pantalla activa
/// (evita doble push a viaje en curso o doble salida por cancelación).
abstract final class BolaNavCoordinationGuard {
  BolaNavCoordinationGuard._();

  static const Duration _ventanaOperativoNav = Duration(seconds: 12);
  static const Duration _ventanaCancel = Duration(seconds: 90);

  static final Map<String, int> _operativoNavHastaMs = <String, int>{};
  static final Map<String, int> _cancelHandledHastaMs = <String, int>{};

  static String _id(String bolaId) => bolaId.trim();

  /// Una sola navegación a viaje en curso por bola en la ventana (espejo listo).
  static bool tryClaimOperativoNav(String bolaId) {
    final String id = _id(bolaId);
    if (id.isEmpty) return false;
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int? hasta = _operativoNavHastaMs[id];
    if (hasta != null && now < hasta) return false;
    _operativoNavHastaMs[id] =
        now + _ventanaOperativoNav.inMilliseconds;
    return true;
  }

  /// La pantalla terminal ya mostró la cancelación; el listener del shell no repite.
  static void markCancelHandled(String bolaId) {
    final String id = _id(bolaId);
    if (id.isEmpty) return;
    _cancelHandledHastaMs[id] =
        DateTime.now().millisecondsSinceEpoch + _ventanaCancel.inMilliseconds;
  }

  static bool shouldSuppressCancelListener(String bolaId) {
    final String id = _id(bolaId);
    if (id.isEmpty) return false;
    final int? hasta = _cancelHandledHastaMs[id];
    if (hasta == null) return false;
    if (DateTime.now().millisecondsSinceEpoch > hasta) {
      _cancelHandledHastaMs.remove(id);
      return false;
    }
    return true;
  }

  /// Primer manejador gana (listener shell); devuelve false si ya se atendió.
  static bool tryClaimCancelListenerNotif(String bolaId) {
    if (shouldSuppressCancelListener(bolaId)) return false;
    markCancelHandled(bolaId);
    return true;
  }
}
