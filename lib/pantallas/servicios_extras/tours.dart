import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje_multi.dart';

class ToursTuristicosScreen extends StatelessWidget {
  const ToursTuristicosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cardDecoration = BoxDecoration(
      color: const Color(0xFF121212),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white24),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Tours / Giras Turísticas',
          style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: cardDecoration,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tours privados o en grupo con FlyGo',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Programa recorridos a playas, montañas, ciudades cercanas o rutas gastronómicas. '
                  'Coordina el transporte con puntualidad y elige el vehículo ideal (carro, jeepeta, minivan, guagua).',
                  style: TextStyle(color: Colors.white70),
                ),
                SizedBox(height: 10),
                Text(
                  'Tip: si habrá varias paradas, usa “múltiples paradas”.',
                  style: TextStyle(color: Colors.greenAccent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProgramarViaje(modoAhora: false)),
                );
              },
              icon: const Icon(Icons.event_available),
              label: const Text('Programar tour (fecha y hora)'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProgramarViajeMulti()),
                );
              },
              icon: const Icon(Icons.alt_route),
              label: const Text('Programar tour con múltiples paradas'),
            ),
          ),
        ],
      ),
    );
  }
}
