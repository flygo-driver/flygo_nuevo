import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/cliente/historial_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/reservas_programadas_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

/// Punto de entrada «Mis viajes»: enlaza a las mismas pantallas que el menú lateral
/// sin anidar varios `AppBar`.
class ClienteMisViajesHub extends StatelessWidget {
  const ClienteMisViajesHub({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis viajes'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        children: [
          if (uid != null)
            StreamBuilder(
              stream: ViajesRepo.streamEstadoViajePorCliente(uid),
              builder: (context, s) {
                final activo = s.data != null;
                return _HubTile(
                  icon: Icons.directions_car_outlined,
                  title: 'Viaje en curso',
                  subtitle: activo
                      ? 'Seguimiento en tiempo real'
                      : 'No tienes un viaje activo',
                  trailing: activo
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: cs.primary),
                          ),
                          child: Text(
                            'Activo',
                            style: TextStyle(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : null,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ViajeEnCursoCliente(),
                      ),
                    );
                  },
                );
              },
            ),
          _HubTile(
            icon: Icons.event_available_outlined,
            title: 'Reservas programadas',
            subtitle: 'Seguimiento y pool de conductores',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ReservasProgramadasCliente(),
                ),
              );
            },
          ),
          _HubTile(
            icon: Icons.history,
            title: 'Historial',
            subtitle: 'Completados y pendientes',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const HistorialCliente(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Text(subtitle),
        trailing: trailing ?? Icon(Icons.chevron_right, color: cs.outline),
        onTap: onTap,
      ),
    );
  }
}
