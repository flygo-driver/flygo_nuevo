import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/utilidades/constante.dart' show rutaBolaPueblo;
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/navegacion/taxista_finanzas_nav.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_programado_confirmacion.dart';
import 'package:flygo_nuevo/utils/trip_publish_windows.dart';
import 'package:flygo_nuevo/pantallas/taxista/corporativo_ruta_detalle_informativo_page.dart';
import 'package:flygo_nuevo/pantallas/taxista/mis_rutas_corporativas_page.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/cliente_shell_nav_bridge.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/rai_local_read_cache.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/shell/cliente_shell.dart';
import 'package:flygo_nuevo/shell/taxista_shell.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';
import 'package:flygo_nuevo/widgets/shell_tab_nav.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Alias de [ActiveTripService.kOverlayClienteViajeActivo] (fuente única).
  static const Duration kOverlayClienteViajeActivo =
      ActiveTripService.kOverlayClienteViajeActivo;

  static Future<T?> push<T>(Widget page) {
    final nav = navigatorKey.currentState;
    if (nav == null) return Future.value(null);
    return nav.push(MaterialPageRoute(builder: (_) => page));
  }

  /// Módulos con barra inferior propia (p. ej. Corporativo RAI): cubren el shell
  /// para no apilar dos [NavigationBar] (shell + módulo).
  static Future<T?> pushModuloConBarraPropia<T>(
    BuildContext context,
    Widget page,
  ) {
    if (!context.mounted) return Future.value(null);
    return Navigator.of(context, rootNavigator: true)
        .push<T>(MaterialPageRoute<T>(builder: (_) => page));
  }

  /// Pantallas de flujo dentro del shell (programar, motor, etc.): usa el
  /// navigator del tab activo para mantener **una** barra inferior.
  /// [push] en el raíz tapa el shell; apilar otro shell en un tab duplica la barra.
  static Future<T?> pushEnTabShell<T>(BuildContext context, Widget page) {
    if (!context.mounted) return Future.value(null);
    final NavigatorState tabNav = Navigator.of(context);
    final NavigatorState rootNav =
        Navigator.of(context, rootNavigator: true);
    ActiveTripService.entrarClienteFlujoSolicitudViaje();
    Future<T?> navegar() {
      if (!identical(tabNav, rootNav) && tabNav.mounted) {
        return tabNav.push<T>(MaterialPageRoute<T>(builder: (_) => page));
      }
      return push<T>(page);
    }
    return navegar().whenComplete(() {
      ActiveTripService.salirClienteFlujoSolicitudViaje();
    });
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

  /// Sale de Mis rutas corporativas (push normal o shell si vino de clearAndGo).
  static void salirMisRutasCorporativas(BuildContext context) {
    final NavigatorState root = Navigator.of(context, rootNavigator: true);
    if (root.canPop()) {
      root.pop();
      return;
    }
    unawaited(
      root.pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const TaxistaShell()),
        (Route<dynamic> r) => false,
      ),
    );
  }

  /// Navigator del tab del shell (o raíz si no hay anidado).
  static ({NavigatorState? tab, NavigatorState? raiz})
      capturarNavigadoresFormulario(BuildContext context) {
    if (!context.mounted) {
      final NavigatorState? r = navigatorKey.currentState;
      return (tab: r, raiz: r);
    }
    final NavigatorState tab = Navigator.of(context);
    final NavigatorState root =
        Navigator.of(context, rootNavigator: true);
    if (identical(tab, root)) {
      return (tab: root, raiz: root);
    }
    return (tab: tab, raiz: root);
  }

  /// Vacía la pila del tab activo del [ClienteShell] (programar, turismo, etc.).
  static void _vaciarPilaTabShellSiAnidada(BuildContext? context) {
    if (context == null || !context.mounted) return;
    final NavigatorState tabNav = Navigator.of(context);
    final NavigatorState rootNav =
        Navigator.of(context, rootNavigator: true);
    if (!identical(tabNav, rootNav) && tabNav.mounted) {
      while (tabNav.canPop()) {
        tabNav.pop();
      }
    }
  }

  static bool _contextoTieneClienteShell(BuildContext? context) {
    if (context == null || !context.mounted) return false;
    return context.findAncestorWidgetOfExactType<ClienteShell>() != null ||
        context.findAncestorWidgetOfExactType<ClienteShellWithDeepLink>() !=
            null;
  }

  static Future<bool> _remontarClienteShell(NavigatorState nav) async {
    if (!nav.mounted) return false;
    await nav.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        builder: (_) => const ClienteShellWithDeepLink(),
      ),
      (Route<dynamic> r) => false,
    );
    ActiveTripService.notificarRebuildShell();
    return true;
  }

  static NavigatorState? navigatorRaiz({BuildContext? context}) {
    if (context != null && context.mounted) {
      return Navigator.of(context, rootNavigator: true);
    }
    return navigatorKey.currentState;
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

  static Future<void> _remontarShellTrasBola({
    required NavigatorState rootNav,
    required bool esTaxista,
  }) async {
    if (!rootNav.mounted) return;
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    if (esTaxista) {
      ShellTabController.taxistaIrARecibir();
      await rootNav.pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const TaxistaShell()),
        (Route<dynamic> r) => false,
      );
    } else {
      ShellTabController.clienteIrAInicio();
      await rootNav.pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(
            builder: (_) => const ClienteShellWithDeepLink()),
        (Route<dynamic> r) => false,
      );
    }
    ActiveTripService.notificarRebuildShell();
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

  /// Taxista: sale del tablero Bola (mapa completo o pestaña COMPARTIDOS) sin
  /// cancelar ofertas ni viajes activos.
  static Future<void> salirVistaBolaTaxista(
    BuildContext context, {
    String? faseViaje,
    String? bolaId,
  }) async {
    final NavigatorState root =
        Navigator.of(context, rootNavigator: true);
    ShellTabController.taxistaIrARecibir();
    final bool viajeOperativo =
        faseViaje == 'acordada' || faseViaje == 'en_curso';
    if (!viajeOperativo) {
      ShellTabController.taxistaIrAPoolAhora();
    }
    if (!root.canPop()) {
      await _remontarShellTrasBola(rootNav: root, esTaxista: true);
      ActiveTripService.notificarRebuildShell();
      return;
    }
    root.pop();
    ActiveTripService.notificarRebuildShell();
  }

  /// Cliente: sale del tablero Bola (mapa, conductores en ruta, etc.) sin
  /// cancelar pedidos ni viajes activos.
  static Future<void> salirVistaBolaCliente(BuildContext context) async {
    final NavigatorState root =
        Navigator.of(context, rootNavigator: true);
    ShellTabController.clienteIrAInicio();

    if (!root.canPop()) {
      await _remontarShellTrasBola(rootNav: root, esTaxista: false);
      return;
    }

    root.pop();
    _vaciarPilaTabShellSiAnidada(context);
  }

  /// Salir del modo viaje Bola hacia el home del flavor (post-factura / cancelación).
  static Future<void> salirModoViajeBola(
    BuildContext context, {
    bool? esTaxista,
  }) async {
    final NavigatorState rootNav =
        Navigator.of(context, rootNavigator: true);
    final bool tx = esTaxista ?? false;

    if (isConductorFlavor) {
      await _remontarShellTrasBola(rootNav: rootNav, esTaxista: true);
      return;
    }

    if (isClienteFlavor) {
      if (!rootNav.canPop()) {
        await _remontarShellTrasBola(rootNav: rootNav, esTaxista: false);
        return;
      }
      rootNav.pop();
      return;
    }

    // App unificada Play (`com.flygo.rd2`): volver al shell según rol actual.
    if (!rootNav.canPop()) {
      await _remontarShellTrasBola(rootNav: rootNav, esTaxista: tx);
      return;
    }
    rootNav.pop();
  }

  /// Tras cerrar ruta corporativa (factura / cierre): tab Trabajo + Mis rutas.
  static Future<void> irAMisRutasCorporativasTrasCierre({
    BuildContext? context,
  }) async {
    ShellTabController.taxistaIrATrabajo();
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    ActiveTripService.cancelarBloqueoShellTaxista();
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
    final NavigatorState? nav2 = navigatorKey.currentState;
    if (nav2 != null && nav2.mounted) {
      await nav2.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const MisRutasCorporativasPage(),
        ),
      );
    }
    ActiveTripService.notificarRebuildShell();
  }

  /// Home del taxista tras cerrar viaje Bola / factura / modo mapa.
  static Future<void> irAlInicioTaxista({
    BuildContext? context,
    String? viajeIdCompletado,
  }) async {
    _cerrarCapasPostViajeEnNavigator(navigatorKey.currentState);
    if (context != null && context.mounted) {
      _cerrarCapasPostViajeEnNavigator(
        Navigator.of(context, rootNavigator: true),
      );
    }
    await ActiveTripService.prepararSalidaTaxistaAlInicio(
      viajeIdCompletado: viajeIdCompletado,
    );
    ShellTabController.taxistaIrARecibir();
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
    ActiveTripService.notificarRebuildShell();
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

  /// Si el navigator raíz ya está en home (cliente/taxista shell), solo activa
  /// overlay — no remonta el árbol (evita pantalla “forzada” y lentitud).
  static Future<bool> _activarOverlayORemontarShell({
    required NavigatorState nav,
    required Widget shell,
  }) async {
    if (!nav.mounted) return false;
    // Ya en la raíz: overlay basta (caso normal: aceptó desde pestaña Recibir
    // o cliente ya estaba en «viaje en curso» buscando chofer).
    if (!nav.canPop()) {
      ActiveTripService.notificarRebuildShell();
      return true;
    }
    await nav.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => shell),
      (Route<dynamic> r) => false,
    );
    ActiveTripService.notificarRebuildShell();
    return true;
  }

  /// Tras crear viaje (p. ej. multiparadas): mismo destino que [ProgramarViaje].
  ///
  /// Preferimos overlay en el [ClienteShell] ya montado. Remontar solo si hay
  /// rutas encima (pago, deep link suelto, etc.).
  static Future<void> clearAndGoViajeEnCursoCliente({
    NavigatorState? preNav,
    bool forzarReabrir = false,
  }) async {
    if (!forzarReabrir && ActiveTripService.clientePostViajeEnHome) {
      print(
        '[VIAJE_ACTIVO] clearAndGoViajeEnCursoCliente omitido (post-viaje en home)',
      );
      return;
    }
    if (forzarReabrir) {
      ActiveTripService.cancelarForzarInicioClienteShell();
    }
    ActiveTripService.restablecerClienteFlujoSolicitudViaje();
    ActiveTripService.mantenerOverlayViajeEnShell(kOverlayClienteViajeActivo);
    ActiveTripService.notificarRebuildShell();

    for (int intento = 0; intento < 6; intento++) {
      NavigatorState? nav = navigatorKey.currentState;
      if (nav == null || !nav.mounted) {
        nav = preNav;
      }
      if (nav != null && nav.mounted) {
        final bool ok = await _activarOverlayORemontarShell(
          nav: nav,
          shell: const ClienteShellWithDeepLink(),
        );
        if (ok) {
          ActiveTripService.mantenerOverlayViajeEnShell(
            kOverlayClienteViajeActivo,
          );
          ActiveTripService.notificarRebuildShell();
          print(
            '[VIAJE_ACTIVO] clearAndGoViajeEnCursoCliente → overlay/shell '
            'intento=$intento',
          );
          return;
        }
      }
      await Future<void>.delayed(
        Duration(milliseconds: 80 * (intento + 1)),
      );
    }
    print('[VIAJE_ACTIVO] clearAndGoViajeEnCursoCliente sin navigator montado');
  }

  /// Misma rama que [ProgramarViaje] tras `crearViajePendiente`: ahora → overlay;
  /// programado lejano → confirmación en tab; turismo → mismo overlay (espera pool
  /// o en curso según [ClientePantallaViajeActivo]).
  ///
  /// [forzarViajeInmediato]: tab «Ahora» / motor (paradas múltiples) — no mandar a programado
  /// aunque falle la heurística de fecha.
  static Future<void> navegarTrasCrearViajeCliente({
    required String viajeId,
    required DateTime fechaHoraPickup,
    String tipoServicio = 'normal',
    NavigatorState? preNav,
    NavigatorState? preNavRaiz,
    bool forzarViajeInmediato = false,
    /// Tras tocar «Confirmar viaje»: vacía el tab del formulario y fuerza overlay.
    bool abrirEnCursoAlConfirmar = false,
  }) async {
    final DateTime nowUtc = DateTime.now().toUtc();
    final DateTime pickupUtc = fechaHoraPickup.toUtc();
    final bool viajeInmediato = forzarViajeInmediato ||
        TripPublishWindows.esProgramadoRecogidaCasiInmediata(pickupUtc, nowUtc) ||
        TripPublishWindows.esAhoraPorFechaPickup(
          pickupUtc,
          DateTime.now(),
        );

    final NavigatorState? raiz =
        preNavRaiz ?? navigatorKey.currentState ?? preNav;

    ActiveTripService.cancelarForzarInicioClienteShell();
    unawaited(ActiveTripService.prepararModeloViajePegadoCliente(
      FirebaseAuth.instance.currentUser?.uid ?? '',
    ));

    if (!viajeInmediato) {
      // Reserva futura: confirmación en tab, sin banner ni overlay de viaje activo.
      ActiveTripService.liberarReservaProgramadaLejanaEnHome(viajeId: viajeId);
      await clearAndGoPage(
        preNav: preNav ?? raiz,
        page: ViajeProgramadoConfirmacion(
          viajeId: viajeId,
          fechaHoraPickup: fechaHoraPickup,
        ),
      );
      return;
    }

    ActiveTripService.liberarReservaProgramadaLejanaEnHome();
    ActiveTripService.registrarViajeOperativoCliente(viajeId);
    ActiveTripService.restablecerClienteFlujoSolicitudViaje();

    await _abrirOverlayViajeEnCursoCliente(
      preNav: raiz,
      forzarReabrir: abrirEnCursoAlConfirmar,
    );
  }

  /// Motor, tab «Ahora» y turismo (catálogo): vacía el formulario y abre overlay.
  static Future<void> navegarTrasConfirmarViajeInmediatoCliente({
    required String viajeId,
    required DateTime fechaHoraPickup,
    NavigatorState? preNav,
    NavigatorState? preNavRaiz,
  }) {
    return navegarTrasCrearViajeCliente(
      viajeId: viajeId,
      fechaHoraPickup: fechaHoraPickup,
      preNav: preNav,
      preNavRaiz: preNavRaiz,
      forzarViajeInmediato: true,
      abrirEnCursoAlConfirmar: true,
    );
  }

  static Future<void> _abrirOverlayViajeEnCursoCliente({
    NavigatorState? preNav,
    bool forzarReabrir = false,
  }) async {
    if (forzarReabrir) {
      ClienteShellNavBridge.popAllTabRoutes();
      ShellTabController.clienteIrAInicio();
    }
    await clearAndGoViajeEnCursoCliente(
      preNav: preNav,
      forzarReabrir: forzarReabrir,
    );
  }

  /// Tras aceptar viaje en pool: pantalla completa [ViajeEnCursoTaxista].
  ///
  /// Si ya estás en el [TaxistaShell] (aceptar desde Recibir), solo overlay —
  /// no remonta el árbol (antes se sentía lento / “forzado”). Remonta solo
  /// si hay rutas encima del shell.
  static Future<bool> clearAndGoViajeEnCursoTaxista({NavigatorState? preNav}) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      final String? corpId =
          await CorporativoTaxistaService.idViajeCorporativoOperativoParaChofer(
        uid,
      );
      if (corpId != null && corpId.isNotEmpty) {
        ActiveTripService.cancelarMantenimientoOverlayViaje();
        ActiveTripService.cancelarBloqueoShellTaxista();
        await ViajesRepo.limpiarViajeActivoSiNoOperativo(uid);
        await RaiLocalReadCache.clearActiveTripId(uid);
        final bool poolEnCurso =
            await ActiveTripService.usuarioTieneViajeEnSeguimiento(uid);
        if (!poolEnCurso) {
          print(
            '[VIAJE_ACTIVO] clearAndGoViajeEnCursoTaxista → corp activo, '
            'sin overlay (usar Rutas corporativas)',
          );
          ActiveTripService.notificarRebuildShell();
          return false;
        }
      }
    }

    ActiveTripService.bloquearShellTaxistaTrasAceptar(const Duration(minutes: 3));
    ActiveTripService.notificarRebuildShell();

    for (int intento = 0; intento < 6; intento++) {
      NavigatorState? nav = navigatorKey.currentState;
      if (nav == null || !nav.mounted) {
        nav = preNav;
      }
      if (nav != null && nav.mounted) {
        final bool ok = await _activarOverlayORemontarShell(
          nav: nav,
          shell: const TaxistaShell(),
        );
        if (ok) {
          ActiveTripService.bloquearShellTaxistaTrasAceptar(
            const Duration(minutes: 3),
          );
          ActiveTripService.notificarRebuildShell();
          print(
            '[VIAJE_ACTIVO] clearAndGoViajeEnCursoTaxista → overlay/shell '
            'intento=$intento',
          );
          return true;
        }
      }
      await Future<void>.delayed(Duration(milliseconds: 40 * (intento + 1)));
    }
    print('[VIAJE_ACTIVO] clearAndGoViajeEnCursoTaxista sin navigator montado');
    ActiveTripService.notificarRebuildShell();
    return false;
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

  /// Espera a que el viaje sea visible en [ViajeEnCursoTaxista] (pool o corporativo).
  static Future<bool> esperarViajeVisibleTaxistaEnCurso({
    required String viajeId,
    required String uidTaxista,
    Duration timeout = const Duration(seconds: 12),
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
          if (ViajesRepo.viajeVisibleEnCursoTaxista(d, uid)) {
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

  /// Tras «Aceptar viaje»: overlay al instante. La confirmación en Firestore
  /// corre en segundo plano (no bloquea la UI hasta 8s).
  static Future<void> irAViajeEnCursoTaxistaTrasAceptar({
    required String viajeId,
    required String uidTaxista,
    NavigatorState? preNav,
  }) async {
    ActiveTripService.bloquearShellTaxistaTrasAceptar(
      const Duration(minutes: 3),
      viajeId: viajeId,
    );
    final bool navego = await clearAndGoViajeEnCursoTaxista(preNav: preNav);
    if (!navego) {
      ActiveTripService.notificarRebuildShell();
    }
    // No await largo aquí: el stream del shell/viaje pinta en cuanto
    // claim escribe uidTaxista. Revalidamos en background.
    unawaited(() async {
      await esperarViajeAsignadoAlTaxista(
        viajeId: viajeId,
        uidTaxista: uidTaxista,
        timeout: const Duration(seconds: 6),
      );
      ActiveTripService.notificarRebuildShell();
    }());
  }

  /// Cliente: al asignarse conductor, abre viaje en curso si aún no está ahí.
  static Future<void> irAViajeEnCursoClienteTrasAsignacionTaxista({
    NavigatorState? preNav,
  }) async {
    ActiveTripService.mantenerOverlayViajeEnShell(const Duration(seconds: 90));
    final NavigatorState? nav = preNav ?? navigatorKey.currentState;
    if (nav == null || !nav.mounted) {
      ActiveTripService.notificarRebuildShell();
      return;
    }
    await clearAndGoViajeEnCursoCliente(preNav: nav);
    ActiveTripService.notificarRebuildShell();
  }

  /// Home del cliente tras cancelar / sin viaje activo (multiparadas, en curso, etc.).
  /// No usar [intentarSalirAlGate] aquí: con navigator anidado o una sola ruta en la pila
  /// no vuelve al [ClienteShell].
  /// [forzarLimpiarViajeActivo]: tras post-viaje o cierre turismo; evita que el shell
  /// reabra espera turismo con `viajeActivoId` obsoleto.
  /// Si es `false`, el viaje sigue activo en servidor (pausa temporal → banner retomar).
  static Future<void> irAlInicioCliente({
    BuildContext? context,
    String? viajeId,
    bool forzarLimpiarViajeActivo = false,
    bool omitirGuardOperativo = false,
    /// Cuando [activarPausaVoluntariaClienteShell] ya fijó el gate de pausa.
    bool omitirForzarInicioShell = false,
  }) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    final String vidLimpieza = (viajeId ?? '').trim();

    // Post-viaje / turismo cerrado: descartar el viaje en RAM antes de quitar
    // el gate de home; si no, un frame re-monta ViajeEnCurso (spinner infinito).
    if (forzarLimpiarViajeActivo && vidLimpieza.isNotEmpty) {
      ActiveTripService.liberarClienteTrasCancelacionOViajeTerminal(vidLimpieza);
    }

    if (!omitirForzarInicioShell) {
      if (!forzarLimpiarViajeActivo) {
        ActiveTripService.forzarInicioClienteShell(
          duracion: const Duration(hours: 24),
        );
      }
    }

    if (uid != null && uid.trim().isNotEmpty) {
      if (forzarLimpiarViajeActivo && vidLimpieza.isNotEmpty) {
        await ActiveTripService.liberarClienteTrasViajeEliminado(
          vidLimpieza,
          uid: uid.trim(),
        );
      }
      await ActiveTripService.prepararSalidaClienteAlInicio(
        uid: uid,
        viajeId: viajeId,
        forzarLimpieza: forzarLimpiarViajeActivo,
      );
      if (forzarLimpiarViajeActivo) {
        await _limpiarViajeActivoClienteEnServidor(uid.trim());
      }
    } else {
      ActiveTripService.cancelarMantenimientoOverlayViaje();
    }

    ShellTabController.clienteIndex.value = 0;

    for (int intento = 0; intento < 6; intento++) {
      NavigatorState? nav = navigatorKey.currentState;
      if ((nav == null || !nav.mounted) &&
          context != null &&
          context.mounted) {
        nav = Navigator.of(context, rootNavigator: true);
      }
      if (nav != null && nav.mounted) {
        // Pantallas dentro del tab (ProgramarViaje, EsperaAsignacionTurismo, etc.)
        // viven en un navigator anidado: vaciarlo antes del rebuild en raíz.
        _vaciarPilaTabShellSiAnidada(context);
        ClienteShellNavBridge.popAllTabRoutes();

        // Ya en ClienteShell en raíz: rebuild basta. Si la ruta actual es otra
        // (p. ej. ViajeProgramadoConfirmacion a pantalla completa), remontar shell.
        if (!nav.canPop()) {
          final BuildContext? navCtx = nav.context;
          if (_contextoTieneClienteShell(navCtx)) {
            ActiveTripService.notificarRebuildShell();
            print(
              '[VIAJE_ACTIVO] irAlInicioCliente → shell en raíz, rebuild sin remontar',
            );
            return;
          }
          await _remontarClienteShell(nav);
          print(
            '[VIAJE_ACTIVO] irAlInicioCliente → shell remontado (ruta no-shell)',
          );
          return;
        }
        await nav.pushAndRemoveUntil<void>(
          MaterialPageRoute<void>(
            builder: (_) => const ClienteShellWithDeepLink(),
          ),
          (Route<dynamic> r) => false,
        );
        if (!omitirForzarInicioShell && !forzarLimpiarViajeActivo) {
          ActiveTripService.forzarInicioClienteShell();
        }
        ActiveTripService.notificarRebuildShell();
        print('[VIAJE_ACTIVO] irAlInicioCliente → shell remontado');
        return;
      }
      await Future<void>.delayed(
        Duration(milliseconds: 80 * (intento + 1)),
      );
    }
    print('[VIAJE_ACTIVO] irAlInicioCliente sin navigator montado');
  }

  /// Salida urgente tras post-viaje o error global: limpia viaje activo y vuelve al home.
  static Future<void> volverAlInicioClienteUrgente({
    BuildContext? context,
    String? viajeId,
  }) async {
    _cerrarCapasPostViajeEnNavigator(navigatorKey.currentState);
    if (context != null && context.mounted) {
      _cerrarCapasPostViajeEnNavigator(
        Navigator.of(context, rootNavigator: true),
      );
    }
    await irAlInicioCliente(
      context: context,
      viajeId: viajeId,
      forzarLimpiarViajeActivo: true,
    );
  }

  /// Quita factura/recibo/post-viaje del stack raíz sin tocar el shell base.
  static void _cerrarCapasPostViajeEnNavigator(NavigatorState? nav) {
    if (nav == null || !nav.mounted) return;
    for (int i = 0; i < 6 && nav.canPop(); i++) {
      nav.pop();
    }
  }

  /// Reserva programada lejana: pantalla de confirmación dentro del tab Inicio.
  static Future<void> abrirConfirmacionProgramadoEnShell({
    required String viajeId,
    DateTime? fechaHoraPickup,
    NavigatorState? preNav,
  }) async {
    ActiveTripService.liberarReservaProgramadaLejanaEnHome(viajeId: viajeId);
    ShellTabController.clienteIrAInicio();
    ClienteShellNavBridge.popAllTabRoutes();
    final Widget page = ViajeProgramadoConfirmacion(
      viajeId: viajeId,
      fechaHoraPickup: fechaHoraPickup,
    );
    if (ClienteShellNavBridge.canPushOnInicioTab) {
      ActiveTripService.entrarClienteFlujoSolicitudViaje();
      return ClienteShellNavBridge.pushOnInicioTab<void>(page).whenComplete(() {
        ActiveTripService.salirClienteFlujoSolicitudViaje();
      });
    }
    NavigatorState? nav = preNav ?? navigatorKey.currentState;
    if (nav != null && nav.mounted) {
      await nav.push<void>(
        MaterialPageRoute<void>(builder: (_) => page),
      );
    }
  }

  /// Sale de la confirmación de reserva programada al home del cliente.
  static Future<void> salirReservaProgramadaAlInicioCliente({
    String? viajeId,
    bool forzarLimpiarViajeActivo = false,
    BuildContext? context,
  }) async {
    final String vid = (viajeId ?? '').trim();

    if (forzarLimpiarViajeActivo) {
      ActiveTripService.forzarInicioClienteShell();
    } else {
      ActiveTripService.liberarReservaProgramadaLejanaEnHome(viajeId: vid);
    }

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.trim().isNotEmpty) {
      await ActiveTripService.prepararSalidaClienteAlInicio(
        uid: uid,
        viajeId: vid.isNotEmpty ? vid : null,
        forzarLimpieza: forzarLimpiarViajeActivo,
      );
      if (forzarLimpiarViajeActivo) {
        await _limpiarViajeActivoClienteEnServidor(uid.trim());
      }
    } else {
      ActiveTripService.cancelarMantenimientoOverlayViaje();
    }

    ShellTabController.clienteIrAInicio();
    ClienteShellNavBridge.popAllTabRoutes();

    if (context != null && context.mounted) {
      _vaciarPilaTabShellSiAnidada(context);
      try {
        final NavigatorState tabNav = Navigator.of(context);
        final NavigatorState rootNav =
            Navigator.of(context, rootNavigator: true);
        if (!identical(tabNav, rootNav) && tabNav.mounted && tabNav.canPop()) {
          tabNav.pop();
          ActiveTripService.notificarRebuildShell();
          print(
            '[VIAJE_ACTIVO] salirReservaProgramadaAlInicioCliente → pop tab',
          );
          return;
        }
      } catch (_) {}
    }

    for (int intento = 0; intento < 6; intento++) {
      NavigatorState? nav = navigatorKey.currentState;
      if ((nav == null || !nav.mounted) &&
          context != null &&
          context.mounted) {
        nav = Navigator.of(context, rootNavigator: true);
      }
      if (nav != null && nav.mounted) {
        if (!nav.canPop() && _contextoTieneClienteShell(nav.context)) {
          ActiveTripService.notificarRebuildShell();
          print(
            '[VIAJE_ACTIVO] salirReservaProgramadaAlInicioCliente → rebuild shell',
          );
          return;
        }
        await _remontarClienteShell(nav);
        print(
          '[VIAJE_ACTIVO] salirReservaProgramadaAlInicioCliente → shell remontado',
        );
        return;
      }
      await Future<void>.delayed(
        Duration(milliseconds: 80 * (intento + 1)),
      );
    }
    print('[VIAJE_ACTIVO] salirReservaProgramadaAlInicioCliente sin navigator');
  }

  /// Reabre el shell taxista tras recarga AZUL (deep link o resume).
  static Future<void> retomarTaxistaTrasRecargaAzul({
    String? recargaId,
  }) async {
    await irAlInicioTaxista();
    final NavigatorState? nav = navigatorKey.currentState;
    if (nav == null || !nav.mounted) return;
    await TaxistaFinanzasNav.abrirMisPagos(
      nav.context,
      scrollToRecargaSection: true,
    );
  }

  /// Reabre el viaje en curso del cliente tras pagar con AZUL (deep link o resume).
  static Future<void> retomarViajeClienteTrasPagoAzul({
    required String viajeId,
  }) async {
    ActiveTripService.cancelarForzarInicioClienteShell();
    ActiveTripService.mantenerOverlayViajeEnShell(const Duration(minutes: 5));
    ClienteShellNavBridge.popAllTabRoutes();
    ShellTabController.clienteIrAInicio();
    await clearAndGoViajeEnCursoCliente();
    ActiveTripService.notificarRebuildShell();
    print(
      '[VIAJE_ACTIVO] retomarViajeClienteTrasPagoAzul viajeId=$viajeId',
    );
  }

  /// Vuelve al home del cliente sin activar pausa ni gate de 24 h
  /// (p. ej. salir de [ProgramarViaje] sin viaje activo).
  static void volverAlHomeClienteLigero({BuildContext? context}) {
    ShellTabController.clienteIndex.value = 0;
    ClienteShellNavBridge.popAllTabRoutes();
    ActiveTripService.notificarRebuildShell();
  }

  /// Pausa el viaje en curso y vuelve al home de RAI sin cancelar ni limpiar
  /// `viajeActivoId` (el cliente puede retomar desde el banner).
  static Future<void> pausarViajeClienteYVolverARai({
    BuildContext? context,
    String? viajeId,
  }) async {
    await irAlInicioCliente(
      context: context,
      viajeId: viajeId,
      forzarLimpiarViajeActivo: false,
      omitirForzarInicioShell: true,
    );
  }

  /// Reabre el viaje tras pausa voluntaria: reserva futura → confirmación;
  /// operativo / en pool → overlay de viaje en curso.
  static void retomarViajeActivoCliente() {
    unawaited(_retomarViajeActivoClienteImpl());
  }

  static DateTime? _fechaHoraDesdeDocViaje(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  static Future<void> _retomarViajeActivoClienteImpl() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      _retomarViajeActivoClienteOverlay();
      return;
    }

    Map<String, dynamic>? docData;
    String? docId;

    try {
      final DocumentSnapshot<Map<String, dynamic>>? doc =
          await ActiveTripService.obtenerDocumentoViajeActivo(uid);
      if (doc != null && doc.exists) {
        docId = doc.id;
        docData = doc.data() ?? <String, dynamic>{};
        if (ViajePoolTaxistaGate.esReservaProgramadaLejana(docData)) {
          await _pushConfirmacionReservaProgramada(
            viajeId: doc.id,
            docHint: docData,
          );
          return;
        }
        if (ActiveTripService.viajeDocCuentaComoSeguimientoParaUsuario(
          docData,
          uid,
        )) {
          ActiveTripService.registrarViajeOperativoCliente(doc.id);
          ActiveTripService.sembrarBootstrapViajeCliente(doc.id, docData);
        }
      } else {
        final String? hid =
            await ActiveTripService.hidratarViajeActivoCliente(uid);
        if (hid != null) {
          docId = hid;
          docData = ActiveTripService.peekResumenViajeCliente(hid);
        }
      }
    } catch (_) {
      // Revisar reserva lejana antes del overlay optimista.
    }

    final String vidFallback =
        ActiveTripService.resolverViajeIdClienteParaPausa(preferido: docId);
    if (vidFallback.isNotEmpty) {
      final bool operativo =
          await ActiveTripService.viajeDocSigueOperativoParaCliente(
        vidFallback,
        uid,
      );
      final Map<String, dynamic>? cache =
          ActiveTripService.peekResumenViajeCliente(vidFallback);
      if (!operativo && (cache == null || cache.isEmpty)) {
        final bool ausente =
            await ActiveTripService.confirmarViajeAusenteEnFirestore(
          vidFallback,
          uid: uid,
        );
        if (ausente) {
          await ActiveTripService.liberarClienteTrasViajeEliminado(
            vidFallback,
            uid: uid,
          );
          snackViajeYaNoDisponible();
          return;
        }
      }
    }
    if (vidFallback.isNotEmpty &&
        await _intentarAbrirReservaProgramadaLejana(
          viajeId: vidFallback,
          docHint: docData,
        )) {
      return;
    }

    _retomarViajeActivoClienteOverlay();
  }

  static Future<bool> _intentarAbrirReservaProgramadaLejana({
    required String viajeId,
    Map<String, dynamic>? docHint,
  }) async {
    Map<String, dynamic>? d = docHint;
    d ??= ActiveTripService.peekResumenViajeCliente(viajeId);
    if (d == null || d.isEmpty) {
      try {
        final DocumentSnapshot<Map<String, dynamic>> snap =
            await FirebaseFirestore.instance
                .collection('viajes')
                .doc(viajeId)
                .get();
        if (snap.exists) {
          d = snap.data() ?? <String, dynamic>{};
        }
      } catch (_) {}
    }
    if (d == null || !ViajePoolTaxistaGate.esReservaProgramadaLejana(d)) {
      return false;
    }
    await _pushConfirmacionReservaProgramada(
      viajeId: viajeId,
      docHint: d,
    );
    return true;
  }

  static Future<void> _pushConfirmacionReservaProgramada({
    required String viajeId,
    Map<String, dynamic>? docHint,
  }) async {
    ActiveTripService.liberarReservaProgramadaLejanaEnHome(viajeId: viajeId);
    if (docHint != null && docHint.isNotEmpty) {
      ActiveTripService.sembrarBootstrapViajeCliente(viajeId, docHint);
    }
    ShellTabController.clienteIrAInicio();
    ClienteShellNavBridge.popAllTabRoutes();
    final DateTime? pickup = _fechaHoraDesdeDocViaje(docHint?['fechaHora']);
    final Widget page = ViajeProgramadoConfirmacion(
      viajeId: viajeId,
      fechaHoraPickup: pickup,
    );
    if (ClienteShellNavBridge.canPushOnInicioTab) {
      await ClienteShellNavBridge.pushOnInicioTab<void>(page);
    } else {
      final NavigatorState? nav = navigatorKey.currentState;
      if (nav != null && nav.mounted) {
        await nav.push<void>(
          MaterialPageRoute<void>(builder: (_) => page),
        );
      }
    }
  }

  static void _retomarViajeActivoClienteOverlay() {
    ActiveTripService.cancelarForzarInicioClienteShell();
    ClienteShellNavBridge.popAllTabRoutes();
    ShellTabController.clienteIrAInicio();
    unawaited(
      clearAndGoViajeEnCursoCliente(forzarReabrir: true).then((_) {
        ActiveTripService.notificarRebuildShell();
      }),
    );
  }

  static Future<void> _limpiarViajeActivoClienteEnServidor(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'viajeActivoId': '',
        'siguienteViajeId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
    } catch (_) {}
    await RaiLocalReadCache.clearActiveTripId(uid);
  }

  /// Misma navegación que [cerrarSesion]: stack limpio y [AuthGatePublic] decide login/home.
  static Future<void> clearToAuthGate() async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    await nav.pushNamedAndRemoveUntil('/auth_check', (Route<dynamic> r) => false);
  }

  static void snackViajeYaNoDisponible({BuildContext? context}) {
    _snackCorporativo(
      'El viaje ya no está disponible. Puedes solicitar uno nuevo.',
      context: context,
      backgroundColor: const Color(0xFF1B5E20),
    );
  }

  static void _snackCorporativo(
    String msg, {
    BuildContext? context,
    Color? backgroundColor,
  }) {
    BuildContext? ctx = context;
    if (ctx != null && !ctx.mounted) ctx = null;
    ctx ??= navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// Abre ruta corporativa en pantalla informativa (sin PIN ni viaje en curso).
  static Future<void> abrirViajeCorporativoTaxista({
    required String uidTaxista,
    String? viajeId,
    String? empresaId,
    String? plantillaId,
    NavigatorState? preNav,
    BuildContext? snackContext,
    bool quedarseEnPantalla = false,
    bool listoSegunOperacion = false,
    bool forzarApertura = false,
  }) async {
    final uid = uidTaxista.trim();
    if (uid.isEmpty) return;

    final id = await CorporativoTaxistaService.resolverViajeCorporativoParaChofer(
      uidTaxista: uid,
      viajeIdPreferido: viajeId,
      empresaId: empresaId,
      plantillaId: plantillaId,
    );
    if (id == null || id.trim().isEmpty) {
      _snackCorporativo(
        'Aún no hay viaje publicado para hoy. '
        'Tocá Abrir ruta de nuevo en unos segundos o pedile al encargado «Enviar ahora».',
        backgroundColor: Colors.orange.shade800,
        context: snackContext,
      );
      return;
    }

    final String viajeIdResuelto = id.trim();
    if (forzarApertura) {
      CorporativoTaxistaService.limpiarDismissRutaCorpInformativa(
        viajeIdResuelto,
      );
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeIdResuelto)
          .get();
      if (!snap.exists) {
        _snackCorporativo(
          'La ruta ya no está disponible.',
          backgroundColor: Colors.orange.shade800,
          context: snackContext,
        );
        return;
      }
      final d = snap.data() ?? <String, dynamic>{};
      if (!CorporativoTaxistaService.esViajeCorporativoAsignado(d, uid)) {
        _snackCorporativo(
          'Esta ruta no está asignada a tu cuenta.',
          context: snackContext,
        );
        return;
      }
      if (!await CorporativoTaxistaService.viajeCorporativoEmpresaVigente(d)) {
        _snackCorporativo(
          'Esta empresa ya no opera con RAI. La ruta fue retirada.',
          backgroundColor: Colors.orange.shade800,
          context: snackContext,
        );
        return;
      }
      if (CorporativoTaxistaService.viajeCorporativoSuperseded(d)) {
        _snackCorporativo(
          'Esta ruta fue reemplazada o cancelada.',
          backgroundColor: Colors.orange.shade800,
          context: snackContext,
        );
        return;
      }
      if (d['completado'] == true) {
        _snackCorporativo(
          'Esta ruta ya fue completada.',
          backgroundColor: Colors.teal.shade800,
          context: snackContext,
        );
        return;
      }
      if (CorporativoTaxistaService.viajeCorporativoInformativoCerradoParaChofer(d)) {
        _snackCorporativo(
          'Esta ruta de hoy ya está cerrada. Mañana se publica la nueva.',
          backgroundColor: Colors.teal.shade800,
          context: snackContext,
        );
        return;
      }
      if (quedarseEnPantalla &&
          CorporativoTaxistaService.viajeCorporativoEnCursoReal(d)) {
        CorporativoTaxistaService.limpiarDismissRutaCorpInformativa(
          viajeIdResuelto,
        );
      } else if (!forzarApertura &&
          CorporativoTaxistaService.rutaCorpInformativaDismissedRecientemente(
            viajeIdResuelto,
          )) {
        CorporativoTaxistaService.limpiarDismissRutaCorpInformativa(
          viajeIdResuelto,
        );
      }
      if (!CorporativoTaxistaService.corporativoListoParaAbrirEnCurso(
        d,
        listoSegunOperacion: listoSegunOperacion,
      )) {
        _snackCorporativo(
          CorporativoTaxistaService.mensajeCorporativoAunNoEsHora(d),
          backgroundColor: Colors.orange.shade800,
          context: snackContext,
        );
        return;
      }
      if (await CorporativoTaxistaService
          .taxistaTieneViajeNoCorporativoBloqueante(uid, exceptViajeId: viajeIdResuelto)) {
        await CorporativoTaxistaService.encolarViajeCorporativoInformativo(
          uidTaxista: uid,
          viajeId: viajeIdResuelto,
        );
        _snackCorporativo(
          'Tenés un viaje en curso. La ruta corporativa quedó en cola.',
          backgroundColor: Colors.orange.shade800,
          context: snackContext,
        );
        return;
      }
    } catch (_) {
      _snackCorporativo(
        'No se pudo cargar la ruta. Reintentá en unos segundos.',
        backgroundColor: Colors.red.shade800,
        context: snackContext,
      );
      return;
    }

    ActiveTripService.cancelarMantenimientoOverlayViaje();
    await ViajesRepo.limpiarViajeActivoSiNoOperativo(uid);
    await RaiLocalReadCache.clearActiveTripId(uid);
    CorporativoTaxistaService.limpiarDismissRutaCorpInformativa(viajeIdResuelto);
    ActiveTripService.registrarViajeOperativoTaxista(viajeIdResuelto);
    ActiveTripService.markTaxistaTripScreenMounted();

    await push(
      CorporativoRutaDetalleInformativoPage(
        viajeId: viajeIdResuelto,
        uidTaxista: uid,
      ),
    );
  }
}
