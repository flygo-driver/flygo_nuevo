// lib/pantallas/comun/factura_bola_pueblo.dart
//
// Comprobante digital RAI — Bola Ahorro (`bolas_pueblo/{id}`) tras
// `finalizarBolaPueblo`. Solo lectura; alinea tono y estructura a operadora formal.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/servicios/comprobante_transferencia_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/utils/precio_viaje_doc.dart';

double _pctComisionDesdeDoc(Map<String, dynamic> data) {
  final raw = data['comisionPct'];
  if (raw is num) {
    final v = raw.toDouble();
    return v <= 1 ? v * 100 : v;
  }
  return PlataformaEconomia.comisionViajePorcentaje;
}

class FacturaBolaPueblo extends StatelessWidget {
  const FacturaBolaPueblo({
    super.key,
    required this.bolaId,
    this.role = 'cliente',
  });

  final String bolaId;
  final String role;

  static Future<void> mostrar(
    BuildContext context, {
    required String bolaId,
    String role = 'cliente',
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => FacturaBolaPueblo(bolaId: bolaId, role: role),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('RAI — Comprobante Bola Ahorro'),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('bolas_pueblo')
            .doc(bolaId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No encontramos el registro de esta operación Bola Ahorro.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            );
          }
          final data = snap.data!.data() ?? <String, dynamic>{};
          return _FacturaBolaContent(
            bolaId: bolaId,
            data: data,
            role: role,
          );
        },
      ),
    );
  }
}

class _FacturaBolaContent extends StatelessWidget {
  const _FacturaBolaContent({
    required this.bolaId,
    required this.data,
    required this.role,
  });

