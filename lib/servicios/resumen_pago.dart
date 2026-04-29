import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ResumenPago extends StatefulWidget {
  final String viajeId;
  final double montoTotal;

  const ResumenPago({
    super.key,
    required this.viajeId,
    required this.montoTotal,
  });

  @override
  State<ResumenPago> createState() => _ResumenPagoState();
}

class _ResumenPagoState extends State<ResumenPago> {
  String metodoPago = "";
  bool cargando = false;

  Future<void> _registrarPago() async {
    if (metodoPago.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Selecciona un método de pago")),
      );
      return;
    }

    setState(() => cargando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    try {
      final comision = widget.montoTotal * 0.20;
      final ganancia = widget.montoTotal * 0.80;

      await FirebaseFirestore.instance
          .collection("viajes")
          .doc(widget.viajeId)
          .update({
        "estadoPago": "pagado",
        "metodoPago": metodoPago,
        "montoTotal": widget.montoTotal,
        "gananciaTaxista": ganancia,
        "comisionFlyGo": comision,
        "pagoRegistradoPor": uid,
        "pagoRegistradoEn": FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Pago registrado: $metodoPago")),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al registrar pago: $e")),
      );
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comision = widget.montoTotal * 0.20;
    final ganancia = widget.montoTotal * 0.80;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Resumen de Pago",
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Monto total: RD\$${widget.montoTotal.toStringAsFixed(2)}",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Ganancia taxista: RD\$${ganancia.toStringAsFixed(2)}",
                style:
                    const TextStyle(color: Colors.greenAccent, fontSize: 18)),
            Text("Comisión FlyGo: RD\$${comision.toStringAsFixed(2)}",
                style: const TextStyle(color: Colors.redAccent, fontSize: 18)),
            const SizedBox(height: 20),
            const Text("Método de pago:",
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: metodoPago == "efectivo"
                          ? Colors.greenAccent
                          : Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => setState(() => metodoPago = "efectivo"),
                    child: const Text("Efectivo"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: metodoPago == "transferencia"
                          ? Colors.greenAccent
                          : Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () =>
                        setState(() => metodoPago = "transferencia"),
                    child: const Text("Transferencia"),
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: cargando ? null : _registrarPago,
                child: cargando
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text("Confirmar pago",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
