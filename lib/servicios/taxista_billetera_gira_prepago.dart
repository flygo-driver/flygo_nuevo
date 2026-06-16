import 'package:flygo_nuevo/servicios/comision_prepago_config_service.dart';

/// Lecturas puras de `billeteras_taxista` para prepago de comisiones en **Giras por cupos**.
/// Sin importar [pool_repo] ni [pagos_taxista_repo] para evitar ciclos.
class TaxistaBilleteraGiraPrepago {
  TaxistaBilleteraGiraPrepago._();

  static const double _umbralComisionLegacyBloqueoRd = 500;

  static double comisionPendienteLegacyRd(Map<String, dynamic>? data) {
    final v = data?['comisionPendiente'];
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  static bool primerViajeComisionGratisConsumido(Map<String, dynamic>? data) {
    return data?['primerViajeComisionGratisConsumido'] == true;
  }

  /// Misma regla que el pool al tomar viajes ([PagosTaxistaRepo.bloqueoOperativoPorComisionEfectivo]).
  static bool bloqueoOperativoComoPool({
    Map<String, dynamic>? billetera,
    Map<String, dynamic>? usuario,
  }) {
    if (usuario != null && usuario['tienePagoPendiente'] == true) return true;
    final pend = comisionPendienteLegacyRd(billetera);
    if (pend >= _umbralComisionLegacyBloqueoRd - 1e-6) return true;
    if (pend > 1e-6) return false;
    if (!primerViajeComisionGratisConsumido(billetera)) return false;
    final double minimo = ComisionPrepagoConfigService.minimoOperativoRd;
    return saldoDisponiblePrepagoComisionRd(billetera) + 1e-9 < minimo;
  }

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
