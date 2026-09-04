import 'package:flutter/material.dart';

import 'package:flygo_nuevo/widgets/datos_transferencia_conductor_panel.dart';
import 'package:flygo_nuevo/widgets/datos_transferencia_rai_panel.dart';

/// UI transferencia en viajes taxi: el cliente paga al conductor.
/// Giras con recaudo central RAI usan pantallas propias (`pools_cliente_detalle`).
class TransferenciaRecaudoUi {
  TransferenciaRecaudoUi._();

  /// Siempre `false` en flujo viaje: la transferencia va a la cuenta del taxista.
  static bool viajeUsaRecaudoEnCuentaRai(Map<String, dynamic> viajeData) => false;

  static String referenciaDesdeViaje(Map<String, dynamic> viajeData) {
    return (viajeData['referenciaRecaudo'] ?? '').toString().trim();
  }

  static Widget panel({
    required Map<String, dynamic> viajeData,
    required String uidTaxista,
    required double montoRd,
    bool fondoOscuro = false,
    String? tituloConductor,
    String? tituloRai,
    Widget? footer,
  }) {
    if (viajeUsaRecaudoEnCuentaRai(viajeData)) {
      return DatosTransferenciaRaiPanel(
        viajeData: viajeData,
        montoRd: montoRd,
        fondoOscuro: fondoOscuro,
        titulo: tituloRai ?? 'PAGAR A RAI (TRANSFERENCIA)',
        footer: footer,
      );
    }
    return DatosTransferenciaConductorPanel(
      viajeData: viajeData,
      uidTaxista: uidTaxista,
      montoRd: montoRd,
      fondoOscuro: fondoOscuro,
      titulo: tituloConductor ?? 'DATOS PARA TRANSFERENCIA AL CONDUCTOR',
      footer: footer,
    );
  }
}
