import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TestFirebase extends StatefulWidget {
  const TestFirebase({super.key});

  @override
  State<TestFirebase> createState() => _TestFirebaseState();
}

class _TestFirebaseState extends State<TestFirebase> {
  String _statusMessage = 'Presiona el botón para enviar datos a Firebase';

  Future<void> _addTestData() async {
    try {
      await FirebaseFirestore.instance.collection('test').add({
        'mensaje': 'Hola Firebase',
        'fecha': DateTime.now(),
      });
      setState(() {
        _statusMessage = '✅ Datos enviados correctamente a Firebase';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error al enviar datos: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prueba Firebase')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _addTestData,
              child: const Text('Enviar datos de prueba'),
            ),
            const SizedBox(height: 20),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
