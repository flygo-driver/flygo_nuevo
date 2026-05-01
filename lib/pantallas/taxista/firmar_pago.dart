import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/estilos.dart';

class FirmarPago extends StatefulWidget {
  final double monto;
  final String metodo;

  const FirmarPago({super.key, required this.monto, required this.metodo});

  @override
  State<FirmarPago> createState() => _FirmarPagoState();
}

class _FirmarPagoState extends State<FirmarPago> {
  final SignatureController _firmaController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
  );
  bool cargando = false;

  Future<void> _guardarRecibo() async {
    // ✅ Capturamos nav y messenger ANTES de cualquier await
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (_firmaController.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Por favor, firma antes de continuar")),
      );
      return;
    }

    if (mounted) setState(() => cargando = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw "Usuario no autenticado";

      final Uint8List? firmaBytes = await _firmaController.toPngBytes();
      if (firmaBytes == null) throw "Error al generar imagen de firma";

      final nombreArchivo =
          'firmas/${user.email}_${DateTime.now().millisecondsSinceEpoch}.png';
      final firmaRef = FirebaseStorage.instance.ref().child(nombreArchivo);
      await firmaRef.putData(firmaBytes);
      final urlFirma = await firmaRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('pagos').add({
        'emailTaxista': user.email,
        'monto': widget.monto,
        'metodo': widget.metodo,
        'fecha': DateTime.now().toIso8601String(),
        'firmaUrl': urlFirma,
      });

      // ✅ Usamos messenger/nav sin context tras await
      messenger.showSnackBar(
        const SnackBar(content: Text("Recibo firmado y guardado")),
      );
      nav.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  @override
  void dispose() {
    _firmaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EstilosRai.fondoOscuro,
      appBar: AppBar(
        title: const Text(
          "Firmar Recibo",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: EstilosRai.fondoOscuro,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: cargando
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    "Monto a pagar: RD\$${widget.monto.toStringAsFixed(2)}",
                    style: const TextStyle(color: Colors.white, fontSize: 22),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Método de pago: ${widget.metodo}",
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    "Firma aquí:",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white),
                      color: Colors.white,
                    ),
                    child: Signature(
                      controller: _firmaController,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => _firmaController.clear(),
                        child: const Text("Borrar firma"),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _guardarRecibo,
                        icon: const Icon(Icons.check),
                        label: const Text("Guardar y Firmar"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
