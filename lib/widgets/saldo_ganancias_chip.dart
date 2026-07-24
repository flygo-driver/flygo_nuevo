// lib/widgets/saldo_ganancias_chip.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/servicios/wallet_service.dart';
import 'package:flygo_nuevo/pantallas/taxista/billetera_taxista.dart';

class SaldoGananciasChip extends StatelessWidget {
  const SaldoGananciasChip({super.key});

  String _rd(double v) =>
      NumberFormat.currency(locale: 'es_DO', symbol: 'RD\$').format(v);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? Colors.greenAccent : const Color(0xFF047857);
    final bg = isDark ? Colors.white10 : const Color(0xFFECFDF5);
    final muted = isDark ? Colors.white70 : const Color(0xFF475467);

    return StreamBuilder<Map<String, int>>(
      stream: WalletService.streamResumenTaxista(uid),
      builder: (context, snap) {
        final data = snap.data;
        final cents = data?['ganancia_cents'] ?? 0;
        final viajes = data?['viajes_completados'] ?? 0;
        final monto = cents / 100.0;

        final child = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: accent, width: 1.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    color: accent, size: 18),
                const SizedBox(width: 6),
                Text(
                  _rd(monto),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${viajes}v)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );

        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Tooltip(
            message: 'Ver billetera',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BilleteraTaxista()),
                  );
                },
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
