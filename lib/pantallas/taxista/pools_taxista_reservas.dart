import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';

class PoolsTaxistaReservas extends StatelessWidget {
  final String poolId;
  const PoolsTaxistaReservas({super.key, required this.poolId});

  void _snack(ScaffoldMessengerState messenger, String m) {
    messenger.showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final poolRef = PoolRepo.pools.doc(poolId);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Reservas',
          style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: poolRef.collection('reservas').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return const Center(child: Text('Error cargando reservas.', style: TextStyle(color: Colors.white54)));
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Sin reservas aún.', style: TextStyle(color: Colors.white54)));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final d = docs[i].data();
              final id = docs[i].id;
              final estado = (d['estado'] ?? '').toString();
              final seats = (d['seats'] ?? 0) as int;
              final total = ((d['total'] ?? 0.0) as num).toDouble();
              final deposit = ((d['deposit'] ?? 0.0) as num).toDouble();

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF121212),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Asientos: $seats  •  Estado: $estado',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total: RD\$ ${total.toStringAsFixed(0)}  •  Depósito: RD\$ ${deposit.toStringAsFixed(0)}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    if (estado != 'pagado')
                      TextButton.icon(
                        onPressed: () async {
                          // Captura el messenger ANTES del await para evitar usar BuildContext luego
                          final messenger = ScaffoldMessenger.of(ctx);
                          try {
                            await PoolRepo.marcarReservaPagada(
                              poolId: poolId,
                              reservaId: id,
                            );
                            _snack(messenger, 'Marcada como pagada');
                          } catch (e) {
                            _snack(messenger, '❌ $e');
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Marcar pagada'),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
