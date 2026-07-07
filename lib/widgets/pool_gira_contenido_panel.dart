import 'package:flutter/material.dart';
import 'package:flygo_nuevo/utils/pool_gira_contenido.dart';

/// Panel de detalle extendido para publicación de gira (cliente).
class PoolGiraContenidoPanel extends StatelessWidget {
  const PoolGiraContenidoPanel({
    super.key,
    required this.extra,
    this.estiloOscuroRojo = false,
  });

  final PoolGiraContenidoExtra extra;
  final bool estiloOscuroRojo;

  static const Color _kFondo = Color(0xFF0A0A0A);
  static const Color _kBorde = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[];

    if (extra.eslogan.trim().isNotEmpty) {
      sections.add(_bloque(
        icon: Icons.format_quote_outlined,
        titulo: 'Eslogan',
        cuerpo: extra.eslogan.trim(),
      ));
    }

    final destinoBits = <String>[
      if (extra.provincia.trim().isNotEmpty) extra.provincia.trim(),
      if (extra.municipio.trim().isNotEmpty) extra.municipio.trim(),
      if (extra.duracionTexto.trim().isNotEmpty)
        'Duración: ${extra.duracionTexto.trim()}',
    ];
    if (destinoBits.isNotEmpty) {
      sections.add(_bloque(
        icon: Icons.map_outlined,
        titulo: 'Ubicación y duración',
        cuerpo: destinoBits.join('\n'),
      ));
    }

    if (extra.direccionExacta.trim().isNotEmpty ||
        extra.referenciaLugar.trim().isNotEmpty) {
      sections.add(_bloque(
        icon: Icons.place_outlined,
        titulo: 'Punto de encuentro',
        cuerpo: [
          if (extra.direccionExacta.trim().isNotEmpty)
            extra.direccionExacta.trim(),
          if (extra.referenciaLugar.trim().isNotEmpty)
            'Ref.: ${extra.referenciaLugar.trim()}',
        ].join('\n'),
      ));
    }

    if (extra.puntosRecogida.isNotEmpty) {
      sections.add(_recorridoRecogida());
    }

    if (extra.itinerario.isNotEmpty) {
      sections.add(_itinerario());
    }

    if (extra.noIncluye.trim().isNotEmpty) {
      sections.add(_bloque(
        icon: Icons.block_outlined,
        titulo: 'No incluye',
        cuerpo: extra.noIncluye.trim(),
      ));
    }

    if (extra.queDebeLlevar.trim().isNotEmpty) {
      sections.add(_bloque(
        icon: Icons.backpack_outlined,
        titulo: 'Qué debe llevar',
        cuerpo: extra.queDebeLlevar.trim(),
      ));
    }

    if (extra.reglas.trim().isNotEmpty) {
      sections.add(_bloque(
        icon: Icons.gavel_outlined,
        titulo: 'Reglas',
        cuerpo: extra.reglas.trim(),
      ));
    }

    final info = <String>[
      if (extra.edadMinima != null && extra.edadMinima! > 0)
        'Edad mínima: ${extra.edadMinima} años',
      'Niños: ${extra.ninosPermitidos ? 'Permitidos' : 'No permitidos'}',
      'Mascotas: ${extra.mascotasPermitidas ? 'Permitidas' : 'No permitidas'}',
      if (extra.observaciones.trim().isNotEmpty) extra.observaciones.trim(),
    ];
    if (info.isNotEmpty) {
      sections.add(_bloque(
        icon: Icons.info_outline,
        titulo: 'Información adicional',
        cuerpo: info.join('\n'),
      ));
    }

    if (sections.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          sections[i],
        ],
      ],
    );
  }

  Widget _bloque({
    required IconData icon,
    required String titulo,
    required String cuerpo,
  }) {
    final textPrimary =
        estiloOscuroRojo ? Colors.white : const Color(0xFF101828);
    final textMuted =
        estiloOscuroRojo ? const Color(0xFF9CA3AF) : const Color(0xFF667085);
    final accent = estiloOscuroRojo ? _kBorde : const Color(0xFF0D9488);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: estiloOscuroRojo ? _kFondo : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: estiloOscuroRojo ? _kBorde : const Color(0xFFE2E8F0),
          width: estiloOscuroRojo ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            cuerpo,
            style: TextStyle(color: textMuted, height: 1.4, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _recorridoRecogida() {
    final textPrimary =
        estiloOscuroRojo ? Colors.white : const Color(0xFF101828);
    final textMuted =
        estiloOscuroRojo ? const Color(0xFF9CA3AF) : const Color(0xFF667085);
    final accent = estiloOscuroRojo ? _kBorde : const Color(0xFF0D9488);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: estiloOscuroRojo ? _kFondo : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: estiloOscuroRojo ? _kBorde : const Color(0xFFE2E8F0),
          width: estiloOscuroRojo ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alt_route, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Recorrido de recogida',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'El conductor pasa por estas paradas antes de salir al destino.',
            style: TextStyle(color: textMuted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 10),
          for (final p in extra.puntosRecogida) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 78,
                  child: Text(
                    p.hora.trim().isEmpty ? '—' : p.hora.trim(),
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    p.lugar.trim(),
                    style: TextStyle(color: textMuted, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _itinerario() {
    final textPrimary =
        estiloOscuroRojo ? Colors.white : const Color(0xFF101828);
    final textMuted =
        estiloOscuroRojo ? const Color(0xFF9CA3AF) : const Color(0xFF667085);
    final accent = estiloOscuroRojo ? _kBorde : const Color(0xFF0D9488);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: estiloOscuroRojo ? _kFondo : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: estiloOscuroRojo ? _kBorde : const Color(0xFFE2E8F0),
          width: estiloOscuroRojo ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_outlined, color: accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Itinerario',
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in extra.itinerario) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    item.hora.trim().isEmpty ? '—' : item.hora.trim(),
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    item.actividad.trim(),
                    style: TextStyle(color: textMuted, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}
