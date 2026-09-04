import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/cliente/cliente_mis_viajes_hub.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/seleccion_servicio.dart'
    show kTurismoClienteEnMantenimiento;
import 'package:flygo_nuevo/pantallas/comun/configuracion_perfil.dart';
import 'package:flygo_nuevo/pantallas/comun/soporte.dart';
import 'package:flygo_nuevo/servicios/cliente_verificacion_identidad_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/servicios/rai_asistente_kb.dart';

import 'package:flygo_nuevo/widgets/rai_asistente_sheet.dart';

/// Navegación desde acciones sugeridas del asistente (no altera flujos existentes).
class RaiAsistenteLauncher {
  RaiAsistenteLauncher._();

  /// Destino vía constructor de [ProgramarViaje] (sin estado global en RAM).
  static ProgramarViaje _programarViajeDesdeAsistente({
    String? tipoServicio,
    DetalleLugar? destino,
  }) {
    return ProgramarViaje(
      modoAhora: true,
      tipoServicio: tipoServicio,
      destinoPrecargado: destino?.displayLabel,
      latDestinoPrecargado: destino?.lat,
      lonDestinoPrecargado: destino?.lon,
    );
  }

  static Future<void> ejecutarAccion(
    BuildContext context,
    RaiAsistenteAction action, {
    DetalleLugar? destino,
  }) async {
    if (!context.mounted) return;

    switch (action) {
      case RaiAsistenteAction.openMotor:
        if (!await ClienteVerificacionIdentidadService.ensureVerificadoOMostrar(
          context,
        )) {
          return;
        }
        if (!context.mounted) return;
        await NavigationService.pushEnTabShell(
          context,
          _programarViajeDesdeAsistente(
            tipoServicio: 'motor',
            destino: destino,
          ),
        );
        break;
      case RaiAsistenteAction.openTaxi:
        if (!await ClienteVerificacionIdentidadService.ensureVerificadoOMostrar(
          context,
        )) {
          return;
        }
        if (!context.mounted) return;
        await NavigationService.pushEnTabShell(
          context,
          _programarViajeDesdeAsistente(destino: destino),
        );
        break;
      case RaiAsistenteAction.openTurismo:
        // El inicio ya frena turismo en mantenimiento; sin esto el asistente era
        // la puerta de atrás para crear solicitudes que nadie va a atender.
        if (kTurismoClienteEnMantenimiento) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Turismo está en mantenimiento. Muy pronto lo activamos.',
              ),
            ),
          );
          return;
        }
        if (!await ClienteVerificacionIdentidadService.ensureVerificadoOMostrar(
          context,
        )) {
          return;
        }
        if (!context.mounted) return;
        await NavigationService.pushEnTabShell(
          context,
          const ProgramarViaje(
            modoAhora: true,
            tipoServicio: 'turismo',
          ),
        );
        break;
      case RaiAsistenteAction.openSoporte:
        await NavigationService.pushEnTabShell(
          context,
          const Soporte(),
        );
        break;
      case RaiAsistenteAction.openMisViajes:
        await NavigationService.pushEnTabShell(
          context,
          const ClienteMisViajesHub(),
        );
        break;
      case RaiAsistenteAction.openPerfil:
        await NavigationService.pushEnTabShell(
          context,
          const ConfiguracionPerfil(),
        );
        break;
      case RaiAsistenteAction.none:
        if (destino != null) {
          if (!await ClienteVerificacionIdentidadService.ensureVerificadoOMostrar(
            context,
          )) {
            return;
          }
          if (!context.mounted) return;
          await NavigationService.pushEnTabShell(
            context,
            _programarViajeDesdeAsistente(destino: destino),
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
