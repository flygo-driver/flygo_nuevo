import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Móvil / escritorio: diálogo nativo de compartir / guardar PDF.
Future<void> descargarLetreroPdf({
  required Uint8List bytes,
  required String filename,
}) async {
  await Printing.sharePdf(bytes: bytes, filename: filename);
}
