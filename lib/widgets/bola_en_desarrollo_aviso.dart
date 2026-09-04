import 'package:flutter/material.dart';
import 'package:flygo_nuevo/utils/bola_ahorro_pool_isolation.dart';

/// Aviso visible mientras Bola Ahorro se alinea con el flujo pool / viaje en curso.
abstract final class BolaEnDesarrolloAviso {
  static const String titulo = 'En desarrollo';
  static const String mensaje =
      'Bola Ahorro está en desarrollo. Vamos alineándolo con viajes normales '
      '(navegación, factura, recarga y bloqueo) antes de producción.';

  /// Entrada nueva al tablero. Retomar bola activa pasa sin bloqueo.
  static Future<bool> intentarEntrarTablero(
    BuildContext context, {
    bool retomarBolaActiva = false,
  }) async {
    if (!BolaAhorroPoolIsolation.enDesarrollo || retomarBolaActiva) {
      return true;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.construction_rounded),
        title: const Text(titulo),
        content: const Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
    return false;
  }

  static Widget banner() {
    if (!BolaAhorroPoolIsolation.enDesarrollo) {
      return const SizedBox.shrink();
    }
    return Material(
      color: const Color(0xFFFFF3E0),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.construction_rounded,
              size: 20,
              color: Color(0xFFE65100),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mensaje,
                style: const TextStyle(
                  color: Color(0xFF5D4037),
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
