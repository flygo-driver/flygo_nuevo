import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/finance_config_service.dart';

/// Bloqueo temporal de cobro con tarjeta hasta credenciales AZUL en producción.
abstract final class PagoTarjetaClienteGate {
  PagoTarjetaClienteGate._();

  static const String titulo = 'Pago con tarjeta en desarrollo';
  static const String mensaje =
      'Estamos en desarrollo con el banco. Por ahora pagá con efectivo '
      'o transferencia bancaria.';

  /// `true` = mostrar aviso y no abrir pasarela AZUL.
  static const bool bloqueado = true;

  /// Muestra la opción Tarjeta en UI aunque aún no esté activa en el banco.
  static bool get mostrarOpcionTarjeta =>
      bloqueado || FinanceConfigService.pagosConTarjetaAzulHabilitados;

  /// Cobro real AZUL solo si remoto ON y no bloqueado por desarrollo.
  static bool get cobroHabilitado =>
      !bloqueado && FinanceConfigService.pagosConTarjetaAzulHabilitados;

  static Future<void> avisarEnDesarrollo(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(titulo),
        content: const Text(mensaje),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  /// `true` si puede continuar con tarjeta (cobro o cambio de método).
  static Future<bool> permitirAccionTarjeta(BuildContext context) async {
    if (!bloqueado) return true;
    await avisarEnDesarrollo(context);
    return false;
  }
}
