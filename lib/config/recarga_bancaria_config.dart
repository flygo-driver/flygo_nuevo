/// Cuenta corporativa RAI (Open ASK Service SRL) — recargas prepago y recaudo.
/// Fuente única empresa: depósitos taxista, bloqueo, factura recaudo, Mis pagos.
/// Los datos bancarios **del conductor** (transferencias de pasajeros) viven en
/// `usuarios/{uid}` vía [ConfiguracionBancaria], no aquí.
class RecargaBancariaConfig {
  RecargaBancariaConfig._();

  static const String titular = 'Open ASK Service SRL';
  static const String nombreLegal = titular;
  static const String banco = 'Banco Popular';
  static const String tipoCuenta = 'Cuenta Corriente';
  static const String numeroCuenta = '787726249';
  static const String rnc = '1320-11767';

  static const String notaRecarga =
      'Depósito a Open ASK Service SRL (RAI). Cuenta corriente Banco Popular. '
      'En concepto indique su nombre de conductor o la referencia que aparece en Mis pagos.';

  /// Resumen corto para UI de giras / reservas cliente.
  static const String resumenCuentaCliente =
      'Open ASK Service SRL · Banco Popular · Cuenta Corriente · $numeroCuenta';

  /// Mapa para `app_config/pagos` en Firestore (admin / seed).
  static Map<String, dynamic> toFirestoreMap() => {
        'banco_nombre': banco,
        'tipo_cuenta': tipoCuenta,
        'numero_cuenta': numeroCuenta,
        'titular': titular,
        'rnc': rnc,
        'alias': '',
        'nota': notaRecarga,
        'qr_url': '',
        'whatsapp_soporte': '',
      };
}
