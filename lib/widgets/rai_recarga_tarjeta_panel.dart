import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flygo_nuevo/servicios/finance_config_service.dart';
import 'package:flygo_nuevo/servicios/pagos/azul_payment_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/azul_card_brands_row.dart';

/// Recarga prepago taxista con tarjeta débito (AZUL). Flag OFF → no se muestra.
class RaiRecargaTarjetaPanel extends StatefulWidget {
  const RaiRecargaTarjetaPanel({
    super.key,
    required this.montoSugeridoRd,
    this.fondoOscuro = false,
  });

  final double montoSugeridoRd;
  final bool fondoOscuro;

  @override
  State<RaiRecargaTarjetaPanel> createState() => _RaiRecargaTarjetaPanelState();
}

class _RaiRecargaTarjetaPanelState extends State<RaiRecargaTarjetaPanel>
    with WidgetsBindingObserver {
  static const List<double> _montos = <double>[200, 500, 700];

  bool _cargando = false;
  bool _verificando = false;
  double? _montoElegido;
  String? _recargaIdPendiente;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _montoElegido = _montos.contains(widget.montoSugeridoRd)
        ? widget.montoSugeridoRd
        : 200;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _recargaIdPendiente != null &&
        !_verificando) {
      _verificarRecargaAlVolver();
    }
  }

  Future<void> _verificarRecargaAlVolver() async {
    final recargaId = _recargaIdPendiente;
    if (recargaId == null || recargaId.isEmpty || _verificando) return;
    if (!FinanceConfigService.recargaPrepagoAzulHabilitados) return;

    _verificando = true;
    try {
      final res = await AzulPaymentService.verifyRecargaTaxista(
        recargaId: recargaId,
      );
      if (!mounted) return;
      final ok = res['captured'] == true ||
          res['estado']?.toString().toLowerCase() == 'pagado';
      if (ok) {
        _recargaIdPendiente = null;
        AzulPaymentService.limpiarRecargaPagoEnCurso(recargaId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Recarga con tarjeta confirmada. Tu cuenta se desbloqueó automáticamente.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (_) {
      // El stream de recargas/billetera actualizará si AZUL ya capturó.
    } finally {
      _verificando = false;
    }
  }

  Future<void> _recargarConTarjeta() async {
    final monto = _montoElegido;
    if (monto == null || monto < 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El monto mínimo de recarga es RD\$200.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_cargando) return;
    setState(() => _cargando = true);
    try {
      final res =
          await AzulPaymentService.createRecargaTaxistaSession(montoRd: monto);
      if (!mounted) return;
      if (res.omitido) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recarga con tarjeta aún no activa (flag OFF).'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (res.notConfigured) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.message ?? 'AZUL cableado: falta configurar credenciales.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final recargaId = res.recargaId?.trim();
      if (recargaId != null && recargaId.isNotEmpty) {
        setState(() => _recargaIdPendiente = recargaId);
        AzulPaymentService.registrarRecargaPagoEnCurso(recargaId);
      }
      final url = res.launchUrl ?? '';
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
                ? 'Sesión AZUL recarga abierta (staging). Al aprobar, se desbloquea automático.'
                : 'Completá el pago en AZUL. Al aprobar, tu saldo se acredita y se desbloquea solo.',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error recarga AZUL: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!FinanceConfigService.recargaPrepagoAzulHabilitados) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final labelColor =
        widget.fondoOscuro ? Colors.white54 : cs.onSurfaceVariant;
    final valueColor = widget.fondoOscuro ? Colors.white : cs.onSurface;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.fondoOscuro
            ? const Color(0xFF1A1A1A)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.fondoOscuro
              ? Colors.tealAccent.withValues(alpha: 0.35)
              : Colors.teal.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Opción 2 · Tarjeta de débito (AZUL)',
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Alternativa a la transferencia: comprá crédito RAI al instante. '
            'Si estabas bloqueado por saldo bajo, al aprobar el pago se desbloquea solo.',
            style: TextStyle(color: labelColor, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _montos.map((m) {
              final sel = _montoElegido == m;
              return ChoiceChip(
                label: Text(FormatosMoneda.rd(m)),
                selected: sel,
                onSelected: _cargando
                    ? null
                    : (_) => setState(() => _montoElegido = m),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          AzulCardBrandsRow(
            compact: widget.fondoOscuro,
            darkSurface: widget.fondoOscuro,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _cargando ? null : _recargarConTarjeta,
            icon: _cargando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.credit_card),
            label: Text(
              _cargando
                  ? 'Conectando…'
                  : 'Pagar ${FormatosMoneda.rd(_montoElegido ?? 200)} con débito',
            ),
          ),
        ],
      ),
    );
  }
}
