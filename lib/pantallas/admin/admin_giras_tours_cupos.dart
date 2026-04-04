// lib/pantallas/admin/admin_giras_tours_cupos.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../servicios/pool_repo.dart';
import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

/// Listado y control admin de giras / tours por cupos (`viajes_pool`).
class AdminGirasToursCupos extends StatefulWidget {
  const AdminGirasToursCupos({super.key});

  @override
  State<AdminGirasToursCupos> createState() => _AdminGirasToursCuposState();
}

class _AdminGirasToursCuposState extends State<AdminGirasToursCupos> {
  int _filtro = 0;

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    return PoolRepo.pools
        .orderBy('createdAt', descending: true)
        .limit(250)
        .snapshots();
  }

  DateTime _fechaSalida(Map<String, dynamic> d) {
    final raw = d['fechaSalida'] ?? d['fecha'] ?? d['fechaHora'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _pasaFiltro(String estado) {
    final e = estado.trim().toLowerCase();
    switch (_filtro) {
      case 0:
        return true;
      case 1:
        return const {
          'abierto',
          'preconfirmado',
          'confirmado',
          'lleno',
          'activo',
          'disponible',
          'buscando',
        }.contains(e);
      case 2:
        return e == 'en_ruta';
      case 3:
        return e == 'finalizado';
      case 4:
        return e == 'cancelado';
      default:
        return true;
    }
  }

  bool _puedeIniciar(Map<String, dynamic> d) {
    final estado = (d['estado'] ?? '').toString().trim().toLowerCase();
    if (estado == 'en_ruta' || estado == 'cancelado' || estado == 'finalizado') {
      return false;
    }
    final minC = ((d['minParaConfirmar'] ?? 0) as num).toInt();
    final cached = d['asientosFirmesSalida'];
    final firm = (cached != null
            ? (cached as num).toInt()
            : ((d['asientosPagados'] ?? 0) as num).toInt())
        .clamp(0, 1 << 30);
    if (firm <= 0) return false;
    if (minC > 0 && firm < minC) return false;
    return true;
  }

  Future<void> _operar(
    BuildContext context, {
    required String action,
    required String poolId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (action == 'iniciar') {
        await PoolRepo.iniciarViajePoolSeguro(poolId: poolId);
        messenger.showSnackBar(const SnackBar(content: Text('Viaje iniciado')));
      } else if (action == 'finalizar') {
        await PoolRepo.finalizarViajePoolSeguro(poolId: poolId);
        messenger.showSnackBar(const SnackBar(content: Text('Viaje finalizado')));
      } else if (action == 'cancelar') {
        await PoolRepo.cancelarViajePoolSeguro(
          poolId: poolId,
          motivo: 'Cancelado por administración',
        );
        messenger.showSnackBar(const SnackBar(content: Text('Viaje cancelado')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _confirmarCancelar(BuildContext context, String poolId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(ctx),
        title: Text('Cancelar gira', style: TextStyle(color: AdminUi.onCard(ctx))),
        content: Text(
          '¿Marcar esta gira como cancelada? Los pasajeros deberán ser avisados por el operador.',
          style: TextStyle(color: AdminUi.secondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('No', style: TextStyle(color: AdminUi.secondary(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Sí, cancelar',
              style: TextStyle(
                color: Theme.of(ctx).brightness == Brightness.light
                    ? Colors.deepOrange.shade800
                    : Colors.orangeAccent,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _operar(context, action: 'cancelar', poolId: poolId);
    }
  }

  void _verReservas(BuildContext context, String poolId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AdminUi.sheetSurface(context),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (_, scroll) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AdminUi.borderSubtle(ctx),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Reservas',
                          style: TextStyle(
                            color: AdminUi.onCard(ctx),
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: Icon(Icons.close, color: AdminUi.secondary(ctx)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: PoolRepo.pools.doc(poolId).collection('reservas').snapshots(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: CircularProgressIndicator(color: AdminUi.progressAccent(context)),
                        );
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Text('Error: ${snap.error}',
                              style: TextStyle(color: AdminUi.secondary(context))),
                        );
                      }
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Center(
                          child: Text('Sin reservas', style: TextStyle(color: AdminUi.muted(context))),
                        );
                      }
                      docs.sort((a, b) {
                        final ta = a.data()['createdAt'];
                        final tb = b.data()['createdAt'];
                        final da = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
                        final db = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
                        return db.compareTo(da);
                      });
                      return ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final r = docs[i].data();
                          final seats = (r['seats'] ?? 0).toString();
                          final est = (r['estado'] ?? '').toString();
                          final uid = (r['uidCliente'] ?? '').toString();
                          final total = ((r['total'] ?? 0) as num).toDouble();
                          return Card(
                            color: AdminUi.card(context),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: AdminUi.borderSubtle(context)),
                            ),
                            child: ListTile(
                              title: Text(
                                '$est · $seats asiento(s) · RD\$ ${total.toStringAsFixed(0)}',
                                style: TextStyle(color: AdminUi.onCard(context), fontSize: 14),
                              ),
                              subtitle: Text(
                                uid.isEmpty ? '—' : uid,
                                style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE d MMM yyyy • HH:mm', 'es');

    final chipSel = AdminUi.infoFill(context);
    final chipOn = AdminUi.onCard(context);
    final chipOff = AdminUi.secondary(context);

    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text(
          'Giras / tours por cupos',
          style: TextStyle(color: AdminUi.onCard(context)),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminUi.infoFill(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AdminUi.infoBorder(context)),
              ),
              child: Text(
                'Control de viajes_pool: estados, cupos y acciones (iniciar, finalizar, cancelar). '
                'Iniciar exige cupos firmes (pagos verificados o efectivo reservado). '
                'Las comisiones al finalizar se validan en Verificar Pagos.',
                style: TextStyle(color: AdminUi.secondary(context), fontSize: 12, height: 1.35),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Todos'),
                  selected: _filtro == 0,
                  onSelected: (_) => setState(() => _filtro = 0),
                  selectedColor: chipSel,
                  checkmarkColor: chipOn,
                  labelStyle: TextStyle(color: _filtro == 0 ? chipOn : chipOff),
                  side: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Activos'),
                  selected: _filtro == 1,
                  onSelected: (_) => setState(() => _filtro = 1),
                  selectedColor: chipSel,
                  checkmarkColor: chipOn,
                  labelStyle: TextStyle(color: _filtro == 1 ? chipOn : chipOff),
                  side: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('En ruta'),
                  selected: _filtro == 2,
                  onSelected: (_) => setState(() => _filtro = 2),
                  selectedColor: chipSel,
                  checkmarkColor: chipOn,
                  labelStyle: TextStyle(color: _filtro == 2 ? chipOn : chipOff),
                  side: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Finalizados'),
                  selected: _filtro == 3,
                  onSelected: (_) => setState(() => _filtro = 3),
                  selectedColor: chipSel,
                  checkmarkColor: chipOn,
                  labelStyle: TextStyle(color: _filtro == 3 ? chipOn : chipOff),
                  side: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Cancelados'),
                  selected: _filtro == 4,
                  onSelected: (_) => setState(() => _filtro = 4),
                  selectedColor: chipSel,
                  checkmarkColor: chipOn,
                  labelStyle: TextStyle(color: _filtro == 4 ? chipOn : chipOff),
                  side: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: AdminUi.progressAccent(context)),
                  );
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error al cargar: ${snap.error}\n'
                        'Si falta índice en Firestore, crea uno para viajes_pool + createdAt.',
                        style: TextStyle(color: AdminUi.secondary(context)),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final todos = snap.data?.docs ?? [];
                final docs = todos.where((doc) {
                  final e = (doc.data()['estado'] ?? '').toString();
                  return _pasaFiltro(e);
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Text('No hay registros con este filtro.',
                        style: TextStyle(color: AdminUi.muted(context))),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final d = doc.data();
                    final id = doc.id;
                    final estado = (d['estado'] ?? '').toString();
                    final estadoL = estado.toLowerCase();
                    final origen = (d['origenTown'] ?? '').toString();
                    final destino = (d['destino'] ?? '').toString();
                    final tipo = (d['tipo'] ?? '').toString();
                    final cap = ((d['capacidad'] ?? 0) as num).toInt();
                    final occ = ((d['asientosReservados'] ?? 0) as num).toInt();
                    final pag = ((d['asientosPagados'] ?? 0) as num).toInt();
                    final owner = (d['taxistaNombre'] ?? d['ownerTaxistaId'] ?? '').toString();
                    final fecha = _fechaSalida(d);

                    final puedeIniciar = _puedeIniciar(d);
                    final puedeFinalizar = estadoL == 'en_ruta';
                    final puedeCancelar = estadoL != 'finalizado' && estadoL != 'cancelado';

                    final green = AdminUi.accentGreen(context);
                    final blue = Theme.of(context).brightness == Brightness.light
                        ? Colors.lightBlue.shade800
                        : Colors.lightBlueAccent;
                    final orange = Theme.of(context).brightness == Brightness.light
                        ? Colors.deepOrange.shade800
                        : Colors.orangeAccent;

                    return Card(
                      color: AdminUi.card(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: AdminUi.borderSubtle(context)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$origen → $destino',
                                        style: TextStyle(
                                          color: AdminUi.onCard(context),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        df.format(fecha),
                                        style: TextStyle(color: AdminUi.secondary(context), fontSize: 13),
                                      ),
                                      Text(
                                        'Tipo: ${tipo.isEmpty ? "—" : tipo} · Estado: $estado',
                                        style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
                                      ),
                                      Text(
                                        'Organiza: ${owner.isEmpty ? "—" : owner}',
                                        style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
                                      ),
                                      Text(
                                        'Cupos: $occ/$cap reservados · $pag pagados',
                                        style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Copiar ID',
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: id));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('ID copiado')),
                                      );
                                    }
                                  },
                                  icon: Icon(Icons.copy, color: AdminUi.secondary(context), size: 20),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (puedeIniciar)
                                  OutlinedButton.icon(
                                    onPressed: () => _operar(context, action: 'iniciar', poolId: id),
                                    icon: const Icon(Icons.play_arrow, size: 18),
                                    label: const Text('Iniciar'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: green,
                                      side: BorderSide(color: green.withValues(alpha: 0.65)),
                                    ),
                                  ),
                                if (puedeFinalizar)
                                  OutlinedButton.icon(
                                    onPressed: () => _operar(context, action: 'finalizar', poolId: id),
                                    icon: const Icon(Icons.flag, size: 18),
                                    label: const Text('Finalizar'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: blue,
                                      side: BorderSide(color: blue),
                                    ),
                                  ),
                                if (puedeCancelar)
                                  OutlinedButton.icon(
                                    onPressed: () => _confirmarCancelar(context, id),
                                    icon: const Icon(Icons.cancel_outlined, size: 18),
                                    label: const Text('Cancelar'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: orange,
                                      side: BorderSide(color: orange),
                                    ),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: () => _verReservas(context, id),
                                  icon: const Icon(Icons.people_outline, size: 18),
                                  label: const Text('Reservas'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AdminUi.secondary(context),
                                    side: BorderSide(color: AdminUi.borderSubtle(context)),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final n = await PoolRepo.limpiarReservasVencidas(id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Reservas vencidas limpiadas: $n')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                                  label: const Text('Limpiar vencidas'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AdminUi.muted(context),
                                    side: BorderSide(color: AdminUi.borderSubtle(context)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
