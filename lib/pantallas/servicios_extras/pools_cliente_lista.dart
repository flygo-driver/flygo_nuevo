import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flygo_nuevo/servicios/pool_repo.dart';
import 'pools_cliente_detalle.dart';

class PoolsClienteLista extends StatefulWidget {
  final String tipo; // "consular" | "tour"
  const PoolsClienteLista({super.key, required this.tipo});

  @override
  State<PoolsClienteLista> createState() => _PoolsClienteListaState();
}

class _PoolsClienteListaState extends State<PoolsClienteLista> {
  final _towns = const [
    'Santo Domingo', 'Santiago', 'La Romana', 'Higüey', 'San Pedro', 'San Cristóbal'
  ];
  String _origenTown = 'Higüey';

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('EEE d MMM • HH:mm', 'es');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.tipo == 'consular' ? 'Servicios Consulares' : 'Tours turísticos',
          style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                const Text('Pueblo:', style: TextStyle(color: Colors.white70)),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _origenTown,
                  dropdownColor: const Color(0xFF1A1A1A),
                  underline: const SizedBox(),
                  items: _towns
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t, style: const TextStyle(color: Colors.white)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _origenTown = v ?? _origenTown),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: PoolRepo.streamPoolsCliente(
                tipo: widget.tipo,
                origenTown: _origenTown,
              ),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No hay salidas próximas desde este pueblo.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }
                final docs = snap.data!.docs;
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: docs.length,
                  itemBuilder: (ctx, i) {
                    final d = docs[i].data();
                    final id = docs[i].id;

                    final cap = (d['capacidad'] ?? 0) as int;
                    final occ = (d['asientosReservados'] ?? 0) as int;
                    final estado = (d['estado'] ?? '').toString();
                    final precio = (d['precioPorAsiento'] as num).toDouble();
                    final mult = (d['sentido'] == 'ida_y_vuelta') ? 2 : 1;
                    final fecha = (d['fechaSalida'] as Timestamp).toDate();

                    final left = (cap - occ).clamp(0, cap);
                    final confirmado = estado == 'confirmado';
                    final titulo = '${d['origenTown']} → ${d['destino']}';
                    final precioTxt = 'RD\$ ${(precio * mult).toStringAsFixed(0)} / pers';

                    return InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PoolsClienteDetalle(poolId: id),
                          ),
                        );
                      },
                      child: Container(
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
                                  titulo,
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (confirmado)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    // Reemplazo de withOpacity -> withValues
                                    color: Colors.green.withValues(alpha: .18),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.greenAccent.withValues(alpha: .5),
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
                            Text(f.format(fecha),
                                style: const TextStyle(color: Colors.white70)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
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
                                const SizedBox(width: 8),
                                Text('$occ/$cap',
                                    style: const TextStyle(color: Colors.white70)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text('Quedan $left cupos',
                                    style: const TextStyle(color: Colors.white70)),
                                const Spacer(),
                                Text(
                                  precioTxt,
                                  style: const TextStyle(
                                      color: Colors.greenAccent, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
