// ignore_for_file: avoid_print

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/taxista/documentos_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/taxista_cuenta_tab.dart';
import 'package:flygo_nuevo/pantallas/taxista/taxista_servicios_tab.dart';
import 'package:flygo_nuevo/pantallas/taxista/taxista_trabajo_hub.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_disponible.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/comision_prepago_config_service.dart';
import 'package:flygo_nuevo/servicios/finance_config_service.dart';
import 'package:flygo_nuevo/servicios/rai_connectivity_service.dart';
import 'package:flygo_nuevo/servicios/rai_local_read_cache.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_taxista_service.dart';
import 'package:flygo_nuevo/widgets/bola_cancelacion_listener.dart';
import 'package:flygo_nuevo/widgets/bola_post_factura_listener.dart';
import 'package:flygo_nuevo/widgets/taxista_post_viaje_listener.dart';
import 'package:flygo_nuevo/widgets/taxista_registro_gate.dart';
import 'package:flygo_nuevo/widgets/taxista_documentos_gate.dart';
import 'package:flygo_nuevo/widgets/rai_offline_banner.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_taxista_banner.dart';
import 'package:flygo_nuevo/servicios/pool_deep_link.dart';

/// Shell del taxista: una barra inferior fija; cada pestaña usa un [Navigator] anidado.
class TaxistaShell extends StatelessWidget {
  const TaxistaShell({super.key, this.openDocumentosOnLaunch = false});

  /// Abre Cuenta y apila [DocumentosTaxista] (documentos pendientes al entrar).
  final bool openDocumentosOnLaunch;

  @override
  Widget build(BuildContext context) {
    return TaxistaRegistroGate(
      child: TaxistaDocumentosGate(
        child: BolaCancelacionListener(
          child: BolaPostFacturaListener(
            child: TaxistaPostViajeListener(
              child: _TaxistaShellScaffold(
                openDocumentosOnLaunch: openDocumentosOnLaunch,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaxistaShellScaffold extends StatefulWidget {
  const _TaxistaShellScaffold({this.openDocumentosOnLaunch = false});

  final bool openDocumentosOnLaunch;

  @override
  State<_TaxistaShellScaffold> createState() => _TaxistaShellScaffoldState();
}

class _TaxistaShellScaffoldState extends State<_TaxistaShellScaffold> {
  int _index = 0;

  final GlobalKey _viajeEnCursoTaxistaShellKey = GlobalKey();

  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List<GlobalKey<NavigatorState>>.generate(
          4, (_) => GlobalKey<NavigatorState>());

  StreamSubscription<bool>? _viajeActivoSub;
  bool? _viajeActivoShell;
  Timer? _bootstrapViajeTimeout;
  VoidCallback? _offlineListener;
  VoidCallback? _shellRebuildListener;

  static const Duration _kBootstrapViajeMaxWait = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    RaiConnectivityService.instance.ensureStarted();
    unawaited(ComisionPrepagoConfigService.ensureStarted());
    unawaited(FinanceConfigService.ensureStarted());
    unawaited(RaiUbicacionTaxistaService.instance.ensureStarted());

    if (widget.openDocumentosOnLaunch) {
      _index = 3;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _navigatorKeys[3].currentState?.push<void>(
              MaterialPageRoute<void>(
                  builder: (_) => const DocumentosTaxista()),
            );
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      unawaited(
        ViajesRepo.intentarPromoverColaTrasInicioSesionTaxista(uid),
      );
      final hint = PoolDeepLink.consumeConductorDeepLinkHint();
      if (hint != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hint), duration: const Duration(seconds: 8)),
        );
      }
    });
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _viajeActivoShell = false;
    } else {
      _offlineListener = () => _resolverBootstrapSiOffline(uid);
      RaiConnectivityService.instance.offline.addListener(_offlineListener!);

      _bootstrapViajeTimeout = Timer(_kBootstrapViajeMaxWait, () {
        if (!mounted || _viajeActivoShell != null) return;
        unawaited(_resolverBootstrapConCache(uid, porTimeout: true));
      });

      _shellRebuildListener = () {
        if (!mounted) return;
        if (!ActiveTripService.debeBloquearShellSinViajeTaxista &&
            !ActiveTripService.debeMantenerOverlayViajeEnShell) {
          return;
        }
        if (_viajeActivoShell != true) {
          print('[VIAJE_ACTIVO] taxista_shell rebuild tick → overlay viaje');
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
            (ActiveTripService.debeMantenerOverlayViajeEnShell ||
                ActiveTripService.debeBloquearShellSinViajeTaxista)) {
          return;
        }
        if (_viajeActivoShell != ok) {
          print('[VIAJE_ACTIVO] taxista_shell stream tieneActivo=$ok');
          setState(() => _viajeActivoShell = ok);
        }
      }, onError: (Object e) {
        print('[VIAJE_ACTIVO] taxista_shell stream error: $e');
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
      '[VIAJE_ACTIVO] taxista_shell bootstrap '
      '${porTimeout ? 'timeout' : 'offline/error'} → viaje=$mostrarViaje',
    );
    setState(() => _viajeActivoShell = mostrarViaje);
  }

  @override
  void dispose() {
    _bootstrapViajeTimeout?.cancel();
    if (_offlineListener != null) {
      RaiConnectivityService.instance.offline.removeListener(_offlineListener!);
    }
    if (_shellRebuildListener != null) {
      ActiveTripService.shellRebuildTick
          .removeListener(_shellRebuildListener!);
    }
    _viajeActivoSub?.cancel();
    RaiUbicacionTaxistaService.instance.disposeService();
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
            const RaiUbicacionTaxistaBanner(),
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      );
    }
    final bool pantallaViajeEnCurso = _viajeActivoShell == true ||
        ActiveTripService.debeBloquearShellSinViajeTaxista;
    if (pantallaViajeEnCurso) {
      print(
          '[VIAJE_ACTIVO] taxista_shell: pantalla completa ViajeEnCursoTaxista (sin tabs)');
      return Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RaiOfflineBanner(uid: uidOffline),
            const RaiUbicacionTaxistaBanner(),
            Expanded(
              child: ViajeEnCursoTaxista(key: _viajeEnCursoTaxistaShellKey),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RaiOfflineBanner(uid: uidOffline),
          const RaiUbicacionTaxistaBanner(),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                _tabNavigator(0, const ViajeDisponible()),
                _tabNavigator(1, const TaxistaTrabajoHub()),
                _tabNavigator(2, const TaxistaServiciosTab()),
                _tabNavigator(3, const TaxistaCuentaTab()),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.local_taxi_outlined),
            selectedIcon: Icon(Icons.local_taxi),
            label: 'Recibir',
          ),
          NavigationDestination(
            icon: Icon(Icons.work_outline),
            selectedIcon: Icon(Icons.work_rounded),
            label: 'Trabajo',
          ),
          NavigationDestination(
            icon: Icon(Icons.travel_explore_outlined),
            selectedIcon: Icon(Icons.travel_explore),
            label: 'Servicios',
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
