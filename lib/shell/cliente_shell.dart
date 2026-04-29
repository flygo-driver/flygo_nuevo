import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_cuenta_tab.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_experiencias_tab.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_home.dart';
import 'package:flygo_nuevo/pantallas/cliente/cliente_mis_viajes_hub.dart';
import 'package:flygo_nuevo/widgets/cliente_fidelidad_milestone_listener.dart';
import 'package:flygo_nuevo/widgets/cliente_post_viaje_listener.dart';

/// Shell del cliente: barra inferior fija; cada pestaña usa un [Navigator] anidado
/// (pantallas con [Navigator.push] no tapan Inicio / Mis viajes / etc.).
class ClienteShell extends StatelessWidget {
  const ClienteShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const ClientePostViajeListener(
      child: ClienteFidelidadMilestoneListener(
        child: _ClienteShellScaffold(),
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

  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List<GlobalKey<NavigatorState>>.generate(
          4, (_) => GlobalKey<NavigatorState>());

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
          _tabNavigator(0, const ClienteHome()),
          _tabNavigator(1, const ClienteMisViajesHub()),
          _tabNavigator(2, const ClienteExperienciasTab()),
          _tabNavigator(3, const ClienteCuentaTab()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
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
