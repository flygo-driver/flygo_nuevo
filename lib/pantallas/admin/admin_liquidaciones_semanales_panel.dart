import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/modelo/liquidacion_semanal.dart';
import 'package:flygo_nuevo/modelo/resumen_por_liquidar_taxista.dart';
import 'package:flygo_nuevo/pantallas/admin/admin_ui_theme.dart';
import 'package:flygo_nuevo/servicios/liquidacion_semanal_repo.dart';
import 'package:flygo_nuevo/utils/liquidacion_semanal_ach_export.dart';
import 'package:flygo_nuevo/widgets/admin_finanzas_reglas_banner.dart';

typedef AdminLiquidacionAccion = Future<void> Function(
  Future<void> Function() job,
);

/// Panel ADM: liquidaciones semanales PR2 con auditoría, cuenta banco y export ACH.
class AdminLiquidacionesSemanalesPanel extends StatefulWidget {
  const AdminLiquidacionesSemanalesPanel({
    super.key,
    required this.formatter,
    required this.dateFormat,
    required this.accionEnCurso,
    required this.onEjecutarAccion,
    required this.onAprobar,
    required this.onCancelar,
    this.buscar = '',
    this.rangoDias = 0,
  });

  final NumberFormat formatter;
  final DateFormat dateFormat;
  final bool accionEnCurso;
  final AdminLiquidacionAccion onEjecutarAccion;
  final Future<void> Function(LiquidacionSemanal liq) onAprobar;
  final Future<void> Function(LiquidacionSemanal liq) onCancelar;
  final String buscar;
  final int rangoDias;

  @override
  State<AdminLiquidacionesSemanalesPanel> createState() =>
      _AdminLiquidacionesSemanalesPanelState();
}

