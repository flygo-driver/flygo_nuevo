import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/acciones_viaje_taxista.dart';

class ViajeDetalleTest extends StatelessWidget {
  final String viajeId;
  const ViajeDetalleTest({super.key, required this.viajeId});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('viajes').doc(viajeId);

    return Scaffold(
      appBar: AppBar(title: const Text('Test Viaje')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('No existe ese viaje'));
          }

          final data = snap.data!.data()!;
          final estado = (data['estado'] ?? '').toString();

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ID: ${snap.data!.id}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('Estado actual: $estado'),
                const SizedBox(height: 16),
                AccionesViajeTaxista(
                  viajeId: snap.data!.id,
                  estadoActual: estado,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
