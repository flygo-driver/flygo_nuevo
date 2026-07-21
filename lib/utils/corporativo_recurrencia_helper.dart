/// Patrones de repetición para rutas corporativas fijas.
abstract final class CorporativoPatronRecurrencia {
  CorporativoPatronRecurrencia._();

  static const String lunVie = 'lun_vie';
  static const String interdiaria = 'interdiaria';
  static const String diario = 'diario';
  static const String personalizado = 'personalizado';

  static const List<String> todos = [lunVie, interdiaria, diario, personalizado];

  static String etiqueta(String patron) {
    switch (patron) {
      case lunVie:
        return 'Lunes a viernes';
      case interdiaria:
        return 'Interdiaria (día sí / día no)';
      case diario:
        return 'Todos los días';
      case personalizado:
        return 'Días personalizados';
      default:
        return patron;
    }
  }

  /// Día ISO: 1=lunes … 7=domingo.
  static int diaSemanaIso(DateTime d) {
    final w = d.weekday;
    return w;
  }

  static DateTime soloFecha(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static int diasEntre(DateTime a, DateTime b) {
    return soloFecha(b).difference(soloFecha(a)).inDays;
  }

  static bool coincideHoy({
    required String patron,
    required List<int> diasSemana,
    DateTime? fechaAnclaInterdiaria,
    DateTime? hoy,
  }) {
    final now = hoy ?? DateTime.now();
    switch (patron) {
      case lunVie:
        final d = diaSemanaIso(now);
        return d >= 1 && d <= 5;
      case diario:
        return true;
      case interdiaria:
        final ancla = fechaAnclaInterdiaria ?? now;
        final diff = diasEntre(soloFecha(ancla), soloFecha(now));
        return diff >= 0 && diff % 2 == 0;
      case personalizado:
        return diasSemana.contains(diaSemanaIso(now));
      default:
        return diasSemana.contains(diaSemanaIso(now));
    }
  }

  static List<int> diasEfectivos(String patron, List<int> diasSemana) {
    switch (patron) {
      case lunVie:
        return [1, 2, 3, 4, 5];
      case diario:
        return [1, 2, 3, 4, 5, 6, 7];
      case interdiaria:
        return diasSemana.isEmpty ? [1, 2, 3, 4, 5] : diasSemana;
      default:
        return diasSemana.isEmpty ? [1, 2, 3, 4, 5] : diasSemana;
    }
  }
}
