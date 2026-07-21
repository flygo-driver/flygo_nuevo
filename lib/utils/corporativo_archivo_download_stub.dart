import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Móvil / escritorio: compartir archivo (descarga vía diálogo del SO).
Future<void> descargarArchivoCorporativo({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  required String subject,
  required String texto,
}) async {
  await Share.shareXFiles(
    [XFile.fromData(bytes, mimeType: mimeType, name: filename)],
    fileNameOverrides: [filename],
    text: texto,
    subject: subject,
  );
}
