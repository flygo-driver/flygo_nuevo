import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../utils/navegacion_salida_app.dart';
import '../../widgets/rai_app_bar.dart';
import '../../modelo/viaje.dart';
import '../../data/viaje_data.dart';
import '../../utils/calculos/estados.dart';
import '../../utils/formatos_moneda.dart';

class HistorialViajesCliente extends StatelessWidget {
  const HistorialViajesCliente({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final formato = DateFormat('dd/MM/yyyy - HH:mm');

    return FlygoSalidaSegura(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: const RaiAppBar(
          title: 'Historial de viajes',
          backWhenCanPop: true,
        ),
      body: user == null
          ? const Center(
              child: Text(
                'Debes iniciar sesión para ver tu historial',
                style: TextStyle(color: Colors.white),
              ),
            )
          : FutureBuilder<List<Viaje>>(
              future: ViajeData.obtenerHistorialCliente(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.greenAccent),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Error al cargar el historial.\n${snapshot.error}',
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final viajes = (snapshot.data ?? [])
                  ..sort((a, b) => b.fechaHora.compareTo(a.fechaHora));

                if (viajes.isEmpty) {
                  return const Center(
                    child: Text(
                      'No tienes viajes en tu historial',
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: viajes.length,
                  itemBuilder: (context, index) {
                    final v = viajes[index];

                    final estadoDesc = EstadosViaje.descripcion(
                      v.estado.isNotEmpty
                          ? v.estado
                          : (v.completado
                              ? EstadosViaje.completado
                              : (v.aceptado
                                  ? EstadosViaje.enCurso
                                  : EstadosViaje.pendiente)),
                    );

                    return Card(
                      color: Colors.grey[900],
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        leading: const Icon(
                          Icons.local_taxi,
                          color: Colors.greenAccent,
                        ),
                        title: Text(
                          '${v.origen} → ${v.destino}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Fecha: ${formato.format(v.fechaHora)}\nEstado: $estadoDesc',
                            style: const TextStyle(
                              color: Colors.white70,
                              height: 1.35,
                            ),
                          ),
                        ),
                        trailing: Text(
                          FormatosMoneda.rd(v.precio),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      ),
    );
  }
}
