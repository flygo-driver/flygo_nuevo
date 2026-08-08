import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_crear.dart';
import 'package:flygo_nuevo/utils/pools_producto_copy.dart';

/// Modo de publicación en salidas por cupos.
enum PoolModoPublicacion {
  /// Gira, excursión o tour — formulario completo actual.
  giraExcursion,

  /// Viaje grupal ida y vuelta (consular, agencia, diligencia) — formulario corto.
  viajeGrupal,
}

abstract final class PoolModoPublicacionUi {
  PoolModoPublicacionUi._();

  static String titulo(PoolModoPublicacion modo) {
    switch (modo) {
      case PoolModoPublicacion.giraExcursion:
        return PoolsProductoCopy.publicarTitulo;
      case PoolModoPublicacion.viajeGrupal:
        return 'Publicar viaje grupal';
    }
  }

  static String subtitulo(PoolModoPublicacion modo) {
    switch (modo) {
      case PoolModoPublicacion.giraExcursion:
        return 'Gira, excursión o tour con itinerario completo';
      case PoolModoPublicacion.viajeGrupal:
        return 'Juntar personas · ida y vuelta · precio por asiento';
    }
  }

  /// Elige modo y abre el formulario correspondiente.
  static Future<void> abrirPublicar(
    BuildContext context, {
    PoolModoPublicacion? modoDirecto,
  }) async {
    final modo = modoDirecto ?? await elegirModo(context);
    if (modo == null || !context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PoolsTaxistaCrear(modo: modo),
      ),
    );
  }

  static Future<PoolModoPublicacion?> elegirModo(BuildContext context) {
    return showModalBottomSheet<PoolModoPublicacion>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '¿Qué vas a publicar?',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.tour_outlined),
                  title: const Text('Gira, tour o excursión'),
                  subtitle: const Text(
                    'Formulario completo: itinerario, paradas, banner y todo manual',
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () => Navigator.pop(
                    ctx,
                    PoolModoPublicacion.giraExcursion,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: const Text('Viaje grupal'),
                  subtitle: const Text(
                    'Formulario corto: nombre, fotos/video, salida, regreso y precio',
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () => Navigator.pop(
                    ctx,
                    PoolModoPublicacion.viajeGrupal,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
