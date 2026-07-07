import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../servicios/pool_repo.dart';
import '../../utils/pool_recaudo_central.dart';
import '../../widgets/admin_pool_cierre_recaudo_panel.dart';
import '../../widgets/admin_pool_comprobante_dialog.dart';
import 'admin_ui_theme.dart';

/// Pagos pool central pendientes + liquidaciones neto al organizador (admin).
class AdminPoolRecaudoCentralPanel extends StatelessWidget {
  const AdminPoolRecaudoCentralPanel({
    super.key,
    required this.accionEnCurso,
    required this.onEjecutar,
    required this.formatter,
  });

  final bool accionEnCurso;
  final Future<void> Function(Future<void> Function() job) onEjecutar;
  final NumberFormat formatter;

  static String _shortId(String id) {
    final t = id.trim();
    if (t.length <= 8) return t.isEmpty ? '—' : t;
    return t.substring(0, 8);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Giras por cupos · recaudo central RAI',
          style: TextStyle(
            color: AdminUi.onCard(context),
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '1) Importá el extracto Popular (Conciliación banco) — giras RAI-P ref+monto exacto se verifican solas.\n'
          '2) Al cerrar la salida, transferí el neto a la cuenta del organizador y marcá liquidado.',
          style: TextStyle(color: AdminUi.secondary(context), height: 1.4),
        ),
        const SizedBox(height: 16),
        Text(
          'Pagos de clientes pendientes de verificar',
          style: TextStyle(
            color: AdminUi.progressAccent(context),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        _PagosPoolPendientesList(
          accionEnCurso: accionEnCurso,
          onEjecutar: onEjecutar,
          formatter: formatter,
        ),
        const SizedBox(height: 20),
        Text(
          'Neto pendiente al organizador',
          style: TextStyle(
            color: AdminUi.progressAccent(context),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        _LiquidacionesPoolPendientesList(
          accionEnCurso: accionEnCurso,
          onEjecutar: onEjecutar,
          formatter: formatter,
        ),
      ],
    );
  }
}

class _PagosPoolPendientesList extends StatelessWidget {
  const _PagosPoolPendientesList({
    required this.accionEnCurso,
    required this.onEjecutar,
    required this.formatter,
  });

  final bool accionEnCurso;
  final Future<void> Function(Future<void> Function() job) onEjecutar;
  final NumberFormat formatter;

  @override
  Widget build(BuildContext context) {
    final stream = PoolRepo.streamReservasPoolRaiPagoPendienteAdmin(poolLimit: 80);

    return StreamBuilder<List<PoolReservaRaiPendienteAdmin>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          final err = snap.error.toString();
          final hint = err.contains('permission-denied') ||
                  err.contains('PERMISSION_DENIED')
              ? 'Sin permiso Firestore (cuenta admin o reglas desplegadas).'
              : 'Error de red o Firestore.';
          return Text(
            'Error listando reservas: $hint\n$err',
            style: const TextStyle(color: Colors.red),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data!;
        if (items.isEmpty) {
          return Text(
            'No hay transferencias pool pendientes de verificar.',
            style: TextStyle(color: AdminUi.secondary(context)),
          );
        }
        return Column(
          children: items.map((item) {
            final r = item.reserva;
            final poolId = item.poolId;
            final reservaId = item.reservaId;
            final pool = item.pool;
            final ref = (r['referenciaRecaudo'] ?? '').toString();
            final comprobante = (r['comprobanteUrl'] ?? '').toString().trim();
            final estadoPago = (r['estadoPago'] ?? '').toString();
            final total = ((r['total'] ?? 0) as num).toDouble();
            final seats = ((r['seats'] ?? 0) as num).toInt();
            final cliente = (r['clienteNombre'] ?? 'Cliente').toString();
            final montoEsp =
                ((r['montoEsperadoRecaudoRd'] ?? total) as num).toDouble();
            final destino = (pool['destino'] ?? '').toString();
            final origen = (pool['origenTown'] ?? '').toString();
            final ruta = destino.isNotEmpty
                ? (origen.isNotEmpty ? '$origen → $destino' : destino)
                : '';
            return Card(
              color: AdminUi.card(context),
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gira ${AdminPoolRecaudoCentralPanel._shortId(poolId)} · '
                      '$seats asiento(s) · ${formatter.format(montoEsp)}',
                      style: TextStyle(
                        color: AdminUi.onCard(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (ruta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          ruta,
                          style: TextStyle(
                            color: AdminUi.secondary(context),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Cliente: $cliente\n'
                      'Referencia: ${ref.isEmpty ? "—" : ref}\n'
                      'Pago: ${estadoPago.isEmpty ? "pendiente" : estadoPago}'
                      '${comprobante.isNotEmpty ? " · Recibo: enviado" : " · Recibo: faltante"}',
                      style: TextStyle(color: AdminUi.secondary(context)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (comprobante.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: accionEnCurso
                                ? null
                                : () => AdminPoolComprobanteDialog.mostrar(
                                      context,
                                      comprobante,
                                    ),
                            icon: const Icon(Icons.receipt_long, size: 18),
                            label: const Text('Ver bauche'),
                          ),
                        if (ref.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: accionEnCurso
                                ? null
                                : () async {
                                    await Clipboard.setData(
                                        ClipboardData(text: ref));
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Referencia copiada')),
                                    );
                                  },
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text('Copiar ref.'),
                          ),
                        FilledButton.icon(
                          onPressed: accionEnCurso
                              ? null
                              : () => onEjecutar(() async {
                                    await PoolRepo.verifyPoolReservaRecaudoAdmin(
                                      poolId: poolId,
                                      reservaId: reservaId,
                                    );
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Pago verificado — cupos confirmados en RAI',
                                        ),
                                      ),
                                    );
                                  }),
                          icon: const Icon(Icons.verified, size: 18),
                          label: const Text('Verificar pago RAI'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _LiquidacionesPoolPendientesList extends StatelessWidget {
  const _LiquidacionesPoolPendientesList({
    required this.accionEnCurso,
    required this.onEjecutar,
    required this.formatter,
  });

  final bool accionEnCurso;
  final Future<void> Function(Future<void> Function() job) onEjecutar;
  final NumberFormat formatter;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('liquidaciones_pool')
        .where('estado', isEqualTo: 'pendiente_pago')
        .limit(40);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text('Error: ${snap.error}',
              style: const TextStyle(color: Colors.red));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Text(
            'No hay liquidaciones neto pendientes.',
            style: TextStyle(color: AdminUi.secondary(context)),
          );
        }
        return Column(
          children: docs.map((doc) {
            final d = doc.data();
            final liqId = doc.id;
            final neto = ((d['netoTotalRd'] ?? 0) as num).toDouble();
            final poolId = (d['poolId'] ?? '').toString();
            final cierre = PoolRecaudoCentral.cierreDesdePool(
              Map<String, dynamic>.from(d),
            );
            final titular = (d['bancoTitular'] ?? '').toString();
            final cuenta = (d['bancoCuenta'] ?? '').toString();
            final banco = (d['bancoNombre'] ?? '').toString();
            final destino = (d['destino'] ?? '').toString();
            final asientosVendidos = ((d['asientosVendidos'] ?? 0) as num).toInt();
            final precioAsiento =
                ((d['precioPorAsiento'] ?? 0) as num).toDouble();
            return Card(
              color: AdminUi.card(context),
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Neto ${formatter.format(neto)} · '
                      'Gira ${AdminPoolRecaudoCentralPanel._shortId(poolId)}',
                      style: TextStyle(
                        color: AdminUi.onCard(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (destino.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Destino: $destino',
                            style: TextStyle(color: AdminUi.secondary(context))),
                      ),
                    if (asientosVendidos > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          precioAsiento > 0
                              ? '$asientosVendidos asiento(s) vendido(s) × ${formatter.format(precioAsiento)}'
                              : '$asientosVendidos asiento(s) vendido(s)',
                          style: TextStyle(
                            color: AdminUi.onCard(context),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    AdminPoolCierreRecaudoPanel(
                      cierre: cierre,
                      compact: true,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Transferir a:\n'
                      '${titular.isEmpty ? "—" : titular}\n'
                      '${banco.isEmpty ? "" : "$banco · "}$cuenta',
                      style: TextStyle(
                        color: AdminUi.onCard(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: accionEnCurso
                          ? null
                          : () async {
                              final refCtrl = TextEditingController();
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Marcar neto transferido'),
                                  content: TextField(
                                    controller: refCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Ref. transferencia (opcional)',
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancelar'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Confirmar'),
                                    ),
                                  ],
                                ),
                              );
                              final refText = refCtrl.text.trim();
                              refCtrl.dispose();
                              if (ok != true) return;
                              if (!context.mounted) return;
                              await onEjecutar(() async {
                                await PoolRepo.approveLiquidacionPoolAdmin(
                                  liquidacionId: liqId,
                                  referenciaBanco:
                                      refText.isEmpty ? null : refText,
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Liquidación marcada como pagada'),
                                  ),
                                );
                              });
                            },
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Neto transferido al organizador'),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
