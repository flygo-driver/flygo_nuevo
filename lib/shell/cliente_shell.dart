// ignore_for_file: avoid_print

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_cuenta_tab.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_experiencias_tab.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_home.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_mis_viajes_hub.dart';
import 'package:flygo_nuevo/widgets/cliente_pantalla_viaje_activo.dart';
import 'package:flygo_nuevo/widgets/viaje_overlay_error_shield.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_solicitado.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/rai_connectivity_service.dart';
import 'package:flygo_nuevo/servicios/rai_local_read_cache.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/widgets/bola_cancelacion_listener.dart';
import 'package:flygo_nuevo/widgets/bola_post_factura_listener.dart';
import 'package:flygo_nuevo/utils/bola_ahorro_pool_isolation.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';
import 'package:flygo_nuevo/widgets/cliente_fidelidad_milestone_listener.dart';
import 'package:flygo_nuevo/widgets/cliente_post_viaje_listener.dart';
import 'package:flygo_nuevo/widgets/cliente_viaje_activo_retomar_banner.dart';
import 'package:flygo_nuevo/widgets/rai_offline_banner.dart';
import 'package:flygo_nuevo/widgets/rai_asistente_fab.dart';
import 'package:flygo_nuevo/widgets/cliente_registro_gate.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_banner_scope.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_cliente_banner.dart';
import 'package:flygo_nuevo/widgets/shell_tab_nav.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_cliente_service.dart';
import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_detalle.dart';
import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_lista.dart';
import 'package:flygo_nuevo/shell/cliente_pool_deep_link_bridge.dart';
import 'package:flygo_nuevo/servicios/pool_deep_link.dart';
import 'package:flygo_nuevo/servicios/pool_timbre_session_guard.dart';
import 'package:flygo_nuevo/servicios/rai_modo_sesion_service.dart';
import 'package:flygo_nuevo/widgets/rai_cambio_modo_sesion_borde.dart';
import 'package:flygo_nuevo/servicios/productos_config_service.dart';
import 'package:flygo_nuevo/servicios/finance_config_service.dart';
import 'package:flygo_nuevo/servicios/cliente_shell_nav_bridge.dart';
import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';

/// Shell del cliente: barra inferior fija; cada pestaña usa un [Navigator] anidado
/// (pantallas con [Navigator.push] no tapan Inicio / Mis viajes / etc.).
/// No apilar otro [ClienteShell] en un tab — usar [NavigationService.irAlInicioCliente].
/// [ClienteShell] + reintento de deep link gira tras montar (login lento).
class ClienteShellWithDeepLink extends StatefulWidget {
  const ClienteShellWithDeepLink({super.key});

  @override
  State<ClienteShellWithDeepLink> createState() =>
      _ClienteShellWithDeepLinkState();
}

class _ClienteShellWithDeepLinkState extends State<ClienteShellWithDeepLink> {
  @override
  void initState() {
    super.initState();
    PoolTimbreSessionGuard.activarSesionPasajero();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PoolDeepLink.notifyClienteShellReady();
    });
  }

  @override
  Widget build(BuildContext context) => const ClienteShell();
}

class ClienteShell extends StatelessWidget {
  const ClienteShell({super.key});

  @override
  Widget build(BuildContext context) {
    Widget core = const ClientePostViajeListener(
      child: ClienteFidelidadMilestoneListener(
        child: _ClienteShellScaffold(),
      ),
    );
    if (!BolaAhorroPoolIsolation.bloquearInterferenciaEnFlujoPool()) {
      core = BolaCancelacionListener(
        child: BolaPostFacturaListener(child: core),
      );
    }
    return ClienteRegistroGate(child: core);
  }
}

class _ClienteShellScaffold extends StatefulWidget {
  const _ClienteShellScaffold();

  @override
  State<_ClienteShellScaffold> createState() => _ClienteShellScaffoldState();
}

class _ClienteShellScaffoldState extends State<_ClienteShellScaffold> {
  int _index = 0;

