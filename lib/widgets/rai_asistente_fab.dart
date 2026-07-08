import 'package:flutter/material.dart';
import 'package:flygo_nuevo/widgets/rai_asistente_launcher.dart';

/// Botón flotante para abrir el asistente RAI (solo capa de ayuda).
class RaiAsistenteFab extends StatelessWidget {
  const RaiAsistenteFab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FloatingActionButton.extended(
      // Sin hero: este FAB vive en el shell y aparece en varias rutas a la vez.
      // Con el tag por defecto chocaría con otros FAB durante las transiciones
      // (p. ej. al cancelar un viaje) y rompería la pantalla.
      heroTag: null,
      onPressed: () => RaiAsistenteLauncher.abrirAsistente(context),
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      icon: const Icon(Icons.auto_awesome_rounded),
      label: const Text(
        'RAI',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}
