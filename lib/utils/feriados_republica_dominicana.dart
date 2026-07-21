/// Feriados oficiales de República Dominicana (actualizables por año).
///
/// Incluye fechas fijas + Viernes Santo / Corpus Christi (móviles).
/// Opcionalmente aplica el traslado a lunes cuando el feriado cae mar–jue
/// (práctica comercial RD / días no laborables extendidos).
abstract final class FeriadosRepublicaDominicana {
  FeriadosRepublicaDominicana._();

  /// Clave yyyy-MM-dd.
  static String clave(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime soloDia(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Pascua (algoritmo de Meeus/Jones/Butcher) → domingo de resurrección.
  static DateTime domingoPascua(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  /// Si aplica traslado comercial a lunes (feriado en mar/mié/jue).
  static DateTime observarSiAplica(DateTime d, {bool trasladar = true}) {
    if (!trasladar) return soloDia(d);
    // Dom=7 Lun=1 … Sáb=6 (DateTime.weekday)
    switch (d.weekday) {
      case DateTime.tuesday: // mar → lun anterior
        return soloDia(d.subtract(const Duration(days: 1)));
      case DateTime.wednesday: // mié → lun anterior
        return soloDia(d.subtract(const Duration(days: 2)));
      case DateTime.thursday: // jue → lun siguiente (vie-dom puente no)
        return soloDia(d.add(const Duration(days: 4)));
      default:
        return soloDia(d);
    }
  }

  static List<({DateTime fecha, String nombre, bool movil})> oficialesDelAno(
    int year, {
    bool trasladarALunes = false,
  }) {
    final pascua = domingoPascua(year);
    final viernesSanto = pascua.subtract(const Duration(days: 2));
    final corpus = pascua.add(const Duration(days: 60));

    DateTime f(int m, int d) => DateTime(year, m, d);

    final raw = <({DateTime fecha, String nombre, bool movil, bool traslada})>[
      (fecha: f(1, 1), nombre: 'Año Nuevo', movil: false, traslada: false),
      (fecha: f(1, 6), nombre: 'Día de Reyes', movil: false, traslada: true),
      (
        fecha: f(1, 21),
        nombre: 'Día de la Altagracia',
        movil: false,
        traslada: false,
      ),
      (fecha: f(1, 26), nombre: 'Día de Duarte', movil: false, traslada: true),
      (
        fecha: f(2, 27),
        nombre: 'Independencia Nacional',
        movil: false,
        traslada: false,
      ),
      (
        fecha: viernesSanto,
        nombre: 'Viernes Santo',
        movil: true,
        traslada: false,
      ),
      (fecha: f(5, 1), nombre: 'Día del Trabajo', movil: false, traslada: true),
      (fecha: corpus, nombre: 'Corpus Christi', movil: true, traslada: false),
      (
        fecha: f(8, 16),
        nombre: 'Día de la Restauración',
        movil: false,
        traslada: true,
      ),
      (
        fecha: f(9, 24),
        nombre: 'Nuestra Señora de las Mercedes',
        movil: false,
        traslada: false,
      ),
      (
        fecha: f(11, 6),
        nombre: 'Día de la Constitución',
        movil: false,
        traslada: true,
      ),
      (fecha: f(12, 25), nombre: 'Navidad', movil: false, traslada: false),
    ];

    return raw
        .map((e) {
          final fecha = e.traslada && trasladarALunes
              ? observarSiAplica(e.fecha)
              : soloDia(e.fecha);
          return (fecha: fecha, nombre: e.nombre, movil: e.movil);
        })
        .toList(growable: false);
  }

  /// Mapa yyyy-MM-dd → nombre, para [year-1, year, year+1] (se renueva solo).
  static Map<String, String> mapaClavesConNombre({
    DateTime? alrededorDe,
    bool trasladarALunes = false,
  }) {
    final base = alrededorDe ?? DateTime.now();
    final out = <String, String>{};
    for (final y in [base.year - 1, base.year, base.year + 1]) {
      for (final h in oficialesDelAno(y, trasladarALunes: trasladarALunes)) {
        out[clave(h.fecha)] = h.nombre;
      }
    }
    return out;
  }

  static Set<String> clavesOficiales({
    DateTime? alrededorDe,
    bool trasladarALunes = false,
  }) =>
      mapaClavesConNombre(
        alrededorDe: alrededorDe,
        trasladarALunes: trasladarALunes,
      ).keys.toSet();

  static String? nombreDe(DateTime d, {bool trasladarALunes = false}) =>
      mapaClavesConNombre(alrededorDe: d, trasladarALunes: trasladarALunes)[
          clave(d)];
}
