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
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/widgets/rai_offline_banner.dart';

/// Shell del taxista: una barra inferior fija; cada pestaña usa un [Navigator] anidado.
class TaxistaShell extends StatefulWidget {
  const TaxistaShell({super.key, this.openDocumentosOnLaunch = false});

  /// Abre Cuenta y apila [DocumentosTaxista] (documentos pendientes al entrar).
  final bool openDocumentosOnLaunch;

  @override
  State<TaxistaShell> createState() => _TaxistaShellState();
}

class _TaxistaShellState extends State<TaxistaShell> {
  int _index = 0;

  final GlobalKey _viajeEnCursoTaxistaShellKey = GlobalKey();

  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List<GlobalKey<NavigatorState>>.generate(
          4, (_) => GlobalKey<NavigatorState>());

  StreamSubscription<bool>? _viajeActivoSub;
  bool? _viajeActivoShell;

  @override
  void initState() {
    super.initState();
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
    });
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _viajeActivoShell = false;
    } else {
      _viajeActivoSub =
          ActiveTripService.streamTieneViajeActivo(uid).listen((bool ok) {
        if (!mounted) return;
        if (_viajeActivoShell != ok) {
          print('[VIAJE_ACTIVO] taxista_shell stream tieneActivo=$ok');
          setState(() => _viajeActivoShell = ok);
        }
      }, onError: (Object e) {
        print('[VIAJE_ACTIVO] taxista_shell stream error: $e');
        if (mounted) setState(() => _viajeActivoShell = false);
      });
    }
  }

  @override
  void dispose() {
    _viajeActivoSub?.cancel();
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
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      );
    }
    if (_viajeActivoShell == true) {
      print(
          '[VIAJE_ACTIVO] taxista_shell: pantalla completa ViajeEnCursoTaxista (sin tabs)');
      return Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RaiOfflineBanner(uid: uidOffline),
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
