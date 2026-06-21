import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ver bauche/comprobante de reserva pool en admin (solo lectura).
class AdminPoolComprobanteDialog {
  AdminPoolComprobanteDialog._();

  static Future<void> mostrar(BuildContext context, String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Recibo de pago (asiento)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  child: Image.network(
                    u,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No se pudo cargar la imagen.\nPodés abrirla en el navegador.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(u);
                    if (uri != null) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir enlace completo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
