import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/config/recarga_bancaria_config.dart';
import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/servicios/comprobante_transferencia_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_pago_service.dart';
import 'package:flygo_nuevo/utils/corporativo_ciclo_facturacion.dart';
import 'package:flygo_nuevo/widgets/rai_cuenta_deposito_panel.dart';

/// Sheet: transferir a cuenta RAI + método de pago + enviar bauche.
Future<bool?> mostrarPagoCorporativoSheet({
  required BuildContext context,
  required String empresaId,
  required CorporativoEmpresa empresa,
  required double montoSugerido,
  String? liquidacionId,
  String? tituloPeriodo,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PagoCorporativoSheet(
      empresaId: empresaId,
      empresa: empresa,
      montoSugerido: montoSugerido,
      liquidacionId: liquidacionId,
      tituloPeriodo: tituloPeriodo,
    ),
  );
}

class _PagoCorporativoSheet extends StatefulWidget {
  const _PagoCorporativoSheet({
    required this.empresaId,
    required this.empresa,
    required this.montoSugerido,
    this.liquidacionId,
    this.tituloPeriodo,
  });

  final String empresaId;
  final CorporativoEmpresa empresa;
  final double montoSugerido;
  final String? liquidacionId;
  final String? tituloPeriodo;

  @override
  State<_PagoCorporativoSheet> createState() => _PagoCorporativoSheetState();
}

class _PagoCorporativoSheetState extends State<_PagoCorporativoSheet> {
  final _refCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  final _fmt = NumberFormat.currency(
    locale: 'es_DO',
    symbol: 'RD\$',
    decimalDigits: 0,
  );

  late String _metodo;
  Uint8List? _preview;
  bool _eligiendo = false;
  bool _enviando = false;

  /// Monto exacto de la factura / liquidación pendiente (no lo escribe el encargado).
  double get _montoFactura =>
      widget.montoSugerido > 0 ? widget.montoSugerido : 0;

  bool get _tieneFacturaPendiente => _montoFactura > 0;

  @override
  void initState() {
    super.initState();
    final preferida = widget.empresa.formaPagoRai.trim().toLowerCase();
    _metodo = CorporativoMetodosPago.todos.contains(preferida)
        ? preferida
        : CorporativoMetodosPago.transferencia;
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirBauche() async {
    if (_eligiendo || _enviando) return;
    setState(() => _eligiendo = true);
    try {
      final bytes =
          await ComprobanteTransferenciaService.seleccionarImagenComprobante(
        context,
      );
      if (!mounted || bytes == null) return;
      setState(() => _preview = bytes);
    } finally {
      if (mounted) setState(() => _eligiendo = false);
    }
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    if (!_tieneFacturaPendiente) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay factura pendiente. El monto se toma del total a pagar a RAI.',
          ),
        ),
      );
      return;
    }
    if (_preview == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adjunta la foto del bauche o comprobante.')),
      );
      return;
    }

    setState(() => _enviando = true);
    try {
      await CorporativoPagoService.enviarPagoConBauche(
        empresaId: widget.empresaId,
        montoRd: _montoFactura,
        metodoPago: _metodo,
        imageBytes: _preview!,
        referenciaBancaria: _refCtrl.text.trim(),
        nota: _notaCtrl.text.trim(),
        liquidacionId: widget.liquidacionId,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo enviar: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        decoration: BoxDecoration(
          color: p.scaffold,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: p.muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pagar liquidación a RAI',
                          style: TextStyle(
                            color: p.onCard,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          widget.tituloPeriodo ??
                              'Facturación ${CorporativoCicloFacturacion.descripcion(widget.empresa.facturacionCicloDias)}'
                              ' · ${CorporativoCicloFacturacion.etiquetaFormaPago(widget.empresa.formaPagoRai)}',
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: p.muted),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  corporativoCard(
                    context,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '1. Datos de la cuenta RAI',
                          style: TextStyle(
                            color: p.onCard,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Paga a Open ASK Service SRL (RAI), no a la cuenta del chofer.',
                          style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                        ),
                        const SizedBox(height: 10),
                        RaiCuentaDepositoPanel(
                          titulo: 'Cuenta para liquidación corporativa',
                          subtitulo:
                              'Concepto sugerido: ${widget.empresa.nombre} · Corporativo RAI',
                          mostrarNota: true,
                          padding: const EdgeInsets.all(12),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final texto =
                                '${RecargaBancariaConfig.titular}\n'
                                'RNC ${RecargaBancariaConfig.rnc}\n'
                                '${RecargaBancariaConfig.banco} · ${RecargaBancariaConfig.tipoCuenta}\n'
                                'Cuenta: ${RecargaBancariaConfig.numeroCuenta}\n'
                                'Concepto: ${widget.empresa.nombre} Corporativo';
                            await Clipboard.setData(ClipboardData(text: texto));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Datos de cuenta copiados'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                          label: const Text('Copiar datos de cuenta'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  corporativoCard(
                    context,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '2. Forma de pago',
                          style: TextStyle(
                            color: p.onCard,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: CorporativoMetodosPago.todos.map((m) {
                            final sel = _metodo == m;
                            return ChoiceChip(
                              label: Text(CorporativoMetodosPago.etiqueta(m)),
                              selected: sel,
                              onSelected: (_) => setState(() => _metodo = m),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          CorporativoMetodosPago.instruccion(_metodo),
                          style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: p.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: p.primary.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Monto de la factura pendiente',
                                style: TextStyle(
                                  color: p.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _tieneFacturaPendiente
                                    ? _fmt.format(_montoFactura)
                                    : 'RD\$0',
                                style: TextStyle(
                                  color: p.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 26,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _tieneFacturaPendiente
                                    ? 'Tomado automático del total a pagar a RAI. '
                                        'El encargado no lo escribe.'
                                    : 'No hay factura pendiente todavía. '
                                        'Cuando haya viajes/liquidación, el monto aparece solo.',
                                style: TextStyle(
                                  color: p.muted,
                                  fontSize: 11,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _refCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Referencia / no. de transferencia (opcional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _notaCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Nota para RAI (opcional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  corporativoCard(
                    context,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '3. Bauche / comprobante',
                          style: TextStyle(
                            color: p.onCard,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tomá foto del bauche o elegí de galería y envialo a RAI para validación.',
                          style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                        ),
                        if (_preview != null) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              _preview!,
                              height: 160,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _eligiendo || _enviando ? null : _elegirBauche,
                          icon: _eligiendo
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.photo_camera_outlined, size: 18),
                          label: Text(
                            _preview == null
                                ? 'Elegir foto del bauche'
                                : 'Cambiar foto del bauche',
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: (_enviando || !_tieneFacturaPendiente)
                              ? null
                              : _enviar,
                          icon: _enviando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_outlined, size: 18),
                          label: Text(
                            _enviando
                                ? 'Enviando a RAI…'
                                : !_tieneFacturaPendiente
                                    ? 'Sin factura pendiente'
                                    : 'Enviar bauche · ${_fmt.format(_montoFactura)}',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
