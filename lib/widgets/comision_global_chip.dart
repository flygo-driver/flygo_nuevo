import 'package:flutter/material.dart';
import '../servicios/wallet_service.dart';
import '../utils/formatos_moneda.dart';

class ComisionGlobalChip extends StatelessWidget {
  const ComisionGlobalChip({super.key});

  @override
  Widget build(BuildContext context) {
    final amber = Theme.of(context).brightness == Brightness.light
        ? Colors.amber.shade900
        : const Color(0xFFFFC107);
    final fill = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.65);

    return StreamBuilder<int>(
      stream: WalletService.streamComisionCentsGlobal(),
      builder: (context, snap) {
        final rd = ((snap.data ?? 0) / 100.0);

        final child = Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(
              color: amber.withValues(alpha: 0.85),
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.trending_up, color: amber, size: 20),
              const SizedBox(width: 6),
              Text(
                FormatosMoneda.rd(rd),
                style: TextStyle(
                  color: amber,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        );

        return Tooltip(message: 'Comisión total (en vivo)', child: child);
      },
    );
  }
}
