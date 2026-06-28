// ignore_for_file: avoid_print

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_cuenta_tab.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_experiencias_tab.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_home.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_mis_viajes_hub.dart';
import 'package:flygo_nuevo/widgets/cliente_pantalla_viaje_activo.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_solicitado.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/rai_connectivity_service.dart';
import 'package:flygo_nuevo/servicios/rai_local_read_cache.dart';
import 'package:flygo_nuevo/widgets/bola_cancelacion_listener.dart';
import 'package:flygo_nuevo/widgets/bola_post_factura_listener.dart';
import 'package:flygo_nuevo/widgets/cliente_fidelidad_milestone_listener.dart';
import 'package:flygo_nuevo/widgets/cliente_post_viaje_listener.dart';
import 'package:flygo_nuevo/widgets/rai_offline_banner.dart';
import 'package:flygo_nuevo/widgets/rai_asistente_fab.dart';
import 'package:flygo_nuevo/widgets/cliente_registro_gate.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_banner_scope.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_cliente_banner.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_cliente_service.dart';
import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_detalle.dart';
import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_lista.dart';
import 'package:flygo_nuevo/shell/cliente_pool_deep_link_bridge.dart';
import 'package:flygo_nuevo/servicios/pool_deep_link.dart';
import 'package:flygo_nuevo/servicios/productos_config_service.dart';
import 'package:flygo_nuevo/servicios/finance_config_service.dart';

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
    return const ClienteRegistroGate(
      child: BolaCancelacionListener(
        child: BolaPostFacturaListener(
          child: ClientePostViajeListener(
            child: ClienteFidelidadMilestoneListener(
              child: _ClienteShellScaffold(),
            ),
          ),
        ),
      ),
    );
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
  Timer? _bootstrapViajeTimeout;
  VoidCallback? _offlineListener;
  VoidCallback? _shellRebuildListener;

  static const Duration _kBootstrapViajeMaxWait = Duration(seconds: 3);
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

  @override
  void initState() {
    super.initState();
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
      _offlineListener = () => _resolverBootstrapSiOffline(uid);
      RaiConnectivityService.instance.offline.addListener(_offlineListener!);

      _bootstrapViajeTimeout = Timer(_kBootstrapViajeMaxWait, () {
        if (!mounted || _viajeActivoShell != null) return;
        unawaited(_resolverBootstrapConCache(uid, porTimeout: true));
      });

      _shellRebuildListener = () {
        if (!mounted) return;
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
        _bootstrapViajeTimeout?.cancel();
        if (_viajeActivoShell == true &&
            !ok &&
            ActiveTripService.debeMantenerOverlayViajeEnShell) {
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
    if (_viajeActivoShell != null) return;
    unawaited(_resolverBootstrapConCache(uid, porTimeout: false));
  }

  /// Sin red o stream lento: no congelar — usar caché local o mostrar inicio.
  Future<void> _resolverBootstrapConCache(
    String uid, {
    required bool porTimeout,
  }) async {
    if (!mounted || _viajeActivoShell != null) return;
    _bootstrapViajeTimeout?.cancel();

    bool mostrarViaje = false;
    if (RaiConnectivityService.instance.isOffline ||
        ActiveTripService.debeMantenerOverlayViajeEnShell) {
      mostrarViaje = ActiveTripService.debeMantenerOverlayViajeEnShell;
      if (!mostrarViaje) {
        final String? cached =
            await RaiLocalReadCache.lastKnownActiveTripId(uid);
        mostrarViaje = (cached ?? '').trim().isNotEmpty;
      }
    }

    if (!mounted || _viajeActivoShell != null) return;
    print(
      '[VIAJE_ACTIVO] cliente_shell bootstrap '
      '${porTimeout ? 'timeout' : 'offline/error'} → viaje=$mostrarViaje',
    );
    setState(() => _viajeActivoShell = mostrarViaje);
    if (!mostrarViaje) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PoolDeepLink.notifyClienteShellReady();
      });
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

  @override
  Widget build(BuildContext context) {
    final String? uidOffline = FirebaseAuth.instance.currentUser?.uid;
    if (_viajeActivoShell == null) {
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
    final bool full = _viajeActivoShell == true ||
        ActiveTripService.debeMantenerOverlayViajeEnShell;
    if (full) {
      print(
          '[VIAJE_ACTIVO] cliente_shell: pantalla completa ViajeEnCursoCliente (sin tabs)');
      return Scaffold(
        body: Column(
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
      );
    }
    return Scaffold(
      floatingActionButton: const RaiAsistenteFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RaiOfflineBanner(uid: uidOffline),
          const RaiUbicacionClienteBanner(),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          if (i == _kTabExperiencias) _notificarDeepLinkSiListo();
        },
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
    );
  }

}
