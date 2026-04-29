// lib/servicios/pay_config.dart
class PayConfig {
  /// Cuando la pasarela de tarjeta esté lista (p. ej. en ~1 mes), pon `true` y
  /// aparecerá "Tarjeta" en reserva / selección de método. Backend ya contempla
  /// `pendiente_pago` para viajes con método tarjeta.
  static const bool pagosConTarjetaHabilitados = false;

  /// Orden sugerido en bottom sheets de reserva (sin tarjeta hasta activar [pagosConTarjetaHabilitados]).
  static List<String> get metodosReservaVisibles => <String>[
        'Efectivo',
        'Transferencia',
        if (pagosConTarjetaHabilitados) 'Tarjeta',
      ];

  // ✅ MOSTRAR SOLO ESTOS MÉTODOS EN TODA LA APP
  static const metodos = ['Transferencia', 'Efectivo'];

  // ✅ CUENTA FLYGO (Rellena con tus datos reales)
  static const bankName = 'Banco Popular Dominicano';
  static const accountType = 'Cuenta Corriente';
  static const accountNumber = '789-123456-7'; // ← CAMBIAR
  static const accountHolder = 'FLYGO GO, SRL'; // ← CAMBIAR
  static const rnc = '1-31-98765-4'; // ← CAMBIAR

  // Tiempo de “bloqueo” de cupo mientras el cliente hace la transferencia
  static const reservaMinutos = 10;

  // Texto fijo que verán al pagar
  static const instrucciones =
      'Realiza la transferencia a la cuenta de FlyGo y sube el comprobante. '
      'Tu reserva quedará en revisión y, al validar, quedará “Pagada”.';

  // Referencia sugerida que el cliente puede poner en la transferencia
  static String referenciaSugerida(String poolId, String uid) =>
      'FLYGO-${poolId.substring(0, 6)}-${uid.substring(0, 6)}';
}
