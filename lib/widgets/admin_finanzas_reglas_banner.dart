import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/admin/admin_ui_theme.dart';

/// Explica las tres vías de dinero sin mezclar efectivo con liquidación semanal.
class AdminFinanzasReglasBanner extends StatelessWidget {
  const AdminFinanzasReglasBanner({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Material(
        color: Colors.indigo.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            'Efectivo → comisión RAI vía recarga prepago (sin escape). '
            'Transferencia/tarjeta → conciliar/verificar → liquidación semanal al taxista.',
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      );
    }
    return Material(
      color: Colors.indigo.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reglas de cobro y liquidación',
              style: TextStyle(
                color: AdminUi.onCard(context),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            _fila(
              context,
              Icons.payments_outlined,
              Colors.teal,
              'Efectivo',
              'Comisión RAI descontada del prepago al cerrar el viaje (config ADM, '
              'típicamente 10% de apertura). Sin saldo → bloqueo hasta recarga.',
            ),
            const SizedBox(height: 6),
            _fila(
              context,
              Icons.account_balance_outlined,
              Colors.blue,
              'Transferencia',
              'Cliente paga a RAI → conciliación → liquidación semanal. '
              'RAI retiene el % de transferencia (config ADM, típ. 15%).',
            ),
            const SizedBox(height: 6),
            _fila(
              context,
              Icons.credit_card_outlined,
              Colors.deepPurple,
              'Tarjeta (AZUL)',
              'Cobro electrónico verificado. RAI retiene el % de tarjeta (config ADM, '
              'típ. 15%); neto al chofer en lote semanal.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _fila(
    BuildContext context,
    IconData icon,
    Color color,
    String titulo,
    String texto,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                color: AdminUi.secondary(context),
                fontSize: 12,
                height: 1.35,
              ),
              children: [
                TextSpan(
                  text: '$titulo: ',
                  style: TextStyle(
                    color: AdminUi.onCard(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: texto),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
