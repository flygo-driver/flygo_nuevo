import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/recarga_bancaria_config.dart';

/// Cuenta corporativa Open ASK — siempre desde [RecargaBancariaConfig] (sin Firestore).
class CuentaOpenAskDepositoPanel extends StatelessWidget {
  const CuentaOpenAskDepositoPanel({
    super.key,
    this.fondoOscuro = false,
    this.mostrarNota = false,
  });

  final bool fondoOscuro;
  final bool mostrarNota;

  Future<void> _copiarNumero(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: RecargaBancariaConfig.numeroCuenta),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Número de cuenta copiado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color labelColor =
        fondoOscuro ? Colors.white54 : cs.onSurfaceVariant;
    final Color valueColor = fondoOscuro ? Colors.white : cs.onSurface;
    final Color accent = fondoOscuro ? Colors.greenAccent : cs.primary;
    final Color bgColor = fondoOscuro
        ? const Color(0xFF1A1A1A)
        : cs.primaryContainer.withValues(alpha: 0.42);
    final Color borderColor = fondoOscuro
        ? Colors.greenAccent.withValues(alpha: 0.45)
        : cs.primary.withValues(alpha: 0.65);

    TextStyle label([double size = 12]) =>
        TextStyle(color: labelColor, fontSize: size, height: 1.35);
    TextStyle value({double size = 13, FontWeight w = FontWeight.w700}) =>
        TextStyle(color: valueColor, fontSize: size, fontWeight: w, height: 1.35);

    Widget fila(String k, String v) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: RichText(
          text: TextSpan(
            style: label(),
            children: [
              TextSpan(text: '$k: '),
              TextSpan(text: v, style: value()),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.account_balance, color: accent, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cuenta para recargar — Open ASK Service SRL',
                  style: value(size: 15, w: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Transferí aquí tu recarga prepago o comisión. '
            'No uses tu cuenta personal de Datos bancarios.',
            style: label(),
          ),
          const SizedBox(height: 10),
          fila('Titular', RecargaBancariaConfig.titular),
          fila('RNC', RecargaBancariaConfig.rnc),
          fila('Banco', RecargaBancariaConfig.banco),
          fila('Tipo', RecargaBancariaConfig.tipoCuenta),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 340;
              final cuenta = Text(
                RecargaBancariaConfig.numeroCuenta,
                style: TextStyle(
                  color: accent,
                  fontSize: stacked ? 20 : 22,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              );
              final copiar = FilledButton.tonalIcon(
                onPressed: () => _copiarNumero(context),
                style: fondoOscuro
                    ? FilledButton.styleFrom(
                        backgroundColor:
                            Colors.greenAccent.withValues(alpha: 0.2),
                        foregroundColor: Colors.greenAccent,
                      )
                    : null,
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copiar'),
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('No. cuenta', style: label()),
                    cuenta,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: copiar),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No. cuenta', style: label()),
                        cuenta,
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  copiar,
                ],
              );
            },
          ),
          if (mostrarNota) ...[
            const SizedBox(height: 8),
            Text(
              RecargaBancariaConfig.notaRecarga,
              style: label(11.5),
            ),
          ],
        ],
      ),
    );
  }
}
