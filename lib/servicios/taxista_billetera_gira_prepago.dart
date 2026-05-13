/// Lecturas puras de `billeteras_taxista` para prepago de comisiones en **Giras por cupos**.
/// Sin importar [pool_repo] ni [pagos_taxista_repo] para evitar ciclos.
class TaxistaBilleteraGiraPrepago {
  TaxistaBilleteraGiraPrepago._();

  static double saldoPrepagoComisionRd(Map<String, dynamic>? data) {
    final v = data?['saldoPrepagoComisionRd'];
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  static double saldoReservadoParaGiras(Map<String, dynamic>? data) {
    final v = data?['saldoReservadoParaGiras'];
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  static double comisionesDescontadas(Map<String, dynamic>? data) {
    final v = data?['comisionesDescontadas'];
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  /// Saldo prepago libre para **nueva** reserva de gira (prepago − ya reservado en giras).
  static double saldoDisponibleParaReservarGira(Map<String, dynamic>? data) {
    final prep = saldoPrepagoComisionRd(data);
    final res = saldoReservadoParaGiras(data);
    return (prep - res).clamp(0.0, double.infinity);
  }

  /// Alias: mismo valor (viajes normales + giras comparten este “disponible”).
  static double saldoDisponiblePrepagoComisionRd(Map<String, dynamic>? data) =>
      saldoDisponibleParaReservarGira(data);
}
