import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/finance_config_service.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/widgets/datos_transferencia_conductor_panel.dart';
import 'package:flygo_nuevo/widgets/datos_transferencia_rai_panel.dart';

/// UI transferencia: cuenta RAI + referencia (Fase 5) vs cuenta conductor (legacy).
class TransferenciaRecaudoUi {
  TransferenciaRecaudoUi._();

  static bool viajeUsaRecaudoEnCuentaRai(Map<String, dynamic> viajeData) {
    final ref = (viajeData['referenciaRecaudo'] ?? '').toString().trim();
    if (ref.isNotEmpty) return true;
    final destino = (viajeData['recaudoDestino'] ?? '').toString().trim().toLowerCase();
    if (destino == 'rai') return true;
    return FinanceConfigService.transferenciaRecaudoEnCuentaRai &&
        MetodoPagoViaje.esTransferencia(viajeData['metodoPago']?.toString());
  }

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
