import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/data/viaje_data.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';

class QuickTripCard extends StatelessWidget {
  const QuickTripCard({super.key});

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return const SizedBox.shrink();

    return StreamBuilder<Viaje?>(
      stream: ViajeData.streamEstadoViajePorCliente(u.uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(color: Colors.greenAccent),
          );
        }
        final v = snap.data;
        if (v == null) return const SizedBox.shrink();

        final estado = v.estado.isNotEmpty
            ? v.estado
            : (v.completado
                ? EstadosViaje.completado
                : (v.aceptado ? EstadosViaje.enCurso : EstadosViaje.pendiente));

        final estadoTexto = (estado == EstadosViaje.completado)
            ? '✅ Viaje completado'
            : (estado == EstadosViaje.enCurso)
                ? '🚕 Tu viaje está en curso'
                : '⌛ Pendiente de asignación';

        return Card(
          color: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  estadoTexto,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "🧭 ${v.origen} → ${v.destino}",
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  "💰 Total: ${FormatosMoneda.rd(v.precio)}",
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ViajeEnCursoCliente(),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.directions_car,
                      color: Colors.greenAccent,
                    ),
                    label: const Text(
                      'Ir a mi viaje',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.greenAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
