import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../modelo/viaje.dart';
import '../../servicios/trips_service.dart';
import '../../utils/formatos_moneda.dart';
import 'viaje_en_curso_taxista.dart';
import '../shared/boarding_pin_sheet.dart';

class EsperandoViajeProgramado extends StatelessWidget {
  const EsperandoViajeProgramado({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('Inicia sesión', style: TextStyle(color: Colors.white)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Programados (asignados)',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<List<Viaje>>(
        stream: TripsService.streamProgramadosAsignados(uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                'Error: ${snap.error}',
                style: const TextStyle(color: Colors.white70),
              ),
            );
          }
          final list = snap.data ?? const <Viaje>[];
          if (list.isEmpty) {
            return const Center(
              child: Text(
                'No tienes viajes programados.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (_, i) => _ItemProg(v: list[i]),
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: list.length,
          );
        },
      ),
    );
  }
}

class _ItemProg extends StatelessWidget {
  final Viaje v;
  const _ItemProg({required this.v});

  bool _esAhora(DateTime fecha) =>
      !fecha.isAfter(DateTime.now().add(const Duration(minutes: 10)));

  @override
  Widget build(BuildContext context) {
    final fechaTxt = DateFormat('EEE d MMM, HH:mm', 'es').format(v.fechaHora);
    final total = FormatosMoneda.rd(v.precio);
    final esAhora = _esAhora(v.fechaHora);

    return Card(
      color: const Color(0xFF121212),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${v.origen} → ${v.destino}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text('Hora: $fechaTxt',
                style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 4),
            Text('Total: $total',
                style: const TextStyle(color: Colors.greenAccent)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.black,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      builder: (_) => BoardingPinSheet(tripId: v.id),
                    ),
                    icon: const Icon(Icons.verified_user),
                    label: const Text('PIN / Abordar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ViajeEnCursoTaxista(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: Text(esAhora ? 'Ir a viaje' : 'Ver en curso'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
