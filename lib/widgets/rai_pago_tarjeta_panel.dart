import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flygo_nuevo/servicios/finance_config_service.dart';
import 'package:flygo_nuevo/servicios/pagos/azul_payment_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';

/// Panel tarjeta AZUL (Fase 6 cableado). Flag OFF → aviso sin botón de cobro.
class RaiPagoTarjetaPanel extends StatefulWidget {
  const RaiPagoTarjetaPanel({
    super.key,
    required this.viajeId,
    required this.viajeData,
    required this.montoRd,
    this.fondoOscuro = false,
    this.mostrarSoloCliente = true,
    this.role = 'cliente',
  });

  final String viajeId;
  final Map<String, dynamic> viajeData;
  final double montoRd;
  final bool fondoOscuro;
  final bool mostrarSoloCliente;
  final String role;

  @override
  State<RaiPagoTarjetaPanel> createState() => _RaiPagoTarjetaPanelState();
}

class _RaiPagoTarjetaPanelState extends State<RaiPagoTarjetaPanel> {
  bool _cargando = false;

  bool get _pagado {
    final ep =
        (widget.viajeData['estadoPago'] ?? '').toString().trim().toLowerCase();
    final ps = (widget.viajeData['payment'] is Map)
        ? (widget.viajeData['payment'] as Map)['status']?.toString().trim().toLowerCase()
        : '';
    return ep == 'verificado' || ps == 'captured';
  }

  Future<void> _pagarConAzul() async {
    if (_cargando) return;
    setState(() => _cargando = true);
    try {
      final res = await AzulPaymentService.createSession(viajeId: widget.viajeId);
      if (!mounted) return;
      if (res.omitido) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pagos con tarjeta aún no activos (flag OFF).'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (res.notConfigured) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.message ??
                  'AZUL cableado: falta configurar credenciales en servidor.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final url = res.paymentPageUrl?.trim() ?? '';
      if (url.isNotEmpty) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.useStub
                ? 'Sesión AZUL stub abierta (staging).'
                : 'Sesión de pago iniciada.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error AZUL: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mostrarSoloCliente && widget.role != 'cliente') {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final labelColor =
        widget.fondoOscuro ? Colors.white54 : cs.onSurfaceVariant;
    final valueColor = widget.fondoOscuro ? Colors.white : cs.onSurface;
    final habilitado = FinanceConfigService.pagosConTarjetaAzulHabilitados;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.fondoOscuro
            ? const Color(0xFF1A1A1A)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.fondoOscuro
              ? Colors.deepPurpleAccent.withValues(alpha: 0.35)
              : cs.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pago con tarjeta (AZUL)',
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Monto: ${FormatosMoneda.rd(widget.montoRd)}',
            style: TextStyle(color: valueColor, fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (_pagado)
            Text(
              'Pago verificado.',
              style: TextStyle(
                color: Colors.green.shade400,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (!habilitado)
            Text(
              'Cableado listo. Activa pagosConTarjetaAzulHabilitados y credenciales AZUL cuando el banco apruebe.',
              style: TextStyle(color: labelColor, fontSize: 12, height: 1.35),
            )
          else
            Text(
              'Pagá con tarjeta de crédito o débito. El cobro va a cuenta RAI (Open ASK Service SRL).',
              style: TextStyle(color: labelColor, fontSize: 12, height: 1.35),
            ),
          if (!_pagado && habilitado) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _cargando ? null : _pagarConAzul,
              icon: _cargando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.credit_card),
              label: Text(_cargando ? 'Conectando…' : 'Pagar con tarjeta'),
            ),
          ],
        ],
      ),
    );
  }
}
