import 'package:flutter/material.dart';

import '../utils/pool_recaudo_central.dart';
import '../pantallas/admin/admin_ui_theme.dart';

/// Desglose admin: recarga, si superó comisión, monto exacto a transferir.
class AdminPoolCierreRecaudoPanel extends StatelessWidget {
  const AdminPoolCierreRecaudoPanel({
    super.key,
    required this.cierre,
    this.liquidacionEstado,
    this.compact = false,
  });

  final PoolCierreRecaudoCentral cierre;
  final String? liquidacionEstado;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final green = AdminUi.accentGreen(context);
    final accent = AdminUi.progressAccent(context);
    final alertColor = cierre.superoRecargaComprada
        ? (Theme.of(context).brightness == Brightness.light
            ? Colors.deepOrange.shade800
            : Colors.orangeAccent)
        : green;

    return Container(
      width: double.infinity,
      margin: compact ? EdgeInsets.zero : const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cierre contable — recaudo central',
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          _linea(context, 'Ventas verificadas (bruto)',
              'RD\$ ${cierre.brutoRecaudadoRd.toStringAsFixed(2)}'),
          _linea(
            context,
            'Comisión RAI (10% sobre ventas)',
            'RD\$ ${cierre.comisionVentasRd.toStringAsFixed(2)}',
            bold: true,
            color: accent,
          ),
          _linea(
            context,
            'Recarga comprada (prepago consumido)',
            'RD\$ ${cierre.recargaCompradaRd.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: alertColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: alertColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              cierre.superoRecargaComprada
                  ? '⚠ Superó la recarga — retener RD\$ ${cierre.montoFaltaRetenerDelRecaudoRd.toStringAsFixed(2)} del recaudo'
                  : '✓ No superó la recarga — comisión cubierta con prepago',
              style: TextStyle(
                color: alertColor,
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            cierre.alertaSuperoRecarga,
            style: TextStyle(
              color: AdminUi.muted(context),
              fontSize: compact ? 10 : 11,
              height: 1.35,
            ),
          ),
          if (cierre.superoRecargaComprada) ...[
            const SizedBox(height: 4),
            _linea(
              context,
              'Retener del recaudo (comisión − recarga)',
              'RD\$ ${cierre.montoFaltaRetenerDelRecaudoRd.toStringAsFixed(2)}',
              bold: true,
              color: accent,
            ),
          ],
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: green.withValues(alpha: 0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TRANSFERIR EXACTO AL ORGANIZADOR',
                  style: TextStyle(
                    color: green,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'RD\$ ${cierre.netoOrganizadorFinalRd.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: green,
                    fontSize: compact ? 16 : 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cierre.formulaTransferenciaExacta,
                  style: TextStyle(
                    color: AdminUi.secondary(context),
                    fontSize: compact ? 10 : 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'RAI total comisión: RD\$ ${cierre.comisionTotalRaiRd.toStringAsFixed(2)} '
                  '(RD\$ ${cierre.prepagoAplicadoRd.toStringAsFixed(2)} prepago + '
                  'RD\$ ${cierre.montoFaltaRetenerDelRecaudoRd.toStringAsFixed(2)} recaudo)',
                  style: TextStyle(
                    color: AdminUi.muted(context),
                    fontSize: compact ? 10 : 11,
                  ),
                ),
              ],
            ),
          ),
          if (liquidacionEstado != null && liquidacionEstado!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Liquidación: $liquidacionEstado',
              style: TextStyle(
                color: AdminUi.muted(context),
                fontSize: compact ? 10 : 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _linea(
    BuildContext context,
    String label,
    String valor, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '$label: $valor',
        style: TextStyle(
          color: color ?? AdminUi.secondary(context),
          fontSize: compact ? 10 : 11,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}
