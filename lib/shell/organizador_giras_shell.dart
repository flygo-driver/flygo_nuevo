import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/utils/pool_modo_publicacion.dart';
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_lista.dart';
import 'package:flygo_nuevo/pantallas/taxista/organizador_giras_perfil_tab.dart';
import 'package:flygo_nuevo/widgets/pool_gira_publicar_ui.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1020) : const Color(0xFFF1F5F9),
      body: Stack(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SafeArea(
                bottom: false,
                child: OrganizadorGirasPerfilStream(
                  builder: (context, data) {
                    final agencia =
                        (data['agenciaNombre'] ?? '').toString().trim();
                    final nombre = (data['nombre'] ?? '').toString().trim();
                    final extra = agencia.isNotEmpty
                        ? agencia
                        : (nombre.isNotEmpty ? nombre : null);
                    return OrganizadorGirasBrandHeader(
                      compact: true,
                      subtitulo: extra != null
                          ? '$extra · vendé cupos con RAI'
                          : null,
                    );
                  },
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: _tabs,
                ),
              ),
            ],
          ),
          if (_index == 1)
            const RaiCambioModoSesionBorde(destinoPasajero: true),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () => PoolModoPublicacionUi.abrirPublicar(context),
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nueva salida'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        height: 68,
        backgroundColor: isDark ? const Color(0xFF121826) : Colors.white,
        indicatorColor: cs.primary.withValues(alpha: 0.16),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded, color: cs.primary),
            label: 'Mis salidas',
          ),
          NavigationDestination(
            icon: const Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded, color: cs.primary),
            label: 'Mi agencia',
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
      return builder(context, const <String, dynamic>{});
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        return builder(context, snap.data?.data() ?? const <String, dynamic>{});
      },
    );
  }
}
