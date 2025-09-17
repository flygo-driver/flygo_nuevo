import 'package:flutter/material.dart';

class SeguridadSOS extends StatelessWidget {
  const SeguridadSOS({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Seguridad / SOS'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Compartir viaje / SOS (fase 2 - placeholder)',
              style: TextStyle(color: Colors.white70),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('SOS enviado (placeholder)')),
                  );
                },
                icon: const Icon(Icons.sos, color: Colors.red),
                label: const Text('Enviar SOS'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
