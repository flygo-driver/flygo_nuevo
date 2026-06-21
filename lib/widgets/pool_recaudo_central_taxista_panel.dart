import 'package:flutter/material.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/pool_recaudo_central.dart';
import 'package:flygo_nuevo/utils/pools_producto_copy.dart';

/// Resumen para el organizador: neto acumulado y cuenta donde RAI le transferirá.
class PoolRecaudoCentralTaxistaPanel extends StatelessWidget {
  const PoolRecaudoCentralTaxistaPanel({
    super.key,
    required this.poolData,
    this.compact = false,
  });

  final Map<String, dynamic> poolData;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!PoolRecaudoCentral.esPoolCentral(poolData)) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF101828);
    final textSecondary = isDark ? Colors.white70 : const Color(0xFF475467);
    const accent = Color(0xFFF59E0B);
    final cardBg = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFFF7ED);
    final border = isDark
        ? const Color(0xFFF59E0B)
        : const Color(0xFFF59E0B);

    final neto =
        ((poolData['montoNetoOrganizadorRd'] ?? 0) as num).toDouble();
    final comision =
        ((poolData['montoComisionRaiRd'] ?? 0) as num).toDouble();
    final recaudado =
        ((poolData['montoRecaudadoRaiRd'] ?? 0) as num).toDouble();
    final liqEstado =
        (poolData['liquidacionOrganizadorEstado'] ?? '').toString().trim();

    final bancoNombre = (poolData['bancoNombre'] ?? '').toString().trim();
    final bancoCuenta = (poolData['bancoCuenta'] ?? '').toString().trim();
    final bancoTipo = (poolData['bancoTipoCuenta'] ?? '').toString().trim();
    final bancoTitular = (poolData['bancoTitular'] ?? '').toString().trim();
    final bancoOk = bancoNombre.isNotEmpty &&
        bancoCuenta.isNotEmpty &&
        bancoTipo.isNotEmpty &&
        bancoTitular.isNotEmpty;

    final pagados = ((poolData['asientosPagados'] ?? 0) as num).toInt();
    final reservados = ((poolData['asientosReservados'] ?? 0) as num).toInt();
    final comEfectivoPrepago =
        ((poolData['comisionEfectivoPrepagoRd'] ?? 0) as num).toDouble();
    final asientosEfectivoComision =
        ((poolData['asientosEfectivoComision'] ?? 0) as num).toInt();

    final liqLabel = _liquidacionLabel(liqEstado, neto);

    return Container(
      width: double.infinity,
      margin: compact ? EdgeInsets.zero : const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recaudo RAI — tu neto',
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 13 : 14,
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 4),
            Text(
              PoolsProductoCopy.recaudoCentralTaxista,
              style: TextStyle(color: textSecondary, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 8),
            Text(
              'Cupos: $pagados pagados en RAI · $reservados reservados en total',
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Neto pendiente de cobrar: ${FormatosMoneda.rd(neto)}',
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 14 : 16,
            ),
          ),
          if (!compact && (recaudado > 0 || comision > 0)) ...[
            const SizedBox(height: 4),
            Text(
              'Verificado en RAI: ${FormatosMoneda.rd(recaudado)} · '
              'Comisión RAI (transferencias): ${FormatosMoneda.rd(comision)}',
              style: TextStyle(color: textSecondary, fontSize: 12),
            ),
          ],
          if (!compact && comEfectivoPrepago > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Efectivo al abordar: comisión RAI ${FormatosMoneda.rd(comEfectivoPrepago)} '
              'descontada del prepago al iniciar '
              '($asientosEfectivoComision asiento(s) × precio publicado).',
              style: TextStyle(color: textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            liqLabel,
            style: TextStyle(color: textSecondary, fontSize: 12),
          ),
          if (!compact) ...[
            const SizedBox(height: 8),
            Text(
              PoolsProductoCopy.recaudoCentralTaxistaPasos,
              style: TextStyle(color: textSecondary, fontSize: 11, height: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Te transferimos el neto a:',
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          if (bancoOk) ...[
            _filaBanco('Banco', bancoNombre, textSecondary, textPrimary),
            _filaBanco('Cuenta', bancoCuenta, textSecondary, textPrimary),
            _filaBanco('Tipo', bancoTipo, textSecondary, textPrimary),
            _filaBanco('Titular', bancoTitular, textSecondary, textPrimary),
          ] else
            const Text(
              'Completa tu cuenta bancaria al publicar la salida para recibir el neto.',
              style: TextStyle(color: Color(0xFFB45309), fontSize: 12),
            ),
        ],
      ),
    );
  }

  static String _liquidacionLabel(String estado, double neto) {
    final e = estado.toLowerCase();
    if (e == 'pendiente_pago') {
      return 'Estado: pendiente de transferencia RAI (salida cerrada).';
    }
    if (e == 'liquidado' || e == 'pagado') {
      return 'Estado: neto transferido a tu cuenta.';
    }
    if (neto > 0) {
      return 'Estado: neto acumulado — se transfiere al cerrar la salida.';
    }
    return 'Estado: sin pagos verificados en RAI todavía.';
  }

  Widget _filaBanco(
    String label,
    String value,
    Color labelColor,
    Color valueColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12, color: labelColor),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: value, style: TextStyle(color: valueColor)),
          ],
        ),
      ),
    );
  }
}
