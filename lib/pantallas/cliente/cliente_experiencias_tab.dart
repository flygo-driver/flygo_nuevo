import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/servicios_extras/pools_cliente_lista.dart';
import 'package:flygo_nuevo/utilidades/constante.dart' show rutaBolaPueblo;
import 'package:flygo_nuevo/pantallas/cliente/bola_conductores_en_ruta_cliente.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';

/// Tours / giras y Bola ahorro (mismas rutas que el drawer).
class ClienteExperienciasTab extends StatelessWidget {
  const ClienteExperienciasTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Experiencias'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        children: [
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
          Card(
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
              subtitle: const Text('Viajes compartidos · tablero'),
              trailing: Icon(Icons.chevron_right, color: cs.outline),
              onTap: () => Navigator.of(context, rootNavigator: true)
                  .pushNamed(rutaBolaPueblo),
            ),
          ),
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
        ],
      ),
    );
  }
}
