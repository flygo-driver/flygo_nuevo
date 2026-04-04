// lib/pantallas/admin/verificar_pagos.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:intl/intl.dart';
import '../../servicios/pagos_taxista_repo.dart';
import '../../servicios/viajes_repo.dart';
import '../../modelo/pago_taxista.dart';
import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

class VerificarPagos extends StatefulWidget {
  const VerificarPagos({super.key});

  @override
  State<VerificarPagos> createState() => _VerificarPagosState();
}

class _VerificarPagosState extends State<VerificarPagos> {
  final formatter = NumberFormat.currency(locale: 'es', symbol: 'RD\$');
  final dateFormat = DateFormat('dd/MM/yyyy');
  String _filtroEstado = 'todos';
  final TextEditingController _buscarCtrl = TextEditingController();
  String _buscar = '';
  int _rangoDias = 0; // 0 = todos
  bool _accionEnCurso = false;
  int _tabIndex = 0;

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _aprobarPago(PagoTaxista pago) async {
    if (_accionEnCurso) return;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(ctx),
        title: Text('Confirmar pago', style: TextStyle(color: AdminUi.onCard(ctx))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Taxista: ${pago.nombreTaxista}', style: TextStyle(color: AdminUi.secondary(ctx))),
            Text('Semana: ${pago.semana}', style: TextStyle(color: AdminUi.secondary(ctx))),
            // ✅ Mostrar correctamente: comisión 20% para admin
            Text('Comisión 20%: ${formatter.format(pago.comision)}', 
                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            Text('Taxista recibe: ${formatter.format(pago.netoAPagar)}', 
                style: TextStyle(color: AdminUi.secondary(ctx))),
            const SizedBox(height: 16),
            Text('¿Confirmas que recibiste el pago?', style: TextStyle(color: AdminUi.onCard(ctx))),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: TextStyle(color: AdminUi.secondary(ctx))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Sí, aprobar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        setState(() => _accionEnCurso = true);
        await PagosTaxistaRepo.verificarPago(pagoId: pago.id, aprobado: true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Pago aprobado correctamente'), 
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _accionEnCurso = false);
      }
    }
  }

