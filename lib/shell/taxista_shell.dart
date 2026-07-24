// ignore_for_file: avoid_print

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
import 'package:flygo_nuevo/widgets/corporativo_auto_abrir_watcher.dart';
import 'package:flygo_nuevo/widgets/taxista_post_viaje_listener.dart';
import 'package:flygo_nuevo/widgets/viaje_overlay_error_shield.dart';
import 'package:flygo_nuevo/widgets/taxista_registro_gate.dart';
import 'package:flygo_nuevo/widgets/taxista_documentos_gate.dart';
import 'package:flygo_nuevo/widgets/rai_offline_banner.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_taxista_banner.dart';
import 'package:flygo_nuevo/widgets/shell_tab_nav.dart';
import 'package:flygo_nuevo/servicios/pool_deep_link.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

/// Shell del taxista: una barra inferior fija; cada pestaña usa un [Navigator] anidado.
class TaxistaShell extends StatelessWidget {
  const TaxistaShell({super.key, this.openDocumentosOnLaunch = false});

  /// Abre Cuenta y apila [DocumentosTaxista] (documentos pendientes al entrar).
  final bool openDocumentosOnLaunch;

  @override
  Widget build(BuildContext context) {
    return TaxistaRegistroGate(
      child: TaxistaDocumentosGate(
        child: CorporativoAutoAbrirWatcher(
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
  int _index = ShellTabController.taxistaTabViajes;

  final GlobalKey _viajeEnCursoTaxistaShellKey = GlobalKey();

  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List<GlobalKey<NavigatorState>>.generate(
          4, (_) => GlobalKey<NavigatorState>());

  StreamSubscription<bool>? _viajeActivoSub;
  bool _viajeActivoShell = false;
  Timer? _viajeOffDebounce;
  bool _mostroViajeAlgunaVez = false;
  bool _corpExcluyeOverlayViajeEnCurso = false;
  Timer? _bootstrapViajeTimeout;
  VoidCallback? _offlineListener;
  VoidCallback? _shellRebuildListener;

  static const Duration _kBootstrapViajeMaxWait = Duration(seconds: 3);
  static const Duration _kViajeOffDebounce = Duration(seconds: 3);

  Future<bool> _viajeIdRequiereOverlayShell(String uid, String viajeId) async {
    final id = viajeId.trim();
    if (id.isEmpty) {
      return ActiveTripService.debeMantenerOverlayViajeEnShell;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(id)
          .get();
      if (!snap.exists) return false;
      return ViajePoolTaxistaGate.viajeDocDebeMostrarOverlayShell(
        snap.data() ?? <String, dynamic>{},
        uid,
      );
    } catch (_) {
      return false;
    }
  }

  void _aplicarViajeActivoDesdeStream(bool ok) {
    if (!mounted) return;
    _bootstrapViajeTimeout?.cancel();

    if (ok) {
      _viajeOffDebounce?.cancel();
      unawaited(_validarOverlayViajeActivoTaxista());
      return;
    }

    if (ActiveTripService.debeMantenerOverlayViajeEnShell ||
        ActiveTripService.debeBloquearShellSinViajeTaxista) {
      unawaited(_validarOverlayViajeActivoTaxista());
      return;
    }

    if (_viajeActivoShell == true && _mostroViajeAlgunaVez) {
      _viajeOffDebounce?.cancel();
      _viajeOffDebounce = Timer(_kViajeOffDebounce, () async {
        if (!mounted) return;
        if (ActiveTripService.debeMantenerOverlayViajeEnShell ||
            ActiveTripService.debeBloquearShellSinViajeTaxista) {
          return;
        }
        final String? uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          final bool sigue =
              await ActiveTripService.usuarioTieneViajeEnSeguimiento(uid);
          if (sigue) return;
        }
        if (!mounted || _viajeActivoShell == false) return;
        print('[VIAJE_ACTIVO] taxista_shell stream tieneActivo=false (confirmado)');
        setState(() {
          _viajeActivoShell = false;
          _mostroViajeAlgunaVez = false;
        });
      });
      return;
    }

    if (_viajeActivoShell != ok) {
      print('[VIAJE_ACTIVO] taxista_shell stream tieneActivo=$ok');
      setState(() {
        _viajeActivoShell = ok;
        if (!ok) _mostroViajeAlgunaVez = false;
      });
    }
  }

  Future<void> _aplicarSinOverlayViajePool() async {
    ActiveTripService.cancelarBloqueoShellTaxista();
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      await ViajesRepo.limpiarViajeActivoSiNoOperativo(uid);
      await RaiLocalReadCache.clearActiveTripId(uid);
    }
    if (!mounted) return;
    setState(() {
      _viajeActivoShell = false;
      _mostroViajeAlgunaVez = false;
    });
  }

  /// Evita overlay «Mi viaje en curso» cuando el activo es ruta corporativa.
  Future<void> _validarOverlayViajeActivoTaxista() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || !mounted) return;
    try {
      final uSnap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      final String vid =
          (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (vid.isNotEmpty) {
        final vSnap = await FirebaseFirestore.instance
            .collection('viajes')
            .doc(vid)
            .get();
        final Map<String, dynamic> d = vSnap.data() ?? <String, dynamic>{};
        if (CorporativoTaxistaService.corpAsignadoUsaPantallaPropia(d, uid)) {
          final bool pantallaDestinos =
              CorporativoTaxistaService.corpDebeUsarPantallaDestinosChofer(
            d,
            uidTaxista: uid,
          );
          if (!mounted) return;
          print(
            '[VIAJE_ACTIVO] taxista_shell stream corp → sin overlay viaje=$vid',
          );
          setState(() {
            _viajeActivoShell = false;
            _mostroViajeAlgunaVez = false;
            _corpExcluyeOverlayViajeEnCurso = pantallaDestinos;
          });
          await _aplicarSinOverlayViajePool();
          ActiveTripService.notificarRebuildShell();
          return;
        }
      }

      final bool pool =
          await ActiveTripService.usuarioTieneViajeEnSeguimiento(uid);
      if (!mounted) return;
      if (!pool) {
        print('[VIAJE_ACTIVO] taxista_shell validar → sin viaje pool');
        await _aplicarSinOverlayViajePool();
        return;
      }

      _mostroViajeAlgunaVez = true;
      if (_viajeActivoShell != true) {
        print('[VIAJE_ACTIVO] taxista_shell stream tieneActivo=true');
        setState(() => _viajeActivoShell = true);
      }
    } catch (e) {
      print('[VIAJE_ACTIVO] taxista_shell validar error: $e');
      if (!mounted) return;
      await _aplicarSinOverlayViajePool();
    }
  }

  Future<void> _reconciliarInicioTaxista(String uid) async {
    try {
      await ViajesRepo.limpiarViajeActivoSiNoOperativo(uid);
      final bool pool =
          await ActiveTripService.usuarioTieneViajeEnSeguimiento(uid);
      if (!mounted) return;
      if (pool) {
        final uSnap = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid)
            .get();
        final vid =
            (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
        final bool overlay = vid.isNotEmpty
            ? await _viajeIdRequiereOverlayShell(uid, vid)
            : true;
        if (!mounted) return;
        if (overlay) {
          setState(() {
            _viajeActivoShell = true;
            _mostroViajeAlgunaVez = true;
          });
        }
        return;
      }
      await RaiLocalReadCache.clearActiveTripId(uid);
      ActiveTripService.cancelarBloqueoShellTaxista();
      ActiveTripService.cancelarMantenimientoOverlayViaje();
      if (!mounted) return;
      setState(() {
        _viajeActivoShell = false;
        _mostroViajeAlgunaVez = false;
        _corpExcluyeOverlayViajeEnCurso = false;
      });
    } catch (e) {
      print('[VIAJE_ACTIVO] taxista_shell reconciliar inicio: $e');
      if (!mounted) return;
      setState(() => _viajeActivoShell = false);
    }
  }

  void _onShellTabController() {
    final i = ShellTabController.taxistaIndex.value;
    if (!mounted || i == _index) return;
    setState(() => _index = i);
  }

  @override
  void initState() {
    super.initState();
    if (widget.openDocumentosOnLaunch) {
      _index = ShellTabController.taxistaTabCuenta;
      ShellTabController.taxistaIndex.value = ShellTabController.taxistaTabCuenta;
    } else {
      ShellTabController.taxistaIrAViajesAhora();
      _index = ShellTabController.taxistaTabViajes;
    }
    ShellTabController.taxistaIndex.addListener(_onShellTabController);
    RaiConnectivityService.instance.ensureStarted();
    unawaited(ComisionPrepagoConfigService.ensureStarted());
    unawaited(FinanceConfigService.ensureStarted());
    unawaited(RaiUbicacionTaxistaService.instance.ensureStarted());

    if (widget.openDocumentosOnLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _navigatorKeys[ShellTabController.taxistaTabCuenta].currentState
            ?.push<void>(
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
      _viajeActivoShell = false;
      unawaited(_reconciliarInicioTaxista(uid));

      _offlineListener = () => _resolverBootstrapSiOffline(uid);
      RaiConnectivityService.instance.offline.addListener(_offlineListener!);

      _bootstrapViajeTimeout = Timer(_kBootstrapViajeMaxWait, () {
        if (!mounted || _viajeActivoShell == true) return;
        unawaited(_resolverBootstrapConCache(uid, porTimeout: true));
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(() async {
          final uSnap = await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(uid)
              .get();
          final vid =
              (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
          var esCorpSinOverlay = false;
          if (vid.isNotEmpty) {
            final vSnap = await FirebaseFirestore.instance
                .collection('viajes')
                .doc(vid)
                .get();
            final d = vSnap.data() ?? <String, dynamic>{};
            esCorpSinOverlay = CorporativoTaxistaService
                .corpAsignadoUsaPantallaPropia(d, uid);
          }
          if (!esCorpSinOverlay) {
            final corpId = await CorporativoTaxistaService
                .idViajeCorporativoOperativoParaChofer(uid);
            esCorpSinOverlay = corpId != null && corpId.isNotEmpty;
          }
          if (!esCorpSinOverlay || !mounted) return;
          ActiveTripService.cancelarBloqueoShellTaxista();
          ActiveTripService.cancelarMantenimientoOverlayViaje();
          await RaiLocalReadCache.clearActiveTripId(uid);
          String? corpVid = vid.isNotEmpty ? vid : null;
          if (corpVid == null) {
            corpVid = await CorporativoTaxistaService
                .idViajeCorporativoOperativoParaChofer(uid);
          }
          if (_viajeActivoShell != false && mounted) {
            setState(() {
              _viajeActivoShell = false;
              _mostroViajeAlgunaVez = false;
              _corpExcluyeOverlayViajeEnCurso = true;
            });
          }
          ActiveTripService.notificarRebuildShell();
        }());
      });

      _shellRebuildListener = () {
        if (!mounted) return;
        if (!ActiveTripService.debeBloquearShellSinViajeTaxista &&
            !ActiveTripService.debeMantenerOverlayViajeEnShell) {
          return;
        }
        final String? uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null || uid.isEmpty) return;
        unawaited(() async {
          final uSnap = await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(uid)
              .get();
          final vid =
              (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
          if (vid.isNotEmpty) {
            final vSnap = await FirebaseFirestore.instance
                .collection('viajes')
                .doc(vid)
                .get();
            final d = vSnap.data() ?? <String, dynamic>{};
            if (CorporativoTaxistaService.corpAsignadoUsaPantallaPropia(
              d,
              uid,
            )) {
              ActiveTripService.cancelarBloqueoShellTaxista();
              ActiveTripService.cancelarMantenimientoOverlayViaje();
              final pantallaDestinos =
                  CorporativoTaxistaService.corpDebeUsarPantallaDestinosChofer(
                d,
                uidTaxista: uid,
              );
              if (_viajeActivoShell != false || pantallaDestinos) {
                print(
                  '[VIAJE_ACTIVO] taxista_shell rebuild tick → corp, sin overlay',
                );
                setState(() {
                  _viajeActivoShell = false;
                  _mostroViajeAlgunaVez = false;
                  if (pantallaDestinos) {
                    _corpExcluyeOverlayViajeEnCurso = true;
                  }
                });
              }
              return;
            }
          }
          final corpOp =
              await CorporativoTaxistaService
                  .idViajeCorporativoOperativoParaChofer(uid);
          if (!mounted) return;
          if (corpOp != null && corpOp.isNotEmpty) {
            ActiveTripService.cancelarBloqueoShellTaxista();
            ActiveTripService.cancelarMantenimientoOverlayViaje();
            if (_viajeActivoShell != false) {
              print(
                '[VIAJE_ACTIVO] taxista_shell rebuild tick → corp operativo, sin overlay',
              );
              setState(() {
                _viajeActivoShell = false;
                _mostroViajeAlgunaVez = false;
                _corpExcluyeOverlayViajeEnCurso = true;
              });
            }
            return;
          }
          final bool pool =
              await ActiveTripService.usuarioTieneViajeEnSeguimiento(uid);
          if (!mounted) return;
          if (!pool) {
            await _aplicarSinOverlayViajePool();
            return;
          }
          if (_viajeActivoShell != true) {
            print('[VIAJE_ACTIVO] taxista_shell rebuild tick → overlay viaje');
            setState(() {
              _viajeActivoShell = true;
              _mostroViajeAlgunaVez = true;
            });
          }
        }());
      };
      ActiveTripService.shellRebuildTick.addListener(_shellRebuildListener!);

      _viajeActivoSub =
          ActiveTripService.streamTieneViajeActivo(uid).listen((bool ok) {
        _aplicarViajeActivoDesdeStream(ok);
      }, onError: (Object e) {
        print('[VIAJE_ACTIVO] taxista_shell stream error: $e');
        if (!mounted) return;
        unawaited(_resolverBootstrapConCache(uid, porTimeout: false));
      });
    }
  }

  void _resolverBootstrapSiOffline(String uid) {
    if (!RaiConnectivityService.instance.isOffline) return;
    if (_viajeActivoShell) return;
    unawaited(_resolverBootstrapConCache(uid, porTimeout: false));
  }

  Future<void> _resolverBootstrapConCache(
    String uid, {
    required bool porTimeout,
  }) async {
    if (!mounted || _viajeActivoShell == true) return;
    _bootstrapViajeTimeout?.cancel();

    bool mostrarViaje = false;
    if (RaiConnectivityService.instance.isOffline) {
      final String? cached =
          await RaiLocalReadCache.lastKnownActiveTripId(uid);
      if ((cached ?? '').trim().isNotEmpty) {
        mostrarViaje =
            await _viajeIdRequiereOverlayShell(uid, cached!);
      }
    } else {
      mostrarViaje =
          await ActiveTripService.usuarioTieneViajeEnSeguimiento(uid);
    }

    if (!mounted || _viajeActivoShell == true) return;
    print(
      '[VIAJE_ACTIVO] taxista_shell bootstrap '
      '${porTimeout ? 'timeout' : 'offline/error'} → viaje=$mostrarViaje',
    );
    setState(() {
      _viajeActivoShell = mostrarViaje;
      if (mostrarViaje) _mostroViajeAlgunaVez = true;
    });
  }

  @override
  void dispose() {
    ShellTabController.taxistaIndex.removeListener(_onShellTabController);
    _bootstrapViajeTimeout?.cancel();
    _viajeOffDebounce?.cancel();
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

  void _seleccionarTab(int i) {
    ShellTabController.taxistaIndex.value = i;
    if (!mounted) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final String? uidOffline = FirebaseAuth.instance.currentUser?.uid;
    final bool pantallaViajeEnCurso =
        !_corpExcluyeOverlayViajeEnCurso && _viajeActivoShell == true;
    if (pantallaViajeEnCurso) {
      print(
          '[VIAJE_ACTIVO] taxista_shell: pantalla completa ViajeEnCursoTaxista (sin tabs)');
      return Scaffold(
        body: ViajeOverlayErrorShield(
          esTaxista: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RaiOfflineBanner(uid: uidOffline),
              Expanded(
                child: ViajeEnCursoTaxista(key: _viajeEnCursoTaxistaShellKey),
              ),
            ],
          ),
        ),
      );
    }
    final Color barSurface = Theme.of(context).colorScheme.surface;
    final bool barOscura =
        ThemeData.estimateBrightnessForColor(barSurface) == Brightness.dark;
    final overlayBarra = SystemUiOverlayStyle(
      systemNavigationBarColor: barSurface,
      systemNavigationBarIconBrightness:
          barOscura ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayBarra,
      child: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RaiOfflineBanner(uid: uidOffline),
          const RaiUbicacionTaxistaBanner(),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                _tabNavigator(
                  0,
                  const ViajeDisponible(ocultarTabCompartidos: true),
                ),
                _tabNavigator(1, const TaxistaServiciosTab()),
                _tabNavigator(2, const TaxistaTrabajoHub()),
                _tabNavigator(3, const TaxistaCuentaTab()),
              ],
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
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  height: 1.1,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith(
                (_) => const IconThemeData(size: 22),
              ),
              indicatorShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
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
                  icon: Icon(Icons.local_taxi_outlined),
                  selectedIcon: Icon(Icons.local_taxi),
                  label: 'Viajes',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view_rounded),
                  label: 'Servicios',
                ),
                NavigationDestination(
                  icon: Icon(Icons.work_outline),
                  selectedIcon: Icon(Icons.work_rounded),
                  label: 'Trabajo',
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
    );
  }
}
