// Radar turismo ADM: todos los pedidos cliente en tiempo real + mensajes.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../servicios/asignacion_turismo_repo.dart';
import '../../servicios/turismo_control_adm_repo.dart';
import '../../utils/calculos/estados.dart';
import '../../widgets/admin_app_bar.dart';
import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';
import 'asignar_viaje_turismo.dart';
import 'viajes_turismo_admin.dart';

enum _FiltroPedidoTurismo {
  todos,
  sinChofer,
  enPool,
  programados,
  enCurso,
}

class AdminTurismoControl extends StatefulWidget {
  const AdminTurismoControl({super.key});

  @override
  State<AdminTurismoControl> createState() => _AdminTurismoControlState();
}

class _AdminTurismoControlState extends State<AdminTurismoControl>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  _FiltroPedidoTurismo _filtro = _FiltroPedidoTurismo.todos;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  static String _ref(String id) =>
      id.length > 8 ? id.substring(0, 8) : id;

  static bool _sinChofer(Map<String, dynamic> d) {
    final uid =
        (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();
    if (uid.isNotEmpty) return false;
    final estado = EstadosViaje.normalizar((d['estado'] ?? '').toString());
    return estado == EstadosViaje.pendiente ||
        estado == EstadosViaje.pendientePago ||
        (d['estado'] ?? '').toString() == 'pendiente_admin' ||
        estado == 'buscando';
  }

  static bool _enPool(Map<String, dynamic> d) =>
      (d['canalAsignacion'] ?? '').toString().trim() ==
      AsignacionTurismoRepo.canalTurismoPool;

  static bool _programado(Map<String, dynamic> d) =>
      d['programado'] == true || d['esAhora'] == false;

  static bool _enCurso(Map<String, dynamic> d) {
    final uid =
        (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();
    if (uid.isEmpty) return false;
    final estado = EstadosViaje.normalizar((d['estado'] ?? '').toString());
    return estado == EstadosViaje.aceptado ||
        estado == EstadosViaje.enCaminoPickup ||
        estado == EstadosViaje.aBordo ||
        estado == EstadosViaje.enCurso;
  }

  static bool _canceladoOFin(Map<String, dynamic> d) {
    final estado = EstadosViaje.normalizar((d['estado'] ?? '').toString());
    return estado == EstadosViaje.cancelado ||
        estado == EstadosViaje.completado ||
        d['completado'] == true ||
        d['cancelado'] == true;
  }

  bool _pasaFiltro(Map<String, dynamic> d) {
    if (_canceladoOFin(d) && _filtro != _FiltroPedidoTurismo.todos) {
      return false;
    }
    switch (_filtro) {
      case _FiltroPedidoTurismo.todos:
        return true;
      case _FiltroPedidoTurismo.sinChofer:
        return _sinChofer(d);
      case _FiltroPedidoTurismo.enPool:
        return _enPool(d) && _sinChofer(d);
      case _FiltroPedidoTurismo.programados:
        return _programado(d) && !_canceladoOFin(d);
      case _FiltroPedidoTurismo.enCurso:
        return _enCurso(d);
    }
  }

  String _etiquetaCanal(Map<String, dynamic> d) {
    final canal = (d['canalAsignacion'] ?? 'admin').toString().trim();
    if (canal == AsignacionTurismoRepo.canalTurismoPool) return 'Pool turístico';
    if (canal == 'admin') return 'Cola ADM';
    return canal.isEmpty ? '—' : canal;
  }

  Color _colorCanal(BuildContext context, Map<String, dynamic> d) {
    if (_enPool(d)) return Colors.deepPurpleAccent;
    if ((d['canalAsignacion'] ?? '').toString() == 'admin') {
      return Colors.orangeAccent;
    }
    return AdminUi.secondary(context);
  }

  String _etiquetaEstado(Map<String, dynamic> d) {
    final raw = (d['estado'] ?? '').toString();
    if (raw == 'pendiente_admin') return 'Pendiente ADM';
    return EstadosViaje.normalizar(raw);
  }

  Future<void> _abrirDetalle(
    BuildContext context,
    String id,
    Map<String, dynamic> d,
  ) async {
    await TurismoControlAdmRepo.marcarMensajesViajeLeidos(id);
    if (!context.mounted) return;

    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final DateTime? pickup = _ts(d['fechaHora']);
    final DateTime? publishAt = _ts(d['publishAt']);
    final String uidTx =
        (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().trim();
    final bool puedeAsignar =
        (d['canalAsignacion'] ?? 'admin').toString().trim() == 'admin' &&
            uidTx.isEmpty &&
            _sinChofer(d);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AdminUi.sheetSurface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (_, scroll) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: ListView(
                controller: scroll,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AdminUi.borderSubtle(context),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    (d['origen'] ?? '—').toString(),
                    style: TextStyle(
                      color: AdminUi.onCard(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  Text(
                    '→ ${(d['destino'] ?? '—')}',
                    style: TextStyle(
                      color: AdminUi.secondary(context),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _detalleFila(ctx, 'Referencia', '#${_ref(id)}'),
                  _detalleFila(ctx, 'Estado', _etiquetaEstado(d)),
                  _detalleFila(ctx, 'Canal', _etiquetaCanal(d)),
                  _detalleFila(
                    ctx,
                    'Recogida',
                    pickup != null ? fmt.format(pickup) : '—',
                  ),
                  if (publishAt != null)
                    _detalleFila(ctx, 'Publicación pool', fmt.format(publishAt)),
                  _detalleFila(
                    ctx,
                    'Tipo',
                    (d['subtipoTurismo'] ?? d['tipoVehiculo'] ?? '—')
                        .toString(),
                  ),
                  _detalleFila(
                    ctx,
                    'Precio',
                    'RD\$ ${_num(d['precio']).toStringAsFixed(0)}',
                  ),
                  _detalleFila(
                    ctx,
                    'Chofer',
                    uidTx.isEmpty
                        ? 'Sin asignar'
                        : (d['nombreTaxista'] ?? uidTx).toString(),
                  ),
                  _detalleFila(
                    ctx,
                    'Cliente',
                    (d['nombreCliente'] ?? d['uidCliente'] ?? '—').toString(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Mensajes del cliente',
                    style: TextStyle(
                      color: AdminUi.onCard(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: TurismoControlAdmRepo.streamMensajesViaje(id),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? const [];
                      if (docs.isEmpty) {
                        return Text(
                          'Sin mensajes in-app todavía.',
                          style: TextStyle(color: AdminUi.muted(context)),
                        );
                      }
                      return Column(
                        children: docs.map((doc) {
                          final m = doc.data();
                          final ts = _ts(m['createdAt']);
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AdminUi.card(context),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AdminUi.borderSubtle(context),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (m['mensaje'] ?? '').toString(),
                                  style: TextStyle(
                                    color: AdminUi.onCard(context),
                                  ),
                                ),
                                if (ts != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    fmt.format(ts),
                                    style: TextStyle(
                                      color: AdminUi.muted(context),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (puedeAsignar)
                    FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (!context.mounted) return;
                        final bool? ok = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AsignarViajeTurismo(
                              viajeId: id,
                              subtipoTurismo:
                                  (d['subtipoTurismo'] ?? 'carro').toString(),
                              tipoVehiculoDoc:
                                  (d['tipoVehiculo'] ?? '').toString(),
                              latOrigen: _num(d['latCliente']) != 0
                                  ? _num(d['latCliente'])
                                  : null,
                              lonOrigen: _num(d['lonCliente']) != 0
                                  ? _num(d['lonCliente'])
                                  : null,
                            ),
                          ),
                        );
                        if (ok == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Chofer asignado'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Asignar chofer'),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ViajesTurismoAdmin(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.travel_explore),
                    label: const Text('Abrir cola de asignación'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detalleFila(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k, style: TextStyle(color: AdminUi.muted(context))),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                color: AdminUi.onCard(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipFiltro(_FiltroPedidoTurismo f, String label) {
    final sel = _filtro == f;
    return FilterChip(
      selected: sel,
      label: Text(label),
      onSelected: (_) => setState(() => _filtro = f),
      selectedColor: AdminUi.infoFill(context),
      checkmarkColor: AdminUi.accentGreen(context),
    );
  }

  Widget _buildPedidosTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              _chipFiltro(_FiltroPedidoTurismo.todos, 'Todos'),
              const SizedBox(width: 6),
              _chipFiltro(_FiltroPedidoTurismo.sinChofer, 'Sin chofer'),
              const SizedBox(width: 6),
              _chipFiltro(_FiltroPedidoTurismo.enPool, 'En pool'),
              const SizedBox(width: 6),
              _chipFiltro(_FiltroPedidoTurismo.programados, 'Programados'),
              const SizedBox(width: 6),
              _chipFiltro(_FiltroPedidoTurismo.enCurso, 'En curso'),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: TurismoControlAdmRepo.streamViajesTurismo(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(
                    color: AdminUi.progressAccent(context),
                  ),
                );
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error: ${snap.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AdminUi.secondary(context)),
                    ),
                  ),
                );
              }

              final docs = (snap.data?.docs ?? const [])
                  .where((d) => _pasaFiltro(d.data()))
                  .toList();

              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    'No hay pedidos turismo en este filtro.',
                    style: TextStyle(color: AdminUi.secondary(context)),
                  ),
                );
              }

              final fmt = DateFormat('dd/MM HH:mm');
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final doc = docs[i];
                  final d = doc.data();
                  final pickup = _ts(d['fechaHora']);
                  final canalColor = _colorCanal(context, d);
                  final uidTx =
                      (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString();

                  return Material(
                    color: AdminUi.card(context),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _abrirDetalle(context, doc.id, d),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: AdminUi.borderSubtle(context)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${d['origen'] ?? '—'} → ${d['destino'] ?? '—'}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AdminUi.onCard(context),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: canalColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: canalColor.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Text(
                                    _etiquetaCanal(d),
                                    style: TextStyle(
                                      color: canalColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              pickup != null
                                  ? 'Recogida ${fmt.format(pickup)}'
                                  : 'Recogida —',
                              style: TextStyle(
                                color: AdminUi.secondary(context),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '#${_ref(doc.id)} · ${_etiquetaEstado(d)} · '
                              '${uidTx.isEmpty ? 'Sin chofer' : 'Con chofer'}',
                              style: TextStyle(
                                color: AdminUi.muted(context),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
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
  }

  Widget _buildMensajesTab() {
    final fmt = DateFormat('dd/MM HH:mm');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: TurismoControlAdmRepo.streamMensajesRecientes(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: AdminUi.progressAccent(context),
            ),
          );
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return Center(
            child: Text(
              'Sin mensajes de clientes turismo.',
              style: TextStyle(color: AdminUi.secondary(context)),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final doc = docs[i];
            final m = doc.data();
            final leido = m['leidoPorAdm'] == true;
            final ts = _ts(m['createdAt']);
            final viajeId = (m['viajeId'] ?? '').toString();

            return Material(
              color: leido
                  ? AdminUi.card(context)
                  : AdminUi.infoFill(context),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  await TurismoControlAdmRepo.marcarMensajeLeido(doc.id);
                  if (!context.mounted || viajeId.isEmpty) return;
                  final vSnap = await FirebaseFirestore.instance
                      .collection('viajes')
                      .doc(viajeId)
                      .get();
                  if (!context.mounted || !vSnap.exists) return;
                  await _abrirDetalle(
                    context,
                    viajeId,
                    vSnap.data() ?? <String, dynamic>{},
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: leido
                          ? AdminUi.borderSubtle(context)
                          : AdminUi.infoBorder(context),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              (m['clienteNombre'] ?? 'Cliente').toString(),
                              style: TextStyle(
                                color: AdminUi.onCard(context),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (!leido)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (m['ruta'] ?? '').toString(),
                        style: TextStyle(
                          color: AdminUi.secondary(context),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        (m['mensaje'] ?? '').toString(),
                        style: TextStyle(color: AdminUi.onCard(context)),
                      ),
                      if (ts != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          fmt.format(ts),
                          style: TextStyle(
                            color: AdminUi.muted(context),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AdminAppBar(
        title: 'Control turismo',
        bottom: TabBar(
          controller: _tabs,
          labelColor: AdminUi.accentGreen(context),
          unselectedLabelColor: AdminUi.tabUnselected(context),
          indicatorColor: AdminUi.accentGreen(context),
          tabs: [
            const Tab(text: 'Pedidos'),
            Tab(
              child: StreamBuilder<int>(
                stream: TurismoControlAdmRepo.streamConteoMensajesNoLeidos(),
                builder: (context, snap) {
                  final n = snap.data ?? 0;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Mensajes'),
                      if (n > 0) ...[
                        const SizedBox(width: 6),
                        CircleAvatar(
                          radius: 9,
                          backgroundColor: Colors.redAccent,
                          child: Text(
                            n > 9 ? '9+' : '$n',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminUi.infoFill(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AdminUi.infoBorder(context)),
              ),
              child: Text(
                'Vista en tiempo real de todos los pedidos turismo del cliente. '
                'Solo lectura aquí; usa «Cola de asignación» para liberar o asignar chofer.',
                style: TextStyle(
                  color: AdminUi.secondary(context),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildPedidosTab(),
                _buildMensajesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
