// lib/servicios/pay_config.dart
//
// Datos bancarios de depósito a RAI: [RecargaBancariaConfig] es la fuente única.
// Métodos visibles y flags de pasarela: [FinanceConfigService] (config/finance).

import 'package:flygo_nuevo/config/recarga_bancaria_config.dart';
import 'package:flygo_nuevo/servicios/finance_config_service.dart';
import 'package:flygo_nuevo/utils/viaje_referencia_recaudo.dart';

class PayConfig {
  /// Legacy compile-time; preferir [tarjetaHabilitada] (remote flag).
  static const bool pagosConTarjetaHabilitados = false;

  static bool get tarjetaHabilitada =>
      FinanceConfigService.pagosConTarjetaAzulHabilitados;

  static List<String> get metodosReservaVisibles => <String>[
        'Efectivo',
        'Transferencia',
        if (tarjetaHabilitada) 'Tarjeta',
      ];

  static const metodos = ['Transferencia', 'Efectivo'];

  static String _fromEnvOr(String key, String fallback) {
    final v = String.fromEnvironment(key);
    return v.trim().isNotEmpty ? v.trim() : fallback;
  }

  static String get bankName =>
      _fromEnvOr('RAI_PAY_BANK_NAME', RecargaBancariaConfig.banco);

  static String get accountType =>
      _fromEnvOr('RAI_PAY_ACCOUNT_TYPE', RecargaBancariaConfig.tipoCuenta);

  static String get accountNumber =>
      _fromEnvOr('RAI_PAY_ACCOUNT_NUMBER', RecargaBancariaConfig.numeroCuenta);

  static String get accountHolder =>
      _fromEnvOr('RAI_PAY_ACCOUNT_HOLDER', RecargaBancariaConfig.titular);

  static String get rnc => _fromEnvOr('RAI_PAY_RNC', RecargaBancariaConfig.rnc);

  static const reservaMinutos = 10;

  static const instrucciones =
      'Realiza la transferencia a la cuenta de RAI (Open ASK Service SRL) y sube el comprobante. '
      'Tu reserva quedará en revisión y, al validar, quedará “Pagada”.';

  static String referenciaSugerida(String poolId, String uid) =>
      'RAI-${poolId.substring(0, 6)}-${uid.substring(0, 6)}';

  /// Referencia única por viaje (generada en servidor cuando flag ON).
  static String referenciaViaje(String viajeId) =>
      ViajeReferenciaRecaudo.generar(viajeId);
}
