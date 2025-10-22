import 'package:flutter/material.dart';
import '../servicios/wallet_service.dart';
import '../utils/formatos_moneda.dart';

class ComisionGlobalChip extends StatelessWidget {
  const ComisionGlobalChip({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: WalletService.streamComisionCentsGlobal(),
      builder: (context, snap) {
        final rd = ((snap.data ?? 0) / 100.0);

        final child = Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white10,
            border: Border.all(
              color: const Color.fromRGBO(255, 193, 7, 0.8),
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.trending_up, color: Color(0xFFFFC107), size: 20),
              const SizedBox(width: 6),
              Text(
                FormatosMoneda.rd(rd),
                style: const TextStyle(
                  color: Color(0xFFFFC107),
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
