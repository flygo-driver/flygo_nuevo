/// Parámetros económicos de RAI: una sola fuente para el % de comisión nominal.
/// Las partidas definitivas de cada viaje siguen siendo `precio_cents` / `comision_cents` en Firestore.
class PlataformaEconomia {
  PlataformaEconomia._();

  /// Comisión RAI sobre el precio del viaje (pool, normal, motor, turismo estándar).
  static const int comisionPorcento = 20;

  /// Espejo Bola / negociación pueblo (alineado con [ViajesRepo.crearViajePendiente]).
  static const int comisionPorcentoBolaEspejo = 10;

  static double get factorComision => comisionPorcento / 100.0;

  /// Redondeo half-up en centavos: comisión desde precio en centavos y % entero.
  static int comisionCentsDesdePrecioCents(
    int precioCents,
    int porcentoEntero,
  ) =>
      ((precioCents * porcentoEntero) + 50) ~/ 100;

  static double comisionRdDesdeTotal(double total) =>
      double.parse((total * factorComision).toStringAsFixed(2));

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
