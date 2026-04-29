import 'package:flutter/material.dart';

/// Bottom sheet con Waze / Google Maps: scrollable, sin overflow en pantallas chicas o textos largos.
Future<void> showNavegacionWazeMapsSheet(
  BuildContext context, {
  required String title,
  String? addressLine,
  bool tieneCoords = false,
  String? gpsCoordinatesLine,
  bool showSinGpsBanner = false,
  String? footerHint,
  required VoidCallback onWaze,
  required VoidCallback onMaps,
  VoidCallback? onCancel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.black,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final bottomInset = MediaQuery.viewPaddingOf(ctx).bottom;
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (addressLine != null && addressLine.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      addressLine.trim(),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14, height: 1.35),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (footerHint != null && footerHint.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      footerHint.trim(),
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12, height: 1.35),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (tieneCoords &&
                      gpsCoordinatesLine != null &&
                      gpsCoordinatesLine.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      gpsCoordinatesLine,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11, height: 1.3),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Coordenadas para navegación precisa.',
                      style: TextStyle(
                          color: Colors.greenAccent, fontSize: 12, height: 1.3),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (showSinGpsBanner) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Sin GPS del punto: se abrirá búsqueda por dirección.',
                      style: TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 12,
                          height: 1.3),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onWaze();
                      },
                      icon: const Icon(Icons.waves, color: Colors.blue),
                      label: const Text(
                        'Waze',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onMaps();
                      },
                      icon: const Icon(Icons.map, color: Colors.green),
                      label: const Text(
                        'Google Maps',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      onCancel?.call();
                    },
                    child: const Text('Cancelar',
                        style: TextStyle(color: Colors.white54)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
