import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_actions.dart';
import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_lista.dart';
import 'package:flygo_nuevo/utilidades/constante.dart' show rutaBolaPueblo;
import 'package:flygo_nuevo/pantallas/cliente/bola_conductores_en_ruta_cliente.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/productos_config_service.dart';

/// Tours / giras y Bola ahorro (mismas rutas que el drawer).
class ClienteExperienciasTab extends StatelessWidget {
  const ClienteExperienciasTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ProductosConfigService.revision,
      builder: (context, _, __) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cards = <Widget>[];

    if (ProductosConfigService.muestraGiras) {
      cards.add(
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            leading: CircleAvatar(
              backgroundColor: cs.tertiaryContainer,
              foregroundColor: cs.onTertiaryContainer,
              child: const Icon(Icons.groups_2_outlined),
            ),
            title: const Text(
              'Giras y tours',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: const Text('Catálogo de agencias y cupos'),
            trailing: Icon(Icons.chevron_right, color: cs.outline),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PoolsClienteLista(tipo: 'todos'),
                ),
              );
            },
          ),
        ),
      );
    }

    if (ProductosConfigService.muestraBola) {
      cards.add(
        StreamBuilder<Map<String, String>?>(
          stream: BolaPuebloRepo.streamBolaActivaCliente(
            FirebaseAuth.instance.currentUser?.uid ?? '',
          ),
          builder: (context, bolaSnap) {
            final Map<String, String>? activa = bolaSnap.data;
            final String subtitle = activa == null
                ? 'Viajes compartidos · tablero'
                : switch ((activa['estado'] ?? '').toString()) {
                    'abierta' => 'Pedido activo · tocá para continuar',
                    'acordada' => 'Bola acordada · Mi viaje',
                    'en_curso' => 'Viaje en curso · Mi viaje',
                    _ => 'Bola activa · tocá para continuar',
                  };
            return Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                leading: CircleAvatar(
                  backgroundColor: cs.secondaryContainer,
                  foregroundColor: cs.onSecondaryContainer,
                  child: const Icon(Icons.swap_horiz_rounded),
                ),
                title: const Text(
                  'Bola ahorro',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                subtitle: Text(subtitle),
                trailing: Icon(Icons.chevron_right, color: cs.outline),
                onTap: () async {
                  if (activa != null) {
                    final String? id = activa['id'];
                    if (id != null && id.isNotEmpty) {
                      await BolaPuebloDialogs.abrirModoViajeBolaPorId(
                        context: context,
                        bolaId: id,
                      );
                      return;
                    }
                  }
                  if (!context.mounted) return;
                  Navigator.of(context, rootNavigator: true)
                      .pushNamed(rutaBolaPueblo);
                },
              ),
            );
          },
        ),
      );
    }

    if (ProductosConfigService.muestraConductoresEnRuta) {
      cards.add(
        Card(
          clipBehavior: Clip.antiAlias,
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            leading: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
              child: const Icon(Icons.local_taxi_outlined),
            ),
            title: const Text(
              'Conductores en ruta',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: const Text(
              'Quién está en X y va para Y · negociás y vas a buscarlo',
            ),
            trailing: Icon(Icons.chevron_right, color: cs.outline),
            onTap: () => NavigationService.push(
              const BolaConductoresEnRutaClientePage(),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Experiencias'),
        centerTitle: true,
      ),
      body: cards.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No hay experiencias disponibles en este momento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              children: cards,
            ),
    );
  }
}