class _AdminLiquidacionesSemanalesPanelState
    extends State<AdminLiquidacionesSemanalesPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _subTab;

  @override
  void initState() {
    super.initState();
    _subTab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _subTab.dispose();
    super.dispose();
  }

  bool _pasaFiltros(LiquidacionSemanal liq) {
    final q = widget.buscar.trim().toLowerCase();
    if (q.isNotEmpty) {
      final match = liq.nombreTaxista.toLowerCase().contains(q) ||
          liq.uidTaxista.toLowerCase().contains(q) ||
          liq.periodo.toLowerCase().contains(q);
      if (!match) return false;
    }
    if (widget.rangoDias > 0) {
      final limite = DateTime.now().subtract(Duration(days: widget.rangoDias));
      if (liq.periodoFin.isBefore(limite)) return false;
    }
    return true;
  }

  List<LiquidacionSemanal> _filtrar(List<LiquidacionSemanal> list) {
    return list.where(_pasaFiltros).toList(growable: false);
  }

  Future<void> _copiar(String label, String valor) async {
    if (valor.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: valor.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado'), duration: const Duration(seconds: 2)),
    );
  }

  bool _pasaFiltrosResumen(ResumenPorLiquidarTaxista r) {
    final q = widget.buscar.trim().toLowerCase();
    if (q.isEmpty) return true;
    return r.nombreTaxista.toLowerCase().contains(q) ||
        r.uidTaxista.toLowerCase().contains(q);
  }

  Future<void> _generarLote({
    required ResumenPorLiquidarTaxista resumen,
    required String periodo,
  }) async {
    await widget.onEjecutarAccion(() async {
      final result = await LiquidacionSemanalRepo.generarParaTaxista(
        uidTaxista: resumen.uidTaxista,
        periodo: periodo,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.mensajeUsuario),
          backgroundColor: result.ok ? Colors.green : Colors.orange,
        ),
      );
      if (result.ok) _subTab.animateTo(1);
    });
  }

  Future<void> _mostrarDialogoGenerar(ResumenPorLiquidarTaxista resumen) async {
    final periodos = resumen.periodosIso;
    if (periodos.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sin períodos ISO en los viajes pendientes'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(ctx),
        title: Text(
          'Generar lote · ${resumen.nombreTaxista}',
          style: TextStyle(color: AdminUi.onCard(ctx)),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Elegí la semana ISO. Solo entran viajes verificados '
                '(transferencia/tarjeta) de ese período.',
                style: TextStyle(color: AdminUi.secondary(ctx), fontSize: 12),
              ),
              const SizedBox(height: 12),
              ...periodos.map((p) {
                final sub = resumen.resumenParaPeriodo(p);
                return Card(
                  color: AdminUi.card(ctx),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      'Semana $p',
                      style: TextStyle(
                        color: AdminUi.onCard(ctx),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Liquidar ${widget.formatter.format(sub.totalNetoRd)} · '
                      'RAI retiene ${widget.formatter.format(sub.comisionRaiRd)} · '
                      '${sub.viajesCount} viaje(s)',
                      style: TextStyle(color: AdminUi.secondary(ctx), fontSize: 12),
                    ),
                    trailing: const Icon(Icons.play_arrow),
                    onTap: () {
                      Navigator.pop(ctx);
                      _generarLote(resumen: resumen, periodo: p);
                    },
                  ),
                );
              }),
              if (periodos.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Si el chofer tiene varias semanas, generá un lote por cada una.',
                    style: TextStyle(color: AdminUi.muted(ctx), fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportarAch(List<LiquidacionSemanal> pendientes) async {
    final exportables = pendientes
        .where(
          (l) =>
              l.estado == 'pendiente_pago' && l.cuentaDestinoSnapshot.estaCompleta,
        )
        .toList(growable: false);
    if (exportables.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay liquidaciones pendientes con cuenta completa'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final csv = LiquidacionSemanalAchExport.buildCsv(exportables);
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'CSV ACH copiado (${exportables.length} filas). Pégalo en Excel o tu banco.',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _mostrarDetalle(LiquidacionSemanal liq) async {
    final lineas = await LiquidacionSemanalRepo.fetchLineas(liq.id);
    final viajes = await LiquidacionSemanalRepo.fetchViajesResumen(
      lineas.map((l) => l.viajeId),
    );
    CuentaDestinoSnapshot? cuentaActual;
    if (!liq.esPagada) {
      cuentaActual =
          await LiquidacionSemanalRepo.fetchCuentaActualTaxista(liq.uidTaxista);
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AdminUi.sheetSurface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, scroll) => _DetalleLiquidacionSheet(
          liq: liq,
          lineas: lineas,
          viajes: viajes,
          cuentaActual: cuentaActual,
          formatter: widget.formatter,
          dateFormat: widget.dateFormat,
          scrollController: scroll,
          onCopiar: _copiar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: AdminFinanzasReglasBanner(compact: true),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Material(
            color: Colors.blue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Liquidación semanal (PR2): neto al conductor por transferencia/tarjeta '
                'verificada. La cuenta bancaria se congela al generar el lote. '
                'Aprobar registra el ACH y marca viajes liquidado=true.',
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
        TabBar(
          controller: _subTab,
          labelColor: AdminUi.onCard(context),
          unselectedLabelColor: AdminUi.muted(context),
          indicatorColor: Colors.blueAccent,
          tabs: const [
            Tab(text: 'A liquidar'),
            Tab(text: 'Lotes pendientes'),
            Tab(text: 'Sin cuenta'),
            Tab(text: 'Pagadas'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _subTab,
            children: [
              _buildPorLiquidarTab(),
              _buildPendientesTab(soloSinCuenta: false),
              _buildPendientesTab(soloSinCuenta: true),
              _buildPagadasTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPorLiquidarTab() {
    return StreamBuilder<List<ResumenPorLiquidarTaxista>>(
      stream: LiquidacionSemanalRepo.streamResumenPorLiquidar(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: AdminUi.progressAccent(context)),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        final raw = snapshot.data ?? const <ResumenPorLiquidarTaxista>[];
        final list = raw.where(_pasaFiltrosResumen).toList(growable: false);

        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No hay choferes con viajes transferencia/tarjeta '
                'verificados pendientes de liquidar.\n\n'
                'Efectivo no aparece aquí: su comisión RAI se cobra por recarga prepago.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AdminUi.secondary(context), height: 1.4),
              ),
            ),
          );
        }

        final totalNeto =
            list.fold<int>(0, (s, r) => s + r.totalNetoCents) / 100.0;
        final totalCom =
            list.fold<int>(0, (s, r) => s + r.comisionRaiCents) / 100.0;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Material(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${list.length} chofer(es) por liquidar',
                        style: TextStyle(
                          color: AdminUi.onCard(context),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Total a pagar a taxistas: ${widget.formatter.format(totalNeto)} · '
                        'RAI retiene ${widget.formatter.format(totalCom)} '
                        '(transf. ${PlataformaEconomia.comisionTransferenciaPorcentaje}% · '
                        'tarj. ${PlataformaEconomia.comisionTarjetaPorcentaje}%)',
                        style: TextStyle(
                          color: AdminUi.secondary(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final r = list[index];
                  return _PorLiquidarCard(
                    resumen: r,
                    formatter: widget.formatter,
                    accionEnCurso: widget.accionEnCurso,
                    onGenerar: () => _mostrarDialogoGenerar(r),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPendientesTab({required bool soloSinCuenta}) {
    return StreamBuilder<List<LiquidacionSemanal>>(
      stream: LiquidacionSemanalRepo.streamPendientesAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: AdminUi.progressAccent(context)),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        var list = _filtrar(snapshot.data ?? const <LiquidacionSemanal>[]);
        if (soloSinCuenta) {
          list = list.where((l) => !l.cuentaDestinoCompleta).toList();
        } else {
          list = list
              .where((l) => l.estado == 'pendiente_pago' && l.cuentaDestinoCompleta)
              .toList();
        }
        if (!soloSinCuenta && list.isNotEmpty) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: widget.accionEnCurso
                        ? null
                        : () => _exportarAch(list),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Exportar CSV ACH'),
                  ),
                ),
              ),
              Expanded(child: _listaCards(list, soloSinCuenta: soloSinCuenta)),
            ],
          );
        }
        return _listaCards(
          list,
          soloSinCuenta: soloSinCuenta,
          vacio: soloSinCuenta
              ? 'No hay borradores sin cuenta bancaria'
              : 'No hay liquidaciones pendientes de pago',
        );
      },
    );
  }

  Widget _buildPagadasTab() {
    return StreamBuilder<List<LiquidacionSemanal>>(
      stream: LiquidacionSemanalRepo.streamPagadasAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: AdminUi.progressAccent(context)),
          );
        }
        final list = _filtrar(snapshot.data ?? const <LiquidacionSemanal>[]);
        return _listaCards(
          list,
          soloSinCuenta: false,
          esHistorial: true,
          vacio: 'No hay liquidaciones pagadas registradas',
        );
      },
    );
  }

  Widget _listaCards(
    List<LiquidacionSemanal> list, {
    required bool soloSinCuenta,
    bool esHistorial = false,
    String vacio = 'Sin registros',
  }) {
    if (list.isEmpty) {
      return Center(
        child: Text(vacio, style: TextStyle(color: AdminUi.secondary(context))),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final liq = list[index];
        return _LiquidacionCard(
          liq: liq,
          formatter: widget.formatter,
          dateFormat: widget.dateFormat,
          accionEnCurso: widget.accionEnCurso,
          esHistorial: esHistorial,
          soloSinCuenta: soloSinCuenta,
          onVerDetalle: () => _mostrarDetalle(liq),
          onAprobar: esHistorial || soloSinCuenta || liq.esBorrador
              ? null
              : () => widget.onAprobar(liq),
          onCancelar:
              esHistorial ? null : () => widget.onCancelar(liq),
          onCopiar: _copiar,
        );
      },
    );
  }
}

class _LiquidacionCard extends StatelessWidget {
  const _LiquidacionCard({
    required this.liq,
    required this.formatter,
    required this.dateFormat,
    required this.accionEnCurso,
    required this.esHistorial,
    required this.soloSinCuenta,
    required this.onVerDetalle,
    required this.onCopiar,
    this.onAprobar,
    this.onCancelar,
  });

  final LiquidacionSemanal liq;
  final NumberFormat formatter;
  final DateFormat dateFormat;
  final bool accionEnCurso;
  final bool esHistorial;
  final bool soloSinCuenta;
  final VoidCallback onVerDetalle;
  final VoidCallback? onAprobar;
  final VoidCallback? onCancelar;
  final void Function(String label, String value) onCopiar;

  @override
  Widget build(BuildContext context) {
    final c = liq.cuentaDestinoSnapshot;
    final esBorrador = liq.esBorrador;
    final colorEstado = esHistorial
        ? Colors.green
        : (esBorrador || soloSinCuenta ? Colors.amber : Colors.blue);
    final estadoLabel = esHistorial
        ? 'PAGADO'
        : (esBorrador || soloSinCuenta ? 'SIN CUENTA / BORRADOR' : 'PENDIENTE PAGO');

    return Card(
      color: AdminUi.card(context),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onVerDetalle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      liq.nombreTaxista,
                      style: TextStyle(
                        color: AdminUi.onCard(context),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (!liq.totalesCuadran)
                    Tooltip(
                      message: 'Los totales por método no cuadran con el neto',
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange.shade300,
                        size: 22,
                      ),
                    ),
                ],
              ),
              Text(
                'Periodo ${liq.periodo} · ${liq.viajesCount} viajes'
                '${liq.viajesEfectivoExcluidosCount > 0 ? ' · ${liq.viajesEfectivoExcluidosCount} efectivo excl.' : ''}',
                style: TextStyle(color: AdminUi.muted(context)),
              ),
              const SizedBox(height: 8),
              _auditoriaMontos(context),
              if (c.estaCompleta || c.banco.isNotEmpty) ...[
                const SizedBox(height: 10),
                _cuentaBanco(context, c),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorEstado.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colorEstado),
                ),
                child: Text(
                  estadoLabel,
                  style: TextStyle(
                    color: colorEstado,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              if (esHistorial && liq.referenciaAch != null &&
                  liq.referenciaAch!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Ref. ACH: ${liq.referenciaAch}',
                  style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
                ),
              ],
              if (esHistorial && liq.pagadoEn != null) ...[
                Text(
                  'Pagado: ${dateFormat.format(liq.pagadoEn!)}',
                  style: TextStyle(color: AdminUi.muted(context), fontSize: 11),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onVerDetalle,
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text('Auditar viajes'),
                    ),
                  ),
                  if (onAprobar != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: accionEnCurso ? null : onAprobar,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Aprobar pago'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (onCancelar != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: accionEnCurso ? null : onCancelar,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Cancelar lote'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _auditoriaMontos(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Liquidar al chofer: ${formatter.format(liq.totalNetoRd)}',
          style: const TextStyle(
            color: Colors.greenAccent,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        Text(
          'RAI retiene (comisión): ${formatter.format(liq.comisionRaiRd)}',
          style: TextStyle(color: Colors.amber.shade200, fontSize: 13),
        ),
        Text(
          'Bruto recaudado ${formatter.format(liq.totalBrutoRd)}',
          style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
        ),
        Text(
          'Transferencia ${formatter.format(liq.totalesPorMetodo.transferencia.totalNetoRd)} '
          '(${liq.totalesPorMetodo.transferencia.viajesCount} viajes) · '
          'Tarjeta ${formatter.format(liq.totalesPorMetodo.tarjeta.totalNetoRd)} '
          '(${liq.totalesPorMetodo.tarjeta.viajesCount} viajes)',
          style: TextStyle(color: AdminUi.muted(context), fontSize: 11),
        ),
      ],
    );
  }

  Widget _cuentaBanco(BuildContext context, CuentaDestinoSnapshot c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance, size: 16, color: AdminUi.muted(context)),
              const SizedBox(width: 6),
              Text(
                'Cuenta destino (snapshot)',
                style: TextStyle(
                  color: AdminUi.secondary(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.copy, size: 16, color: AdminUi.muted(context)),
                onPressed: () => onCopiar(
                  'Cuenta',
                  '${c.banco} · ${c.tipoCuenta} · ${c.numeroCuenta} · ${c.titular}',
                ),
              ),
            ],
          ),
          Text(
            '${c.banco} · ${c.tipoCuenta.isEmpty ? '—' : c.tipoCuenta}',
            style: TextStyle(color: AdminUi.onCard(context), fontSize: 13),
          ),
          Text(
            c.numeroCuenta,
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            c.titular,
            style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
          ),
          if (c.ci.isNotEmpty)
            Text('CI: ${c.ci}', style: TextStyle(color: AdminUi.muted(context), fontSize: 11)),
        ],
      ),
    );
  }
}

