import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/servicios/comprobante_transferencia_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/utils/precio_viaje_doc.dart';
import 'package:flygo_nuevo/utils/transferencia_recaudo_ui.dart';
import 'package:flygo_nuevo/widgets/rai_driver_ui.dart';
import 'package:flygo_nuevo/widgets/rai_pago_tarjeta_panel.dart';

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
    this.autoCerrarAlContinuar = false,
  });

  final String viajeId;
  final String role;

  /// Tras finalizar viaje: cierra sola cuando el pago quedó resuelto (o el
  /// conductor ya vio el comprobante) y deja seguir post-viaje / cola.
  final bool autoCerrarAlContinuar;

  /// Helper para abrir la factura desde cualquier parte de la app.
  /// Usa `rootNavigator` para que el modal viva por encima de los Navigators
  /// anidados de los Shells (ClienteShell, TaxistaShell).
  static Future<void> mostrar(
    BuildContext context, {
    required String viajeId,
    String role = 'cliente',
    bool autoCerrarAlContinuar = false,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => FacturaViaje(
          viajeId: viajeId,
          role: role,
          autoCerrarAlContinuar: autoCerrarAlContinuar,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? RaiDriverColors.bg : cs.surface;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: isDark ? RaiDriverColors.surface : cs.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RaiDriverBrandMark(compact: true),
            const SizedBox(height: 4),
            Text(
              'Comprobante de viaje',
              style: TextStyle(
                color: isDark ? RaiDriverColors.textMuted : cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cerrar',
          onPressed: () {
            final NavigatorState rootNav =
                Navigator.of(context, rootNavigator: true);
            if (rootNav.canPop()) {
              rootNav.pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
              autoCerrarAlContinuar: autoCerrarAlContinuar,
            );
          },
        ),
      ),
    );
  }
}

/// Post-viaje: cuándo puede cerrarse la factura y seguir (recibo/cola/inicio).
bool facturaViajeListaParaContinuarFlujo({
  required Map<String, dynamic> data,
  required String role,
}) {
  if (!viajeDocCompletado(data)) return false;

  final String metodo =
      (data['metodoPago'] ?? 'Efectivo').toString().trim();

  if (role == 'taxista') return true;

  if (MetodoPagoViaje.esEfectivo(metodo)) return true;

  if (MetodoPagoViaje.esTarjeta(metodo)) {
    final String ep =
        (data['estadoPago'] ?? '').toString().trim().toLowerCase();
    final dynamic pay = data['payment'];
    final String ps = pay is Map
        ? (pay['status'] ?? '').toString().trim().toLowerCase()
        : '';
    return ep == 'verificado' || ps == 'captured';
  }

  if (MetodoPagoViaje.esTransferencia(metodo)) {
    if (data['transferenciaConfirmada'] == true) return true;
    final String ep =
        (data['estadoPago'] ?? '').toString().trim().toLowerCase();
    if (ep == 'verificado') return true;
    final String url =
        (data['comprobanteTransferenciaUrl'] ?? '').toString().trim();
    if (url.isNotEmpty) return true;
    return false;
  }

  return true;
}

class _FacturaContent extends StatefulWidget {
  const _FacturaContent({
    required this.viajeId,
    required this.data,
    required this.role,
    this.autoCerrarAlContinuar = false,
  });

  final String viajeId;
  final Map<String, dynamic> data;
  final String role;
  final bool autoCerrarAlContinuar;

  @override
  State<_FacturaContent> createState() => _FacturaContentState();
}

