// Genera PNG de QR para Google Play (cliente). Sin Flutter; solo Dart VM.
// Ejecutar desde la raíz del proyecto:
//   dart run tools/generate_qr.dart
//
// Paquetes: `qr` (generación QR en Dart puro) + `image` (encode PNG).
// Nota: no existe `dart_qrcode` en pub.dev; `qr` es el paquete estándar equivalente.

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

const _playStoreUrl =
    'https://play.google.com/store/apps/details?id=com.flygo.rd2';

const _outputRelative = 'assets/qr_rai_play_store_cliente.png';

/// Módulo en píxeles y margen en módulos (borde blanco).
const _modulePixelSize = 8;
const _marginModules = 4;

void main(List<String> args) {
  final projectRoot = _resolveProjectRoot();
  final outFile = File('${projectRoot.path}${Platform.pathSeparator}$_outputRelative');

  final qrCode = QrCode.fromData(
    data: _playStoreUrl,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final qrImage = QrImage(qrCode);

  final side = (qrImage.moduleCount + _marginModules * 2) * _modulePixelSize;
  final image = img.Image(width: side, height: side);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));

  for (var row = 0; row < qrImage.moduleCount; row++) {
    for (var col = 0; col < qrImage.moduleCount; col++) {
      if (!qrImage.isDark(row, col)) continue;
      final x1 = (col + _marginModules) * _modulePixelSize;
      final y1 = (row + _marginModules) * _modulePixelSize;
      img.fillRect(
        image,
        x1: x1,
        y1: y1,
        x2: x1 + _modulePixelSize - 1,
        y2: y1 + _modulePixelSize - 1,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
  }

  outFile.parent.createSync(recursive: true);
  outFile.writeAsBytesSync(img.encodePng(image));

  stdout.writeln('QR guardado: ${outFile.path}');
  stdout.writeln('URL: $_playStoreUrl');
}

Directory _resolveProjectRoot() {
  final script = Platform.script.toFilePath();
  final toolsDir = File(script).parent;
  return toolsDir.parent;
}
