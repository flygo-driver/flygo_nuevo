import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'pools_taxista_reservas.dart';
import 'pools_taxista_crear.dart';

class PoolsTaxistaLista extends StatelessWidget {
  const PoolsTaxistaLista({super.key});

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    final f = DateFormat('EEE d MMM • HH:mm', 'es');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Mis viajes por cupos',
          style: TextStyle(
            color: Colors.greenAccent,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PoolsTaxistaCrear()),
            ),
            icon: const Icon(Icons.add),
            tooltip: 'Crear viaje',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: PoolRepo.streamPoolsTaxista(ownerTaxistaId: u!.uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No tienes viajes creados.',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final d = docs[i].data();
              final id = docs[i].id;

              final cap = (d['capacidad'] ?? 0) as int;
              final occ = (d['asientosReservados'] ?? 0) as int;
              final pag = (d['asientosPagados'] ?? 0) as int;
              final fee = ((d['feePct'] ?? 0.0) as num).toDouble();
              final precio = (d['precioPorAsiento'] as num).toDouble();
              final mult = (d['sentido'] == 'ida_y_vuelta') ? 2 : 1;
              final ingresoAseg = ((d['montoPagado'] ?? 0.0) as num).toDouble();
              final ingresoProj = occ * precio * mult;
              final neto = ingresoAseg * (1 - fee);
              final estado = (d['estado'] ?? '').toString();
              final confirmado = estado == 'confirmado';

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF121212),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          '${d['origenTown']} → ${d['destino']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (confirmado)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            // Reemplazo de withOpacity(.18)
                            color: Colors.green.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                            // Reemplazo de withOpacity(.5)
                            border: Border.all(
                              color: Colors.greenAccent.withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Text(
                            'Confirmado',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      f.format((d['fechaSalida'] as Timestamp).toDate()),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: const LinearProgressIndicator(
                              // value se setea fuera con Stateful/stream; aquí lo dejamos dinámico abajo
                              // pero como estamos en Stateless y value depende de cap/occ, lo armamos aquí mismo:
                              // (usamos un widget builder inline más abajo)
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$occ/$cap',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                    // El LinearProgressIndicator necesita el value, así que lo añadimos aquí:
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: cap == 0 ? 0 : (occ / cap).clamp(0, 1),
                          backgroundColor: Colors.white12,
                          color: Colors.greenAccent,
                          minHeight: 8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pagados: $pag  •  Ingreso asegurado: RD\$ ${ingresoAseg.toStringAsFixed(0)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      'Proyectado: RD\$ ${ingresoProj.toStringAsFixed(0)}  •  Payout neto: RD\$ ${neto.toStringAsFixed(0)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Estado: $estado',
                          style: const TextStyle(color: Colors.white60),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () async {
                            final n = await PoolRepo.limpiarReservasVencidas(id);
                            // Evita "use_build_context_synchronously"
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Reservas vencidas limpiadas: $n',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.cleaning_services),
                          label: const Text('Limpiar vencidas'),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PoolsTaxistaReservas(poolId: id),
                              ),
                            );
                          },
                          icon: const Icon(Icons.people_alt_outlined),
                          label: const Text('Reservas'),
                        ),
                      ],
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
