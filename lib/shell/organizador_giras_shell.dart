import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/utils/pool_modo_publicacion.dart';
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_lista.dart';
import 'package:flygo_nuevo/pantallas/taxista/organizador_giras_perfil_tab.dart';
import 'package:flygo_nuevo/widgets/rai_cambio_modo_sesion_borde.dart';

/// Shell reducido: solo giras por cupos (organizador sin guagua propia).
class OrganizadorGirasShell extends StatefulWidget {
  const OrganizadorGirasShell({super.key});

  @override
  State<OrganizadorGirasShell> createState() => _OrganizadorGirasShellState();
}

class _OrganizadorGirasShellState extends State<OrganizadorGirasShell> {
  int _index = 0;

  static const _tabs = <Widget>[
    PoolsTaxistaLista(embeddedInOrganizadorShell: true),
    OrganizadorGirasPerfilTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
        index: _index,
        children: _tabs,
      ),
          if (_index == 1)
            const RaiCambioModoSesionBorde(destinoPasajero: true),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () => PoolModoPublicacionUi.abrirPublicar(context),
              icon: const Icon(Icons.add),
              label: const Text('Nueva salida'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.tour_outlined),
            selectedIcon: Icon(Icons.tour, color: cs.primary),
            label: 'Mis giras',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: cs.primary),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

/// Cabecera con nombre de agencia para pantallas del organizador.
class OrganizadorGirasPerfilStream extends StatelessWidget {
  const OrganizadorGirasPerfilStream({super.key, required this.builder});

  final Widget Function(BuildContext context, Map<String, dynamic> data)
      builder;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return builder(context, const {});
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        return builder(context, snap.data?.data() ?? const {});
      },
    );
  }
}
