import 'package:flutter/material.dart';

class ReciboPago extends StatelessWidget {
  final String nombreTaxista;
  final String correoTaxista;
  final double monto;
  final String metodo;
  final DateTime fecha;
  final String urlFirma;
  final String reciboId;

  const ReciboPago({
    super.key,
    required this.nombreTaxista,
    required this.correoTaxista,
    required this.monto,
    required this.metodo,
    required this.fecha,
    required this.urlFirma,
    required this.reciboId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Recibo de Pago',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.greenAccent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoTexto("🧑‍✈️ Taxista", nombreTaxista),
              _infoTexto("📧 Correo", correoTaxista),
              _infoTexto("💰 Monto pagado", "RD\$${monto.toStringAsFixed(2)}"),
              _infoTexto("💳 Método de pago", metodo),
              _infoTexto(
                "📅 Fecha",
                "${fecha.day}/${fecha.month}/${fecha.year} ${fecha.hour}:${fecha.minute.toString().padLeft(2, '0')}",
              ),
              _infoTexto("🧾 ID del Recibo", reciboId),
              const SizedBox(height: 20),
              const Text(
                "Firma del taxista:",
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 10),
              Center(
                child: Image.network(
                  urlFirma,
                  width: 300,
                  height: 150,
                  fit: BoxFit.contain,
                ),
              ),
              const Spacer(),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Descarga de PDF no disponible temporalmente.',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  },
                  icon: const Icon(Icons.download),
                  label: const Text("Descargar Recibo"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.green,
                    minimumSize: const Size(double.infinity, 50),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoTexto(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RichText(
        text: TextSpan(
          text: "$titulo: ",
          style: const TextStyle(color: Colors.greenAccent, fontSize: 16),
          children: [
            TextSpan(
              text: valor,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
