import 'package:flutter/material.dart';

/// Diálogo profesional al pausar un viaje y volver al home de RAI.
class ClienteVolverRaiDialog {
  ClienteVolverRaiDialog._();

  static Future<bool> confirmar(
    BuildContext context, {
    String? subtitulo,
  }) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        final Color surface = Theme.of(ctx).colorScheme.surface;
        final Color onSurface = Theme.of(ctx).colorScheme.onSurface;
        return AlertDialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF1B5E20).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.home_work_rounded,
              color: Color(0xFF69F0AE),
              size: 28,
            ),
          ),
          title: Text(
            '¿Volver a RAI?',
            style: TextStyle(
              color: onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          content: Text(
            subtitulo ??
                'Tu viaje seguirá activo. Podrás retomarlo cuando quieras '
                    'desde el banner en la pantalla principal o al volver a abrir la app.',
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.72),
              height: 1.45,
              fontSize: 14.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Seguir en el viaje'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.home_rounded, size: 18),
              label: const Text('Volver a RAI'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        );
      },
    );
    return ok == true;
  }
}
