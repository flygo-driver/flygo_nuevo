// lib/servicios/pay_config.dart
//
// Datos bancarios en release: opcionalmente por --dart-define (CI) sin editar código:
//   --dart-define=RAI_PAY_BANK_NAME=...
//   --dart-define=RAI_PAY_ACCOUNT_TYPE=...
//   --dart-define=RAI_PAY_ACCOUNT_NUMBER=...
//   --dart-define=RAI_PAY_ACCOUNT_HOLDER=...
//   --dart-define=RAI_PAY_RNC=...
//
// Valores por defecto: los que ya usaba la app; verifica que coincidan con la cuenta real
// operativa antes de publicar en Play Console.

class PayConfig {
  /// Cuando la pasarela de tarjeta esté lista, pon `true` y aparecerá "Tarjeta".
  static const bool pagosConTarjetaHabilitados = false;

  static List<String> get metodosReservaVisibles => <String>[
        'Efectivo',
        'Transferencia',
        if (pagosConTarjetaHabilitados) 'Tarjeta',
      ];

  static const metodos = ['Transferencia', 'Efectivo'];

  static const String bankName = String.fromEnvironment(
    'RAI_PAY_BANK_NAME',
    defaultValue: 'Banco Popular Dominicano',
  );
  static const String accountType = String.fromEnvironment(
    'RAI_PAY_ACCOUNT_TYPE',
    defaultValue: 'Cuenta Corriente',
  );
  static const String accountNumber = String.fromEnvironment(
    'RAI_PAY_ACCOUNT_NUMBER',
    defaultValue: '789-123456-7',
  );
  static const String accountHolder = String.fromEnvironment(
    'RAI_PAY_ACCOUNT_HOLDER',
    defaultValue: 'Open ASK Service SRL',
  );
  static const String rnc = String.fromEnvironment(
    'RAI_PAY_RNC',
    defaultValue: '1320-11767',
  );

  static const reservaMinutos = 10;

  static const instrucciones =
      'Realiza la transferencia a la cuenta de RAI (Open ASK Service SRL) y sube el comprobante. '
      'Tu reserva quedará en revisión y, al validar, quedará “Pagada”.';

  static String referenciaSugerida(String poolId, String uid) =>
      'RAI-${poolId.substring(0, 6)}-${uid.substring(0, 6)}';
}
