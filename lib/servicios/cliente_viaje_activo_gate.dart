import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';

/// Evita que el cliente pida otro viaje mientras tiene uno pausado.
class ClienteViajeActivoGate {
  ClienteViajeActivoGate._();

  /// Tras «Volver a RAI» el viaje sigue activo pero el shell muestra el home.
  static bool get debeBloquearFlujosNuevoViaje =>
      ActiveTripService.debeForzarInicioClienteShell;

  /// `true` si puede continuar al flujo nuevo; `false` si se bloqueó o retomó.
  static Future<bool> intentarFlujoNuevoViaje(BuildContext context) async {
    if (!debeBloquearFlujosNuevoViaje) return true;
    if (!context.mounted) return false;

    final bool? retomar = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        icon: const Icon(Icons.local_taxi_rounded, color: Color(0xFF1B5E20)),
        title: const Text('Tenés un viaje en curso'),
        content: const Text(
          'No podés buscar otro conductor ni pedir un viaje nuevo '
          'mientras tu viaje actual sigue activo.\n\n'
          'Retomá tu viaje para seguir el recorrido o pagar con tarjeta.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Quedarme aquí'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Retomar viaje'),
          ),
        ],
      ),
    );

    if (retomar == true) {
      NavigationService.retomarViajeActivoCliente();
    }
    return false;
  }
}
