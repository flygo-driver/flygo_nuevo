import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/post_viaje_cliente_flow.dart';
import 'package:flygo_nuevo/pantallas/comun/factura_viaje.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';

/// Cierre post-viaje del cliente: mismo orden que el taxista (comprobante → flujo).
class PostViajeClienteNav {
  PostViajeClienteNav._();

  /// Comprobante formal [FacturaViaje] y luego recibo + calificación.
  static Future<void> abrirFacturaYFlujo({
    BuildContext? context,
    required String viajeId,
    Map<String, dynamic>? viajeDataSemilla,
  }) async {
    final NavigatorState? nav = _navigator(context);
    if (nav == null || !nav.mounted) return;

    if (await CorporativoTaxistaService.debeOcultarEnAppClientePorId(
      viajeId,
      semilla: viajeDataSemilla,
    )) {
      return;
    }

    if (!nav.mounted) return;

    await FacturaViaje.mostrar(
      nav.context,
      viajeId: viajeId,
      role: 'cliente',
      autoCerrarAlContinuar: true,
    );
    if (!nav.mounted) return;

    await nav.push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PostViajeClienteFlow(
          viajeId: viajeId,
          viajeDataSemilla: viajeDataSemilla,
        ),
      ),
    );
  }

  static NavigatorState? _navigator(BuildContext? context) {
    final NavigatorState? fromKey = NavigationService.navigatorKey.currentState;
    if (fromKey != null && fromKey.mounted) return fromKey;
    if (context != null && context.mounted) {
      return Navigator.of(context, rootNavigator: true);
    }
    return null;
  }
}
