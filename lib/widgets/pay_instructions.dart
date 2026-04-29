// lib/widgets/pay_instructions.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flygo_nuevo/servicios/pay_config.dart';

class PayInstructions extends StatelessWidget {
  final String referencia; // referencia sugerida (opcional pero útil)
  final bool showEfectivoNote; // nota “pagar al abordar” si aplica

  const PayInstructions({
    super.key,
    required this.referencia,
    this.showEfectivoNote = false,
  });

  void _copy(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    // No esperamos el Future para no crear async gap
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copiado')));
  }

  @override
  Widget build(BuildContext context) {
    final border = Border.all(color: const Color(0xFF2A2A2A));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12),
        border: border,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cuenta FlyGo (Transferencia)',
              style: TextStyle(
                  color: Colors.greenAccent, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _row(context, 'Banco', PayConfig.bankName),
          _row(context, 'Tipo', PayConfig.accountType),
          _row(context, 'No. de cuenta', PayConfig.accountNumber, copy: true),
          _row(context, 'Titular', PayConfig.accountHolder),
          _row(context, 'RNC', PayConfig.rnc),
          const SizedBox(height: 8),
          _row(context, 'Referencia', referencia, copy: true),
          const SizedBox(height: 10),
          const Text(
            PayConfig.instrucciones,
            style: TextStyle(color: Colors.white70),
          ),
          if (showEfectivoNote) ...[
            const SizedBox(height: 8),
            const Text(
              'Si eliges EFECTIVO: pagarás al abordar con el conductor asignado.',
              style:
                  TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String k, String v, {bool copy = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(k, style: const TextStyle(color: Colors.white54)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(color: Colors.white)),
          ),
          if (copy)
            IconButton(
              onPressed: () => _copy(context, k, v),
              icon: const Icon(Icons.copy, color: Colors.white70, size: 18),
              tooltip: 'Copiar $k',
            ),
        ],
      ),
    );
  }
}
