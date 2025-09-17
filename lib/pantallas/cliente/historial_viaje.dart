import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/viaje_data.dart';
import '../../modelo/viaje.dart';

class HistorialCliente extends StatelessWidget {
  const HistorialCliente({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final formatoFecha = DateFormat('dd/MM/yyyy - HH:mm');

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text("No has iniciado sesión.")),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("Historial de Viajes")),
      body: StreamBuilder<List<Viaje>>(
        stream: ViajeData.streamHistorialCliente(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            );
          }

          final viajes = snapshot.data ?? const <Viaje>[];
          if (viajes.isEmpty) {
            return const Center(
              child: Text(
                "No hay viajes realizados.",
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return ListView.builder(
            itemCount: viajes.length,
            itemBuilder: (context, index) {
              final viaje = viajes[index];
              return Card(
                color: const Color(0xFF151515),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(
                    "${viaje.origen} → ${viaje.destino}",
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        "Fecha: ${formatoFecha.format(viaje.fechaHora)}",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        "Método de Pago: ${viaje.metodoPago}",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        "Precio: RD\$${viaje.precio.toStringAsFixed(2)}",
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