  final String bolaId;
  final Map<String, dynamic> data;
  final String role;

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  String _fechaLegible() {
    final v = data['finalizadaEn'] ??
        data['updatedAt'] ??
        data['acordadaEn'] ??
        data['createdAt'];
    DateTime? dt;
    if (v is Timestamp) dt = v.toDate();
    if (v is DateTime) dt = v;
    dt ??= DateTime.now();
    return DateFormat("EEEE d 'de' MMMM yyyy, HH:mm", 'es').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final String origen = (data['origen'] ?? '').toString();
    final String destino = (data['destino'] ?? '').toString();
    final String metodoPago = (data['metodoPago'] ?? 'Efectivo').toString();
    final bool esTransferencia = MetodoPagoViaje.esTransferencia(metodoPago);
    final bool esEfectivo = MetodoPagoViaje.esEfectivo(metodoPago);

    final double total = totalRdDesdeDocViaje(data);
    final bool montoPendienteServidor =
        (data['estado'] ?? '').toString().trim().toLowerCase() == 'finalizada' &&
            total <= 1e-6;
    final double comision = _toDouble(data['comisionRd'] ?? 0);
    final double gananciaNeta =
        _toDouble(data['gananciaNetaChoferRd'] ?? (total - comision));
    final double pctComision = _pctComisionDesdeDoc(data);
    final String uidTaxista = (data['uidTaxista'] ?? '').toString().trim();
    final double? saldoPrepagoFactura = data['facturaSaldoPrepagoComisionRd']
        is num
        ? (data['facturaSaldoPrepagoComisionRd'] as num).toDouble()
        : null;
    final String estadoPago =
        (data['estadoPago'] ?? '').toString().trim().toLowerCase();
    final String comprobanteUrl =
        (data['comprobanteTransferenciaUrl'] ?? '').toString().trim();
    final bool transferenciaConfirmada =
        data['transferenciaConfirmada'] == true;

    final bool esTaxista = role == 'taxista';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _DocBanner(cs: cs, tt: tt),
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_outlined,
                        size: 18, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'SERVICIO FINALIZADO',
                      style: tt.labelLarge?.copyWith(
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Icon(Icons.savings_outlined, color: cs.primary, size: 40),
              const SizedBox(height: 8),
              Text(
                'Bola Ahorro',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                _fechaLegible(),
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Text(
                'ID de operación',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              SelectableText(
                bolaId,
                style: tt.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: bolaId));
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar ID'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionCard(
          title: 'Itinerario',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row(label: 'Origen', value: origen.isEmpty ? '—' : origen),
              _Row(label: 'Destino', value: destino.isEmpty ? '—' : destino),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: esTaxista
              ? 'Importe del traslado y liquidación RAI'
              : 'Importe acordado con el conductor',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row(
                label: 'Total del traslado (RD\$)',
                value: montoPendienteServidor
                    ? 'Confirmando…'
                    : FormatosMoneda.rd(total),
                boldValue: true,
              ),
              _Row(
                label: 'Medio de pago acordado',
                value: MetodoPagoViaje.etiquetaDocumento(metodoPago),
              ),
              if (esTaxista) ...[
                const Divider(height: 22),
                _Row(
                  label:
                      'Comisión RAI (${pctComision.toStringAsFixed(pctComision == pctComision.roundToDouble() ? 0 : 1)}%)',
                  value: FormatosMoneda.rd(comision),
                ),
                _Row(
                  label: 'Ingreso neto para el conductor',
                  value: FormatosMoneda.rd(gananciaNeta),
                  boldValue: true,
                ),
                if (esEfectivo && saldoPrepagoFactura != null) ...[
                  const SizedBox(height: 8),
                  _Row(
                    label: 'Saldo prepago comisión (tras este viaje)',
                    value: FormatosMoneda.rd(saldoPrepagoFactura),
                    boldValue: true,
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  esEfectivo
                      ? 'La comisión de plataforma se registró en tu billetera de conductor '
                          '(saldo prepago y/o comisión pendiente de efectivo), conforme a las '
                          'políticas vigentes. Regularizá en Mis pagos para mantener tu cuenta '
                          'operativa sin restricciones.'
                      : 'Pago por transferencia: el importe neto acordado lo recibís del '
                          'pasajero. La comisión RAI se liquida según el modelo de viajes '
                          'estándar (sin descuento automático del prepago en efectivo).',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 10),
                Text(
                  'El importe indicado corresponde al acuerdo entre pasajero y conductor. '
                  'RAI no custodia ese monto en Bola Ahorro: el pago se realiza directamente al conductor '
                  'según el medio indicado.',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (montoPendienteServidor) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Confirmando monto',
            child: Text(
              'El servidor está registrando el monto acordado. '
              'Este comprobante se actualizará solo en unos segundos.',
              style: tt.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
        ],
        if (esEfectivo) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Instrucción de pago en efectivo',
            tone: _SectionTone.highlight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.attach_money_rounded, color: Colors.green.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    esTaxista
                        ? 'Cobrá ${FormatosMoneda.rd(total)} en efectivo al pasajero, conforme al acuerdo.'
                        : 'Entregá ${FormatosMoneda.rd(total)} en efectivo al conductor al concluir el traslado.',
                    style: tt.bodyMedium?.copyWith(height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (esTransferencia && uidTaxista.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SeccionTransferenciaBola(
            bolaId: bolaId,
            uidTaxista: uidTaxista,
            total: total,
            role: role,
            comprobanteUrl: comprobanteUrl,
            transferenciaConfirmada: transferenciaConfirmada,
            estadoPago: estadoPago,
          ),
        ],
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Aviso legal breve',
          tone: _SectionTone.muted,
          child: Text(
            'Documento informativo generado electrónicamente a partir de los datos '
            'registrados en la plataforma RAI al momento del cierre. Conservalo como respaldo '
            'ante consultas o conciliaciones. Ante incidencias usá el chat de la publicación '
            'o los canales de soporte oficiales de RAI.',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: const Text('Entendido, cerrar comprobante'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
          ),
        ),
      ],
    );
  }
}

enum _SectionTone { normal, highlight, muted }

class _DocBanner extends StatelessWidget {
  const _DocBanner({required this.cs, required this.tt});

  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.gavel_outlined, color: cs.primary, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cierre auditado en servidor',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Este comprobante refleja el estado registrado por RAI al finalizar el traslado. '
                    'Solo lectura; no modifica montos ni contratos.',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.3,
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.tone = _SectionTone.normal,
  });

  final String title;
  final Widget child;
  final _SectionTone tone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color? bg;
    if (tone == _SectionTone.highlight) {
      bg = Colors.green.withValues(alpha: 0.06);
    } else if (tone == _SectionTone.muted) {
      bg = cs.surfaceContainerHighest.withValues(alpha: 0.4);
    }
    return Card(
      elevation: tone == _SectionTone.normal ? 0 : 0,
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: tone == _SectionTone.normal
              ? cs.outlineVariant.withValues(alpha: 0.5)
              : cs.outline.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.boldValue = false,
  });

  final String label;
  final String value;
  final bool boldValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 11,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            flex: 10,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: boldValue ? FontWeight.w800 : FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeccionTransferenciaBola extends StatelessWidget {
  const _SeccionTransferenciaBola({
    required this.bolaId,
    required this.uidTaxista,
    required this.total,
    required this.role,
    required this.comprobanteUrl,
    required this.transferenciaConfirmada,
    required this.estadoPago,
  });

  final String bolaId;
  final String uidTaxista;
  final double total;
  final String role;
  final String comprobanteUrl;
  final bool transferenciaConfirmada;
  final String estadoPago;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('bolas_pueblo')
          .doc(bolaId)
          .snapshots(),
      builder: (context, bolaSnap) {
        final bd = bolaSnap.data?.data() ?? <String, dynamic>{};
        final String url =
            (bd['comprobanteTransferenciaUrl'] ?? comprobanteUrl).toString().trim();
        final bool confirmada =
            bd['transferenciaConfirmada'] == true || transferenciaConfirmada;
        final String ep =
            (bd['estadoPago'] ?? estadoPago).toString().trim().toLowerCase();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BancariosTaxistaStream(uidTaxista: uidTaxista, total: total),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Estado de la transferencia',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Row(
                    label: 'Estado',
                    value: confirmada
                        ? 'Confirmada por el conductor'
                        : (url.isEmpty
                            ? 'Pendiente de comprobante'
                            : 'Comprobante enviado — pendiente confirmación'),
                    boldValue: confirmada,
                  ),
                  if (ep.isNotEmpty && !confirmada)
                    _Row(label: 'Detalle', value: ep),
                  if (url.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Comprobante',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        height: 200,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          height: 48,
                          child: Center(
                            child: Text('No se pudo cargar el comprobante.'),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (role == 'cliente' &&
                      !confirmada &&
                      url.isEmpty) ...[
                    const SizedBox(height: 14),
                    _BotonSubirComprobanteBola(bolaId: bolaId),
                  ],
                  if (role == 'taxista' &&
                      !confirmada &&
                      url.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _BotonConfirmarTransferenciaBola(bolaId: bolaId),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BotonSubirComprobanteBola extends StatefulWidget {
  const _BotonSubirComprobanteBola({required this.bolaId});
  final String bolaId;

  @override
  State<_BotonSubirComprobanteBola> createState() =>
      _BotonSubirComprobanteBolaState();
}

class _BotonSubirComprobanteBolaState extends State<_BotonSubirComprobanteBola> {
  bool _subiendo = false;

  Future<void> _subir() async {
    if (_subiendo) return;
    setState(() => _subiendo = true);
    final r = await ComprobanteTransferenciaService.subirYReportarBola(
      bolaId: widget.bolaId,
    );
    if (!mounted) return;
    setState(() => _subiendo = false);
    ComprobanteTransferenciaService.mostrarFeedback(context, r);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _subiendo ? null : _subir,
        icon: _subiendo
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.upload_file_rounded),
        label: Text(_subiendo
            ? 'Subiendo comprobante…'
            : 'Subir comprobante de pago'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}

class _BotonConfirmarTransferenciaBola extends StatefulWidget {
  const _BotonConfirmarTransferenciaBola({required this.bolaId});
  final String bolaId;

  @override
  State<_BotonConfirmarTransferenciaBola> createState() =>
      _BotonConfirmarTransferenciaBolaState();
}

class _BotonConfirmarTransferenciaBolaState
    extends State<_BotonConfirmarTransferenciaBola> {
  bool _busy = false;

  Future<void> _confirmar() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await BolaPuebloRepo.confirmarTransferenciaPorTaxista(
        bolaId: widget.bolaId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transferencia confirmada.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _busy ? null : _confirmar,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.verified_rounded),
        label: Text(_busy
            ? 'Confirmando…'
            : 'Confirmar que recibí la transferencia'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
        ),
      ),
    );
  }
}

class _BancariosTaxistaStream extends StatelessWidget {
  const _BancariosTaxistaStream({
    required this.uidTaxista,
    required this.total,
  });

  final String uidTaxista;
  final double total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uidTaxista)
          .snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data() ?? <String, dynamic>{};
        final banco = (d['banco'] ?? '').toString().trim();
        final cuenta = (d['numeroCuenta'] ?? '').toString().trim();
        final tipo = (d['tipoCuenta'] ?? '').toString().trim();
        final titular =
            (d['titularCuenta'] ?? d['titular'] ?? '').toString().trim();

        return _SectionCard(
          title: 'Datos para transferencia al conductor',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Instrucciones de tesorería',
                style: tt.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              if (banco.isEmpty && cuenta.isEmpty)
                Text(
                  'El conductor no tiene cuenta bancaria cargada en el perfil RAI. '
                  'Coordiná el abono por el chat seguro de la publicación o por el teléfono indicado en la Bola.',
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                )
              else ...[
                if (banco.isNotEmpty) _Row(label: 'Banco', value: banco),
                if (tipo.isNotEmpty) _Row(label: 'Tipo de cuenta', value: tipo),
                if (cuenta.isNotEmpty) _Row(label: 'Número de cuenta', value: cuenta),
                if (titular.isNotEmpty) _Row(label: 'Titular', value: titular),
              ],
              const SizedBox(height: 12),
              Text(
                'Importe a transferir: ${total > 1e-6 ? FormatosMoneda.rd(total) : 'Confirmando…'}',
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Subí el comprobante desde este comprobante RAI cuando hayas '
                'realizado la transferencia (botón abajo).',
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
