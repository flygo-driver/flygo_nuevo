import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/historial_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/reservas_programadas_cliente.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/widgets/shell_tab_nav.dart';

/// Punto de entrada Mis viajes: enlaza a las mismas pantallas que el menu lateral
/// sin anidar varios AppBar.
class ClienteMisViajesHub extends StatelessWidget {
  const ClienteMisViajesHub({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return RaiShellTabScaffold(
      title: 'Mis viajes',
      backTooltip: 'Inicio',
      onBack: ShellTabController.clienteIrAInicio,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        children: [
          if (uid != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uid)
                  .snapshots(),
              builder: (context, userSnap) {
                final String vidFirestore = (userSnap.data?.data()?['viajeActivoId'] ??
                        '')
                    .toString()
                    .trim();
                final String vidPausa =
                    ActiveTripService.viajeIdPausaVoluntariaCliente;
                final String vidEfectivo =
                    ActiveTripService.resolverViajeIdClienteParaPausa(
                  preferido: vidFirestore.isNotEmpty ? vidFirestore : vidPausa,
                );

                return StreamBuilder<Viaje?>(
                  stream: ViajesRepo.streamEstadoViajePorCliente(uid),
                  builder: (context, s) {
                    final bool activo =
                        s.data != null || vidEfectivo.isNotEmpty;
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
                  onTap: () async {
                    if (!activo) {
                      final String? hidratado =
                          await ActiveTripService.hidratarViajeActivoCliente(
                        uid,
                      );
                      if (hidratado == null || hidratado.isEmpty) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'No tienes un viaje activo. Revisa «Reservas programadas» '
                              'o solicita un viaje desde Inicio.',
                            ),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                        return;
                      }
                    }
                    NavigationService.retomarViajeActivoCliente();
                  },
                );
                  },
                );
              },
            ),
          _HubTile(
            icon: Icons.event_available_outlined,
            title: 'Reservas programadas',
            subtitle: 'Próximas recogidas y seguimiento del pool',
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
            subtitle: 'Viajes completados · factura y detalle',
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