import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/widgets/cliente_pantalla_viaje_activo.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
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

  /// Igual que [clearAndGo] con [preNav] capturado antes de un `await` largo.
  static Future<void> clearAndGoPage({
    required Widget page,
    NavigatorState? preNav,
  }) async {
    final NavigatorState? nav = preNav ?? navigatorKey.currentState;
    if (nav == null || !nav.mounted) return;
    await nav.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => page),
      (Route<dynamic> r) => false,
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

  /// Tras aceptar viaje en pool: pantalla completa [ViajeEnCursoTaxista].
  static Future<void> clearAndGoViajeEnCursoTaxista({NavigatorState? preNav}) async {
    // Siempre el navigator raíz del [MaterialApp]: el de la pestaña Recibir es anidado
    // y un pushAndRemoveUntil ahí no abre viaje en curso a pantalla completa.
    for (int intento = 0; intento < 6; intento++) {
      NavigatorState? nav = navigatorKey.currentState;
      if (nav == null || !nav.mounted) {
        nav = preNav;
      }
      if (nav != null && nav.mounted) {
        await nav.pushNamedAndRemoveUntil<void>(
          '/viaje_en_curso_taxista',
          (Route<dynamic> r) => false,
        );
        print(
          '[VIAJE_ACTIVO] clearAndGoViajeEnCursoTaxista ok intento=$intento',
        );
        return;
      }
      await Future<void>.delayed(Duration(milliseconds: 40 * (intento + 1)));
    }
    print('[VIAJE_ACTIVO] clearAndGoViajeEnCursoTaxista sin navigator montado');
  }

  /// Espera a que el viaje quede asignado al taxista en servidor (evita flicker del shell).
  static Future<bool> esperarViajeAsignadoAlTaxista({
    required String viajeId,
    required String uidTaxista,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final String vid = viajeId.trim();
    final String uid = uidTaxista.trim();
    if (vid.isEmpty || uid.isEmpty) return false;
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final DocumentSnapshot<Map<String, dynamic>> snap =
            await FirebaseFirestore.instance
                .collection('viajes')
                .doc(vid)
                .get(const GetOptions(source: Source.server));
        if (snap.exists) {
          final Map<String, dynamic> d = snap.data() ?? <String, dynamic>{};
          final String tx =
              (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();
          final String st =
              EstadosViaje.normalizar((d['estado'] ?? '').toString());
          if (tx == uid &&
              d['activo'] == true &&
              EstadosViaje.activos.contains(st)) {
            return true;
          }
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return false;
  }

  /// Tras «Aceptar viaje»: abre viaje en curso al instante (navigator raíz); la espera
  /// de Firestore corre en paralelo para que [ViajeEnCursoTaxista] tenga el doc listo.
  static Future<void> irAViajeEnCursoTaxistaTrasAceptar({
    required String viajeId,
    required String uidTaxista,
    NavigatorState? preNav,
  }) async {
    ActiveTripService.bloquearShellTaxistaTrasAceptar(
      const Duration(minutes: 3),
    );
    await clearAndGoViajeEnCursoTaxista(preNav: preNav);
    unawaited(
      esperarViajeAsignadoAlTaxista(
        viajeId: viajeId,
        uidTaxista: uidTaxista,
      ),
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
