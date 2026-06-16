/// Parámetros económicos de RAI: % de comisión nominal en viajes estándar (efectivo / pool).
/// El valor efectivo de [comisionViajePorcentaje] se sincroniza desde Firestore (`config/comision`)
/// vía [ComisionViajePctService]; las partidas definitivas de cada viaje siguen siendo
/// `precio_cents` / `comision_cents` en Firestore.
class PlataformaEconomia {
  PlataformaEconomia._();

  static double _comisionViajePct = 20;
  static double _comisionGiraPct = 20;

  /// Porcentaje global (0–100) usado en cotización y comisión en efectivo estándar.
  static double get comisionViajePorcentaje => _comisionViajePct;

  /// Comisión RAI sobre **Giras por cupos** (`viajes_pool`): mismo % que [comisionViajePorcentaje]
  /// (`config/comision`; legacy `comision_gira_porcentaje` solo si falta config/comision).
  static double get comisionGiraPorcentaje => _comisionGiraPct;

  static double get factorComisionGira => _comisionGiraPct / 100.0;

  /// Entero redondeado (etiquetas simples). Preferir [comisionViajePorcentaje] en cálculos.
  static int get comisionPorcento => _comisionViajePct.round();

  static void syncComisionViajePorcentajeFromRemote(double p) {
    if (!p.isFinite) return;
    if (p < 0 || p > 100) return;
    _comisionViajePct = p;
  }

  static void syncComisionGiraPorcentajeFromRemote(double p) {
    if (!p.isFinite) return;
    if (p < 0 || p > 100) return;
    _comisionGiraPct = p;
  }

  /// Obsoleto: el cliente unifica con [comisionViajePorcentaje] en espejo Bola (`comisionPorcentaje` en doc).
  static const int comisionPorcentoBolaEspejo = 10;

  static double get factorComision => _comisionViajePct / 100.0;

  /// Etiqueta UI: `20%` o `10.5%`.
  static String etiquetaPorcentajeComision() {
    final p = _comisionViajePct;
    if (p == p.roundToDouble()) return '${p.round()}%';
    return '${p.toStringAsFixed(1)}%';
  }

  /// Etiqueta UI ganancia del conductor (100 − comisión plataforma).
  static String etiquetaPorcentajeGananciaTaxista() {
    final g = (100.0 - _comisionViajePct).clamp(0.0, 100.0);
    if (g == g.roundToDouble()) return '${g.round()}%';
    return '${g.toStringAsFixed(1)}%';
  }

  static String etiquetaComisionRai({String prefijo = 'Comisión RAI'}) =>
      '$prefijo (${etiquetaPorcentajeComision()})';

  /// Redondeo half-up en centavos: comisión desde precio en centavos y % entero (legacy).
  static int comisionCentsDesdePrecioCents(
    int precioCents,
    int porcentoEntero,
  ) =>
      ((precioCents * porcentoEntero) + 50) ~/ 100;

  /// Comisión nominal en centavos alineada con backend: `round2(totalRd * pct/100)`.
  static int comisionViajeCentsDesdePrecioCents(int precioCents) {
    return comisionViajeCentsDesdePrecioCentsConPct(
      precioCents,
      _comisionViajePct,
    );
  }

  static int comisionViajeCentsDesdePrecioCentsConPct(
    int precioCents,
    double pct,
  ) {
    final totalRd = precioCents / 100.0;
    final comisionRd = double.parse(
      (totalRd * (pct / 100.0)).toStringAsFixed(2),
    );
    return (comisionRd * 100).round();
  }

  static double comisionRdDesdeTotal(double total) =>
      comisionRdDesdeTotalConPct(total, _comisionViajePct);

  static double comisionRdDesdeTotalConPct(double total, double pct) =>
      double.parse((total * (pct / 100.0)).toStringAsFixed(2));

  static double gananciaTaxistaRdDesdeTotal(double total) =>
      double.parse((total - comisionRdDesdeTotal(total)).toStringAsFixed(2));

  static Map<String, double> comisionYGananciaDesdePrecio(double precioTotal) {
    final comision = comisionRdDesdeTotal(precioTotal);
    final ganancia = double.parse((precioTotal - comision).toStringAsFixed(2));
    return <String, double>{
      'comision': comision,
      'gananciaTaxista': ganancia,
    };
  }
}
