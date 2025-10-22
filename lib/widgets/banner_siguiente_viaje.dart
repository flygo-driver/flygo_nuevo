import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

class BannerSiguienteViaje extends StatelessWidget {
  const BannerSiguienteViaje({
    super.key,
    required this.uidTaxista,
    this.db, // opcional; no se usa
  });

  final String uidTaxista;

  // ignore: unused_field
  final FirebaseFirestore? db;

  @override
  Widget build(BuildContext context) {
    // Leemos el doc del usuario directamente (no necesitamos helper)
    final streamUsuario = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uidTaxista)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: streamUsuario,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final data = snap.data!.data();
        final siguienteId = (data?['siguienteViajeId'] ?? '').toString();
        if (siguienteId.isEmpty) return const SizedBox.shrink();

        return Card(
          color: Colors.amber.shade100,
          margin: const EdgeInsets.all(8),
          child: ListTile(
            title: const Text('Tienes un viaje en cola'),
            subtitle: Text('ID: $siguienteId'),
            trailing: TextButton(
              onPressed: () async {
                try {
                  // ✅ Llamada estática al repo
                  await ViajesRepo.liberarReserva(
                    viajeId: siguienteId,
                    uidTaxista: uidTaxista,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reserva cancelada')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('No se pudo cancelar: $e')),
                  );
                }
              },
              child: const Text('Cancelar'),
            ),
          ),
        );
      },
    );
  }
}
