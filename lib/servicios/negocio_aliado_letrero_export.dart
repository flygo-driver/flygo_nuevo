// lib/servicios/negocio_aliado_letrero_export.dart
//
// Genera PDF del letrero (QR + texto) para llevar a imprenta.

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:flygo_nuevo/servicios/negocio_aliado_config.dart';
import 'package:flygo_nuevo/servicios/negocio_aliado_letrero_download_stub.dart'
    if (dart.library.html) 'package:flygo_nuevo/servicios/negocio_aliado_letrero_download_web.dart';
import 'package:flygo_nuevo/servicios/negocios_aliados_repo.dart';

abstract final class NegocioAliadoLetreroExport {
  NegocioAliadoLetreroExport._();

  static Future<void> descargarPdf(NegocioAliado negocio) async {
    final bytes = await generarPdfBytes(negocio);
    final nombre = _nombreArchivo(negocio);
    await descargarLetreroPdf(bytes: bytes, filename: nombre);
  }

  static Future<void> imprimir(NegocioAliado negocio) async {
    final bytes = await generarPdfBytes(negocio);
    if (kIsWeb) {
      await descargarLetreroPdf(
        bytes: bytes,
        filename: _nombreArchivo(negocio),
      );
      return;
    }
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  static String _nombreArchivo(NegocioAliado n) {
    final slug = n.codigo.replaceAll(RegExp(r'[^A-Z0-9-]'), '');
    return 'RAI-letrero-$slug.pdf';
  }

  static Future<Uint8List> generarPdfBytes(NegocioAliado negocio) async {
    final url = NegocioAliadoConfig.urlDescarga(negocio.codigo);

    pw.ImageProvider? logo;
    try {
      final logoData = await rootBundle.load('assets/icon/logo_rai_app.png');
      logo = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {}

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (logo != null)
                pw.Center(
                  child: pw.Image(logo, width: 72, height: 72),
                ),
              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Text(
                  'RAI DRIVER',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 24),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: url,
                  width: 200,
                  height: 200,
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Center(
                child: pw.Text(
                  'DESCARGA Y PIDE TU TAXI',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Center(
                child: pw.Text(
                  '${NegocioAliadoConfig.promoViajesM} viajes y el '
                  '${NegocioAliadoConfig.promoViajesM + NegocioAliadoConfig.promoViajesK}.º GRATIS',
                  style: const pw.TextStyle(fontSize: 14),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text(
                  'Válido ${NegocioAliadoConfig.vigenciaDias} días · Solo con este código',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Spacer(),
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  negocio.nombre.trim().isEmpty ? negocio.codigo : negocio.nombre,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              if (negocio.ciudad.trim().isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    negocio.ciudad,
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ),
              ],
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  'Aliado RAI Driver · ${negocio.codigo}',
                  style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  url,
                  style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
                ),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }
}
