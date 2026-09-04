// lib/servicios/negocio_aliado_geo.dart
//
// Promo gratis solo en el pueblo/ciudad del negocio aliado (no inter-pueblo).

import 'package:geocoding/geocoding.dart';

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

  static List<String> variantesCiudad(String ciudadNegocio) {
    final out = <String>[];
    for (final parte in ciudadNegocio.split(RegExp(r'[,/|;]'))) {
      final c = normalizarCiudad(parte);
      if (c.isNotEmpty && !out.contains(c)) out.add(c);
    }
    return out;
  }

  static String _textoUbicacionCompleto(String direccion, [String geoExtra = '']) {
    return normalizarCiudad('$direccion $geoExtra');
  }

  /// Texto geográfico (localidad/provincia) desde coordenadas para validar pueblo.
  static Future<String> geoTextoDesdeCoordenadas(double lat, double lon) async {
    try {
      final marks = await placemarkFromCoordinates(lat, lon);
      if (marks.isEmpty) return '';
      final p = marks.first;
      final partes = <String?>[
        p.locality,
        p.subLocality,
        p.subAdministrativeArea,
        p.administrativeArea,
        p.name,
      ];
      return normalizarCiudad(
        partes.where((s) => (s ?? '').trim().isNotEmpty).join(' '),
      );
    } catch (_) {
      return '';
    }
  }

  /// Origen y destino deben estar en el mismo pueblo del negocio.
  static bool viajeEsLocalEnPuebloNegocio({
    required String ciudadNegocio,
    required String origen,
    required String destino,
    String origenGeoExtra = '',
    String destinoGeoExtra = '',
  }) {
    final variantes = variantesCiudad(ciudadNegocio);
    if (variantes.isEmpty) return false;
    final o = _textoUbicacionCompleto(origen, origenGeoExtra);
    final d = _textoUbicacionCompleto(destino, destinoGeoExtra);
    if (o.isEmpty || d.isEmpty) return false;
    return variantes.any((c) => o.contains(c) && d.contains(c));
  }
}
