import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/recarga_bancaria_config.dart';
import '../servicios/app_config_service.dart';
import '../utils/pool_gira_tropical_theme.dart';

/// Cuenta RAI (Open ASK Service SRL) para que el taxista deposite recarga/comisión.
/// Lee en vivo `app_config/pagos` con fallback a [RecargaBancariaConfig].
/// No confundir con la cuenta personal del conductor ([ConfiguracionBancaria]).
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
    this.fondoOscuro = false,
    this.estiloVerano = false,
  });

  final String titulo;
  final String? subtitulo;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool mostrarCopiar;
  final bool mostrarRnc;
  final bool mostrarNota;
  final bool fondoOscuro;
  /// Marco verano/tropical para giras por cupos (claro, oscuro y dynamic color).
  final bool estiloVerano;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tropical =
        estiloVerano ? PoolGiraTropicalTheme.of(context) : null;
    final Color labelColor = fondoOscuro
        ? Colors.white54
        : (estiloVerano ? cs.onSurfaceVariant : cs.onSurfaceVariant);
    final Color valueColor = fondoOscuro ? Colors.white : cs.onSurface;
    final Color borderColor = estiloVerano
        ? tropical!.cardBorder
        : (fondoOscuro
            ? Colors.white24
            : cs.outlineVariant.withValues(alpha: 0.7));
    final Color bgColor = estiloVerano
        ? tropical!.cardFill
        : (fondoOscuro
            ? const Color(0xFF1A1A1A)
            : cs.surfaceContainerHighest.withValues(alpha: 0.55));
    final Color iconColor = estiloVerano
        ? tropical!.ocean
        : (fondoOscuro ? Colors.greenAccent : cs.primary);

    return StreamBuilder<DatosBancarios>(
      stream: AppConfigService.streamDatosBancariosEfectivos(),
      builder: (context, snap) {
        final cfg = snap.data ?? AppConfigService.datosBancariosPorDefecto;
        final cuenta = RecargaBancariaConfig.numeroCuenta;
        final rnc = RecargaBancariaConfig.rnc;
        final titularEmpresa = RecargaBancariaConfig.titular;
        final tipoCuenta = RecargaBancariaConfig.tipoCuenta;
        final bancoNombre = RecargaBancariaConfig.banco;

        final inner = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  estiloVerano ? Icons.wb_sunny_outlined : Icons.account_balance,
                  color: iconColor,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    style: TextStyle(
                      color: valueColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            if (estiloVerano) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      tropical!.sunset.withValues(alpha: 0.18),
                      tropical.ocean.withValues(alpha: 0.14),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tropical.chipBorder),
                ),
                child: Text(
                  RecargaBancariaConfig.resumenCuentaCliente,
                  style: TextStyle(
                    color: valueColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            if (subtitulo != null && subtitulo!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitulo!,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 8),
            _linea('Empresa / titular', titularEmpresa, labelColor, valueColor),
            if (mostrarRnc) _linea('RNC', rnc, labelColor, valueColor),
            _linea('Banco', bancoNombre, labelColor, valueColor),
            _lineaDestacada(
              'Tipo',
              tipoCuenta,
              labelColor,
              valueColor,
              destacar: estiloVerano,
              accent: tropical?.ocean,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _linea(
                    'No. cuenta',
                    cuenta,
                    labelColor,
                    valueColor,
                  ),
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
                    icon: Icon(Icons.copy, color: iconColor, size: 22),
                  ),
              ],
            ),
            if (mostrarNota && cfg.nota.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                cfg.nota.trim(),
                style: TextStyle(
                  color: labelColor,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ],
        );

        if (!estiloVerano) {
          return Container(
            width: double.infinity,
            margin: margin,
            padding: padding,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: inner,
          );
        }

        return Container(
          width: double.infinity,
          margin: margin,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: tropical!.frameGradient,
            boxShadow: [
              BoxShadow(
                color: tropical.shadow,
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(2.5),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: borderColor),
            ),
            child: inner,
          ),
        );
      },
    );
  }

  Widget _lineaDestacada(
    String label,
    String value,
    Color labelColor,
    Color valueColor, {
    bool destacar = false,
    Color? accent,
  }) {
    final v = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: labelColor,
            fontSize: 13,
            height: 1.3,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: v,
              style: TextStyle(
                color: destacar ? (accent ?? valueColor) : valueColor,
                fontWeight: destacar ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _linea(
    String label,
    String value,
    Color labelColor,
    Color valueColor,
  ) {
    final v = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: labelColor,
            fontSize: 13,
            height: 1.3,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: v,
              style: TextStyle(
                color: valueColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
