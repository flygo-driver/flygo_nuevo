// Torre de control ADM: viajes en vivo (escalable, paginado vía CF + stream limitado).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../servicios/admin_dashboard_service.dart';
import '../../utils/calculos/estados.dart';
import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

class AdminTorreControl extends StatefulWidget {
  const AdminTorreControl({super.key});

  @override
  State<AdminTorreControl> createState() => _AdminTorreControlState();
}

class _AdminTorreControlState extends State<AdminTorreControl>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _cargando = false;
  List<AdminViajeResumen> _items = const [];
  String? _cursor;
  String _modo = 'activos';

  static const _activos = [
    'aceptado',
    'asignado',
    'en_camino_pickup',
    'en_camino',
    'a_bordo',
    'en_curso',
  ];

  static const _buscando = ['pendiente', 'buscando', 'pendiente_pago'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        setState(() {
          _modo = _tabs.index == 0 ? 'activos' : 'buscando';
          _cursor = null;
          _items = const [];
        });
        _cargar();
      }
    });
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool mas = false}) async {
    if (_cargando) return;
    setState(() => _cargando = true);
    try {
      final batch = await AdminDashboardService.listViajesActivos(
        modo: _modo,
        limit: 60,
        cursor: mas ? _cursor : null,
      );
      if (!mounted) return;
      setState(() {
        if (mas) {
          _items = [..._items, ...batch];
        } else {
          _items = batch;
        }
        _cursor = batch.isNotEmpty ? batch.last.id : null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando viajes: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamLive() {
    final estados = _modo == 'activos' ? _activos : _buscando;
    return FirebaseFirestore.instance
        .collection('viajes')
        .where('estado', whereIn: estados)
        .orderBy('updatedAt', descending: true)
        .limit(80)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        title: Text('Torre de control',
            style: TextStyle(color: AdminUi.onCard(context))),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AdminUi.accentGreen(context),
          unselectedLabelColor: AdminUi.tabUnselected(context),
          indicatorColor: AdminUi.accentGreen(context),
          tabs: const [
            Tab(text: 'En vivo'),
            Tab(text: 'Buscando chofer'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AdminUi.iconStandard(context)),
            onPressed: () => _cargar(),
          ),
        ],
      ),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('admin_metrics')
                .doc('live')
                .snapshots(),
            builder: (context, snap) {
              final m = snap.data?.data() ?? const {};
              final activos = (m['viajesActivos'] as num?)?.toInt() ?? 0;
              final buscando = (m['viajesBuscando'] as num?)?.toInt() ?? 0;
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AdminUi.infoFill(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AdminUi.infoBorder(context)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.radar, color: AdminUi.accentGreen(context)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ahora: $activos en curso · $buscando buscando chofer',
                        style: TextStyle(
                          color: AdminUi.onCard(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _streamLive(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: AdminUi.progressAccent(context),
                    ),
                  );
                }
                if (snap.hasError) {
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (_, i) => _ViajeTile(v: _items[i]),
                  );
                }
                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty && _items.isEmpty) {
                  return Center(
                    child: Text(
                      'Sin viajes en esta cola',
                      style: TextStyle(color: AdminUi.secondary(context)),
                    ),
                  );
                }
                final list = docs.isNotEmpty ? docs.length : _items.length;
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: list,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (docs.isNotEmpty) {
                      final d = docs[i];
                      final data = d.data();
                      return _ViajeTile.fromFirestore(d.id, data);
                    }
                    return _ViajeTile(v: _items[i]);
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

class _ViajeTile extends StatelessWidget {
  final AdminViajeResumen? v;
  final String? id;
  final Map<String, dynamic>? data;

  const _ViajeTile({this.v}) : id = null, data = null;

  const _ViajeTile.fromFirestore(this.id, this.data) : v = null;

  @override
  Widget build(BuildContext context) {
    final estado = v?.estado ?? (data?['estado'] ?? '').toString();
    final norm = EstadosViaje.normalizar(estado);
    final origen = v?.origen ??
        (data?['origen'] ?? data?['origenTexto'] ?? '—').toString();
    final destino = v?.destino ??
        (data?['destino'] ?? data?['destinoTexto'] ?? '—').toString();
    final tipo = v?.tipoServicio ?? (data?['tipoServicio'] ?? '').toString();
    final tarifa = v?.tarifa ??
        ((data?['tarifa'] ?? data?['precio']) as num?)?.toDouble() ??
        0.0;
    final viajeId = v?.id ?? id ?? '';

    Color badge;
    switch (norm) {
      case EstadosViaje.enCurso:
      case EstadosViaje.aBordo:
        badge = Colors.green;
      case EstadosViaje.enCaminoPickup:
        badge = Colors.orange;
      default:
        badge = Colors.blueGrey;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badge.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  norm,
                  style: TextStyle(
                    color: badge,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              if (tipo.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(tipo,
                    style: TextStyle(
                        color: AdminUi.secondary(context), fontSize: 12)),
              ],
              const Spacer(),
              Text(
                'RD\$ ${tarifa.toStringAsFixed(0)}',
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$origen → $destino',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AdminUi.onCard(context)),
          ),
          const SizedBox(height: 6),
          Text(
            'ID ${viajeId.length > 8 ? viajeId.substring(0, 8) : viajeId}',
            style: TextStyle(color: AdminUi.muted(context), fontSize: 11),
          ),
        ],
      ),
    );
  }
}
