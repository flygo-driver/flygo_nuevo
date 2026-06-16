// Monitor asistente RAI — uso diario en vivo desde rai_asistente_usage.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

class AdminRaiMonitor extends StatefulWidget {
  const AdminRaiMonitor({super.key});

  @override
  State<AdminRaiMonitor> createState() => _AdminRaiMonitorState();
}

class _AdminRaiMonitorState extends State<AdminRaiMonitor> {
  static const int _dailyLimit = 50;
  static const int _listLimit = 80;

  final Map<String, String> _nombreCache = <String, String>{};

  String _todayKey() => DateTime.now().toIso8601String().substring(0, 10);

  Stream<QuerySnapshot<Map<String, dynamic>>> _usageStream() {
    return FirebaseFirestore.instance
        .collection('rai_asistente_usage')
        .where('day', isEqualTo: _todayKey())
        .orderBy('count', descending: true)
        .limit(_listLimit)
        .snapshots();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        title: Text('Asistente RAI',
            style: TextStyle(color: AdminUi.onCard(context))),
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
          final totalCalls =
              items.fold<int>(0, (acc, i) => acc + i.count);
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
      ),
    );
  }
}
