import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/cliente/cliente_mis_viajes_hub.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/solicitar_motor_rai.dart';
import 'package:flygo_nuevo/pantallas/comun/configuracion_perfil.dart';
import 'package:flygo_nuevo/pantallas/comun/soporte.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/servicios/rai_asistente_destino_pendiente.dart';
import 'package:flygo_nuevo/servicios/rai_asistente_kb.dart';

import 'package:flygo_nuevo/widgets/rai_asistente_sheet.dart';

/// Navegación desde acciones sugeridas del asistente (no altera flujos existentes).
class RaiAsistenteLauncher {
  RaiAsistenteLauncher._();

  static Future<void> ejecutarAccion(
    BuildContext context,
    RaiAsistenteAction action, {
    DetalleLugar? destino,
  }) async {
    if (destino != null) {
      RaiAsistenteDestinoPendiente.guardar(destino);
    }

    if (!context.mounted) return;

    switch (action) {
      case RaiAsistenteAction.openMotor:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SolicitarMotorRai()),
        );
        break;
      case RaiAsistenteAction.openTaxi:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProgramarViaje(
              modoAhora: true,
              destinoPrecargado: destino?.displayLabel,
              latDestinoPrecargado: destino?.lat,
              lonDestinoPrecargado: destino?.lon,
            ),
          ),
        );
        break;
      case RaiAsistenteAction.openTurismo:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ProgramarViaje(
              modoAhora: true,
              tipoServicio: 'turismo',
            ),
          ),
        );
        break;
      case RaiAsistenteAction.openSoporte:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const Soporte()),
        );
        break;
      case RaiAsistenteAction.openMisViajes:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ClienteMisViajesHub()),
        );
        break;
      case RaiAsistenteAction.openPerfil:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ConfiguracionPerfil()),
        );
        break;
      case RaiAsistenteAction.none:
        if (destino != null) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProgramarViaje(
                modoAhora: true,
                destinoPrecargado: destino.displayLabel,
                latDestinoPrecargado: destino.lat,
                lonDestinoPrecargado: destino.lon,
              ),
            ),
          );
        }
        break;
    }
  }

  static Future<void> abrirAsistente(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const RaiAsistenteSheet(),
    );
  }
}