class _DetalleLiquidacionSheet extends StatelessWidget {
  const _DetalleLiquidacionSheet({
    required this.liq,
    required this.lineas,
    required this.viajes,
    required this.cuentaActual,
    required this.formatter,
    required this.dateFormat,
    required this.scrollController,
    required this.onCopiar,
  });

  final LiquidacionSemanal liq;
  final List<LiquidacionSemanalLinea> lineas;
  final Map<String, Map<String, dynamic>> viajes;
  final CuentaDestinoSnapshot? cuentaActual;
  final NumberFormat formatter;
  final DateFormat dateFormat;
  final ScrollController scrollController;
  final void Function(String label, String value) onCopiar;

  @override
  Widget build(BuildContext context) {
    int sumBruto = 0;
    int sumCom = 0;
    int sumNeto = 0;
    for (final l in lineas) {
      sumBruto += l.precioCents;
      sumCom += l.comisionCents;
      sumNeto += l.gananciaCents;
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AdminUi.borderSubtle(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Auditoría · ${liq.nombreTaxista}',
          style: TextStyle(
            color: AdminUi.onCard(context),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Periodo ${liq.periodo} · ${liq.viajesCount} viajes en lote',
          style: TextStyle(color: AdminUi.muted(context)),
        ),
        if (liq.viajesEfectivoExcluidosCount > 0) ...[
          const SizedBox(height: 8),
          Material(
            color: Colors.teal.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                '${liq.viajesEfectivoExcluidosCount} viaje(s) en efectivo en el período '
                'no entran aquí: su comisión RAI se cobra vía prepago/recarga.',
                style: TextStyle(color: AdminUi.onCard(context), fontSize: 12),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _resumenFila(context, 'Total bruto (líneas)', formatter.format(sumBruto / 100)),
        _resumenFila(context, 'Comisión RAI (líneas)', formatter.format(sumCom / 100)),
        _resumenFila(
          context,
          'Neto taxista (líneas)',
          formatter.format(sumNeto / 100),
          destacado: true,
        ),
        _resumenFila(context, 'Neto documento', formatter.format(liq.totalNetoRd)),
        if ((sumNeto - liq.totalNetoCents).abs() > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '⚠ Diferencia entre suma de líneas y total del lote. Revisar antes de pagar.',
              style: TextStyle(color: Colors.orange.shade300, fontSize: 12),
            ),
          ),
        const Divider(height: 24),
        Text(
          'Viajes incluidos',
          style: TextStyle(
            color: AdminUi.onCard(context),
            fontWeight: FontWeight.bold,
          ),
        ),
        if (lineas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Sin líneas de detalle',
              style: TextStyle(color: AdminUi.muted(context)),
            ),
          )
        else
          ...lineas.map((l) {
            final v = viajes[l.viajeId] ?? const <String, dynamic>{};
            final cliente = (v['clienteNombre'] ?? '').toString();
            final origen = (v['origen'] ?? '').toString();
            final destino = (v['destino'] ?? '').toString();
            return Card(
              color: AdminUi.card(context),
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                dense: true,
                title: Text(
                  '${l.metodoPagoNormalizado.toUpperCase()} · ${formatter.format(l.gananciaRd)} neto',
                  style: TextStyle(color: AdminUi.onCard(context), fontSize: 13),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (cliente.isNotEmpty)
                      Text('Cliente: $cliente', style: _sub(context)),
                    if (origen.isNotEmpty || destino.isNotEmpty)
                      Text(
                        '$origen → $destino',
                        style: _sub(context),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      'Bruto ${formatter.format(l.precioRd)} · '
                      'Com. ${formatter.format(l.comisionRd)} · '
                      'Pago: ${l.estadoPago}',
                      style: _sub(context),
                    ),
                    if (l.finalizadoEn != null)
                      Text(
                        dateFormat.format(l.finalizadoEn!),
                        style: _sub(context),
                      ),
                    Text(
                      'ID viaje: ${l.viajeId}',
                      style: TextStyle(
                        color: AdminUi.muted(context),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        if (cuentaActual != null) ...[
          const Divider(height: 24),
          Text(
            'Cuenta actual en perfil (comparar con snapshot)',
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          _cuentaComparacion(context, liq.cuentaDestinoSnapshot, cuentaActual!),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  TextStyle _sub(BuildContext context) =>
      TextStyle(color: AdminUi.secondary(context), fontSize: 11);

  Widget _resumenFila(
    BuildContext context,
    String label,
    String valor, {
    bool destacado = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AdminUi.secondary(context))),
          Text(
            valor,
            style: TextStyle(
              color: destacado ? Colors.greenAccent : AdminUi.onCard(context),
              fontWeight: destacado ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cuentaComparacion(
    BuildContext context,
    CuentaDestinoSnapshot snap,
    CuentaDestinoSnapshot actual,
  ) {
    final cambio = snap.numeroCuenta.trim() != actual.numeroCuenta.trim() ||
        snap.banco.trim() != actual.banco.trim();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (cambio ? Colors.orange : Colors.green).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cambio ? Colors.orange : Colors.green,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cambio
                ? 'La cuenta cambió desde el snapshot. Pagar al snapshot o regenerar lote.'
                : 'Cuenta actual coincide con el snapshot.',
            style: TextStyle(
              color: cambio ? Colors.orange.shade200 : Colors.greenAccent,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Actual: ${actual.banco} · ${actual.numeroCuenta} · ${actual.titular}',
            style: TextStyle(color: AdminUi.onCard(context), fontSize: 12),
          ),
          TextButton.icon(
            onPressed: () => onCopiar(
              'Cuenta actual',
              '${actual.banco} · ${actual.numeroCuenta} · ${actual.titular}',
            ),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copiar cuenta actual'),
          ),
        ],
      ),
    );
  }
}

class _PorLiquidarCard extends StatelessWidget {
  const _PorLiquidarCard({
    required this.resumen,
    required this.formatter,
    required this.accionEnCurso,
    required this.onGenerar,
  });

  final ResumenPorLiquidarTaxista resumen;
  final NumberFormat formatter;
  final bool accionEnCurso;
  final VoidCallback onGenerar;

  @override
  Widget build(BuildContext context) {
    final t = resumen.totalesPorMetodo.transferencia;
    final c = resumen.totalesPorMetodo.tarjeta;

    return Card(
      color: AdminUi.card(context),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              resumen.nombreTaxista,
              style: TextStyle(
                color: AdminUi.onCard(context),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${resumen.viajesCount} viaje(s) verificados · '
              'Semanas: ${resumen.periodosIso.join(', ')}',
              style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hay que liquidarle: ${formatter.format(resumen.totalNetoRd)}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'RAI retiene (comisión): ${formatter.format(resumen.comisionRaiRd)}',
                    style: TextStyle(
                      color: Colors.amber.shade200,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Bruto transferencia/tarjeta: ${formatter.format(resumen.totalBrutoRd)}',
                    style: TextStyle(color: AdminUi.secondary(context), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (t.viajesCount > 0)
              Text(
                'Transferencia: liquidar ${formatter.format(t.totalNetoRd)} · '
                'RAI ${formatter.format(t.comisionRaiCents / 100)} · ${t.viajesCount} viaje(s)',
                style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
              ),
            if (c.viajesCount > 0)
              Text(
                'Tarjeta: liquidar ${formatter.format(c.totalNetoRd)} · '
                'RAI ${formatter.format(c.comisionRaiCents / 100)} · ${c.viajesCount} viaje(s)',
                style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: accionEnCurso ? null : onGenerar,
                icon: const Icon(Icons.receipt_long, size: 18),
                label: const Text('Generar lote de liquidación'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
