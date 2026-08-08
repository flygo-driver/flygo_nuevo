// lib/servicios/negocio_aliado_codigo.dart

/// Genera código único legible para QR (ej. LA-CENA-SDN).
abstract final class NegocioAliadoCodigo {
  NegocioAliadoCodigo._();

  static String generarDesdeNombreCiudad({
    required String nombre,
    required String ciudad,
  }) {
    final parts = <String>[
      _slugPart(nombre, maxLen: 12),
      if (ciudad.trim().isNotEmpty) _slugPart(ciudad, maxLen: 6),
    ].where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'NEGOCIO';
    return parts.join('-');
  }

  static String normalizar(String raw) {
    final t = raw.trim().toUpperCase();
    if (t.isEmpty) return '';
    final buf = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      final ch = t[i];
      if (RegExp(r'[A-Z0-9]').hasMatch(ch)) {
        buf.write(ch);
      } else if (ch == '-' || ch == '_' || ch == ' ') {
        if (buf.isNotEmpty && buf.toString().endsWith('-')) continue;
        buf.write('-');
      }
    }
    var out = buf.toString();
    while (out.contains('--')) {
      out = out.replaceAll('--', '-');
    }
    out = out.replaceAll(RegExp(r'^-+|-+$'), '');
    return out.length > 32 ? out.substring(0, 32) : out;
  }

  static String _slugPart(String raw, {required int maxLen}) {
    final norm = raw
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (norm.isEmpty) return '';
    final joined = norm.take(3).join('-');
    return joined.length > maxLen ? joined.substring(0, maxLen) : joined;
  }
}
