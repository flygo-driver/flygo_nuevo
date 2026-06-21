import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/comun/factura_viaje.dart';
import 'package:flygo_nuevo/pantallas/taxista/post_viaje_taxista_flow.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';

/// Cierre post-viaje taxista: mismo orden global que cliente (comprobante → flujo).
class PostViajeTaxistaNav {
  PostViajeTaxistaNav._();

  static Future<void> abrirFacturaYFlujo({
    BuildContext? context,
    required String viajeId,
    required String uidTaxista,
    Map<String, dynamic>? viajeDataSemilla,
  }) async {
    final NavigatorState? nav = _navigator(context);
    if (nav == null || !nav.mounted) return;

    await FacturaViaje.mostrar(
      nav.context,
      viajeId: viajeId,
      role: 'taxista',
      autoCerrarAlContinuar: true,
    );
    if (!nav.mounted) return;

    await nav.push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PostViajeTaxistaFlow(
          viajeId: viajeId,
          uidTaxista: uidTaxista,
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
