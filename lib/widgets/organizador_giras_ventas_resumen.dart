import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'package:flygo_nuevo/widgets/pool_ventas_rai_resumen.dart';

/// Resumen en vivo de ventas de giras activas del organizador.
class OrganizadorGirasVentasResumen extends StatelessWidget {
  const OrganizadorGirasVentasResumen({super.key});

  static const Set<String> _estadosActivos = <String>{
    'abierto',
    'preconfirmado',
    'confirmado',
    'lleno',
    'activo',
    'disponible',
    'buscando',
    'en_ruta',
  };

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: PoolRepo.streamPoolsTaxista(ownerTaxistaId: uid),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 3),
          );
        }

        final docs = snap.data!.docs.where((doc) {
          final e = (doc.data()['estado'] ?? '').toString().toLowerCase();
          return _estadosActivos.contains(e);
        }).toList();

        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white12
                    : const Color(0xFFE2E8F0),
              ),
            ),
            child: Text(
              'Cuando publiques una gira, aquí verás en tiempo real '
              'cuántos cupos se venden en RAI y cuántos quedan.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isDark ? Colors.white70 : const Color(0xFF475467),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Tus ventas en vivo',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            ...docs.take(4).map((doc) {
              final d = doc.data();
              final destino = (d['destino'] ?? 'Destino').toString();
              final origen = (d['origenTown'] ?? '').toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '$origen → $destino',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    PoolVentasRaiResumen(poolData: d, compact: true),
                  ],
                ),
              );
            }),
            if (docs.length > 4)
              Text(
                'Y ${docs.length - 4} salida(s) más en «Mis salidas».',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : const Color(0xFF667085),
                ),
              ),
          ],
        );
      },
    );
  }
}
