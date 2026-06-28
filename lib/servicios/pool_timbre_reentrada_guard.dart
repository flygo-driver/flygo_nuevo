/// Evita timbre al reentrar al pool tras finalizar un viaje (ofertas que ya estaban
/// en pantalla no deben sonar como "nuevas").
abstract final class PoolTimbreReentradaGuard {
  PoolTimbreReentradaGuard._();

  static const Duration _ventanaSilencio = Duration(seconds: 8);

  static int? _silenciarHastaMs;

  static void marcarTrasFinalizarViaje() {
    _silenciarHastaMs =
        DateTime.now().millisecondsSinceEpoch + _ventanaSilencio.inMilliseconds;
  }

  static bool get activo {
    final int? hasta = _silenciarHastaMs;
    if (hasta == null) return false;
    if (DateTime.now().millisecondsSinceEpoch > hasta) {
      _silenciarHastaMs = null;
      return false;
    }
    return true;
  }
}
