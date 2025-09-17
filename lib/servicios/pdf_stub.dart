import 'package:flutter/material.dart';

class PdfReciboService {
  // Ajusta la firma de los métodos a lo que uses en tu app
  static Future<void> generarYMostrarRecibo(
    BuildContext context, {
    required String nombreTaxista,
    required String correoTaxista,
    required double montoPagado,
    required DateTime fechaHora,
    required String metodoPago,
    String? urlFirma,
    String? reciboId,
  }) async {
    // Temporalmente deshabilitado: solo informamos
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generación de PDF deshabilitada temporalmente'),
      ),
    );
  }

  static Future<void> compartirRecibo(
    BuildContext context,
    List<int> pdfBytes, {
    String filename = 'recibo_flygo.pdf',
  }) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Compartir PDF deshabilitado temporalmente'),
      ),
    );
  }
}
