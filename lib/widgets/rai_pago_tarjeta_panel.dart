import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/servicios/finance_config_service.dart';
import 'package:flygo_nuevo/servicios/pagos/azul_payment_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/widgets/azul_card_brands_row.dart';

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
    this.modoViajeEnCurso = false,
  });

  final String viajeId;
  final Map<String, dynamic> viajeData;
  final double montoRd;
  final bool fondoOscuro;
  final bool mostrarSoloCliente;
  final String role;
  final bool modoViajeEnCurso;

  @override
  State<RaiPagoTarjetaPanel> createState() => _RaiPagoTarjetaPanelState();
}

class _RaiPagoTarjetaPanelState extends State<RaiPagoTarjetaPanel>
    with WidgetsBindingObserver {
  bool _cargando = false;
  bool _verificando = false;
  bool _cambiandoEfectivo = false;

  bool get _pagado => MetodoPagoViaje.tarjetaPagadoVerificado(widget.viajeData);

  bool get _fallido => MetodoPagoViaje.tarjetaPagoFallido(widget.viajeData);

  bool get _mostrarOpcionEfectivo =>
      !_pagado && (widget.modoViajeEnCurso || _fallido);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_pagado && !_verificando) {
      _verificarPagoAlVolver();
    }
  }

  Future<void> _verificarPagoAlVolver() async {
    if (!FinanceConfigService.pagosConTarjetaAzulHabilitados) return;
    _verificando = true;
    try {
      final res = await AzulPaymentService.verifyPayment(
        viajeId: widget.viajeId,
      );
      if (!mounted) return;
      final captured = res['captured'] == true ||
          res['reconciled'] == true ||
          res['estadoPago']?.toString().toLowerCase() == 'verificado';
      if (captured) {
        AzulPaymentService.limpiarViajePagoEnCurso(widget.viajeId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pago con tarjeta confirmado.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (_) {
      // Silencioso: el stream del viaje actualizará si AZUL ya capturó.
    } finally {
      _verificando = false;
    }
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
      final url = res.launchUrl ?? '';
      if (url.isNotEmpty) {
        AzulPaymentService.registrarViajePagoEnCurso(widget.viajeId);
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo abrir el navegador para el pago.'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.useStub
                ? 'Completá el pago en el navegador y volvé a la app.'
                : 'Completá el pago en AZUL y volvé a la app para ver la confirmación.',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
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

  Future<void> _pagarEnEfectivo() async {
    if (_cambiandoEfectivo || _cargando) return;

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Pagar en efectivo?'),
        content: Text(
          'Si tu tarjeta no tiene saldo o no se pudo cobrar, podés pagar en efectivo '
          'directo al conductor al llegar.\n\n'
          'Monto: ${FormatosMoneda.rd(widget.montoRd)}\n\n'
          'El conductor verá el cambio al instante en su app.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Seguir con tarjeta'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pagar en efectivo'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _cambiandoEfectivo = true);
    try {
      await AzulPaymentService.cambiarTarjetaAEfectivo(viajeId: widget.viajeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Listo: pagá ${FormatosMoneda.rd(widget.montoRd)} en efectivo al conductor.',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cambiar a efectivo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _cambiandoEfectivo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mostrarSoloCliente && widget.role != 'cliente') {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final bool dark = widget.fondoOscuro ||
        Theme.of(context).brightness == Brightness.dark;
    final habilitado = FinanceConfigService.pagosConTarjetaAzulHabilitados;
    final Color accent = widget.modoViajeEnCurso
        ? RaiDsColors.neon
        : (dark ? RaiDsColors.neonSoft : cs.primary);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [
                  const Color(0xFF0F1A14),
                  const Color(0xFF121212),
                  const Color(0xFF0D1117),
                ]
              : [
                  cs.surfaceContainerHighest,
                  cs.surface,
                ],
        ),
        border: Border.all(
          color: accent.withValues(alpha: widget.modoViajeEnCurso ? 0.45 : 0.22),
          width: widget.modoViajeEnCurso ? 1.5 : 1,
        ),
        boxShadow: widget.modoViajeEnCurso
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned(
              right: -24,
              top: -24,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.06),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Icon(
                          _pagado
                              ? Icons.check_circle_outline_rounded
                              : Icons.credit_card_rounded,
                          color: accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.modoViajeEnCurso
                                  ? 'Pagá ahora con tarjeta'
                                  : 'Pago con tarjeta',
                              style: TextStyle(
                                color: dark ? Colors.white : cs.onSurface,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Procesado por AZUL · Open ASK Service SRL',
                              style: TextStyle(
                                color: dark ? Colors.white54 : cs.onSurfaceVariant,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: dark
                          ? Colors.black.withValues(alpha: 0.28)
                          : cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.08)
                            : cs.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL A PAGAR',
                          style: TextStyle(
                            color: dark ? Colors.white54 : cs.onSurfaceVariant,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          FormatosMoneda.rd(widget.montoRd),
                          style: TextStyle(
                            color: dark ? Colors.white : cs.onSurface,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.05,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_pagado)
                    _StatusBanner(
                      icon: Icons.verified_rounded,
                      color: RaiDsColors.neon,
                      dark: dark,
                      text:
                          'Pago verificado. El conductor puede finalizar el viaje.',
                    )
                  else if (MetodoPagoViaje.tarjetaPagoFallido(widget.viajeData))
                    _StatusBanner(
                      icon: Icons.error_outline_rounded,
                      color: Colors.redAccent,
                      dark: dark,
                      text: MetodoPagoViaje.tarjetaUltimoErrorAzul(widget.viajeData) !=
                              null
                          ? 'Tarjeta rechazada: ${MetodoPagoViaje.tarjetaUltimoErrorAzul(widget.viajeData)}. '
                              'Probá otra tarjeta o pagá en efectivo al conductor.'
                          : 'Tarjeta rechazada (sin fondos o declinada). '
                              'Probá otra tarjeta o pagá en efectivo al conductor.',
                    )
                  else if (!habilitado)
                    _StatusBanner(
                      icon: Icons.info_outline_rounded,
                      color: Colors.orangeAccent,
                      dark: dark,
                      text:
                          'Cableado listo. Activa pagos con tarjeta cuando el banco apruebe.',
                    )
                  else
                    _StatusBanner(
                      icon: Icons.phonelink_lock_rounded,
                      color: accent,
                      dark: dark,
                      text: widget.modoViajeEnCurso
                          ? 'Estás a bordo: pagá antes de llegar. Se abre la pasarela AZUL en el navegador y volvés a la app al terminar.'
                          : 'Pagá con crédito o débito. Recibirás recibo digital en RD\$.',
                    ),
                  if (!_pagado && habilitado) ...[
                    const SizedBox(height: 12),
                    _PaymentStepsRow(dark: dark),
                  ],
                  const SizedBox(height: 14),
                  AzulCardBrandsRow(
                    compact: true,
                    darkSurface: dark,
                  ),
                  if (!_pagado && habilitado) ...[
                    const SizedBox(height: 14),
                    _PayButton(
                      loading: _cargando,
                      accent: accent,
                      destacado: widget.modoViajeEnCurso,
                      onPressed: _pagarConAzul,
                    ),
                  ],
                  if (_mostrarOpcionEfectivo) ...[
                    const SizedBox(height: 10),
                    _EfectivoButton(
                      loading: _cambiandoEfectivo,
                      dark: dark,
                      destacado: _fallido,
                      onPressed: _pagarEnEfectivo,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.text,
    required this.dark,
  });

  final IconData icon;
  final Color color;
  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final Color body = dark
        ? Colors.white.withValues(alpha: 0.78)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: body,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentStepsRow extends StatelessWidget {
  const _PaymentStepsRow({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StepPill(step: '1', label: 'Tocá pagar', dark: dark)),
        const SizedBox(width: 6),
        Expanded(child: _StepPill(step: '2', label: 'AZUL seguro', dark: dark)),
        const SizedBox(width: 6),
        Expanded(child: _StepPill(step: '3', label: 'Volvé a RAI', dark: dark)),
      ],
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({
    required this.step,
    required this.label,
    required this.dark,
  });

  final String step;
  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final Color labelColor =
        dark ? Colors.white60 : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.04)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Text(
            step,
            style: TextStyle(
              color: dark ? RaiDsColors.neonSoft : Theme.of(context).colorScheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: labelColor,
              fontSize: 9.5,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  const _PayButton({
    required this.loading,
    required this.accent,
    required this.destacado,
    required this.onPressed,
  });

  final bool loading;
  final Color accent;
  final bool destacado;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: destacado
              ? [const Color(0xFF00C853), const Color(0xFF00E676)]
              : [accent, accent.withValues(alpha: 0.85)],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black87,
                    ),
                  )
                else
                  const Icon(
                    Icons.lock_rounded,
                    color: Color(0xFF0A1F12),
                    size: 20,
                  ),
                const SizedBox(width: 10),
                Text(
                  loading
                      ? 'Conectando con AZUL…'
                      : (destacado
                          ? 'Pagar con tarjeta ahora'
                          : 'Pagar con tarjeta'),
                  style: const TextStyle(
                    color: Color(0xFF0A1F12),
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EfectivoButton extends StatelessWidget {
  const _EfectivoButton({
    required this.loading,
    required this.dark,
    required this.destacado,
    required this.onPressed,
  });

  final bool loading;
  final bool dark;
  final bool destacado;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Color border = destacado
        ? Colors.amberAccent.withValues(alpha: 0.55)
        : (dark
            ? Colors.white.withValues(alpha: 0.18)
            : Theme.of(context).colorScheme.outline.withValues(alpha: 0.45));
    final Color fg = destacado
        ? Colors.amberAccent
        : (dark ? Colors.white70 : Theme.of(context).colorScheme.onSurface);

    return OutlinedButton(
      onPressed: loading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(color: border, width: destacado ? 1.5 : 1),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: destacado
            ? Colors.amber.withValues(alpha: 0.08)
            : Colors.transparent,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: fg,
              ),
            )
          else
            Icon(
              Icons.payments_outlined,
              color: fg,
              size: 20,
            ),
          const SizedBox(width: 10),
          Text(
            loading ? 'Cambiando a efectivo…' : 'Pagar en efectivo al conductor',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
            ),
          ),
        ],
      ),
    );
  }
}
