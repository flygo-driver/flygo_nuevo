import 'package:flutter/material.dart';

import 'package:flygo_nuevo/widgets/cliente_pantalla_viaje_activo.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/shell/cliente_shell.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static Future<T?> push<T>(Widget page) {
    final nav = navigatorKey.currentState;
    if (nav == null) return Future.value(null);
    return nav.push(MaterialPageRoute(builder: (_) => page));
  }

  static Future<T?> replaceWith<T>(Widget page) {
    final nav = navigatorKey.currentState;
    if (nav == null) return Future.value(null);
    return nav.pushReplacement(MaterialPageRoute(builder: (_) => page));
  }

  static Future<T?> pushNamed<T>(String routeName, {Object? args}) {
    final nav = navigatorKey.currentState;
    if (nav == null) return Future.value(null);
    return nav.pushNamed<T>(routeName, arguments: args);
  }

  static void pop<T extends Object?>([T? result]) {
    final nav = navigatorKey.currentState;
    if (nav?.canPop() ?? false) nav!.pop(result);
  }

  static Future<void> clearAndGo(Widget page) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    await nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => page),
      (route) => false,
    );
  }

  /// Tras crear viaje (p. ej. multiparadas): mismo destino que [ProgramarViaje].
  /// [preNav] se captura **antes** del `await` a Firestore; si el formulario se
  /// desmonta al actualizar `viajeActivoId`, el push sigue con ese navigator.
  static Future<void> clearAndGoViajeEnCursoCliente({NavigatorState? preNav}) async {
    final NavigatorState? nav = preNav ?? navigatorKey.currentState;
    if (nav == null || !nav.mounted) return;
    await nav.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        builder: (_) => const ClientePantallaViajeActivo(),
      ),
      (Route<dynamic> r) => false,
    );
  }

  /// Home del cliente tras cancelar / sin viaje activo (multiparadas, en curso, etc.).
  /// No usar [intentarSalirAlGate] aquí: con navigator anidado o una sola ruta en la pila
  /// no vuelve al [ClienteShell].
  static Future<void> irAlInicioCliente({BuildContext? context}) async {
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    NavigatorState? nav = navigatorKey.currentState;
    if ((nav == null || !nav.mounted) &&
        context != null &&
        context.mounted) {
      nav = Navigator.of(context, rootNavigator: true);
    }
    if (nav == null || !nav.mounted) return;
    await nav.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => const ClienteShell()),
      (Route<dynamic> r) => false,
    );
  }

  /// Misma navegación que [cerrarSesion]: stack limpio y [AuthGatePublic] decide login/home.
  static Future<void> clearToAuthGate() async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    await nav.pushNamedAndRemoveUntil('/auth_check', (Route<dynamic> r) => false);
  }
}
