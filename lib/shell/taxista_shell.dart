import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/taxista/documentos_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/taxista_cuenta_tab.dart';
import 'package:flygo_nuevo/pantallas/taxista/taxista_servicios_tab.dart';
import 'package:flygo_nuevo/pantallas/taxista/taxista_trabajo_hub.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_disponible.dart';

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

  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List<GlobalKey<NavigatorState>>.generate(
          4, (_) => GlobalKey<NavigatorState>());

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
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          _tabNavigator(0, const ViajeDisponible()),
          _tabNavigator(1, const TaxistaTrabajoHub()),
          _tabNavigator(2, const TaxistaServiciosTab()),
          _tabNavigator(3, const TaxistaCuentaTab()),
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
