// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

/// Web: descarga directa con un clic (Share.shareXFiles es poco fiable en navegador).
Future<void> descargarArchivoCorporativo({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  required String subject,
  required String texto,
}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
