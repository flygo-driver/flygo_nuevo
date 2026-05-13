// lib/pantallas/comun/factura_viaje.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/servicios/comprobante_transferencia_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';

/// Pantalla de factura visual del viaje.
///
/// Diseño:
/// - SOLO LECTURA del doc `viajes/{id}` (vía `Stream` para reflejar en vivo
///   el cambio de `transferenciaConfirmada` o el `comprobanteTransferenciaUrl`
///   tras subirlo desde la propia factura).
/// - Para los datos bancarios, prioriza los snapshots inmutables que el
///   taxista grabó al finalizar el viaje (`bancoTaxista`, `numeroCuentaTaxista`,
///   `tipoCuentaTaxista`, `titularCuentaTaxista`). Si están vacíos (viajes
///   antiguos / fallback), hace una lectura en vivo de `usuarios/{uidTaxista}`.
/// - Si [role] == 'cliente' y el método de pago es transferencia y aún no se
///   ha enviado comprobante (o fue rechazado), muestra un botón grande
///   "Subir comprobante de pago" que invoca al servicio reusable
///   [ComprobanteTransferenciaService.subirYReportar].
/// - El botón de cierre simplemente hace `pop()`. La pantalla que abrió la
///   factura sigue su flujo normal después (cola del taxista, post-viaje del
///   cliente, etc.).
class FacturaViaje extends StatelessWidget {
  const FacturaViaje({
    super.key,
    required this.viajeId,
    this.role = 'cliente',
  });

  final String viajeId;
  final String role;

  /// Helper para abrir la factura desde cualquier parte de la app.
  /// Usa `rootNavigator` para que el modal viva por encima de los Navigators
  /// anidados de los Shells (ClienteShell, TaxistaShell).
  static Future<void> mostrar(
    BuildContext context, {
    required String viajeId,
    String role = 'cliente',
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => FacturaViaje(viajeId: viajeId, role: role),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('RAI — Comprobante de viaje'),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('viajes')
            .doc(viajeId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No encontramos el registro de este viaje en la plataforma RAI.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            );
          }
          final data = snap.data!.data() ?? <String, dynamic>{};
          return _FacturaContent(
            viajeId: viajeId,
            data: data,
            role: role,
          );
        },
      ),
    );
  }
}

class _FacturaContent extends StatelessWidget {
  const _FacturaContent({
    required this.viajeId,
    required this.data,
    required this.role,
  });

  final String viajeId;
  final Map<String, dynamic> data;
  final String role;

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  String _fechaLegible() {
    final v = data['completadoEn'] ??
        data['actualizadoEn'] ??
        data['updatedAt'] ??
        data['fechaHora'];
    DateTime? dt;
    if (v is Timestamp) dt = v.toDate();
    if (v is DateTime) dt = v;
    dt ??= DateTime.now();
    return DateFormat("EEEE d 'de' MMMM yyyy, HH:mm", 'es').format(dt);
  }

  /// Lee primero los snapshots grabados al finalizar el viaje. Si todos
  /// están vacíos (viajes antiguos o fallo de escritura), retorna `null`
  /// para que el caller haga el fallback live a `usuarios/{uidTaxista}`.
  _DatosBancarios? _bancariosDesdeViaje() {
    final String banco = (data['bancoTaxista'] ??
            data['bancoTaxistaSnapshot'] ??
            '')
        .toString()
        .trim();
    final String cuenta = (data['numeroCuentaTaxista'] ??
            data['numeroCuentaTaxistaSnapshot'] ??
            '')
        .toString()
        .trim();
    final String tipoCuenta = (data['tipoCuentaTaxista'] ??
            data['tipoCuentaTaxistaSnapshot'] ??
            '')
        .toString()
        .trim();
    final String titular = (data['titularCuentaTaxista'] ??
            data['titularCuentaTaxistaSnapshot'] ??
            '')
        .toString()
        .trim();

    if (banco.isEmpty && cuenta.isEmpty && titular.isEmpty) {
      return null;
    }
    return _DatosBancarios(
      banco: banco,
      cuenta: cuenta,
      tipoCuenta: tipoCuenta,
      titular: titular,
    );
  }

