// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

/// Web ADM: descarga directa del PDF (Printing.sharePdf no está en web).
Future<void> descargarLetreroPdf({
  required Uint8List bytes,
  required String filename,
}) async {
  final blob = html.Blob(<Uint8List>[bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
