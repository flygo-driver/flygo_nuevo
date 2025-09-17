// lib/widgets/resumen_pago_taxista.dart
import 'package:flutter/material.dart';

class ResumenPagoTaxista extends StatelessWidget {
  final double precioTotal;
  final double comision;
  final double ganancia;

  const ResumenPagoTaxista({
    super.key,
    required this.precioTotal,
    required this.comision,
    required this.ganancia,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Resumen de Pago",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "💰 Precio Total del Viaje: RD\$${precioTotal.toStringAsFixed(2)}",
            ),
            Text(
              "🧾 Comisión de FlyGo (20%): RD\$${comision.toStringAsFixed(2)}",
            ),
            Text("🚖 Ganancia del Taxista: RD\$${ganancia.toStringAsFixed(2)}"),
          ],
        ),
      ),
    );
  }
}