  Future<void> _rechazarPago(PagoTaxista pago) async {
    if (_accionEnCurso) return;
    final TextEditingController motivoCtrl = TextEditingController();
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: AdminUi.dialogSurface(ctx),
          title: Text('Rechazar pago', style: TextStyle(color: AdminUi.onCard(ctx))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Motivo del rechazo:', style: TextStyle(color: AdminUi.secondary(ctx))),
              const SizedBox(height: 8),
              TextField(
                controller: motivoCtrl,
                style: TextStyle(color: AdminUi.onCard(ctx)),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Ej: Comprobante ilegible, monto incorrecto...',
                  hintStyle: TextStyle(color: AdminUi.secondary(ctx).withValues(alpha: 0.75)),
                  filled: true,
                  fillColor: AdminUi.inputFill(ctx),
                  border: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: AdminUi.borderSubtle(ctx)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: AdminUi.borderSubtle(ctx)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: cs.primary, width: 1.4),
                  ),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar', style: TextStyle(color: AdminUi.secondary(ctx))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Rechazar pago'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        setState(() => _accionEnCurso = true);
        await PagosTaxistaRepo.verificarPago(
          pagoId: pago.id,
          aprobado: false,
          notaAdmin: motivoCtrl.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Pago rechazado'), 
            backgroundColor: Colors.orange,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _accionEnCurso = false);
      }
    }
  }

  Future<void> _verDetalle(PagoTaxista pago) async {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AdminUi.sheetSurface(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))
      ),
      builder: (BuildContext ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (BuildContext sheetContext, ScrollController controller) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AdminUi.borderSubtle(sheetContext),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Detalle del pago',
                style: TextStyle(
                  color: AdminUi.onCard(sheetContext), 
                  fontSize: 20, 
                  fontWeight: FontWeight.bold
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: <Widget>[
                    _detalleItem(sheetContext, 'Taxista', pago.nombreTaxista),
                    _detalleItem(sheetContext, 'Semana', pago.semana),
                    _detalleItem(sheetContext, 'Período', 
                      '${dateFormat.format(pago.fechaInicio)} - ${dateFormat.format(pago.fechaFin)}'),
                    _detalleItem(sheetContext, 'Viajes realizados', '${pago.viajesSemana} viajes'),
                    _detalleItem(sheetContext, 'Total recaudado', formatter.format(pago.totalGanado + pago.comision)),
                    // ✅ Comisión 20% destacada en verde
                    _detalleItem(sheetContext, 'Comisión (20%)', formatter.format(pago.comision), 
                      color: Colors.greenAccent, isBold: true),
                    _detalleItem(sheetContext, 'Neto para taxista', formatter.format(pago.netoAPagar)),
                    if (pago.comprobanteUrl != null && pago.comprobanteUrl!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.image, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Comprobante: ${pago.comprobanteUrl}',
                                style: TextStyle(color: AdminUi.secondary(sheetContext)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (pago.notaAdmin != null && pago.notaAdmin!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.note, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Nota: ${pago.notaAdmin}',
                                style: TextStyle(color: AdminUi.secondary(sheetContext)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detalleItem(BuildContext context, String label, String value, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: AdminUi.muted(context), fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: color ?? AdminUi.onCard(context),
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(
    BuildContext context, {
    required String label,
    required String value,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(color: AdminUi.muted(context), fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(color: color ?? AdminUi.onCard(context), fontSize: 13, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/icon/icono_app_R.png',
            height: 28,
            fit: BoxFit.contain,
            errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => SizedBox(
              width: 28,
              child: Icon(Icons.error, color: AdminUi.appBarFg(context), size: 20),
            ),
          ),
        ),
        title: Text('Verificar Pagos', style: TextStyle(color: AdminUi.onCard(context))),
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: _tabButton('Comisiones semanales', 0),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _tabButton('Transferencias pendientes', 1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _tabButton('Transferencias validadas', 2),
                ),
              ],
            ),
          ),
          Expanded(
            child: _tabIndex == 0
                ? _buildComisionesSemanales()
                : (_tabIndex == 1 ? _buildTransferenciasPendientes() : _buildPagosATaxistas()),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final bool active = _tabIndex == index;
    final cs = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: () => setState(() => _tabIndex = index),
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? cs.primary : Colors.transparent,
        side: BorderSide(color: active ? cs.primary : AdminUi.borderSubtle(context)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: active ? cs.onPrimary : AdminUi.secondary(context),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildComisionesSemanales() {
    return StreamBuilder<List<PagoTaxista>>(
      stream: PagosTaxistaRepo.streamPagosPendientes(),
      builder: (BuildContext context, AsyncSnapshot<List<PagoTaxista>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AdminUi.progressAccent(context))
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

          final List<PagoTaxista> pagos = snapshot.data ?? [];

          if (pagos.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 80),
                  const SizedBox(height: 16),
                  Text(
                    '¡Todos los pagos están al día!',
                    style: TextStyle(color: AdminUi.secondary(context), fontSize: 16),
                  ),
                ],
              ),
            );
          }

          final List<PagoTaxista> pagosFiltrados = pagos.where((PagoTaxista pago) {
            final String q = _buscar.toLowerCase();
            if (q.isNotEmpty) {
              final bool match = pago.nombreTaxista.toLowerCase().contains(q) ||
                  pago.uidTaxista.toLowerCase().contains(q) ||
                  pago.semana.toLowerCase().contains(q);
              if (!match) return false;
            }
            if (_rangoDias > 0) {
              final DateTime limite = DateTime.now().subtract(Duration(days: _rangoDias));
              if (pago.fechaFin.isBefore(limite)) return false;
            }
            if (_filtroEstado == 'todos') return true;
            if (_filtroEstado == 'pendiente') return pago.estado == 'pendiente';
            if (_filtroEstado == 'revision') return pago.estado == 'pendiente_verificacion';
            return true;
          }).toList();

          if (pagosFiltrados.isEmpty) {
            return Center(
              child: Text(
                'No hay pagos con el filtro seleccionado',
                style: TextStyle(color: AdminUi.secondary(context)),
              ),
            );
          }

          return Column(
            children: [
              // Filtros rápidos
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    TextField(
                      controller: _buscarCtrl,
                      onChanged: (v) => setState(() => _buscar = v.trim()),
                      style: TextStyle(color: AdminUi.onCard(context)),
                      decoration: InputDecoration(
                        hintText: 'Buscar por taxista, UID o semana',
                        hintStyle: TextStyle(color: AdminUi.secondary(context).withValues(alpha: 0.85)),
                        prefixIcon: Icon(Icons.search, color: AdminUi.secondary(context)),
                        suffixIcon: _buscar.isEmpty
                            ? null
                            : IconButton(
                                icon: Icon(Icons.close, color: AdminUi.secondary(context)),
                                onPressed: () {
                                  _buscarCtrl.clear();
                                  setState(() => _buscar = '');
                                },
                              ),
                        filled: true,
                        fillColor: AdminUi.inputFill(context),
                        border: OutlineInputBorder(
                          borderRadius: const BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: const BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(color: AdminUi.borderSubtle(context)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: const BorderRadius.all(Radius.circular(8)),
                          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _filtroChip('Todos', 'todos'),
                        const SizedBox(width: 8),
                        _filtroChip('Pendientes', 'pendiente'),
                        const SizedBox(width: 8),
                        _filtroChip('En revisión', 'revision'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _rangoChip('Todo', 0),
                        const SizedBox(width: 8),
                        _rangoChip('7d', 7),
                        const SizedBox(width: 8),
                        _rangoChip('30d', 30),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: pagosFiltrados.length,
                  itemBuilder: (BuildContext context, int index) {
                    final PagoTaxista pago = pagosFiltrados[index];
                    final bool esPendiente = pago.estado == 'pendiente';
                    final bool esEnRevision = pago.estado == 'pendiente_verificacion';

                    return Card(
                      color: AdminUi.card(context),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: esPendiente 
                            ? Colors.red.withValues(alpha: 0.5) 
                            : Colors.orange.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    pago.nombreTaxista,
                                    style: TextStyle(
                                      color: AdminUi.onCard(context), 
                                      fontSize: 18, 
                                      fontWeight: FontWeight.bold
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10, 
                                    vertical: 4
                                  ),
                                  decoration: BoxDecoration(
                                    color: esPendiente 
                                      ? Colors.red.withValues(alpha: 0.2) 
                                      : Colors.orange.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: esPendiente ? Colors.red : Colors.orange
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Icon(
                                        esPendiente ? Icons.warning : Icons.hourglass_top,
                                        color: esPendiente ? Colors.red : Colors.orange,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        esPendiente ? 'PENDIENTE' : 'EN REVISIÓN',
                                        style: TextStyle(
                                          color: esPendiente ? Colors.red : Colors.orange,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: _infoChip(
                                    context,
                                    label: 'Semana', 
                                    value: pago.semana
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _infoChip(
                                    context,
                                    label: 'Viajes', 
                                    value: '${pago.viajesSemana}'
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: _infoChip(
                                    context,
                                    label: 'Total recaudado', 
                                    value: formatter.format(pago.totalGanado + pago.comision)
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _infoChip(
                                    context,
                                    label: 'Comisión 20%', 
                                    value: formatter.format(pago.comision),
                                    color: Colors.greenAccent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Período: ${dateFormat.format(pago.fechaInicio)} - ${dateFormat.format(pago.fechaFin)}',
                              style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _verDetalle(pago),
                                    icon: const Icon(Icons.visibility, size: 18),
                                    label: const Text('Ver detalle'),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: AdminUi.borderSubtle(context)),
                                      foregroundColor: AdminUi.onCard(context),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (esPendiente || esEnRevision) ...<Widget>[
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _accionEnCurso ? null : () => _aprobarPago(pago),
                                      icon: const Icon(Icons.check, size: 18),
                                      label: const Text('Aprobar'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _accionEnCurso ? null : () => _rechazarPago(pago),
                                      icon: const Icon(Icons.close, size: 18),
                                      label: const Text('Rechazar'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                    ),
                                  ),
                                ] else ...<Widget>[
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.green),
                                      ),
                                      child: const Text(
                                        'PAGADO', 
                                        style: TextStyle(
                                          color: Colors.green, 
                                          fontWeight: FontWeight.bold
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
      },
    );
  }

  Widget _buildTransferenciasPendientes() {
    final stream = fs.FirebaseFirestore.instance
        .collection('viajes')
        .where('metodoPago', isEqualTo: 'Transferencia')
        .where('estado', isEqualTo: 'pendiente_confirmacion')
        .where('transferenciaConfirmada', isEqualTo: false)
        .snapshots();

    return StreamBuilder<fs.QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: AdminUi.progressAccent(context)));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text('No hay transferencias pendientes.', style: TextStyle(color: AdminUi.secondary(context))),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...docs.map((doc) {
              final d = doc.data();
              final viajeId = doc.id;
              final total = (d['precio'] as num?)?.toDouble() ?? 0;
              final taxista = (d['nombreTaxista'] ?? 'Taxista').toString();
              final comprobante = (d['comprobanteTransferenciaUrl'] ?? '').toString();
              return Card(
                color: AdminUi.card(context),
                child: ListTile(
                  title: Text('Viaje #${viajeId.substring(0, 6)} • ${formatter.format(total)}',
                      style: TextStyle(color: AdminUi.onCard(context))),
                  subtitle: Text(
                    'Taxista: $taxista${comprobante.isNotEmpty ? '\nComprobante: cargado' : '\nComprobante: faltante'}',
                    style: TextStyle(color: AdminUi.secondary(context)),
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: comprobante.isEmpty
                            ? null
                            : () async {
                                await ViajesRepo.confirmarTransferenciaCliente(viajeId: viajeId);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Transferencia confirmada'), backgroundColor: Colors.green),
                                );
                              },
                        child: const Text('Confirmar'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final motivoCtrl = TextEditingController();
                          final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) {
                                  final cs = Theme.of(ctx).colorScheme;
                                  return AlertDialog(
                                    backgroundColor: AdminUi.dialogSurface(ctx),
                                    title: Text('Rechazar transferencia', style: TextStyle(color: AdminUi.onCard(ctx))),
                                    content: TextField(
                                      controller: motivoCtrl,
                                      style: TextStyle(color: AdminUi.onCard(ctx)),
                                      maxLines: 3,
                                      decoration: InputDecoration(
                                        hintText: 'Motivo del rechazo',
                                        hintStyle: TextStyle(color: AdminUi.secondary(ctx).withValues(alpha: 0.75)),
                                        filled: true,
                                        fillColor: AdminUi.inputFill(ctx),
                                        border: OutlineInputBorder(
                                          borderRadius: const BorderRadius.all(Radius.circular(8)),
                                          borderSide: BorderSide(color: AdminUi.borderSubtle(ctx)),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: const BorderRadius.all(Radius.circular(8)),
                                          borderSide: BorderSide(color: AdminUi.borderSubtle(ctx)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: const BorderRadius.all(Radius.circular(8)),
                                          borderSide: BorderSide(color: cs.primary, width: 1.4),
                                        ),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: Text('Cancelar', style: TextStyle(color: AdminUi.secondary(ctx))),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Rechazar'),
                                      ),
                                    ],
                                  );
                                },
                              ) ??
                              false;
                          if (!ok) return;
                          await ViajesRepo.rechazarTransferenciaCliente(
                            viajeId: viajeId,
                            motivo: motivoCtrl.text.trim().isEmpty
                                ? 'No se encontro deposito en la cuenta de RAI.'
                                : motivoCtrl.text.trim(),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Transferencia rechazada'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        },
                        child: const Text('Rechazar'),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            Text(
              'Giras por cupos • Comisión empresa (10%)',
              style: TextStyle(color: AdminUi.progressAccent(context), fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _buildComisionesGirasPendientes(),
          ],
        );
      },
    );
  }

  Widget _buildPagosATaxistas() {
    final stream = fs.FirebaseFirestore.instance
        .collection('viajes')
        .where('metodoPago', isEqualTo: 'Transferencia')
        .where('transferenciaConfirmada', isEqualTo: true)
        .snapshots();

    return StreamBuilder<fs.QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: AdminUi.progressAccent(context)));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text('No hay transferencias validadas.', style: TextStyle(color: AdminUi.secondary(context))),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...docs.map((doc) {
              final d = doc.data();
              final viajeId = doc.id;
              final ganancia = (d['gananciaTaxista'] as num?)?.toDouble() ?? 0;
              final taxista = (d['nombreTaxista'] ?? 'Taxista').toString();
              final estado = (d['estado'] ?? '').toString();
              return Card(
                color: AdminUi.card(context),
                child: ListTile(
                  title: Text('Taxista: $taxista', style: TextStyle(color: AdminUi.onCard(context))),
                  subtitle: Text(
                    'Viaje #${viajeId.substring(0, 6)} • Estado: $estado • ${formatter.format(ganancia)}',
                    style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
                  ),
                  trailing: Icon(Icons.verified, color: AdminUi.progressAccent(context)),
                ),
              );
            }),
            const SizedBox(height: 16),
            Text(
              'Giras por cupos • Comisiones validadas',
              style: TextStyle(color: AdminUi.progressAccent(context), fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _buildComisionesGirasValidadas(),
          ],
        );
      },
    );
  }

  Widget _buildComisionesGirasPendientes() {
    final stream = fs.FirebaseFirestore.instance
        .collection('viajes_pool')
        .where('estado', isEqualTo: 'finalizado')
        .where('comisionPendientePagoAdmin', isEqualTo: true)
        .snapshots();
    return StreamBuilder<fs.QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(color: AdminUi.progressAccent(context))),
          );
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No hay comisiones de giras pendientes.', style: TextStyle(color: AdminUi.secondary(context))),
          );
        }
        return Column(
          children: docs.map((doc) {
            final d = doc.data();
            final poolId = doc.id;
            final totalGira = (d['totalGira'] as num?)?.toDouble() ??
                (d['montoReservado'] as num?)?.toDouble() ??
                0;
            final comision = (d['montoComision'] as num?)?.toDouble() ?? (totalGira * 0.10);
            final owner = (d['agenciaNombre'] ?? d['taxistaNombre'] ?? 'Taxista').toString();
            final destino = (d['destino'] ?? '').toString();
            return Card(
              color: AdminUi.card(context),
              child: ListTile(
                title: Text(
                  'Gira #${poolId.substring(0, 6)} • Comisión 10%: ${formatter.format(comision)}',
                  style: TextStyle(color: AdminUi.onCard(context), fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'Publicado por: $owner • Destino: $destino\nTotal gira: ${formatter.format(totalGira)}',
                  style: TextStyle(color: AdminUi.secondary(context)),
                ),
                trailing: ElevatedButton(
                  onPressed: () async {
                    await fs.FirebaseFirestore.instance.collection('viajes_pool').doc(poolId).update({
                      'comisionPendientePagoAdmin': false,
                      'comisionEstado': 'transferencia_validada_admin',
                      'comisionTransferenciaValidadaAt': fs.FieldValue.serverTimestamp(),
                    });
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Comisión de gira validada (transferencia).'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  child: const Text('Validar transferencia'),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildComisionesGirasValidadas() {
    final stream = fs.FirebaseFirestore.instance
        .collection('viajes_pool')
        .where('estado', isEqualTo: 'finalizado')
        .where('comisionEstado', isEqualTo: 'transferencia_validada_admin')
        .snapshots();
    return StreamBuilder<fs.QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(color: AdminUi.progressAccent(context))),
          );
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No hay comisiones de giras validadas.', style: TextStyle(color: AdminUi.secondary(context))),
          );
        }
        return Column(
          children: docs.map((doc) {
            final d = doc.data();
            final poolId = doc.id;
            final comision = (d['montoComision'] as num?)?.toDouble() ?? 0;
            final owner = (d['agenciaNombre'] ?? d['taxistaNombre'] ?? 'Taxista').toString();
            return Card(
              color: AdminUi.card(context),
              child: ListTile(
                title: Text(
                  'Gira #${poolId.substring(0, 6)} • ${formatter.format(comision)}',
                  style: TextStyle(color: AdminUi.onCard(context)),
                ),
                subtitle: Text(
                  'Publicado por: $owner • Transferencia validada',
                  style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
                ),
                trailing: Icon(Icons.verified, color: AdminUi.progressAccent(context)),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _filtroChip(String label, String valor) {
    final seleccionado = _filtroEstado == valor;
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: seleccionado,
      onSelected: (selected) {
        setState(() {
          _filtroEstado = valor;
        });
      },
      backgroundColor: AdminUi.card(context),
      selectedColor: cs.primary,
      side: BorderSide(color: AdminUi.borderSubtle(context)),
      labelStyle: TextStyle(
        color: seleccionado ? cs.onPrimary : AdminUi.onCard(context),
        fontWeight: FontWeight.w600,
      ),
      checkmarkColor: seleccionado ? cs.onPrimary : AdminUi.secondary(context),
    );
  }

  Widget _rangoChip(String label, int dias) {
    final seleccionado = _rangoDias == dias;
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: seleccionado,
      onSelected: (_) => setState(() => _rangoDias = dias),
      backgroundColor: AdminUi.card(context),
      selectedColor: cs.secondaryContainer,
      side: BorderSide(color: AdminUi.borderSubtle(context)),
      labelStyle: TextStyle(
        color: seleccionado ? cs.onSecondaryContainer : AdminUi.secondary(context),
        fontWeight: FontWeight.w600,
      ),
      checkmarkColor: seleccionado ? cs.onSecondaryContainer : AdminUi.secondary(context),
    );
  }
}