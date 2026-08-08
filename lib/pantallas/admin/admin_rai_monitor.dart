// Monitor asistente RAI — uso diario + historial de mensajes.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

class AdminRaiMonitor extends StatefulWidget {
  const AdminRaiMonitor({super.key});

  @override
  State<AdminRaiMonitor> createState() => _AdminRaiMonitorState();
}

class _AdminRaiMonitorState extends State<AdminRaiMonitor>
    with SingleTickerProviderStateMixin {
  static const int _dailyLimit = 50;
  static const int _listLimit = 80;
  static const int _mensajesLimit = 100;

  final Map<String, String> _nombreCache = <String, String>{};
  bool _soloPedidosViaje = false;
  late final TabController _tabs;

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

  String _todayKey() => DateTime.now().toIso8601String().substring(0, 10);

  Stream<QuerySnapshot<Map<String, dynamic>>> _usageStream() {
    return FirebaseFirestore.instance
        .collection('rai_asistente_usage')
        .where('day', isEqualTo: _todayKey())
        .orderBy('count', descending: true)
        .limit(_listLimit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _mensajesStream() {
    return FirebaseFirestore.instance
        .collection('rai_asistente_mensajes')
        .where('day', isEqualTo: _todayKey())
        .limit(_mensajesLimit)
        .snapshots();
  }

  int _compareMensajesPorFecha(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final ta = a.data()['createdAt'] as Timestamp?;
    final tb = b.data()['createdAt'] as Timestamp?;
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return tb.compareTo(ta);
  }

  Future<void> _hydrateNombres(Iterable<String> uids) async {
    final missing =
        uids.where((u) => u.isNotEmpty && !_nombreCache.containsKey(u)).toList();
    if (missing.isEmpty) return;

    final db = FirebaseFirestore.instance;
    for (final uid in missing.take(20)) {
      try {
        final snap = await db.collection('usuarios').doc(uid).get();
        final nombre = (snap.data()?['nombre'] ?? '').toString().trim();
        if (!mounted) return;
        setState(() => _nombreCache[uid] = nombre);
      } catch (_) {
        if (mounted) setState(() => _nombreCache[uid] = '');
      }
    }
  }

  String _nombreFor(String uid) {
    final cached = _nombreCache[uid];
    if (cached != null && cached.isNotEmpty) return cached;
    return uid.length > 12 ? '${uid.substring(0, 12)}…' : uid;
  }

  String _etiquetaAccion(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'open_taxi':
        return 'Pedir taxi';
      case 'open_motor':
        return 'Pedir motor';
      case 'open_turismo':
        return 'Turismo';
      case 'open_soporte':
        return 'Soporte';
      case 'open_mis_viajes':
        return 'Mis viajes';
      case 'open_perfil':
        return 'Completar perfil';
      default:
        return 'Consulta';
    }
  }

  String _horaDesde(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate().toLocal();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AdminAppBar(
        guiaId: AdminGuiaIds.asistente,
        title: 'Asistente RAI',
        bottom: TabBar(
          controller: _tabs,
          labelColor: AdminUi.accentGreen(context),
          unselectedLabelColor: AdminUi.secondary(context),
          indicatorColor: AdminUi.accentGreen(context),
          tabs: const [
            Tab(text: 'Uso hoy'),
            Tab(text: 'Mensajes'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                'En vivo',
                style: TextStyle(
                  color: AdminUi.accentGreen(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildUsoTab(),
          _buildMensajesTab(),
        ],
      ),
    );
  }

  Widget _buildUsoTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _usageStream(),
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
                'No se pudo cargar uso RAI: ${snap.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: AdminUi.secondary(context)),
              ),
            ),
          );
        }

        final docs = snap.data?.docs ?? const [];
        _hydrateNombres(docs.map((d) => d.id));

        final items = docs
            .map((d) {
              final data = d.data();
              return (
                uid: d.id,
                count: (data['count'] as num?)?.toInt() ?? 0,
              );
            })
            .toList();
        final totalCalls = items.fold<int>(0, (acc, i) => acc + i.count);
        final day = _todayKey();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AdminUi.infoFill(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AdminUi.infoBorder(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Uso hoy ($day)',
                    style: TextStyle(
                      color: AdminUi.onCard(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$totalCalls consultas · límite $_dailyLimit/día por cliente',
                    style: TextStyle(color: AdminUi.secondary(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Top clientes (${items.length})',
              style: TextStyle(
                color: AdminUi.onCard(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Text(
                'Sin uso registrado hoy',
                style: TextStyle(color: AdminUi.secondary(context)),
              )
            else
              ...items.map((u) {
                final pct = (u.count / _dailyLimit).clamp(0.0, 1.0);
                final critico = u.count >= _dailyLimit;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AdminUi.card(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: critico
                          ? Colors.redAccent.withValues(alpha: 0.5)
                          : AdminUi.borderSubtle(context),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _nombreFor(u.uid),
                              style: TextStyle(
                                color: AdminUi.onCard(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${u.count}/$_dailyLimit',
                            style: TextStyle(
                              color: critico
                                  ? Colors.redAccent
                                  : AdminUi.accentGreen(context),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: pct,
                        backgroundColor: AdminUi.borderSubtle(context),
                        color: critico
                            ? Colors.redAccent
                            : AdminUi.accentGreen(context),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Widget _buildMensajesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Mensajes de hoy',
                  style: TextStyle(
                    color: AdminUi.onCard(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilterChip(
                label: const Text('Solo pedidos de viaje'),
                selected: _soloPedidosViaje,
                onSelected: (v) => setState(() => _soloPedidosViaje = v),
                selectedColor: AdminUi.accentGreen(context).withValues(alpha: 0.2),
                checkmarkColor: AdminUi.accentGreen(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _mensajesStream(),
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
                      'No se pudieron cargar mensajes: ${snap.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AdminUi.secondary(context)),
                    ),
                  ),
                );
              }

              final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(
                snap.data?.docs ?? const [],
              )
                ..sort(_compareMensajesPorFecha);
              final filtered = docs
                  .where((d) {
                    if (!_soloPedidosViaje) return true;
                    return d.data()['solicitaViaje'] == true;
                  })
                  .toList(growable: false);
              _hydrateNombres(
                filtered.map((d) => (d.data()['uid'] ?? '').toString()),
              );

              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    _soloPedidosViaje
                        ? 'Sin pedidos de viaje por asistente hoy'
                        : 'Sin mensajes registrados hoy',
                    style: TextStyle(color: AdminUi.secondary(context)),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final data = filtered[i].data();
                  final uid = (data['uid'] ?? '').toString();
                  final message = (data['message'] ?? '').toString();
                  final reply = (data['reply'] ?? '').toString();
                  final action = (data['suggestedAction'] ?? '').toString();
                  final address =
                      (data['addressQuery'] ?? '').toString().trim();
                  final solicitaViaje = data['solicitaViaje'] == true;
                  final source = (data['source'] ?? '').toString();
                  final hora = _horaDesde(data['createdAt'] as Timestamp?);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdminUi.card(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: solicitaViaje
                            ? AdminUi.accentGreen(context)
                                .withValues(alpha: 0.55)
                            : AdminUi.borderSubtle(context),
                        width: solicitaViaje ? 1.4 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _nombreFor(uid),
                                style: TextStyle(
                                  color: AdminUi.onCard(context),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              hora,
                              style: TextStyle(
                                color: AdminUi.secondary(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (solicitaViaje)
                              _chip(
                                context,
                                _etiquetaAccion(action),
                                AdminUi.accentGreen(context),
                              ),
                            _chip(context, source, AdminUi.secondary(context)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Cliente',
                          style: TextStyle(
                            color: AdminUi.secondary(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          style: TextStyle(color: AdminUi.onCard(context)),
                        ),
                        if (address.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Destino: $address',
                            style: TextStyle(
                              color: AdminUi.accentGreen(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'RAI',
                          style: TextStyle(
                            color: AdminUi.secondary(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          reply,
                          style: TextStyle(
                            color: AdminUi.onCard(context).withValues(alpha: 0.9),
                            fontSize: 13,
                          ),
                        ),
                      ],
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

  Widget _chip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
