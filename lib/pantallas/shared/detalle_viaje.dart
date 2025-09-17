// lib/pantallas/shared/detalle_viaje.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../modelo/viaje.dart';
import 'boarding_pin_sheet.dart';

class DetalleViaje extends StatelessWidget {
  final String viajeId;
  const DetalleViaje({super.key, required this.viajeId});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('viajes').doc(viajeId);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Detalle de viaje', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
          }
          if (snap.hasError || !snap.hasData || !snap.data!.exists) {
            return const Center(
              child: Text('No se encontró el viaje', style: TextStyle(color: Colors.white70)),
            );
          }
          final v = Viaje.fromMap(snap.data!.id, snap.data!.data()!);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('${v.origen} → ${v.destino}',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Estado: ${v.estado}',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Text('Cliente: ${v.uidCliente}',
                  style: const TextStyle(color: Colors.white70)),
              if (v.uidTaxista.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Taxista: ${v.nombreTaxista} (${v.uidTaxista})',
                    style: const TextStyle(color: Colors.white70)),
              ],
              const SizedBox(height: 16),
              if (v.uidTaxista.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.black,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (_) => BoardingPinSheet(tripId: v.id),
                  ),
                  icon: const Icon(Icons.verified_user),
                  label: const Text('PIN / Abordaje'),
                ),
            ],
          );
        },
      ),
    );
  }
}
