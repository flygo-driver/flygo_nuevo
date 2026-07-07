import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/cliente_verificacion_identidad_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';

/// Navegación a flujos de pedir viaje con verificación de identidad si corresponde.
abstract final class ClienteViajeNavegacion {
  ClienteViajeNavegacion._();

  static Future<void> pushTrasVerificacion(
    BuildContext context,
    Widget page,
  ) async {
    final ok =
        await ClienteVerificacionIdentidadService.ensureVerificadoOMostrar(
      context,
    );
    if (!ok || !context.mounted) return;
    await NavigationService.pushEnTabShell(context, page);
  }
}
