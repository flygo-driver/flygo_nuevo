import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../widgets/cliente_drawer.dart';
import '../../modelo/viaje.dart';
import '../../data/viaje_data.dart';

class HistorialCliente extends StatelessWidget {
  const HistorialCliente({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final formatoFecha = DateFormat('dd/MM/yyyy - HH:mm');

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const ClienteDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text('Historial de viajes', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: user == null
          ? const Center(
              child: Text(
                'Debes iniciar sesión',
                style: TextStyle(color: Colors.white),
              ),
            )
          : StreamBuilder<List<Viaje>>(
              stream: ViajeData.streamHistorialCliente(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.greenAccent),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  );
                }
                final viajes = snapshot.data ?? [];
                if (viajes.isEmpty) {
                  return const Center(
                    child: Text(
                      'No tienes viajes realizados',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: viajes.length,
                  itemBuilder: (context, index) {
                    final v = viajes[index];
                    return Card(
                      color: Colors.grey[900],
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        title: Text(
                          '${v.origen} → ${v.destino}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              'Fecha: ${formatoFecha.format(v.fechaHora)}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            Text(
                              'Pago: ${v.metodoPago}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                        trailing: Text(
                          'RD\$${v.precio.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
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