/// Semana ISO (año-Www) en hora civil República Dominicana (UTC-4 fijo).
class PeriodoIsoSemana {
  final int isoYear;
  final int isoWeek;

  const PeriodoIsoSemana({required this.isoYear, required this.isoWeek});

  String get etiqueta =>
      '$isoYear-W${isoWeek.toString().padLeft(2, '0')}';

  static DateTime _utcFromRd(int y, int m, int d, {int h = 12}) {
    return DateTime.utc(y, m, d, h).add(const Duration(hours: 4));
  }

  static ({int y, int m, int d}) _rdParts(DateTime utc) {
    final local = utc.add(const Duration(hours: -4));
    return (y: local.year, m: local.month, d: local.day);
  }

  /// Semana ISO a partir de una fecha UTC (p. ej. [finalizadoEn] del viaje).
  factory PeriodoIsoSemana.desdeFechaUtc(DateTime utc) {
    final p = _rdParts(utc);
    final target = _utcFromRd(p.y, p.m, p.d);
    final day = target.weekday == DateTime.sunday ? 7 : target.weekday;
    final thursday = target.add(Duration(days: 4 - day));
    final isoYear = thursday.year;
    final yearStart = DateTime.utc(isoYear, 1, 1);
    final isoWeek =
        ((thursday.difference(yearStart).inDays + 1) / 7).ceil().clamp(1, 53);
    return PeriodoIsoSemana(isoYear: isoYear, isoWeek: isoWeek);
  }

  /// Semana ISO anterior a hoy (RD).
  factory PeriodoIsoSemana.semanaAnteriorRd() {
    final now = DateTime.now().toUtc();
    final p = _rdParts(now);
    final hoy = _utcFromRd(p.y, p.m, p.d);
  final prev = hoy.subtract(const Duration(days: 7));
    return PeriodoIsoSemana.desdeFechaUtc(prev);
  }

  /// Últimas [n] semanas incluyendo la anterior.
  static List<PeriodoIsoSemana> ultimasSemanas(int n) {
    final base = PeriodoIsoSemana.semanaAnteriorRd();
    final out = <PeriodoIsoSemana>[base];
    var cur = base;
    for (var i = 1; i < n; i++) {
      var w = cur.isoWeek - 1;
      var y = cur.isoYear;
      if (w < 1) {
        y -= 1;
        w = 52;
      }
      cur = PeriodoIsoSemana(isoYear: y, isoWeek: w);
      out.add(cur);
    }
    return out;
  }
}