  String _uidTaxista() {
    final String a = (data['uidTaxista'] ?? '').toString().trim();
    if (a.isNotEmpty) return a;
    final String b = (data['taxistaId'] ?? '').toString().trim();
    return b;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final String origen = (data['origen'] ?? '').toString();
    final String destino = (data['destino'] ?? '').toString();
    final String metodoPago = (data['metodoPago'] ?? 'Efectivo').toString();
    final bool esTransferencia = MetodoPagoViaje.esTransferencia(metodoPago);
    final bool esEfectivo = MetodoPagoViaje.esEfectivo(metodoPago);
    final double total =
        _toDouble(data['precioFinal'] ?? data['precio'] ?? 0);
    final double tarifaBase = _toDouble(data['tarifaBase'] ?? 0);
    final double distanciaKm = _toDouble(data['distanciaKm'] ?? 0);
    final String estadoPago =
        (data['estadoPago'] ?? '').toString().trim().toLowerCase();
    final String paymentStatus =
        (data['payment']?['status'] ?? '').toString().trim().toLowerCase();
    final String comprobanteUrl =
        (data['comprobanteTransferenciaUrl'] ?? '').toString();
    final bool transferenciaConfirmada =
        data['transferenciaConfirmada'] == true;
    final String motivoRechazo =
        (data['motivoRechazoTransferencia'] ?? '').toString().trim();

    final _DatosBancarios? snapBancario = _bancariosDesdeViaje();
    final String uidTaxista = _uidTaxista();

    // Estado lógico del pago para el sello superior.
    final _EstadoPagoUI estadoUI = _calcularEstadoPagoUI(
      esEfectivo: esEfectivo,
      esTransferencia: esTransferencia,
      transferenciaConfirmada: transferenciaConfirmada,
      estadoPago: estadoPago,
      paymentStatus: paymentStatus,
      hayComprobante: comprobanteUrl.isNotEmpty,
    );

    final bool esTaxista = role == 'taxista';
    double comisionCond = 0;
    final ccRaw = data['comision_cents'];
    if (ccRaw is num && ccRaw > 0) {
      comisionCond = ccRaw.toDouble() / 100.0;
    } else {
      comisionCond = _toDouble(data['comision'] ?? data['comisionFlygo'] ?? 0);
    }
    double gananciaCond = 0;
    final gcRaw = data['ganancia_cents'];
    if (gcRaw is num && gcRaw > 0) {
      gananciaCond = gcRaw.toDouble() / 100.0;
    } else {
      gananciaCond = _toDouble(data['gananciaTaxista'] ?? 0);
    }
    final bool mostrarLiquidacionTx =
        esTaxista && (comisionCond > 1e-6 || gananciaCond > 1e-6);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _FacturaViajeDocBanner(cs: cs, tt: Theme.of(context).textTheme),
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
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: estadoUI.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(estadoUI.icon, color: estadoUI.color, size: 36),
              ),
              const SizedBox(height: 12),
              Text(
                'Viaje completado',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                _fechaLegible(),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Text(
                'ID de operación',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              SelectableText(
                viajeId,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: viajeId));
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar ID'),
              ),
              const SizedBox(height: 8),
              _SelloEstado(estado: estadoUI),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionCard(
          title: 'Itinerario',
          children: [
            _Row(
              icon: Icons.my_location_rounded,
              iconColor: cs.primary,
              label: 'Origen',
              value: origen.isEmpty ? '—' : origen,
            ),
            _Row(
              icon: Icons.flag_rounded,
              iconColor: cs.error,
              label: 'Destino',
              value: destino.isEmpty ? '—' : destino,
            ),
            if (distanciaKm > 0)
              _Row(
                icon: Icons.straighten_rounded,
                iconColor: cs.tertiary,
                label: 'Distancia',
                value: FormatosMoneda.km(distanciaKm),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Importe y forma de pago',
          children: [
            if (tarifaBase > 0)
              _Row(
                icon: Icons.confirmation_number_rounded,
                iconColor: cs.outline,
                label: 'Tarifa base',
                value: FormatosMoneda.rd(tarifaBase),
              ),
            _Row(
              icon: Icons.payments_rounded,
              iconColor: cs.primary,
              label: 'Total del servicio (RD\$)',
              value: FormatosMoneda.rd(total),
              valueBold: true,
            ),
            _Row(
              icon: esTransferencia
                  ? Icons.account_balance_rounded
                  : Icons.attach_money_rounded,
              iconColor: cs.secondary,
              label: 'Medio de pago acordado',
              value: MetodoPagoViaje.etiquetaDocumento(metodoPago),
            ),
          ],
        ),
        if (mostrarLiquidacionTx) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Liquidación RAI (conductor)',
            children: [
              _Row(
                icon: Icons.percent_rounded,
                iconColor: cs.tertiary,
                label: 'Comisión plataforma RAI',
                value: FormatosMoneda.rd(comisionCond),
              ),
              _Row(
                icon: Icons.savings_outlined,
                iconColor: Colors.green.shade700,
                label: 'Ingreso neto para el conductor',
                value: FormatosMoneda.rd(gananciaCond),
                valueBold: true,
              ),
              const SizedBox(height: 8),
              Text(
                'Los montos reflejan el cierre registrado en servidor. La comisión de plataforma '
                'se gestiona en tu billetera de conductor (prepago y/o comisión pendiente). '
                'Regularizá en Mis pagos para mantener la cuenta operativa.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ],
        if (esEfectivo) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Instrucción de pago en efectivo',
            children: [
              _InfoBanner(
                icon: Icons.attach_money_rounded,
                color: Colors.green,
                text: role == 'taxista'
                    ? 'Cobrá ${FormatosMoneda.rd(total)} en efectivo al pasajero, conforme al servicio prestado.'
                    : 'Entregá ${FormatosMoneda.rd(total)} en efectivo al conductor al concluir el traslado.',
              ),
            ],
          ),
        ],
        if (esTransferencia) ...[
          const SizedBox(height: 12),
          _SectionTransferencia(
            viajeId: viajeId,
            role: role,
            total: total,
            uidTaxista: uidTaxista,
            snap: snapBancario,
            comprobanteUrl: comprobanteUrl,
            transferenciaConfirmada: transferenciaConfirmada,
            estadoPago: estadoPago,
            paymentStatus: paymentStatus,
            motivoRechazo: motivoRechazo,
          ),
        ],
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Aviso legal breve',
          muted: true,
          children: [
            Text(
              'Documento informativo generado electrónicamente a partir de los datos registrados '
              'en la plataforma RAI. Conservalo como respaldo ante consultas o conciliaciones. '
              'El estado del pago por transferencia puede actualizarse cuando se valide el comprobante.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ],
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

  static _EstadoPagoUI _calcularEstadoPagoUI({
    required bool esEfectivo,
    required bool esTransferencia,
    required bool transferenciaConfirmada,
    required String estadoPago,
    required String paymentStatus,
    required bool hayComprobante,
  }) {
    if (esEfectivo) {
      return const _EstadoPagoUI(
        label: 'PAGO EN EFECTIVO',
        color: Colors.green,
        icon: Icons.attach_money_rounded,
      );
    }
    if (transferenciaConfirmada || estadoPago == 'verificado') {
      return const _EstadoPagoUI(
        label: 'PAGADO',
        color: Colors.green,
        icon: Icons.verified_rounded,
      );
    }
    if (paymentStatus == 'bank_transfer_rejected') {
      return const _EstadoPagoUI(
        label: 'COMPROBANTE RECHAZADO',
        color: Colors.redAccent,
        icon: Icons.error_outline_rounded,
      );
    }
    if (hayComprobante ||
        estadoPago == 'pagado' ||
        paymentStatus == 'pending_admin_confirmation') {
      return const _EstadoPagoUI(
        label: 'COMPROBANTE EN VALIDACIÓN',
        color: Colors.orange,
        icon: Icons.hourglass_top_rounded,
      );
    }
    return const _EstadoPagoUI(
      label: 'PAGO PENDIENTE',
      color: Colors.orange,
      icon: Icons.hourglass_top_rounded,
    );
  }
}

class _FacturaViajeDocBanner extends StatelessWidget {
  const _FacturaViajeDocBanner({required this.cs, required this.tt});

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
                    'Este comprobante refleja el estado del viaje registrado por RAI. '
                    'Solo lectura; el cliente puede adjuntar comprobante de transferencia cuando aplique.',
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

/// Sección "Datos de la transferencia". Hace dos cosas distintas según el
/// dato disponible en el viaje:
///
/// 1) Si el doc del viaje ya trae el snapshot bancario (caso normal post
///    `_finalizarViaje` del taxista) → renderiza directo, sin extra read.
/// 2) Si el snapshot está vacío (viajes antiguos, viajes finalizados antes
///    de esta versión, o fallo de escritura) → hace fallback live a
///    `usuarios/{uidTaxista}` para no dejar al cliente sin info.
class _SectionTransferencia extends StatelessWidget {
  const _SectionTransferencia({
    required this.viajeId,
    required this.role,
    required this.total,
    required this.uidTaxista,
    required this.snap,
    required this.comprobanteUrl,
    required this.transferenciaConfirmada,
    required this.estadoPago,
    required this.paymentStatus,
    required this.motivoRechazo,
  });

  final String viajeId;
  final String role;
  final double total;
  final String uidTaxista;
  final _DatosBancarios? snap;
  final String comprobanteUrl;
  final bool transferenciaConfirmada;
  final String estadoPago;
  final String paymentStatus;
  final String motivoRechazo;

  @override
  Widget build(BuildContext context) {
    if (snap != null) {
      return _renderConDatos(context, snap!);
    }
    if (uidTaxista.isEmpty) {
      return const _SectionCard(
        title: 'Datos para transferencia al conductor',
        children: [
          _InfoBanner(
            icon: Icons.warning_amber_rounded,
            color: Colors.orange,
            text:
                'Este registro no tiene datos bancarios del conductor. Contactá soporte RAI si necesitás completar el pago.',
          ),
        ],
      );
    }
    // Fallback live: lee usuarios/{uidTaxista}.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uidTaxista)
          .snapshots(),
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting && !s.hasData) {
          return const _SectionCard(
            title: 'Datos para transferencia al conductor',
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          );
        }
        final m = s.data?.data() ?? const <String, dynamic>{};
        final live = _DatosBancarios(
          banco: (m['banco'] ?? '').toString().trim(),
          cuenta: (m['numeroCuenta'] ?? '').toString().trim(),
          tipoCuenta: (m['tipoCuenta'] ?? '').toString().trim(),
          titular: (m['titularCuenta'] ?? m['titular'] ?? '').toString().trim(),
        );
        if (live.banco.isEmpty &&
            live.cuenta.isEmpty &&
            live.titular.isEmpty) {
          return const _SectionCard(
            title: 'Datos para transferencia al conductor',
            children: [
              _InfoBanner(
                icon: Icons.warning_amber_rounded,
                color: Colors.orange,
                text:
                    'El conductor no tiene datos bancarios completos en RAI. Coordiná por chat o soporte oficial.',
              ),
            ],
          );
        }
        return _renderConDatos(context, live);
      },
    );
  }

  Widget _renderConDatos(BuildContext context, _DatosBancarios b) {
    final cs = Theme.of(context).colorScheme;
    return _SectionCard(
      title: 'Datos para transferencia al conductor',
      children: [
        Text(
          'Instrucciones de tesorería',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        _InfoBanner(
          icon: Icons.payments_rounded,
          color: cs.primary,
          text: role == 'taxista'
              ? 'El pasajero debe transferirte ${FormatosMoneda.rd(total)} a la cuenta indicada.'
              : 'Transferí ${FormatosMoneda.rd(total)} a la cuenta del conductor:',
        ),
        const SizedBox(height: 6),
        if (b.banco.isNotEmpty)
          _Row(
            icon: Icons.account_balance_outlined,
            iconColor: cs.primary,
            label: 'Banco',
            value: b.banco,
          ),
        if (b.cuenta.isNotEmpty)
          _Row(
            icon: Icons.numbers_rounded,
            iconColor: cs.primary,
            label: 'Cuenta',
            value: b.cuenta,
          ),
        if (b.tipoCuenta.isNotEmpty)
          _Row(
            icon: Icons.category_rounded,
            iconColor: cs.primary,
            label: 'Tipo de cuenta',
            value: b.tipoCuenta,
          ),
        if (b.titular.isNotEmpty)
          _Row(
            icon: Icons.person_rounded,
            iconColor: cs.primary,
            label: 'Titular',
            value: b.titular,
          ),
        _Row(
          icon: transferenciaConfirmada
              ? Icons.verified_rounded
              : Icons.hourglass_top_rounded,
          iconColor: transferenciaConfirmada ? Colors.green : Colors.orange,
          label: 'Estado de la transferencia',
          value: transferenciaConfirmada
              ? 'Confirmada'
              : (estadoPago.isEmpty ? 'Pendiente' : estadoPago),
        ),
        if (motivoRechazo.isNotEmpty && !transferenciaConfirmada) ...[
          const SizedBox(height: 6),
          _InfoBanner(
            icon: Icons.error_outline_rounded,
            color: Colors.redAccent,
            text: 'Motivo de rechazo: $motivoRechazo',
          ),
        ],
        if (comprobanteUrl.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Comprobante',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              comprobanteUrl,
              fit: BoxFit.cover,
              height: 220,
              errorBuilder: (_, __, ___) => Container(
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'No se pudo cargar el comprobante.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ],
        // Botón "Subir comprobante" solo para cliente, si es transferencia y
        // (a) aún no se ha enviado, o (b) fue rechazado por admin.
        if (_clienteDebePoderSubirComprobante()) ...[
          const SizedBox(height: 14),
          _BotonSubirComprobante(viajeId: viajeId),
        ],
      ],
    );
  }

  bool _clienteDebePoderSubirComprobante() {
    if (role != 'cliente') return false;
    if (transferenciaConfirmada) return false;
    if (paymentStatus == 'bank_transfer_rejected') return true;
    if (comprobanteUrl.isEmpty) return true;
    return false;
  }
}

/// Botón con estado local "subiendo..." que invoca al servicio reusable.
/// No vuelve a leer el doc del viaje al terminar: el `StreamBuilder` raíz
/// de `FacturaViaje` recibe el cambio (comprobante + estadoPago) y rebuildea.
class _BotonSubirComprobante extends StatefulWidget {
  const _BotonSubirComprobante({required this.viajeId});
  final String viajeId;

  @override
  State<_BotonSubirComprobante> createState() => _BotonSubirComprobanteState();
}

class _BotonSubirComprobanteState extends State<_BotonSubirComprobante> {
  bool _subiendo = false;

  Future<void> _subir() async {
    if (_subiendo) return;
    setState(() => _subiendo = true);
    final r = await ComprobanteTransferenciaService.subirYReportar(
      viajeId: widget.viajeId,
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
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.upload_file_rounded),
        label: Text(_subiendo
            ? 'Subiendo comprobante…'
            : 'Subir comprobante de pago'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

class _DatosBancarios {
  const _DatosBancarios({
    required this.banco,
    required this.cuenta,
    required this.tipoCuenta,
    required this.titular,
  });
  final String banco;
  final String cuenta;
  final String tipoCuenta;
  final String titular;
}

class _EstadoPagoUI {
  const _EstadoPagoUI({
    required this.label,
    required this.color,
    required this.icon,
  });
  final String label;
  final Color color;
  final IconData icon;
}

class _SelloEstado extends StatelessWidget {
  const _SelloEstado({required this.estado});
  final _EstadoPagoUI estado;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: estado.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: estado.color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(estado.icon, size: 16, color: estado.color),
          const SizedBox(width: 6),
          Text(
            estado.label,
            style: TextStyle(
              color: estado.color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.text,
  });
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    this.muted = false,
  });

  final String title;
  final List<Widget> children;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color bg = muted
        ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
        : cs.surfaceContainerLowest;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: muted
              ? cs.outline.withValues(alpha: 0.35)
              : cs.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
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
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueBold = false,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool valueBold;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: valueBold ? 18 : 14,
                    fontWeight:
                        valueBold ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
