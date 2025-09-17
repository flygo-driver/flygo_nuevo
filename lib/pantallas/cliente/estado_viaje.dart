import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/viaje_data.dart';
import '../../modelo/viaje.dart';
import '../../utils/calculos/estados.dart';

class PantallaEstadoViaje extends StatelessWidget {
  const PantallaEstadoViaje({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "Estado del Viaje",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.greenAccent,
          ),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: user == null
          ? const Center(
              child: Text(
                "No has iniciado sesión",
                style: TextStyle(fontSize: 20, color: Colors.white),
              ),
            )
          : StreamBuilder<Viaje?>(
              stream: ViajeData.streamEstadoViajePorCliente(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.greenAccent),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      "Error: ${snapshot.error}",
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final viaje = snapshot.data;

                if (viaje == null) {
                  return const Center(
                    child: Text(
                      "No tienes viaje en curso",
                      style: TextStyle(fontSize: 20, color: Colors.white),
                    ),
                  );
                }

                final String estado = (viaje.estado.isNotEmpty)
                    ? viaje.estado
                    : (viaje.completado
                          ? EstadosViaje.completado
                          : (viaje.aceptado
                                ? EstadosViaje.enCurso
                                : EstadosViaje.pendiente));

                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _dato("🛫 Origen", viaje.origen),
                      _dato("🛬 Destino", viaje.destino),
                      _dato("💳 Método de Pago", viaje.metodoPago),
                      _dato("🚗 Tipo de Vehículo", viaje.tipoVehiculo),
                      _dato(
                        "💰 Precio",
                        "RD\$${viaje.precio.toStringAsFixed(2)}",
                      ),
                      _dato(
                        "👨‍✈️ Conductor",
                        viaje.nombreTaxista.isNotEmpty
                            ? viaje.nombreTaxista
                            : 'Por asignar',
                      ),
                      const SizedBox(height: 30),
                      Text(
                        "📍 Estado: ${EstadosViaje.descripcion(estado)}",
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _dato(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 20, color: Colors.white),
          children: [
            TextSpan(
              text: "$titulo: ",
              style: const TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: valor,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
