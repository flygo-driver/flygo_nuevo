// Auditoría ADM: historial de config + log admin_audit (paginado CF).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../servicios/admin_dashboard_service.dart';
import '../../widgets/admin_app_bar.dart';
import 'package:flygo_nuevo/widgets/admin_guia_uso.dart';
import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

class AdminAuditoriaPage extends StatefulWidget {
  const AdminAuditoriaPage({super.key});

  @override
  State<AdminAuditoriaPage> createState() => _AdminAuditoriaPageState();
}

class _AdminAuditoriaPageState extends State<AdminAuditoriaPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _fmt = DateFormat('dd/MM/yy HH:mm');

  bool _cargandoAudit = false;
  List<AdminAuditItem> _audit = const [];
  String? _auditCursor;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (_tabs.index == 1 && _audit.isEmpty) _cargarAudit();
    });
    _cargarAudit();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargarAudit({bool mas = false}) async {
    if (_cargandoAudit) return;
    setState(() => _cargandoAudit = true);
    try {
      final batch = await AdminDashboardService.listAudit(
        limit: 50,
        cursor: mas ? _auditCursor : null,
      );
      if (!mounted) return;
      setState(() {
        if (mas) {
          _audit = [..._audit, ...batch];
        } else {
          _audit = batch;
        }
        _auditCursor = batch.isNotEmpty ? batch.last.id : null;
      });
    } finally {
      if (mounted) setState(() => _cargandoAudit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AdminAppBar(
        guiaId: AdminGuiaIds.auditoria,
        title: 'Auditoría',
        bottom: TabBar(
          controller: _tabs,
          labelColor: AdminUi.accentGreen(context),
          unselectedLabelColor: AdminUi.tabUnselected(context),
          indicatorColor: AdminUi.accentGreen(context),
          tabs: const [
            Tab(text: 'Cambios config'),
            Tab(text: 'Log sistema'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AdminUi.iconStandard(context)),
            onPressed: () {
              if (_tabs.index == 1) _cargarAudit();
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('configuraciones_historial')
                .orderBy('createdAt', descending: true)
                .limit(80)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(
                    color: AdminUi.progressAccent(context),
                  ),
                );
              }
              final docs = snap.data?.docs ?? const [];
              if (docs.isEmpty) {
                return Center(
                  child: Text('Sin historial',
                      style: TextStyle(color: AdminUi.secondary(context))),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  final key = (d['configKey'] ?? '').toString();
                  final motivo = (d['motivo'] ?? '').toString();
                  final by = (d['changedBy'] ?? '').toString();
                  final ts = d['createdAt'];
                  String cuando = '';
                  if (ts is Timestamp) {
                    cuando = _fmt.format(ts.toDate().toLocal());
                  }
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdminUi.card(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AdminUi.borderSubtle(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(key,
                            style: TextStyle(
                              color: AdminUi.onCard(context),
                              fontWeight: FontWeight.w700,
                            )),
                        if (motivo.isNotEmpty)
                          Text(motivo,
                              style: TextStyle(
                                  color: AdminUi.secondary(context),
                                  fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          '$cuando · $by',
                          style: TextStyle(
                              color: AdminUi.muted(context), fontSize: 11),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          _auditTab(),
        ],
      ),
    );
  }

  Widget _auditTab() {
    if (_cargandoAudit && _audit.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: AdminUi.progressAccent(context)),
      );
    }
    if (_audit.isEmpty) {
      return Center(
        child: Text('Sin registros de auditoría',
            style: TextStyle(color: AdminUi.secondary(context))),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _audit.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        if (i == _audit.length) {
          return TextButton(
            onPressed: _cargandoAudit ? null : () => _cargarAudit(mas: true),
            child: Text(_cargandoAudit ? 'Cargando…' : 'Cargar más'),
          );
        }
        final a = _audit[i];
        final cuando =
            a.ts != null ? _fmt.format(a.ts!.toLocal()) : '';
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AdminUi.card(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AdminUi.borderSubtle(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.action,
                  style: TextStyle(
                    color: AdminUi.onCard(context),
                    fontWeight: FontWeight.w700,
                  )),
              Text(
                '${a.resourceType} · ${a.resourceId}',
                style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
              ),
              Text(
                '$cuando · ${a.actorUid}',
                style: TextStyle(color: AdminUi.muted(context), fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}
