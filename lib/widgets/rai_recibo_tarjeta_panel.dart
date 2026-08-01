import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flygo_nuevo/utils/recibo_tarjeta_azul.dart';

/// Recibo digital de pago con tarjeta (AZUL) — alineado con requisitos comercio.
class RaiReciboTarjetaPanel extends StatelessWidget {
  const RaiReciboTarjetaPanel({
    super.key,
    required this.recibo,
    this.fondoOscuro = false,
  });

  final ReciboTarjetaAzul recibo;
  final bool fondoOscuro;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = fondoOscuro
        ? Colors.greenAccent.withValues(alpha: 0.35)
        : cs.primary.withValues(alpha: 0.35);
    final bg = fondoOscuro
        ? const Color(0xFF0D1117)
        : cs.surfaceContainerHighest;
    final labelColor =
        fondoOscuro ? Colors.white54 : cs.onSurfaceVariant;
    final valueColor = fondoOscuro ? Colors.white : cs.onSurface;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                recibo.pagado ? Icons.receipt_long : Icons.hourglass_top,
                color: recibo.pagado ? Colors.green.shade600 : Colors.orange,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'RECIBO DE PAGO — RAI DRIVER',
                  style: TextStyle(
                    color: valueColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (!recibo.pagado)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Pendiente',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _fila('Comercio', recibo.comercio, labelColor, valueColor),
          _fila('RNC', recibo.rnc, labelColor, valueColor),
          _fila('Dirección', recibo.direccionComercio, labelColor, valueColor),
          _fila('Fecha', recibo.fechaLegible, labelColor, valueColor),
          _fila('No. orden', recibo.numeroOrden, labelColor, valueColor,
              mono: true),
          _fila('Referencia AZUL', recibo.referenciaAzul, labelColor, valueColor,
              mono: true),
          if (recibo.autorizacion != null)
            _fila('Autorización', recibo.autorizacion!, labelColor, valueColor,
                mono: true),
          if (recibo.rrn != null)
            _fila('RRN', recibo.rrn!, labelColor, valueColor, mono: true),
          _fila('Concepto', recibo.concepto, labelColor, valueColor),
          _fila('ID viaje', recibo.viajeId, labelColor, valueColor, mono: true),
          _fila('Método', recibo.metodoEtiqueta, labelColor, valueColor),
          const Divider(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'MONTO TOTAL (${recibo.moneda}):',
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                recibo.montoLegible,
                style: TextStyle(
                  color: recibo.pagado ? Colors.green.shade700 : valueColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Procesado por AZUL · Moneda: DOP (peso dominicano)\n'
            'Este documento constituye comprobante de pago electrónico.',
            style: TextStyle(color: labelColor, fontSize: 10.5, height: 1.35),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _copiarResumen(context),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copiar recibo'),
            ),
          ),
        ],
      ),
    );
  }

  void _copiarResumen(BuildContext context) {
    final buf = StringBuffer()
      ..writeln('RECIBO DE PAGO — RAI DRIVER')
      ..writeln('Comercio: ${recibo.comercio}')
      ..writeln('RNC: ${recibo.rnc}')
      ..writeln('Dirección: ${recibo.direccionComercio}')
      ..writeln('Fecha: ${recibo.fechaLegible}')
      ..writeln('No. orden: ${recibo.numeroOrden}')
      ..writeln('Referencia AZUL: ${recibo.referenciaAzul}');
    if (recibo.autorizacion != null) {
      buf.writeln('Autorización: ${recibo.autorizacion}');
    }
    if (recibo.rrn != null) buf.writeln('RRN: ${recibo.rrn}');
    buf
      ..writeln('Concepto: ${recibo.concepto}')
      ..writeln('ID viaje: ${recibo.viajeId}')
      ..writeln('Método: ${recibo.metodoEtiqueta}')
      ..writeln('MONTO TOTAL (DOP): ${recibo.montoLegible}')
      ..writeln('Procesado por AZUL');
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Recibo copiado al portapapeles')),
    );
  }

  Widget _fila(
    String label,
    String value,
    Color labelColor,
    Color valueColor, {
    bool mono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              '$label:',
              style: TextStyle(color: labelColor, fontSize: 11.5),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
