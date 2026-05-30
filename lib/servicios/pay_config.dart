// lib/servicios/pay_config.dart
//
// Datos bancarios de depósito a RAI: [RecargaBancariaConfig] es la fuente única.
// Override opcional en CI con --dart-define=RAI_PAY_* (si el define está vacío, usa recarga).
//
//   --dart-define=RAI_PAY_BANK_NAME=...
//   --dart-define=RAI_PAY_ACCOUNT_TYPE=...
//   --dart-define=RAI_PAY_ACCOUNT_NUMBER=...
//   --dart-define=RAI_PAY_ACCOUNT_HOLDER=...
//   --dart-define=RAI_PAY_RNC=...

import 'package:flygo_nuevo/config/recarga_bancaria_config.dart';

class PayConfig {
  /// Cuando la pasarela de tarjeta esté lista, pon `true` y aparecerá "Tarjeta".
  static const bool pagosConTarjetaHabilitados = false;

  static List<String> get metodosReservaVisibles => <String>[
        'Efectivo',
        'Transferencia',
        if (pagosConTarjetaHabilitados) 'Tarjeta',
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
}
