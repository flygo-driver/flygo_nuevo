import 'package:flutter/material.dart';

import '../servicios/pool_repo.dart';

/// Diálogo de confirmación antes de cancelar una salida por cupos (taxista).
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

/// Diálogo unificado para acciones admin (cancelar / anular cierre).
Future<({bool confirmed, String motivo})> confirmarAccionAdminGira({
  required BuildContext context,
  required Map<String, dynamic> poolData,
  required String titulo,
  String? cuerpoExtra,
  String accionLabel = 'Confirmar',
  bool exigirMotivo = true,
}) async {
  final bool conReservas = PoolRepo.giraTieneReservasActivas(poolData);
  final occ = ((poolData['asientosReservados'] ?? 0) as num).toInt();
  final pag = ((poolData['asientosPagados'] ?? 0) as num).toInt();
  final prepagoRd =
      ((poolData['comisionGiraEstimadaRd'] ?? 0) as num).toDouble();
  final etapaPrepago =
      (poolData['prepagoComisionEtapa'] ?? '').toString().trim().toLowerCase();
  final bool prepagoReservado =
      prepagoRd > 0 && etapaPrepago == 'reservada_creacion';

  final motivoCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  try {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final resumen = <String>[
          if (conReservas)
            'Cupos: $occ reservado(s), $pag pagado(s). Los pasajeros perderán la reserva.',
          if (prepagoReservado)
            'Prepago comisión organizador: RD\$ ${prepagoRd.toStringAsFixed(0)} (se devuelve al cancelar).',
          if (!conReservas && !prepagoReservado)
            'Sin reservas activas ni prepago pendiente.',
          if (cuerpoExtra != null && cuerpoExtra.trim().isNotEmpty) cuerpoExtra.trim(),
          'Los pasajeros no reciben aviso automático desde ADM.',
        ].join('\n\n');

        return AlertDialog(
          title: Text(titulo),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(resumen),
                const SizedBox(height: 12),
                TextField(
                  controller: motivoCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: exigirMotivo
                        ? 'Motivo (obligatorio)'
                        : 'Motivo (opcional)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (conReservas) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Escribe CANCELAR para confirmar',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(accionLabel),
            ),
          ],
        );
      },
    );
    if (ok != true) return (confirmed: false, motivo: '');
    if (exigirMotivo && motivoCtrl.text.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Escribe un motivo antes de continuar.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return (confirmed: false, motivo: '');
    }
    if (conReservas &&
        confirmCtrl.text.trim().toUpperCase() != 'CANCELAR') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debes escribir CANCELAR para confirmar.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return (confirmed: false, motivo: '');
    }
    return (confirmed: true, motivo: motivoCtrl.text.trim());
  } finally {
    motivoCtrl.dispose();
    confirmCtrl.dispose();
  }
}
