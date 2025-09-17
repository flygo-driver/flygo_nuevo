import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';

class ServiciosConsularesScreen extends StatelessWidget {
  const ServiciosConsularesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Servicios Consulares',
          style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Traslados por pueblo → ciudad (citas consulares)',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Programa tu viaje con antelación para llegar puntual a tu cita. '
                    'Podemos coordinar grupos y vehículos grandes.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Sugerencia: elige “Autobús/Guagua” si viajan varias personas.',
                    style: TextStyle(color: Colors.greenAccent),
                  ),
                ],
              ),
            ),
            const Spacer(),
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
                label: const Text('Programar servicio consular'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
