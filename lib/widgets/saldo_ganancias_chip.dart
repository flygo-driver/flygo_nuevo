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

    return StreamBuilder<Map<String, int>>(
      stream: WalletService.streamResumenTaxista(uid),
      builder: (context, snap) {
        final data = snap.data;
        final cents = data?['ganancia_cents'] ?? 0;
        final viajes = data?['viajes_completados'] ?? 0;
        final monto = cents / 100.0;

        final child = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white10,
            border: Border.all(color: Colors.greenAccent, width: 1.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.greenAccent, size: 18),
              const SizedBox(width: 6),
              Text(
                _rd(monto),
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${viajes}v)',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );

        return Padding(
          padding: const EdgeInsets.only(right: 10),
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
