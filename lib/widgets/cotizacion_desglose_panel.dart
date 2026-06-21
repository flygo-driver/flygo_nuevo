import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Desglose compacto de cotización (tramos o lineal).
class CotizacionDesglosePanel extends StatelessWidget {
  const CotizacionDesglosePanel({
    super.key,
    required this.desglose,
    this.textColor,
    this.mutedColor,
  });

  final Map<String, dynamic> desglose;
  final Color? textColor;
  final Color? mutedColor;

  static final NumberFormat _rd =
      NumberFormat.currency(locale: 'es', symbol: 'RD\$');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = textColor ?? cs.onSurface;
    final muted = mutedColor ?? cs.onSurfaceVariant;
    final modo = (desglose['modo'] ?? '').toString();

    if (modo != 'tramos') return const SizedBox.shrink();

    final lineas = desglose['lineas'];
    if (lineas is! List || lineas.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            desglose['esLargaDistancia'] == true
                ? 'Desglose · larga distancia'
                : 'Desglose del precio',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 8),
          _fila(muted, fg, 'Base', desglose['baseRd']),
          ...lineas.map((raw) {
            if (raw is! Map) return const SizedBox.shrink();
            final km = (raw['km'] as num?)?.toDouble() ?? 0;
            final porKm = (raw['porKm'] as num?)?.toDouble() ?? 0;
            final importe = (raw['importeRd'] as num?)?.toDouble() ?? 0;
            final etiqueta = (raw['etiquetaTramo'] ?? '').toString().trim();
            return _fila(
              muted,
              fg,
              etiqueta.isNotEmpty
                  ? '$etiqueta · ${km.toStringAsFixed(0)} km × RD\$${porKm.toStringAsFixed(0)}/km'
                  : '${km.toStringAsFixed(0)} km × RD\$${porKm.toStringAsFixed(0)}/km',
              importe,
            );
          }),
          if (((desglose['peajeRd'] as num?)?.toDouble() ?? 0) > 0)
            _fila(muted, fg, 'Peaje', desglose['peajeRd']),
          if (desglose['idaVuelta'] == true)
            _fila(muted, fg, 'Ida y vuelta (×1.8)', null,
                nota: 'Aplicado sobre tramo + peaje'),
          if (desglose['promoOmitidaPorLargaDistancia'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Promoción no aplica en larga distancia.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fila(Color muted, Color fg, String label, Object? valor, {String? nota}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: muted, fontSize: 11.5)),
                if (nota != null)
                  Text(nota, style: TextStyle(color: muted, fontSize: 10.5)),
              ],
            ),
          ),
          if (valor is num)
            Text(
              _rd.format(valor.toDouble()),
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
        ],
      ),
    );
  }
}
