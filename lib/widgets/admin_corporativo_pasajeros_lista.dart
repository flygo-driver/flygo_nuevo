import 'package:flutter/material.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_ui_theme.dart';

/// Lista ordenada de pasajeros para asignación admin (origen → destinos).
class AdminCorporativoPasajerosLista extends StatelessWidget {
  const AdminCorporativoPasajerosLista({
    super.key,
    required this.plantilla,
    this.compact = false,
    this.mostrarInactivos = true,
  });

  final CorporativoPlantilla plantilla;
  final bool compact;
  final bool mostrarInactivos;

  @override
  Widget build(BuildContext context) {
    final activos = plantilla.pasajerosActivos;
    final inactivos = mostrarInactivos
        ? plantilla.pasajeros.where((p) => !p.activo).toList()
        : const <CorporativoPasajero>[];

    if (activos.isEmpty && inactivos.isEmpty) {
      return Text(
        'Sin pasajeros cargados en esta ruta.',
        style: TextStyle(
          color: Colors.orange.shade800,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (plantilla.origenLabel.trim().isNotEmpty) ...[
          _filaParada(
            context,
            numero: 'O',
            titulo: 'Recogida grupo',
            subtitulo: plantilla.origenLabel.trim(),
            esOrigen: true,
          ),
          if (activos.isNotEmpty) const SizedBox(height: 4),
        ],
        ...activos.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          final destino = p.destinoLabel.trim();
          final sector = p.sector.trim();
          final ref = p.referencia.trim();
          final detalles = <String>[
            if (sector.isNotEmpty) sector,
            if (destino.isNotEmpty) '→ $destino',
            if (ref.isNotEmpty) 'Ref: $ref',
            if (p.horaDejada.trim().isNotEmpty) 'Dejar ${p.horaDejada.trim()}',
          ];
          return Padding(
            padding: EdgeInsets.only(top: compact ? 2 : 4),
            child: _filaParada(
              context,
              numero: '${i + 1}',
              titulo: p.nombre.trim().isNotEmpty ? p.nombre.trim() : 'Pasajero ${i + 1}',
              subtitulo: detalles.join(' · '),
            ),
          );
        }),
        if (inactivos.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Fuera de ruta (${inactivos.length})',
            style: TextStyle(
              color: Colors.red.shade700,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          ...inactivos.map(
            (p) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '· ${p.nombre}${p.destinoLabel.trim().isNotEmpty ? ' → ${p.destinoLabel.trim()}' : ''}',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: compact ? 10 : 11,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _filaParada(
    BuildContext context, {
    required String numero,
    required String titulo,
    required String subtitulo,
    bool esOrigen = false,
  }) {
    final color = esOrigen ? Colors.indigo.shade700 : Colors.teal.shade800;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 22 : 26,
          height: compact ? 22 : 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(
            numero,
            style: TextStyle(
              color: color,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitulo.trim().isNotEmpty)
                Text(
                  subtitulo,
                  style: TextStyle(
                    color: AdminUi.secondary(context),
                    fontSize: compact ? 10 : 11,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
