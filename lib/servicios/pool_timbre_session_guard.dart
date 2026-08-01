import 'dart:async';

import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/servicios/push_service.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';

/// Sesión activa pasajero vs conductor (app Play unificada `com.flygo.rd2`).
/// El timbre del pool **solo** suena con sesión conductor explícita (opt-in).
abstract final class PoolTimbreSessionGuard {
  static bool _conductorSesionActiva = false;

  /// APK conductor: siempre puede sonar. Play unificada: solo con shell taxista abierto.
  static bool get timbrePoolPermitido {
    if (isClienteFlavor) return false;
    if (isConductorFlavor) return true;
    return _conductorSesionActiva;
  }

  static bool get debeSuprimirPoolTimbre => !timbrePoolPermitido;

  static void activarSesionPasajero() {
    _conductorSesionActiva = false;
    NotificationService.I.suprimirTimbrePoolCliente(
      duracion: const Duration(hours: 8),
    );
    unawaited(PushService.refreshForegroundPresentationOptions());
    unawaited(NotificationService.I.stopTimbre());
  }

  static void activarSesionConductor() {
    _conductorSesionActiva = true;
    unawaited(PushService.refreshForegroundPresentationOptions());
  }

  static Future<void> sincronizarRol(String uid) async {
    final String? rol = await RolesService.getRol(uid);
    if (rol == Roles.cliente) {
      activarSesionPasajero();
    } else if (rol == Roles.taxista) {
      activarSesionConductor();
    }
  }
}
