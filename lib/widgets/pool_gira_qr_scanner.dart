import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Extrae token RAI-XXXXXXXX de texto escaneado o pegado.
String? extraerTokenGiraDesdeTexto(String raw) {
  final t = raw.trim().toUpperCase();
  if (t.isEmpty) return null;
  final m = RegExp(r'RAI-[A-Z0-9]{6,12}').firstMatch(t);
  return m?.group(0);
}

/// Escáner QR con cámara (móvil). En web devuelve null — usar pegado manual.
Future<String?> escanearTokenGiraConCamara(BuildContext context) async {
  if (kIsWeb) return null;

  final cam = await Permission.camera.request();
  if (!cam.isGranted) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se necesita permiso de cámara para escanear el QR'),
        ),
      );
    }
    return null;
  }

  if (!context.mounted) return null;
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (_) => const _PoolGiraQrScannerPage(),
    ),
  );
}

class _PoolGiraQrScannerPage extends StatefulWidget {
  const _PoolGiraQrScannerPage();

  @override
  State<_PoolGiraQrScannerPage> createState() => _PoolGiraQrScannerPageState();
}

class _PoolGiraQrScannerPageState extends State<_PoolGiraQrScannerPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _capturado = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_capturado) return;
    for (final b in capture.barcodes) {
      final token = extraerTokenGiraDesdeTexto(b.rawValue ?? '');
      if (token == null) continue;
      _capturado = true;
      Navigator.of(context).pop(token);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Escanear ticket'),
        actions: [
          IconButton(
            tooltip: 'Linterna',
            onPressed: () => _controller.toggleTorch(),
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, _) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                );
              },
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: cs.primary, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Text(
              'Centra el QR del pasajero. También puedes volver y pegar el código.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
