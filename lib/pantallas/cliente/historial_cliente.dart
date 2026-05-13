import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../modelo/viaje.dart';
import '../../data/viaje_data.dart';
import '../comun/factura_viaje.dart';

class HistorialCliente extends StatelessWidget {
  const HistorialCliente({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final formatoFecha = DateFormat('dd/MM/yyyy - HH:mm');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Historial de viajes',
            style: TextStyle(color: Colors.white)),
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
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: InkWell(
                        // Toda la tarjeta abre la factura del viaje. La
                        // pantalla de factura es de SOLO LECTURA y reusa
                        // exactamente el mismo widget que se muestra al
                        // finalizar el viaje, con datos bancarios + estado
                        // de pago + posibilidad de subir comprobante si es
                        // transferencia y aún no se envió.
                        onTap: () => FacturaViaje.mostrar(
                          context,
                          viajeId: v.id,
                          role: 'cliente',
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${v.origen} → ${v.destino}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Fecha: ${formatoFecha.format(v.fechaHora)}',
                                      style: const TextStyle(
                                          color: Colors.white70),
                                    ),
                                    Text(
                                      'Pago: ${v.metodoPago}',
                                      style: const TextStyle(
                                          color: Colors.white70),
                                    ),
                                    const SizedBox(height: 8),
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.receipt_long_rounded,
                                          color: Colors.greenAccent,
                                          size: 14,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Ver factura',
                                          style: TextStyle(
                                            color: Colors.greenAccent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'RD\$${v.precio.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.white38,
                                  ),
                                ],
                              ),
                            ],
                          ),
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
