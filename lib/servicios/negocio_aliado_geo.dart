// lib/servicios/negocio_aliado_geo.dart
//
// Promo gratis solo en el pueblo/ciudad del negocio aliado (no inter-pueblo).

abstract final class NegocioAliadoGeo {
  NegocioAliadoGeo._();

  static String normalizarCiudad(String raw) {
    var t = raw.trim().toUpperCase();
    t = t.replaceAll(RegExp(r'[ÁÀÂÄ]'), 'A');
    t = t.replaceAll(RegExp(r'[ÉÈÊË]'), 'E');
    t = t.replaceAll(RegExp(r'[ÍÌÎÏ]'), 'I');
    t = t.replaceAll(RegExp(r'[ÓÒÔÖ]'), 'O');
    t = t.replaceAll(RegExp(r'[ÚÙÛÜ]'), 'U');
    t = t.replaceAll(RegExp(r'[^A-Z0-9\s]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  /// Origen y destino deben estar en el mismo pueblo del negocio.
  static bool viajeEsLocalEnPuebloNegocio({
    required String ciudadNegocio,
    required String origen,
    required String destino,
  }) {
    final c = normalizarCiudad(ciudadNegocio);
    if (c.isEmpty) return false;
    final o = normalizarCiudad(origen);
    final d = normalizarCiudad(destino);
    if (o.isEmpty || d.isEmpty) return false;
    return o.contains(c) && d.contains(c);
  }
}