class _FacturaContentState extends State<_FacturaContent> {
  bool _autoCierreProgramado = false;
  bool _listaParaContinuarPrev = false;
  bool _facturaCerrada = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisarAutoCierre());
  }

  @override
  void didUpdateWidget(covariant _FacturaContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.autoCerrarAlContinuar != widget.autoCerrarAlContinuar) {
      _revisarAutoCierre();
    }
  }

  void _cerrarFactura({String? snack}) {
    if (_facturaCerrada || !mounted) return;
    if (snack != null && snack.isNotEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(snack), duration: const Duration(seconds: 2)),
      );
    }
    _facturaCerrada = true;
    final NavigatorState rootNav = Navigator.of(context, rootNavigator: true);
    if (rootNav.canPop()) {
      rootNav.pop();
      return;
    }
    final NavigatorState? localNav = Navigator.maybeOf(context);
    if (localNav != null && localNav.canPop()) {
      localNav.pop();
      return;
    }
    _facturaCerrada = false;
  }

  void _revisarAutoCierre() {
    if (!widget.autoCerrarAlContinuar ||
        _autoCierreProgramado ||
        _facturaCerrada) {
      return;
    }

    final bool lista = facturaViajeListaParaContinuarFlujo(
      data: widget.data,
      role: widget.role,
    );
    if (!lista) {
      _listaParaContinuarPrev = false;
      return;
    }

    final bool transicion = !_listaParaContinuarPrev;
    _listaParaContinuarPrev = true;
    _autoCierreProgramado = true;

    final Duration delay = transicion &&
            !MetodoPagoViaje.esEfectivo(
                (widget.data['metodoPago'] ?? 'Efectivo').toString()) &&
            widget.role == 'cliente'
        ? const Duration(milliseconds: 900)
        : const Duration(milliseconds: 2200);

    Future<void>.delayed(delay, () {
      if (!mounted || _facturaCerrada) return;
      final String msg = widget.role == 'taxista'
          ? 'Comprobante listo. Volviendo al trabajo…'
          : MetodoPagoViaje.esTransferencia(
                  (widget.data['metodoPago'] ?? '').toString()) &&
              widget.data['transferenciaConfirmada'] != true
          ? 'Comprobante recibido. Puedes seguir; RAI validará el pago.'
          : 'Pago listo. Continuando…';
      _cerrarFactura(snack: msg);
    });
  }

  Map<String, dynamic> get data => widget.data;
  String get viajeId => widget.viajeId;
  String get role => widget.role;

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
    final String ci = (data['ciTaxista'] ?? data['cedulaTaxista'] ?? '')
        .toString()
        .trim();

    if (banco.isEmpty &&
        cuenta.isEmpty &&
        titular.isEmpty &&
        tipoCuenta.isEmpty &&
        ci.isEmpty) {
      return null;
    }
    return _DatosBancarios(
      banco: banco,
      cuenta: cuenta,
      tipoCuenta: tipoCuenta,
      titular: titular,
      ci: ci,
    );
  }

  String _lineaSaldoPrepagoFactura() {
    final String metodo = (data['metodoPago'] ?? 'Efectivo').toString();
    final bool aplicaPrepago = MetodoPagoViaje.esEfectivo(metodo) ||
        MetodoPagoViaje.esTransferencia(metodo) ||
        MetodoPagoViaje.esTarjeta(metodo);
    if (!aplicaPrepago) {
      return 'Saldo restante en tu billetera de recargas (comisión): No aplica';
    }
    final v = data['facturaSaldoPrepagoComisionRd'];
    if (v == null) {
      return 'Saldo restante en tu billetera de recargas (comisión): no registrado en este comprobante';
    }
    if (v is num) {
      return 'Saldo restante en tu billetera de recargas (comisión): ${FormatosMoneda.rd(v.toDouble())}';
    }
    final parsed = double.tryParse(v.toString());
    if (parsed != null) {
      return 'Saldo restante en tu billetera de recargas (comisión): ${FormatosMoneda.rd(parsed)}';
    }
    return 'Saldo restante en tu billetera de recargas (comisión): —';
  }

  String _uidTaxista() {
    final String a = (data['uidTaxista'] ?? '').toString().trim();
    if (a.isNotEmpty) return a;
    final String b = (data['taxistaId'] ?? '').toString().trim();
    return b;
  }

  List<Map<String, dynamic>> _waypointsDesdeData() {
    final dynamic raw = data['waypoints'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final dynamic w in raw) {
      if (w is! Map) continue;
      final String label = (w['label'] ?? '').toString().trim();
      if (label.isEmpty) continue;
      out.add(Map<String, dynamic>.from(w));
    }
    return out;
  }

  double _peajeDesdeData() {
    final dynamic extras = data['extras'];
    if (extras is Map) {
      final dynamic p = extras['peaje_total'] ?? extras['peaje'];
      if (p is num) return p.toDouble();
    }
    return _toDouble(data['peaje'] ?? data['peaje_total'] ?? 0);
  }

  bool get _esViajeMulti =>
      (data['categoria'] ?? '').toString().trim().toLowerCase() == 'multi';

  ({double comision, double ganancia}) _liquidacionTaxistaDesdeDoc(
      double total) {
    double comision = 0;
    final ccRaw = data['comision_cents'];
    if (ccRaw is num && ccRaw > 0) {
      comision = ccRaw.toDouble() / 100.0;
    } else {
      comision = _toDouble(data['comision'] ?? data['comisionFlygo'] ?? 0);
    }
    double ganancia = 0;
    final gcRaw = data['ganancia_cents'];
    if (gcRaw is num && gcRaw > 0) {
      ganancia = gcRaw.toDouble() / 100.0;
    } else {
      ganancia = _toDouble(data['gananciaTaxista'] ?? 0);
    }
    if (comision <= 1e-6 && total > 1e-6) {
      comision = PlataformaEconomia.comisionRdDesdeTotal(total);
    }
    if (ganancia <= 1e-6 && total > 1e-6) {
      ganancia = PlataformaEconomia.gananciaTaxistaRdDesdeTotal(total);
    }
    return (comision: comision, ganancia: ganancia);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final String origen = (data['origen'] ?? '').toString();
    final String destino = (data['destino'] ?? '').toString();
    final String metodoPago = (data['metodoPago'] ?? 'Efectivo').toString();
    final bool esTransferencia = MetodoPagoViaje.esTransferencia(metodoPago);
    final bool esEfectivo = MetodoPagoViaje.esEfectivo(metodoPago);
    final bool esTarjeta = MetodoPagoViaje.esTarjeta(metodoPago);
    final bool usaRecaudoRai = TransferenciaRecaudoUi.viajeUsaRecaudoEnCuentaRai(data);
    final double total = totalRdDesdeDocViaje(data);
    final bool montoPendienteServidor =
        viajeDocCompletado(data) && total <= 1e-6;
    final String etiquetaServicio = etiquetaTipoServicioFactura(data);
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
      esTarjeta: esTarjeta,
      transferenciaConfirmada: transferenciaConfirmada,
      estadoPago: estadoPago,
      paymentStatus: paymentStatus,
      hayComprobante: comprobanteUrl.isNotEmpty,
    );

    final bool esTaxista = role == 'taxista';
    final bool esCorporativo =
        CorporativoTaxistaService.esViajeCorporativoDoc(data);
    final ({double comision, double ganancia}) liq =
        _liquidacionTaxistaDesdeDoc(total);
    final double comisionCond = liq.comision;
    final double gananciaCond = liq.ganancia;
    final double peaje = _peajeDesdeData();
    final List<Map<String, dynamic>> waypoints = _waypointsDesdeData();
    final List<Map<String, dynamic>> visitadas = data['multiparadaParadasVisitadas']
            is List
        ? List<Map<String, dynamic>>.from(
            (data['multiparadaParadasVisitadas'] as List).map(
              (dynamic e) =>
                  e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{},
            ),
          )
        : <Map<String, dynamic>>[];
    bool _legVisitado(int legIndex) {
      for (final Map<String, dynamic> v in visitadas) {
        if (v['legIndex'] is num && (v['legIndex'] as num).toInt() == legIndex) {
          return true;
        }
      }
      return false;
    }

    final bool viajeCompletado = viajeDocCompletado(data);
    final bool mostrarLiquidacionTx = esTaxista &&
        viajeCompletado &&
        total > 1e-6 &&
        (comisionCond > 1e-6 || gananciaCond > 1e-6);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color neon = isDark ? RaiDriverColors.neon : cs.primary;

    // Espacio bajo el botón final: la barra de navegación/gestos del sistema
    // tapaba "Entendido, cerrar comprobante" con el padding fijo de 28.
    final MediaQueryData mq = MediaQuery.of(context);
    final double sysBottom = mq.viewPadding.bottom > mq.padding.bottom
        ? mq.viewPadding.bottom
        : mq.padding.bottom;
    final double bottomScrollPad = sysBottom + 16;
    final String etiquetaBotonCierre = widget.autoCerrarAlContinuar
        ? 'Continuar'
        : 'Entendido, cerrar comprobante';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomScrollPad),
      children: [
        _FacturaViajeDocBanner(cs: cs, tt: Theme.of(context).textTheme),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 22),
          decoration: BoxDecoration(
            color: isDark ? RaiDriverColors.cardElevated : cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: neon.withValues(alpha: isDark ? 0.45 : 0.35),
            ),
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: neon.withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: neon.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: neon.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_outlined, size: 18, color: neon),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'SERVICIO FINALIZADO',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: neon,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
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
              if (!montoPendienteServidor && total > 1e-6) ...[
                const SizedBox(height: 20),
                Text(
                  FormatosMoneda.rd(total),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: neon,
                        letterSpacing: -0.5,
                        height: 1.05,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Total del servicio',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionCard(
          title: _esViajeMulti ? 'Itinerario (múltiples paradas)' : 'Itinerario',
          children: [
            _Row(
              icon: Icons.my_location_rounded,
              iconColor: cs.primary,
              label: 'Origen',
              value: origen.isEmpty ? '—' : origen,
            ),
            ...waypoints.asMap().entries.map(
              (MapEntry<int, Map<String, dynamic>> e) {
                final String label =
                    (e.value['label'] ?? 'Parada ${e.key + 1}').toString();
                final bool ok = _legVisitado(e.key);
                return _Row(
                  icon: ok ? Icons.check_circle_rounded : Icons.place_outlined,
                  iconColor: ok ? Colors.green.shade700 : cs.secondary,
                  label: 'Parada ${e.key + 1}${ok ? ' ✓' : ''}',
                  value: label,
                );
              },
            ),
            _Row(
              icon: _legVisitado(waypoints.length)
                  ? Icons.check_circle_rounded
                  : Icons.flag_rounded,
              iconColor: _legVisitado(waypoints.length)
                  ? Colors.green.shade700
                  : cs.error,
              label: 'Destino final${_legVisitado(waypoints.length) ? ' ✓' : ''}',
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
        if (montoPendienteServidor) ...[
          const SizedBox(height: 12),
          const _SectionCard(
            title: 'Confirmando monto',
            children: [
              _InfoBanner(
                icon: Icons.hourglass_top_rounded,
                color: Colors.orange,
                text:
                    'El servidor está registrando el monto final del viaje. '
                    'Este comprobante se actualizará solo en unos segundos; '
                    'no cierres la app.',
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Importe y forma de pago',
          children: [
            if (etiquetaServicio.isNotEmpty)
              _Row(
                icon: Icons.local_taxi_rounded,
                iconColor: cs.tertiary,
                label: 'Tipo de servicio',
                value: etiquetaServicio,
              ),
            if (tarifaBase > 0)
              _Row(
                icon: Icons.confirmation_number_rounded,
                iconColor: cs.outline,
                label: 'Tarifa base',
                value: FormatosMoneda.rd(tarifaBase),
              ),
            if (peaje > 0)
              _Row(
                icon: Icons.toll_rounded,
                iconColor: cs.outline,
                label: 'Peaje incluido',
                value: FormatosMoneda.rd(peaje),
              ),
            _Row(
              icon: Icons.payments_rounded,
              iconColor: cs.primary,
              label: esCorporativo && esTaxista
                  ? 'Tu neto acumulado (RD\$)'
                  : 'Total del servicio (RD\$)',
              value: montoPendienteServidor
                  ? 'Confirmando…'
                  : FormatosMoneda.rd(
                      esCorporativo && esTaxista ? gananciaCond : total,
                    ),
              valueBold: true,
            ),
            if (esCorporativo && esTaxista && total > 1e-6)
              _Row(
                icon: Icons.receipt_long_outlined,
                iconColor: cs.outline,
                label: 'Tarifa ruta (empresa)',
                value: FormatosMoneda.rd(total),
              ),
            _Row(
              icon: esCorporativo
                  ? Icons.business_center_outlined
                  : (esTransferencia
                      ? Icons.account_balance_rounded
                      : Icons.attach_money_rounded),
              iconColor: cs.secondary,
              label: 'Medio de pago acordado',
              value: esCorporativo
                  ? 'Corporativo (empresa)'
                  : MetodoPagoViaje.etiquetaDocumento(metodoPago),
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
                esCorporativo
                    ? 'Ruta corporativa B2B: este neto se acumula en Ganancias → Corporativo. '
                        'RAI cobra a la empresa y te transfiere al liquidar el período.'
                    : esEfectivo
                    ? 'Los montos reflejan el cierre en servidor. En efectivo, la comisión RAI '
                        'impacta tu prepago y/o comisión pendiente; regularizá en Mis pagos.'
                    : 'Los montos reflejan el cierre en servidor. En transferencia, cobrás el '
                        'neto al pasajero y la comisión RAI se descuenta de tu prepago (recarga); '
                        'si no alcanzó, queda como comisión pendiente. Regularizá en Mis pagos.',
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
        if (esTransferencia && !esCorporativo) ...[
          const SizedBox(height: 12),
          if (usaRecaudoRai)
            _FacturaSectionRecaudoRai(
              viajeId: viajeId,
              role: role,
              data: data,
              total: total,
              transferenciaConfirmada: transferenciaConfirmada,
              estadoPago: estadoPago,
              comprobanteUrl: comprobanteUrl,
              uidTaxista: uidTaxista,
            )
          else
            _SectionTransferencia(
              viajeId: viajeId,
              role: role,
              total: total,
              montoPendienteServidor: montoPendienteServidor,
              uidTaxista: uidTaxista,
              snap: snapBancario,
              comprobanteUrl: comprobanteUrl,
              transferenciaConfirmada: transferenciaConfirmada,
              estadoPago: estadoPago,
              paymentStatus: paymentStatus,
              motivoRechazo: motivoRechazo,
            ),
        ],
        if (esTarjeta) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Pago con tarjeta',
            children: [
              RaiPagoTarjetaPanel(
                viajeId: viajeId,
                viajeData: data,
                montoRd: total,
                role: role,
              ),
            ],
          ),
        ],
        if (esTaxista) ...[
          const SizedBox(height: 12),
          _FacturaPanelComisionRecargaBloqueo(
            uidTaxista: uidTaxista,
            esEfectivo: esEfectivo,
            esTransferencia: esTransferencia,
            esCorporativo: esCorporativo,
            comisionViaje: comisionCond,
            gananciaViaje: gananciaCond,
            lineaSaldoPrepagoFactura: _lineaSaldoPrepagoFactura(),
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
      ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: FilledButton.icon(
              onPressed: _facturaCerrada ? null : () => _cerrarFactura(),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: Text(etiquetaBotonCierre),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: isDark ? RaiDriverColors.neon : cs.primary,
                foregroundColor: isDark ? Colors.black : cs.onPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static _EstadoPagoUI _calcularEstadoPagoUI({
    required bool esEfectivo,
    required bool esTransferencia,
    required bool esTarjeta,
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
    if (esTarjeta) {
      if (estadoPago == 'verificado' || paymentStatus == 'captured') {
        return const _EstadoPagoUI(
          label: 'TARJETA PAGADA',
          color: Colors.green,
          icon: Icons.verified_rounded,
        );
      }
      if (paymentStatus == 'pending') {
        return const _EstadoPagoUI(
          label: 'TARJETA PENDIENTE',
          color: Colors.orange,
          icon: Icons.credit_card,
        );
      }
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

/// Comisión del viaje, saldo prepago, deuda legacy (admin) y bloqueo operativo:
/// misma información que «Mis pagos», alineada al cierre (viaje estándar y multiparadas).
String _saldoPrepagoTrasCierreTexto(String lineaFactura, double saldoLive) {
  const String prefijo =
      'Saldo restante en tu billetera de recargas (comisión): ';
  if (lineaFactura.contains('No aplica')) return 'No aplica';
  if (lineaFactura.startsWith(prefijo)) {
    final String tail = lineaFactura.substring(prefijo.length).trim();
    if (tail.isNotEmpty && tail != '—' && !tail.contains('no registrado')) {
      return tail;
    }
  }
  if (saldoLive > 1e-6) return FormatosMoneda.rd(saldoLive);
  return lineaFactura.replaceFirst(prefijo, '').trim().isEmpty
      ? '—'
      : lineaFactura.replaceFirst(prefijo, '').trim();
}

class _FacturaPanelComisionRecargaBloqueo extends StatelessWidget {
  const _FacturaPanelComisionRecargaBloqueo({
    required this.uidTaxista,
    required this.esEfectivo,
    required this.esTransferencia,
    required this.esCorporativo,
    required this.comisionViaje,
    required this.gananciaViaje,
    required this.lineaSaldoPrepagoFactura,
  });

  final String uidTaxista;
  final bool esEfectivo;
  final bool esTransferencia;
  final bool esCorporativo;
  final double comisionViaje;
  final double gananciaViaje;
  final String lineaSaldoPrepagoFactura;

  Widget _cardSinStreams(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return _SectionCard(
      title: 'Comisión, recarga y bloqueo',
      muted: true,
      children: [
        if (comisionViaje > 1e-6)
          _Row(
            icon: Icons.percent_rounded,
            iconColor: cs.tertiary,
            label: 'Comisión RAI (este viaje)',
            value: FormatosMoneda.rd(comisionViaje),
          ),
        if (gananciaViaje > 1e-6)
          _Row(
            icon: Icons.savings_outlined,
            iconColor: Colors.green.shade700,
            label: 'Ingreso neto (este viaje)',
            value: FormatosMoneda.rd(gananciaViaje),
            valueBold: true,
          ),
        Text(
          lineaSaldoPrepagoFactura,
          style: tt.bodyMedium?.copyWith(height: 1.45),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (uidTaxista.isEmpty) {
      return _cardSinStreams(context);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('billeteras_taxista')
          .doc(uidTaxista)
          .snapshots(),
      builder: (context, billSnap) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('usuarios')
              .doc(uidTaxista)
              .snapshots(),
          builder: (context, userSnap) {
            final Map<String, dynamic>? bill = billSnap.data?.data();
            final Map<String, dynamic>? uData = userSnap.data?.data();

            final double pend =
                PagosTaxistaRepo.comisionPendienteDesdeBilletera(bill);
            final double saldoPrepago =
                PagosTaxistaRepo.saldoPrepagoComisionDesdeBilletera(bill);
            final double disponible =
                PagosTaxistaRepo.saldoDisponiblePrepagoComisionDesdeBilletera(
                    bill);
            final bool bloqueoPrepago =
                PagosTaxistaRepo.bloqueoOperativoPorComisionEfectivo(bill);
            final bool bloqueoPool =
                PagosTaxistaRepo.bloqueoPorDeudaPoolAdminDesdeUsuario(uData) ||
                    uData?['tienePagoPendiente'] == true;
            final bool legacyTope =
                PagosTaxistaRepo.bloqueoPorComisionLegacyTope(bill);
            final double minSaldo = PagosTaxistaRepo.minSaldoPrepagoComisionRd;
            final bool riesgoPrepago = !bloqueoPrepago &&
                !bloqueoPool &&
                pend <= 1e-6 &&
                PagosTaxistaRepo.primerViajeComisionGratisConsumido(bill) &&
                disponible > 1e-6 &&
                disponible < minSaldo;

            final bool cuentaBloqueada =
                bloqueoPrepago || bloqueoPool || legacyTope;

            final Color estadoColor = cuentaBloqueada
                ? Colors.red.shade700
                : (riesgoPrepago ? Colors.orange : Colors.green.shade700);

            final String estadoTxt = cuentaBloqueada
                ? PagosTaxistaRepo.mensajeCuentaBloqueadaOperativo(
                    deudaSemanalVencida: false,
                    billeData: bill,
                    usuarioData: uData,
                  )
                : (riesgoPrepago
                    ? 'ALERTA: prepago bajo para viajes en efectivo. Recargá en Mis pagos antes de quedar bloqueado.'
                    : 'ACTIVO: podés operar (efectivo y transferencia) según las reglas de RAI.');

            final String pie = esCorporativo
                ? 'Ruta corporativa B2B: tu neto de este viaje se acumula en '
                    'Ganancias → Corporativo. RAI cobra a la empresa y te transfiere '
                    'según el ciclo acordado — no pidas pago al pasajero.'
                : esTransferencia
                ? 'Este viaje se cobró por transferencia al pasajero (arriba: datos bancarios y comprobante). '
                    'Al cerrar, la comisión RAI se descontó de tu prepago (arriba «Saldo prepago tras este cierre»). '
                    'Para recargar: Mis pagos → cuenta RAI → monto → foto del bauche → revisión del administrador.'
                : 'Este viaje fue en efectivo: al cerrar, el servidor actualizó tu prepago (arriba «Saldo prepago tras este cierre»). '
                    'Para recargar: Mis pagos → cuenta RAI → monto → foto del bauche → revisión del administrador.';

            return _SectionCard(
              title: 'Comisión, recarga y bloqueo',
              children: [
                _Row(
                  icon: esCorporativo
                      ? Icons.business_center_outlined
                      : (esTransferencia
                          ? Icons.account_balance_rounded
                          : Icons.attach_money_rounded),
                  iconColor: cs.primary,
                  label: 'Forma de pago de este viaje',
                  value: esCorporativo
                      ? 'Corporativo (empresa)'
                      : (esTransferencia ? 'Transferencia' : 'Efectivo'),
                ),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: estadoColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: estadoColor.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        cuentaBloqueada
                            ? Icons.lock_rounded
                            : (riesgoPrepago
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline_rounded),
                        size: 20,
                        color: estadoColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          estadoTxt,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (esEfectivo || esTransferencia)
                  _Row(
                    icon: Icons.account_balance_wallet_outlined,
                    iconColor: cs.primary,
                    label: 'Saldo prepago tras este cierre',
                    value: _saldoPrepagoTrasCierreTexto(
                      lineaSaldoPrepagoFactura,
                      saldoPrepago,
                    ),
                  ),
                _Row(
                  icon: Icons.savings_outlined,
                  iconColor: cs.secondary,
                  label: 'Prepago disponible (ahora)',
                  value: FormatosMoneda.rd(disponible),
                ),
                if (pend > 1e-6)
                  _Row(
                    icon: Icons.history_rounded,
                    iconColor: Colors.orange.shade800,
                    label: 'Comisión pendiente (legacy / admin)',
                    value: FormatosMoneda.rd(pend),
                  ),
                const SizedBox(height: 8),
                Text(
                  pie,
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _FacturaViajeDocBanner extends StatelessWidget {
  const _FacturaViajeDocBanner({required this.cs, required this.tt});

  final ColorScheme cs;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark
          ? RaiDriverColors.card
          : cs.surfaceContainerHighest.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.gavel_outlined,
              color: isDark ? RaiDriverColors.neon : cs.primary,
              size: 26,
            ),
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

/// Transferencia a cuenta RAI (referencia + QR cableado).
class _FacturaSectionRecaudoRai extends StatelessWidget {
  const _FacturaSectionRecaudoRai({
    required this.viajeId,
    required this.role,
    required this.data,
    required this.total,
    required this.transferenciaConfirmada,
    required this.estadoPago,
    required this.comprobanteUrl,
    required this.uidTaxista,
  });

  final String viajeId;
  final String role;
  final Map<String, dynamic> data;
  final double total;
  final bool transferenciaConfirmada;
  final String estadoPago;
  final String comprobanteUrl;
  final String uidTaxista;

  @override
  Widget build(BuildContext context) {
    final bool pagado =
        transferenciaConfirmada || estadoPago == 'verificado';
    return _SectionCard(
      title: 'Pago a cuenta RAI (transferencia)',
      children: [
        TransferenciaRecaudoUi.panel(
          viajeData: data,
          uidTaxista: uidTaxista,
          montoRd: total,
          tituloRai: 'PAGAR A RAI — COMPROBANTE DE VIAJE',
        ),
        if (!pagado && role == 'cliente' && comprobanteUrl.isEmpty) ...[
          const SizedBox(height: 12),
          _BotonSubirComprobante(viajeId: viajeId),
        ],
        if (pagado) ...[
          const SizedBox(height: 8),
          const _InfoBanner(
            icon: Icons.verified_rounded,
            color: Colors.green,
            text: 'Transferencia verificada por RAI.',
          ),
        ],
      ],
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
    required this.montoPendienteServidor,
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
  final bool montoPendienteServidor;
  final String uidTaxista;
  final _DatosBancarios? snap;
  final String comprobanteUrl;
  final bool transferenciaConfirmada;
  final String estadoPago;
  final String paymentStatus;
  final String motivoRechazo;

  @override
  Widget build(BuildContext context) {
    if (snap != null &&
        snap!.banco.isNotEmpty &&
        snap!.cuenta.isNotEmpty &&
        snap!.titular.isNotEmpty) {
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
          ci: (m['ciTaxista'] ?? m['cedula'] ?? m['cedulaTaxista'] ?? '')
              .toString()
              .trim(),
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
          text: montoPendienteServidor
              ? (role == 'taxista'
                  ? 'El monto exacto se confirmará en unos segundos. '
                      'El pasajero debe transferirte a la cuenta indicada.'
                  : 'El monto exacto se confirmará en unos segundos. '
                      'Transferí a la cuenta del conductor cuando aparezca arriba:')
              : (role == 'taxista'
                  ? 'El pasajero debe transferirte ${FormatosMoneda.rd(total)} a la cuenta indicada.'
                  : 'Transferí ${FormatosMoneda.rd(total)} a la cuenta del conductor:'),
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
            trailing: role == 'cliente' && b.cuenta.trim().isNotEmpty
                ? IconButton(
                    tooltip: 'Copiar número de cuenta',
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: b.cuenta.trim()),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Número de cuenta copiado'),
                        ),
                      );
                    },
                  )
                : null,
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
        if (b.ci.isNotEmpty)
          _Row(
            icon: Icons.badge_outlined,
            iconColor: cs.primary,
            label: 'C.I.',
            value: b.ci,
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
    this.ci = '',
  });
  final String banco;
  final String cuenta;
  final String tipoCuenta;
  final String titular;
  final String ci;
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
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - 56,
      ),
      child: Container(
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
            Flexible(
              child: Text(
                estado.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: estado.color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = muted
        ? (isDark
            ? RaiDriverColors.card.withValues(alpha: 0.6)
            : cs.surfaceContainerHighest.withValues(alpha: 0.4))
        : (isDark ? RaiDriverColors.card : cs.surfaceContainerLowest);
    final Color borderColor = isDark
        ? RaiDriverColors.border
        : (muted
            ? cs.outline.withValues(alpha: 0.35)
            : cs.outlineVariant.withValues(alpha: 0.55));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
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
    this.trailing,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool valueBold;
  final Widget? trailing;

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
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
