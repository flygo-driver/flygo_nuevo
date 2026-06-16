import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../servicios/app_config_service.dart';

/// Cuenta RAI para que el taxista deposite recarga/comisión.
/// Lee en vivo `app_config/pagos` (misma fuente que ADM → Configuración RAI).
class RaiCuentaDepositoPanel extends StatelessWidget {
  const RaiCuentaDepositoPanel({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.mostrarCopiar = true,
    this.mostrarRnc = true,
    this.mostrarNota = false,
  });

  final String titulo;
  final String? subtitulo;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool mostrarCopiar;
  final bool mostrarRnc;
  final bool mostrarNota;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<DatosBancarios?>(
      stream: AppConfigService.streamDatosBancarios(),
      builder: (context, snap) {
        final cfg = AppConfigService.efectivos(snap.data);
        final cuenta = cfg.numeroCuenta.trim();

        return Container(
          width: double.infinity,
          margin: margin,
          padding: padding,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.account_balance, color: cs.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      titulo,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              if (subtitulo != null && subtitulo!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitulo!,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _linea(context, 'Titular', cfg.titular),
              if (mostrarRnc && cfg.rnc.trim().isNotEmpty)
                _linea(context, 'RNC', cfg.rnc),
              _linea(context, 'Banco', cfg.bancoNombre),
              _linea(context, 'Tipo', cfg.tipoCuenta),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _linea(context, 'No. cuenta', cuenta),
                  ),
                  if (mostrarCopiar && cuenta.isNotEmpty)
                    IconButton(
                      tooltip: 'Copiar número de cuenta',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: cuenta));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Número de cuenta copiado'),
                          ),
                        );
                      },
                      icon: Icon(Icons.copy, color: cs.primary, size: 22),
                    ),
                ],
              ),
              if (mostrarNota && cfg.nota.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  cfg.nota.trim(),
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _linea(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    final v = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 13,
            height: 1.3,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: v,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
