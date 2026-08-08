// lib/servicios/negocio_aliado_config.dart
// Reglas fijas del programa negocios aliados (piloto).

abstract final class NegocioAliadoConfig {
  NegocioAliadoConfig._();

  static const String collection = 'negocios_aliados';

  static const String httpsHost = 'flygo-rd.web.app';
  static const String playStorePackage = 'com.flygo.rd2';

  /// Promo cliente: 5 viajes pagados → 6.º gratis.
  static const int promoViajesM = 5;
  static const int promoViajesK = 1;

  /// Vigencia promo + comisión negocio.
  static const int vigenciaDias = 90;

  /// % comisión al negocio (sobre viaje pagado).
  static const double pctComisionNegocio = 3.0;

  /// % comisión taxista en viajes referidos (cualquier método).
  static const double pctComisionTaxistaReferido = 15.0;

  /// Tope viaje gratis promo (RD$).
  static const double topeViajeGratisRd = 600.0;

  static String urlDescarga(String codigo) {
    final c = codigo.trim();
    return Uri(
      scheme: 'https',
      host: httpsHost,
      path: '/descarga/index.html',
      queryParameters: <String, String>{'ref': c},
    ).toString();
  }

  static String urlPlayStoreConReferrer(String codigo) {
    final ref = Uri.encodeComponent('ref=$codigo');
    return 'https://play.google.com/store/apps/details'
        '?id=$playStorePackage&referrer=$ref';
  }
}
