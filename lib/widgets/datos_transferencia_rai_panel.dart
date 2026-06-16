import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/transferencia_recaudo_ui.dart';
import 'package:flygo_nuevo/widgets/rai_cuenta_deposito_panel.dart';
import 'package:flygo_nuevo/widgets/rai_recaudo_qr_panel.dart';

/// Cliente transfiere a cuenta RAI con referencia única (conciliación Banco Popular).
class DatosTransferenciaRaiPanel extends StatelessWidget {
  const DatosTransferenciaRaiPanel({
    super.key,
    required this.viajeData,
    required this.montoRd,
    this.titulo = 'PAGAR A RAI (TRANSFERENCIA)',
    this.fondoOscuro = false,
    this.footer,
  });

  final Map<String, dynamic> viajeData;
  final double montoRd;
  final String titulo;
  final bool fondoOscuro;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final referencia = TransferenciaRecaudoUi.referenciaDesdeViaje(viajeData);
    final cs = Theme.of(context).colorScheme;
    final labelColor = fondoOscuro ? Colors.white54 : cs.onSurfaceVariant;
    final valueColor = fondoOscuro ? Colors.white : cs.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RaiCuentaDepositoPanel(
          titulo: titulo,
          subtitulo:
              'Transferí el monto del viaje a la cuenta de RAI (Open ASK Service SRL). '
              'Indicá la referencia en App Popular → Pagos de servicios.',
          mostrarNota: true,
          margin: EdgeInsets.zero,
        ),
        if (montoRd > 0) ...[
          const SizedBox(height: 12),
          _bloqueMonto(context, labelColor, valueColor),
        ],
        if (referencia.isNotEmpty) ...[
          const SizedBox(height: 12),
          _bloqueReferencia(context, referencia, labelColor, valueColor),
        ],
        const SizedBox(height: 12),
        RaiRecaudoQrPanel(viajeData: viajeData, fondoOscuro: fondoOscuro),
        const SizedBox(height: 8),
        Text(
          'Conservá el comprobante. RAI conciliará el pago con esta referencia.',
          style: TextStyle(color: labelColor, fontSize: 12, height: 1.35),
        ),
        if (footer != null) ...[
          const SizedBox(height: 12),
          footer!,
        ],
      ],
    );
  }

  Widget _bloqueMonto(
    BuildContext context,
    Color labelColor,
    Color valueColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fondoOscuro
            ? const Color(0xFF1A1A1A)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: fondoOscuro ? Colors.white12 : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monto a transferir', style: TextStyle(color: labelColor, fontSize: 12)),
          Text(
            FormatosMoneda.rd(montoRd),
            style: TextStyle(
              color: valueColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloqueReferencia(
    BuildContext context,
    String referencia,
    Color labelColor,
    Color valueColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fondoOscuro
            ? const Color(0xFF1A1A1A)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: fondoOscuro ? Colors.greenAccent.withValues(alpha: 0.35) : Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Referencia de pago', style: TextStyle(color: labelColor, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  referencia,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar referencia',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: referencia));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Referencia copiada')),
              );
            },
            icon: Icon(
              Icons.copy,
              color: fondoOscuro ? Colors.greenAccent : Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
