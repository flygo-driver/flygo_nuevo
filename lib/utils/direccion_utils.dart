import 'dart:math';

class DireccionUtils {
  /// Resume una dirección larga tipo “inDrive”.
  /// - Quita saltos de línea
  /// - Reemplaza “República Dominicana/Dominican Republic/RD” por “RD”
  /// - Mantiene las 3–4 primeras partes y corta con “…” si excede [max]
  static String resumir(String raw,
      {int max = 60, int maxPartes = 4, bool quitarPais = true}) {
    if (raw.trim().isEmpty) return '';

    String s =
        raw.replaceAll('\n', ' ').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    // Normalizaciones comunes
    s = s
        .replaceAll(RegExp(r'Dominican Republic', caseSensitive: false), 'RD')
        .replaceAll(
            RegExp(r'Rep(ú|u)blica Dominicana', caseSensitive: false), 'RD')
        .replaceAll(RegExp(r',?\s*RD$', caseSensitive: false), ', RD')
        .replaceAll(RegExp(r'\bSto\.?\s*Dgo\.?\b', caseSensitive: false),
            'Santo Domingo')
        .replaceAll(RegExp(r'Higuey', caseSensitive: false), 'Higüey')
        .replaceAll(RegExp(r'San Pedro de Macoris', caseSensitive: false),
            'San Pedro de Macorís');

    // Partes por coma
    final partes =
        s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    // Opcional: quitar el país si es RD para acortar
    if (quitarPais && partes.isNotEmpty) {
      final last = partes.last.toLowerCase();
      if (last == 'rd' || last.contains('república dominicana')) {
        partes.removeLast();
      }
    }

    final tomadas = partes.take(min(maxPartes, partes.length)).toList();
    final String out = tomadas.join(', ');

    if (out.length <= max) return out;
    return '${out.substring(0, max).trimRight()}…';
  }

  /// Texto amigable para fecha/hora compacta.
  /// Ej: "hoy 16:56", "mañana 09:10", "18/09 16:56"
  static String fechaCorta(DateTime dt) {
    final now = DateTime.now();
    final hoy = DateTime(now.year, now.month, now.day);
    final f = DateTime(dt.year, dt.month, dt.day);

    final String hhmm = '${_two(dt.hour)}:${_two(dt.minute)}';
    if (f == hoy) return 'hoy $hhmm';
    if (f == hoy.add(const Duration(days: 1))) return 'mañana $hhmm';
    return '${_two(dt.day)}/${_two(dt.month)} $hhmm';
  }

  /// Diferencia hasta [dt] en lenguaje corto: "en 2d 3h", "en 45m", "ya"
  static String hasta(DateTime dt) {
    final now = DateTime.now();
    final Duration d = dt.difference(now);
    if (d.inMinutes <= 0) return 'ya';

    final dias = d.inDays;
    final horas = d.inHours % 24;
    final mins = d.inMinutes % 60;

    if (dias > 0) return 'en ${dias}d ${horas}h';
    if (horas > 0) return 'en ${horas}h ${mins}m';
    return 'en ${mins}m';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
