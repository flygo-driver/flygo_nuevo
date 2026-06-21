import 'package:flutter/material.dart';

import '../servicios/pool_repo.dart';

/// Diálogo de confirmación antes de cancelar una salida por cupos (taxista/admin).
Future<bool> confirmarCancelarGiraSalida(
  BuildContext context,
  Map<String, dynamic> poolData,
) async {
  final bool conReservas = PoolRepo.giraTieneReservasActivas(poolData);
  final occ = ((poolData['asientosReservados'] ?? 0) as num).toInt();
  final pag = ((poolData['asientosPagados'] ?? 0) as num).toInt();

  if (!conReservas) {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar esta salida?'),
        content: const Text(
          'La gira desaparecerá del catálogo. Si había prepago apartado al publicar, '
          'se devuelve a tu billetera.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  final TextEditingController confirmCtrl = TextEditingController();
  try {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar salida con reservas'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Hay $occ cupo(s) reservado(s) y $pag pago(s) registrado(s). '
                'Los pasajeros perderán la reserva. El prepago de comisión de esta salida '
                'se devuelve a tu billetera. Esta acción no se puede deshacer.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                decoration: const InputDecoration(
                  labelText: 'Escribe CANCELAR para confirmar',
                ),
                textCapitalization: TextCapitalization.characters,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar salida'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    return confirmCtrl.text.trim().toUpperCase() == 'CANCELAR';
  } finally {
    confirmCtrl.dispose();
  }
}
