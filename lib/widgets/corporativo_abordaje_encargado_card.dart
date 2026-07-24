import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/widgets/corporativo_pasajeros_chofer_card.dart';

/// Panel encargado: quién abordó y quién fue dejado en destino (viaje en vivo).
class CorporativoAbordajeEncargadoCard extends StatelessWidget {
  const CorporativoAbordajeEncargadoCard({
    super.key,
    required this.viajeId,
    this.titulo = 'Registro de abordaje',
  });

  final String viajeId;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    if (viajeId.trim().isEmpty) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data();
        if (d == null) return const SizedBox.shrink();
        final estado = (d['estado'] ?? '').toString();
        final activo = d['activo'] == true;
        if (!activo &&
            estado != 'en_curso' &&
            estado != 'a_bordo' &&
            estado != 'completado' &&
            estado != 'finalizado') {
          return const SizedBox.shrink();
        }

        final pasajeros =
            CorporativoPasajerosChoferCard.pasajerosDesdeMapViaje(d);
        if (pasajeros.isEmpty) return const SizedBox.shrink();

        final abordados = pasajeros.where((x) => x.abordado).length;
        final dejados = pasajeros.where((x) => x.dejadoConfirmado).length;

        return corporativoCard(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.how_to_reg, color: p.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      titulo,
                      style: TextStyle(
                        color: p.onCard,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    '$abordados/${pasajeros.length} abordo',
                    style: TextStyle(color: p.muted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Dejados en destino: $dejados/${pasajeros.length}',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              ...pasajeros.map((pas) {
                IconData icon;
                Color color;
                String estadoTxt;
                if (pas.dejadoConfirmado) {
                  icon = Icons.check_circle;
                  color = Colors.green.shade700;
                  estadoTxt = 'Dejado en destino';
                } else if (pas.abordado) {
                  icon = Icons.directions_bus;
                  color = Colors.blue.shade700;
                  estadoTxt = 'Abordó';
                } else {
                  icon = Icons.hourglass_empty;
                  color = Colors.orange.shade700;
                  estadoTxt = 'Pendiente';
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(icon, color: color, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pas.nombre,
                              style: TextStyle(
                                color: p.onCard,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '$estadoTxt · ${pas.destinoLabel}',
                              style: TextStyle(color: p.muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
