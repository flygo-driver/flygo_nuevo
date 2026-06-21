import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/utilidades/constante.dart' show rutaBolaPueblo;
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/pantallas/cliente/espera_asignacion_turismo.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_programado_confirmacion.dart';
import 'package:flygo_nuevo/utils/trip_publish_windows.dart';
import 'package:flygo_nuevo/widgets/cliente_pantalla_viaje_activo.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/shell/cliente_shell.dart';
import 'package:flygo_nuevo/shell/taxista_shell.dart';

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

  /// Tablero Bola Ahorro a pantalla completa (stack limpio).
  static Future<void> clearAndGoBolaTablero({NavigatorState? preNav}) async {
    final NavigatorState? nav = preNav ?? navigatorKey.currentState;
    if (nav == null || !nav.mounted) return;
    await nav.pushNamedAndRemoveUntil<void>(
      rutaBolaPueblo,
      (Route<dynamic> r) => false,
    );
  }

  /// Flecha atrás en pantallas Bola: vuelve al tablero de negociación.
  static void popOrGoBolaTablero(BuildContext context) {
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    unawaited(
      clearAndGoBolaTablero(
        preNav: Navigator.of(context, rootNavigator: true),
      ),
    );
  }

  /// Salir del modo viaje Bola hacia el home del flavor (post-factura / cancelación).
  static Future<void> salirModoViajeBola(BuildContext context) async {
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    final NavigatorState rootNav =
        Navigator.of(context, rootNavigator: true);

    if (isConductorFlavor) {
      await rootNav.pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const TaxistaShell()),
        (Route<dynamic> r) => false,
      );
      return;
    }

    if (isClienteFlavor) {
      if (rootNav.canPop()) {
        rootNav.pop();
        return;
      }
      await rootNav.pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const ClienteShell()),
        (Route<dynamic> r) => false,
      );
      return;
    }

    if (rootNav.canPop()) {
      rootNav.pop();
      return;
    }
    await clearAndGoBolaTablero(preNav: rootNav);
  }

  /// Home del taxista tras cerrar viaje Bola / factura / modo mapa.
  static Future<void> irAlInicioTaxista({BuildContext? context}) async {
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    NavigatorState? nav = navigatorKey.currentState;
    if ((nav == null || !nav.mounted) &&
        context != null &&
        context.mounted) {
      nav = Navigator.of(context, rootNavigator: true);
    }
    if (nav == null || !nav.mounted) return;
    await nav.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => const TaxistaShell()),
      (Route<dynamic> r) => false,
    );
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

  /// Misma rama que [ProgramarViaje] tras `crearViajePendiente`: ahora → en curso;
  /// programado lejano → espera; turismo → asignación o en curso si ya hay chofer.
  ///
  /// [forzarViajeInmediato]: tab «Ahora» / motor (paradas múltiples) — no mandar a programado
  /// aunque falle la heurística de fecha.
  static Future<void> navegarTrasCrearViajeCliente({
    required String viajeId,
    required DateTime fechaHoraPickup,
    String tipoServicio = 'normal',
    NavigatorState? preNav,
    bool forzarViajeInmediato = false,
  }) async {
    final DateTime nowUtc = DateTime.now().toUtc();
    final DateTime pickupUtc = fechaHoraPickup.toUtc();
    final bool viajeInmediato = forzarViajeInmediato ||
        TripPublishWindows.esProgramadoRecogidaCasiInmediata(pickupUtc, nowUtc) ||
        TripPublishWindows.esAhoraPorFechaPickup(
          pickupUtc,
          DateTime.now(),
        );

    final String tipo = tipoServicio.trim().toLowerCase();

    if (!viajeInmediato) {
      await clearAndGoPage(
        preNav: preNav,
        page: ViajeProgramadoConfirmacion(
          viajeId: viajeId,
          fechaHoraPickup: fechaHoraPickup,
        ),
      );
      return;
    }

    if (tipo == 'turismo') {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance.collection('viajes').doc(viajeId).get();
      final Map<String, dynamic> d = snap.data() ?? <String, dynamic>{};
      final bool choferAsignado =
          (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim().isNotEmpty;
      if (choferAsignado) {
        await clearAndGoViajeEnCursoCliente(preNav: preNav);
      } else {
        await clearAndGoPage(
          preNav: preNav,
          page: EsperaAsignacionTurismo(viajeId: viajeId),
        );
      }
      return;
    }

    await clearAndGoViajeEnCursoCliente(preNav: preNav);
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

  /// Tras acordar Bola: espera `viajeActivoId` + espejo operativo en el cliente.
  static Future<bool> esperarViajeEspejoBolaCliente({
    required String viajeId,
    required String uidCliente,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final String vid = viajeId.trim();
    final String uid = uidCliente.trim();
    if (vid.isEmpty || uid.isEmpty) return false;
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final DocumentSnapshot<Map<String, dynamic>> userSnap =
            await FirebaseFirestore.instance
                .collection('usuarios')
                .doc(uid)
                .get(const GetOptions(source: Source.server));
        final String activoId =
            (userSnap.data()?['viajeActivoId'] ?? '').toString().trim();
        if (activoId != vid) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        final DocumentSnapshot<Map<String, dynamic>> vSnap =
            await FirebaseFirestore.instance
                .collection('viajes')
                .doc(vid)
                .get(const GetOptions(source: Source.server));
        if (!vSnap.exists) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        final Map<String, dynamic> d = vSnap.data() ?? <String, dynamic>{};
        final String uidCli =
            (d['uidCliente'] ?? d['clienteId'] ?? '').toString().trim();
        final String st =
            EstadosViaje.normalizar((d['estado'] ?? '').toString());
        if (uidCli == uid &&
            d['activo'] == true &&
            EstadosViaje.activos.contains(st)) {
          return true;
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