  final GlobalKey _viajeEnCursoShellKey = GlobalKey();

  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List<GlobalKey<NavigatorState>>.generate(
          4, (_) => GlobalKey<NavigatorState>());

  StreamSubscription<bool>? _viajeActivoSub;
  bool? _viajeActivoShell;
  bool _bootstrapViajeResuelto = false;
  bool _bootstrapViajeEnCurso = false;
  Timer? _bootstrapViajeTimeout;
  VoidCallback? _offlineListener;
  VoidCallback? _shellRebuildListener;

  static const Duration _kBootstrapViajeMaxWait = Duration(seconds: 8);
  static const Duration _kBootstrapQueryMaxWait = Duration(seconds: 5);
  static const int _kTabExperiencias = 2;

  String? _lastDeepLinkPoolOpened;

  bool _shellListoParaDeepLinkGira() =>
      mounted && _viajeActivoShell == false;

  void _abrirGiraDeepLinkEnExperiencias(String poolId) {
    final String id = poolId.trim();
    if (id.isEmpty) return;
    if (_lastDeepLinkPoolOpened == id) return;

    void pushDetalle({required int attempt}) {
      if (!mounted || !_shellListoParaDeepLinkGira()) {
        if (attempt < 40) {
          Future<void>.delayed(const Duration(milliseconds: 150), () {
            if (mounted) pushDetalle(attempt: attempt + 1);
          });
        }
        return;
      }

      final NavigatorState? tabNav =
          _navigatorKeys[_kTabExperiencias].currentState;
      if (tabNav == null) {
        if (attempt < 40) {
          Future<void>.delayed(const Duration(milliseconds: 150), () {
            if (mounted) pushDetalle(attempt: attempt + 1);
          });
        }
        return;
      }

      tabNav.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PoolsClienteDetalle(poolId: id),
        ),
      );
      _lastDeepLinkPoolOpened = id;
      ClientePoolDeepLinkBridge.markNavigationComplete(id);
    }

    setState(() => _index = _kTabExperiencias);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pushDetalle(attempt: 0);
    });
  }

  void _abrirGirasListaDeepLink() {
    if (_lastDeepLinkPoolOpened == PoolDeepLink.girasListaMarker) return;

    void pushLista({required int attempt}) {
      if (!mounted || !_shellListoParaDeepLinkGira()) {
        if (attempt < 40) {
          Future<void>.delayed(const Duration(milliseconds: 150), () {
            if (mounted) pushLista(attempt: attempt + 1);
          });
        }
        return;
      }

      final NavigatorState? tabNav =
          _navigatorKeys[_kTabExperiencias].currentState;
      if (tabNav == null) {
        if (attempt < 40) {
          Future<void>.delayed(const Duration(milliseconds: 150), () {
            if (mounted) pushLista(attempt: attempt + 1);
          });
        }
        return;
      }

      tabNav.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const PoolsClienteLista(tipo: 'todos'),
        ),
      );
      _lastDeepLinkPoolOpened = PoolDeepLink.girasListaMarker;
      ClientePoolDeepLinkBridge.markGirasListaNavigationComplete();
    }

    setState(() => _index = _kTabExperiencias);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pushLista(attempt: 0);
    });
  }

  void _onShellTabController() {
    final i = ShellTabController.clienteIndex.value;
    if (!mounted || i == _index) return;
    setState(() => _index = i);
  }

  void _popAllTabRoutes() {
    for (final GlobalKey<NavigatorState> key in _navigatorKeys) {
      final NavigatorState? nav = key.currentState;
      if (nav != null && nav.mounted) {
        nav.popUntil((Route<dynamic> route) => route.isFirst);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    ClienteShellNavBridge.bind(
      popAllTabRoutes: _popAllTabRoutes,
      pushOnInicioTab: (Widget page) {
        final NavigatorState? nav = _navigatorKeys[0].currentState;
        if (nav == null || !nav.mounted) return Future<Object?>.value(null);
        return nav.push<Object?>(
          MaterialPageRoute<Object?>(builder: (_) => page),
        );
      },
    );
    ShellTabController.clienteIndex.value = 0;
    ShellTabController.clienteIndex.addListener(_onShellTabController);
    ClientePoolDeepLinkBridge.bindShell(
      isReady: _shellListoParaDeepLinkGira,
      openPool: _abrirGiraDeepLinkEnExperiencias,
      openGirasLista: _abrirGirasListaDeepLink,
      onNavigationComplete: PoolDeepLink.markNavigationComplete,
    );
    RaiConnectivityService.instance.ensureStarted();
    unawaited(RaiUbicacionClienteService.instance.ensureStarted());
    unawaited(ProductosConfigService.ensureStarted());
    unawaited(FinanceConfigService.ensureStarted());

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _viajeActivoShell = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PoolDeepLink.notifyClienteShellReady();
      });
    } else {
      unawaited(ActiveTripService.prepararModeloViajePegadoCliente(uid));
      // Como taxista_shell: no bloquear la UI con spinner indefinido en cold start.
      if (ActiveTripService.debeMantenerOverlayViajeEnShell) {
        _viajeActivoShell = true;
      } else {
        _viajeActivoShell = false;
      }

      _offlineListener = () => _resolverBootstrapSiOffline(uid);
      RaiConnectivityService.instance.offline.addListener(_offlineListener!);

      unawaited(_resolverBootstrapConCache(uid, porTimeout: false));

      _bootstrapViajeTimeout = Timer(_kBootstrapViajeMaxWait, () {
        if (!mounted || _bootstrapViajeResuelto) return;
        unawaited(_resolverBootstrapConCache(uid, porTimeout: true));
      });

      _shellRebuildListener = () {
        if (!mounted) return;
        if (ActiveTripService.clientePostViajeEnHome) {
          if (_viajeActivoShell != false) {
            print('[VIAJE_ACTIVO] cliente_shell rebuild tick → post-viaje home');
            setState(() => _viajeActivoShell = false);
          }
          return;
        }
        if (!ActiveTripService.debeMantenerOverlayViajeEnShell) return;
        if (_viajeActivoShell != true) {
          print('[VIAJE_ACTIVO] cliente_shell rebuild tick → overlay viaje');
          setState(() => _viajeActivoShell = true);
        }
      };
      ActiveTripService.shellRebuildTick.addListener(_shellRebuildListener!);

      _viajeActivoSub =
          ActiveTripService.streamTieneViajeActivo(uid).listen((bool ok) {
        if (!mounted) return;
        if (ActiveTripService.clienteSuprimirOverlayViajeActivo) {
          if (_viajeActivoShell != false) {
            print(
              '[VIAJE_ACTIVO] cliente_shell solicitud/cotización → mantener home',
            );
            setState(() => _viajeActivoShell = false);
          }
          return;
        }
        if (ok) {
          _bootstrapViajeTimeout?.cancel();
          _bootstrapViajeResuelto = true;
        }
        if (ActiveTripService.clientePostViajeEnHome) {
          if (_viajeActivoShell != false) {
            print('[VIAJE_ACTIVO] cliente_shell post-viaje → home');
            setState(() {
              _viajeActivoShell = false;
              _lastDeepLinkPoolOpened = null;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              PoolDeepLink.notifyClienteShellReady();
            });
          }
          return;
        }
        if (_viajeActivoShell == true &&
            !ok &&
            (ActiveTripService.debeMantenerOverlayViajeEnShell ||
                ActiveTripService.retomarClienteEnCurso ||
                ActiveTripService.viajeOperativoClienteConocido.isNotEmpty)) {
          return;
        }
        if (_viajeActivoShell != ok) {
          print('[VIAJE_ACTIVO] cliente_shell stream tieneActivo=$ok');
          setState(() {
            _viajeActivoShell = ok;
            if (!ok) {
              _lastDeepLinkPoolOpened = null;
            }
          });
          if (!ok) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              PoolDeepLink.notifyClienteShellReady();
            });
          }
        }
      }, onError: (Object e) {
        print('[VIAJE_ACTIVO] cliente_shell stream error: $e');
        if (!mounted) return;
        unawaited(_resolverBootstrapConCache(uid, porTimeout: false));
      });
    }
  }

  void _resolverBootstrapSiOffline(String uid) {
    if (!RaiConnectivityService.instance.isOffline) return;
    if (_bootstrapViajeResuelto) return;
    unawaited(_resolverBootstrapConCache(uid, porTimeout: false));
  }

  /// Sin red o stream lento: no congelar — usar caché local o mostrar inicio.
  Future<void> _resolverBootstrapConCache(
    String uid, {
    required bool porTimeout,
  }) async {
    if (!mounted || _bootstrapViajeResuelto) return;
    if (_bootstrapViajeEnCurso && !porTimeout) return;
    if (porTimeout && _bootstrapViajeEnCurso) {
      print('[VIAJE_ACTIVO] cliente_shell bootstrap timeout forzado');
    }
    _bootstrapViajeEnCurso = true;
    try {
      await ActiveTripService.prepararModeloViajePegadoCliente(uid);

      if (_viajeActivoShell == true) {
        _bootstrapViajeResuelto = true;
        return;
      }

      bool mostrarViaje = false;
      final bool bloquearPorPostViaje =
          ActiveTripService.flujoPostViajeClienteActivo;
      if (!bloquearPorPostViaje) {
        mostrarViaje = ActiveTripService.debeMantenerOverlayViajeEnShell;

        // Query primero: es la fuente fiable cuando GET directo falla (PIN / cold start).
        DocumentSnapshot<Map<String, dynamic>>? docQuery;
        try {
          docQuery = await ActiveTripService.obtenerDocumentoViajeActivo(uid)
              .timeout(_kBootstrapQueryMaxWait);
        } on TimeoutException {
          print('[VIAJE_ACTIVO] cliente_shell bootstrap query timeout');
        }
        if (docQuery != null && docQuery.exists) {
          if (ActiveTripService.viajeClienteDescartadoEnSesion(docQuery.id) ||
              await ViajesRepo.viajeQueryMatchEsFantasmaParaCliente(
                docQuery.id,
              )) {
            print(
              '[VIAJE_ACTIVO] cliente_shell bootstrap → viaje fantasma id=${docQuery.id}',
            );
            unawaited(
              ActiveTripService.liberarClienteTrasViajeEliminado(
                docQuery.id,
                uid: uid,
              ),
            );
          } else {
          final Map<String, dynamic> d =
              docQuery.data() ?? <String, dynamic>{};
          if (ViajePoolTaxistaGate.esReservaProgramadaLejana(d)) {
            mostrarViaje = false;
            ActiveTripService.liberarReservaProgramadaLejanaEnHome(
              viajeId: docQuery.id,
            );
            ActiveTripService.sembrarBootstrapViajeCliente(docQuery.id, d);
            print(
              '[VIAJE_ACTIVO] cliente_shell bootstrap → reserva programada id=${docQuery.id}',
            );
          } else if (ActiveTripService.viajeDocCuentaComoSeguimientoParaUsuario(
            d,
            uid,
          )) {
            mostrarViaje = true;
            ActiveTripService.registrarViajeOperativoCliente(docQuery.id);
            ActiveTripService.cancelarForzarInicioClienteShell();
            ActiveTripService.mantenerOverlayViajeEnShell(
              const Duration(minutes: 5),
            );
            unawaited(RaiLocalReadCache.rememberActiveTripId(uid, docQuery.id));
            ActiveTripService.sembrarBootstrapViajeCliente(docQuery.id, d);
            print(
              '[VIAJE_ACTIVO] cliente_shell bootstrap → viaje desde query id=${docQuery.id}',
            );
            unawaited(
              ActiveTripService.repararViajeActivoClienteSiHuerfano(
                uid,
                viajeIdHint: docQuery.id,
              ),
            );
          }
          }
        }

        if (!mostrarViaje) {
          try {
            final DocumentSnapshot<Map<String, dynamic>> userSnap =
                await FirebaseFirestore.instance
                    .collection('usuarios')
                    .doc(uid)
                    .get();
            final String activoId =
                (userSnap.data()?['viajeActivoId'] ?? '').toString().trim();
            if (activoId.isNotEmpty) {
              Map<String, dynamic>? dActivo;
              try {
                final DocumentSnapshot<Map<String, dynamic>> vSnap =
                    await FirebaseFirestore.instance
                        .collection('viajes')
                        .doc(activoId)
                        .get()
                        .timeout(_kBootstrapQueryMaxWait);
                if (vSnap.exists) {
                  dActivo = vSnap.data();
                }
              } catch (_) {}
              if (dActivo != null &&
                  ViajePoolTaxistaGate.esReservaProgramadaLejana(dActivo)) {
                mostrarViaje = false;
                ActiveTripService.liberarReservaProgramadaLejanaEnHome(
                  viajeId: activoId,
                );
                ActiveTripService.sembrarBootstrapViajeCliente(
                  activoId,
                  dActivo,
                );
                print(
                  '[VIAJE_ACTIVO] cliente_shell bootstrap → reserva programada viajeActivoId=$activoId',
                );
              } else if (dActivo != null &&
                  ActiveTripService.viajeDocCuentaComoSeguimientoParaUsuario(
                    dActivo,
                    uid,
                  )) {
                mostrarViaje = true;
                ActiveTripService.registrarViajeOperativoCliente(activoId);
                ActiveTripService.cancelarForzarInicioClienteShell();
                ActiveTripService.mantenerOverlayViajeEnShell(
                  const Duration(minutes: 5),
                );
                print(
                  '[VIAJE_ACTIVO] cliente_shell bootstrap → overlay viajeActivoId=$activoId',
                );
                unawaited(
                  ActiveTripService.repararViajeActivoClienteSiHuerfano(
                    uid,
                    viajeIdHint: activoId,
                  ),
                );
              } else if (dActivo == null) {
                print(
                  '[VIAJE_ACTIVO] cliente_shell bootstrap → sin doc activoId=$activoId (sin overlay optimista)',
                );
                unawaited(
                  ActiveTripService.reconciliarViajeActivoHuerfanoCliente(uid),
                );
              }
            }
          } catch (e) {
            print('[VIAJE_ACTIVO] cliente_shell bootstrap viajeActivoId: $e');
          }
        }

        final String cachedId =
            (await RaiLocalReadCache.lastKnownActiveTripId(uid) ?? '').trim();

        if (!mostrarViaje && cachedId.isNotEmpty) {
          Map<String, dynamic>? dCache;
          try {
            final DocumentSnapshot<Map<String, dynamic>> vSnap =
                await FirebaseFirestore.instance
                    .collection('viajes')
                    .doc(cachedId)
                    .get()
                    .timeout(_kBootstrapQueryMaxWait);
            if (vSnap.exists) dCache = vSnap.data();
          } catch (_) {}
          if (dCache != null &&
              ViajePoolTaxistaGate.esReservaProgramadaLejana(dCache)) {
            ActiveTripService.liberarReservaProgramadaLejanaEnHome(
              viajeId: cachedId,
            );
            ActiveTripService.sembrarBootstrapViajeCliente(cachedId, dCache);
            print(
              '[VIAJE_ACTIVO] cliente_shell bootstrap → reserva programada caché=$cachedId',
            );
          } else if (dCache != null &&
              ActiveTripService.viajeDocCuentaComoSeguimientoParaUsuario(
                dCache,
                uid,
              )) {
            mostrarViaje = true;
            ActiveTripService.registrarViajeOperativoCliente(cachedId);
            ActiveTripService.cancelarForzarInicioClienteShell();
            ActiveTripService.mantenerOverlayViajeEnShell(
              const Duration(minutes: 5),
            );
            print(
              '[VIAJE_ACTIVO] cliente_shell bootstrap → overlay caché=$cachedId',
            );
            unawaited(
              ActiveTripService.repararViajeActivoClienteSiHuerfano(
                uid,
                viajeIdHint: cachedId,
              ),
            );
          }
        } else if (!mostrarViaje &&
            docQuery != null &&
            docQuery.exists &&
            !ViajePoolTaxistaGate.esReservaProgramadaLejana(
              docQuery.data() ?? <String, dynamic>{},
            ) &&
            ActiveTripService.viajeDocCuentaComoSeguimientoParaUsuario(
              docQuery.data() ?? <String, dynamic>{},
              uid,
            )) {
          ActiveTripService.sembrarViajeClienteParaRetomarEnHome(
            docQuery.id,
            docHint: docQuery.data(),
          );
        } else if (mostrarViaje && cachedId.isNotEmpty) {
          bool sigue = true;
          try {
            sigue = await ActiveTripService.viajeDocSigueOperativoParaCliente(
              cachedId,
              uid,
            ).timeout(_kBootstrapQueryMaxWait);
          } on TimeoutException {
            print(
              '[VIAJE_ACTIVO] cliente_shell bootstrap validar caché timeout',
            );
          }
          if (!sigue && docQuery == null) {
            mostrarViaje = false;
            ActiveTripService.cancelarMantenimientoOverlayViaje();
            unawaited(RaiLocalReadCache.clearActiveTripId(uid));
            print(
              '[VIAJE_ACTIVO] cliente_shell bootstrap → caché invalidada, sin viaje',
            );
          }
        }
      }

      if (!mounted) return;
      _bootstrapViajeResuelto = true;
      _bootstrapViajeTimeout?.cancel();
      print(
        '[VIAJE_ACTIVO] cliente_shell bootstrap '
        '${porTimeout ? 'timeout' : 'inicio'} → viaje=$mostrarViaje',
      );
      if (_viajeActivoShell != mostrarViaje) {
        setState(() => _viajeActivoShell = mostrarViaje);
      }
      if (!mostrarViaje) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          PoolDeepLink.notifyClienteShellReady();
        });
      }
    } finally {
      _bootstrapViajeEnCurso = false;
    }
  }

  void _notificarDeepLinkSiListo() {
    if (!_shellListoParaDeepLinkGira()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_shellListoParaDeepLinkGira()) return;
      PoolDeepLink.notifyClienteShellReady();
    });
  }

  @override
  void dispose() {
    ClienteShellNavBridge.unbind();
    ShellTabController.clienteIndex.removeListener(_onShellTabController);
    ClientePoolDeepLinkBridge.unbindShell();
    _bootstrapViajeTimeout?.cancel();
    if (_offlineListener != null) {
      RaiConnectivityService.instance.offline.removeListener(_offlineListener!);
    }
    if (_shellRebuildListener != null) {
      ActiveTripService.shellRebuildTick
          .removeListener(_shellRebuildListener!);
    }
    _viajeActivoSub?.cancel();
    RaiUbicacionClienteService.instance.disposeService();
    super.dispose();
  }

  Widget _tabNavigator(int index, Widget rootPage) {
    return Navigator(
      key: _navigatorKeys[index],
      initialRoute: '/',
      onGenerateRoute: (RouteSettings settings) {
        if (settings.name == '/') {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => rootPage,
          );
        }
        return null;
      },
    );
  }

  void _seleccionarTab(int i) {
    if (i == _index) {
      final NavigatorState? nav = _navigatorKeys[i].currentState;
      if (nav != null && nav.mounted) {
        nav.popUntil((Route<dynamic> route) => route.isFirst);
      }
      return;
    }
    ShellTabController.clienteIndex.value = i;
    if (!mounted) return;
    setState(() => _index = i);
    if (i == _kTabExperiencias) _notificarDeepLinkSiListo();
  }

  @override
  Widget build(BuildContext context) {
    final String? uidOffline = FirebaseAuth.instance.currentUser?.uid;
    // Si ya pedimos overlay (p. ej. tras confirmar viaje), no quedarse en spinner
    // aunque el stream de viajeActivo aún no haya emitido.
    final bool forzarInicio = ActiveTripService.clientePostViajeEnHome;
    final bool suprimirOverlaySolicitud =
        ActiveTripService.clienteSuprimirOverlayViajeActivo;
    final bool overlayForzado = !forzarInicio &&
        !suprimirOverlaySolicitud &&
        ActiveTripService.debeMantenerOverlayViajeEnShell;
    if (_viajeActivoShell == null && !overlayForzado && !forzarInicio) {
      return Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RaiOfflineBanner(uid: uidOffline),
            const RaiUbicacionClienteBanner(),
            const Expanded(
              child: RaiUbicacionBannerScope(
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        ),
      );
    }
    final bool full = !forzarInicio &&
        !suprimirOverlaySolicitud &&
        (_viajeActivoShell == true || overlayForzado);
    if (full) {
      print(
          '[VIAJE_ACTIVO] cliente_shell: pantalla completa ViajeEnCursoCliente (sin tabs)');
      return Scaffold(
        body: ViajeOverlayErrorShield(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RaiOfflineBanner(uid: uidOffline),
              const RaiUbicacionClienteBanner(),
              Expanded(
                child: RaiUbicacionBannerScope(
                  child: ClientePantallaViajeActivo(
                    viajeEnCursoKey: _viajeEnCursoShellKey,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final Color barSurface = Theme.of(context).colorScheme.surface;
    final bool barOscura =
        ThemeData.estimateBrightnessForColor(barSurface) == Brightness.dark;
    final Color navAccent =
        barOscura ? RaiDsColors.neon : const Color(0xFF16A34A);
    final Color navMuted = barOscura
        ? RaiDsColors.textMuted
        : const Color(0xFF6B7280);
    final overlayBarra = SystemUiOverlayStyle(
      systemNavigationBarColor: barSurface,
      systemNavigationBarIconBrightness:
          barOscura ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayBarra,
      child: Stack(
        children: [
          Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RaiOfflineBanner(uid: uidOffline),
          const RaiUbicacionClienteBanner(),
          if (uidOffline != null && uidOffline.isNotEmpty)
            ClienteViajeActivoRetomarBanner(uid: uidOffline),
          Expanded(
            child: RaiUbicacionBannerScope(
              child: IndexedStack(
                index: _index,
                children: [
                  _tabNavigator(
                    0,
                    const ViajeSolicitadoActivoBootstrap(child: ClienteHome()),
                  ),
                  _tabNavigator(1, const ClienteMisViajesHub()),
                  _tabNavigator(2, const ClienteExperienciasTab()),
                  _tabNavigator(3, const ClienteCuentaTab()),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: ColoredBox(
        color: barSurface,
        child: Theme(
          data: Theme.of(context).copyWith(
            navigationBarTheme: NavigationBarThemeData(
              height: MediaQuery.textScalerOf(context).scale(58).clamp(58, 76),
              elevation: 0,
              indicatorColor: navAccent.withValues(alpha: 0.16),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  height: 1.1,
                  color: selected ? navAccent : navMuted,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return IconThemeData(
                  size: 22,
                  color: selected ? navAccent : navMuted,
                );
              }),
              indicatorShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            minimum: EdgeInsets.zero,
            child: NavigationBar(
              backgroundColor: barSurface,
              surfaceTintColor: Colors.transparent,
              selectedIndex: _index,
              onDestinationSelected: _seleccionarTab,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Inicio',
                ),
                NavigationDestination(
                  icon: Icon(Icons.directions_car_outlined),
                  selectedIcon: Icon(Icons.directions_car),
                  label: 'Mis viajes',
                ),
                NavigationDestination(
                  icon: Icon(Icons.travel_explore_outlined),
                  selectedIcon: Icon(Icons.travel_explore),
                  label: 'Experiencias',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Cuenta',
                ),
              ],
            ),
          ),
        ),
      ),
          ),
          const RaiAsistenteFab(),
          if (RaiModoSesionService.enModoPasajero &&
              _index == 3)
            const RaiCambioModoSesionBorde(destinoPasajero: false),
        ],
      ),
    );
  }

}
