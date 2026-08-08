import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_crear.dart';
import 'package:flygo_nuevo/utils/pools_producto_copy.dart';
import 'package:flygo_nuevo/widgets/pool_gira_publicar_ui.dart';

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
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const OrganizadorGirasBrandHeader(compact: true),
                const SizedBox(height: 16),
                Text(
                  '¿Qué vas a publicar?',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Elegí el tipo de salida. Podés cambiar detalles en cada paso del formulario.',
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                ),
                const SizedBox(height: 16),
                _ModoCard(
                  icon: Icons.landscape_rounded,
                  color: const Color(0xFF0D9488),
                  title: 'Gira, tour o excursión',
                  subtitle:
                      'Itinerario, paradas, banner y detalle profesional para turistas.',
                  onTap: () => Navigator.pop(ctx, PoolModoPublicacion.giraExcursion),
                ),
                const SizedBox(height: 10),
                _ModoCard(
                  icon: Icons.groups_rounded,
                  color: const Color(0xFF6366F1),
                  title: 'Viaje grupal',
                  subtitle:
                      'Formulario corto: nombre, fotos, salida, regreso y precio por asiento.',
                  onTap: () => Navigator.pop(ctx, PoolModoPublicacion.viajeGrupal),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ModoCard extends StatelessWidget {
  const _ModoCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.35)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                color.withValues(alpha: 0.12),
                color.withValues(alpha: 0.04),
              ],
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
