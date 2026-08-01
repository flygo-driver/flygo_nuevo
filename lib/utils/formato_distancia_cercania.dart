/// Formato legible de distancias para pool y cola del taxista.
abstract final class FormatoDistanciaCercania {
  FormatoDistanciaCercania._();

  static String metrosKm(double metros) {
    if (!metros.isFinite || metros < 0) return '—';
    if (metros < 1000) return '${metros.round()} m';
    if (metros < 10000) {
      return '${(metros / 1000).toStringAsFixed(1)} km';
    }
    return '${(metros / 1000).round()} km';
  }

  static String cercaDeTi(double metros) =>
      'Cerca de ti · ${metrosKm(metros)}';

  static String desdeTuDestino(double metros) =>
      'Desde tu destino · ${metrosKm(metros)}';

  static String aRecogida(double metros) =>
      'A recogida · ${metrosKm(metros)}';

  /// Cliente a bordo: distancia del pickup del candidato al destino del viaje actual.
  static String pickupCercaDeDestinoActual(
    double metros, {
    String? destinoActual,
  }) {
    final String d = metrosKm(metros);
    final String dest = (destinoActual ?? '').trim();
    if (dest.isNotEmpty) {
      return 'Pickup a $d de donde dejas al cliente · $dest';
    }
    return 'Pickup a $d del destino de este viaje';
  }

  /// Pool libre / sin cliente a bordo.
  static String pickupCercaDeTuPosicion(double metros) =>
      'Cerca de ti · ${metrosKm(metros)}';

  /// Muy cerca: borde destacado y badge «más cercano».
  static bool esMuyCerca(double metros) => metros.isFinite && metros <= 800;

  /// Cerca: chip verde suave.
  static bool esCerca(double metros) => metros.isFinite && metros <= 2500;

  /// Tier visual 0=lejos, 1=cerca, 2=muy cerca.
  static int tierCercania(double metros) {
    if (esMuyCerca(metros)) return 2;
    if (esCerca(metros)) return 1;
    return 0;
  }
}
