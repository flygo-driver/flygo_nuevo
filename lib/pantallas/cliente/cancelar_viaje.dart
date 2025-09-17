import 'package:flutter/material.dart';

class CancelarViaje extends StatefulWidget {
  final String? viajeId;
  const CancelarViaje({super.key, this.viajeId});

  @override
  State<CancelarViaje> createState() => _CancelarViajeState();
}

class _CancelarViajeState extends State<CancelarViaje> {
  final _motivoCtrl = TextEditingController();

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    // TODO: update Firestore (viajes/{id}) con {estado: cancelado, motivo, timestamp}
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Solicitud enviada (placeholder)')),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Cancelar / Reprogramar'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Motivo (opcional)',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _motivoCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Escribe el motivo...',
                hintStyle: TextStyle(color: Colors.white38),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _enviar,
                child: const Text('Enviar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
