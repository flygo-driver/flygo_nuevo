// Alertas operativas ADM — tiempo real desde admin_alertas.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../servicios/admin_dashboard_service.dart';
import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

class AdminAlertasPage extends StatefulWidget {
  const AdminAlertasPage({super.key});

  @override
  State<AdminAlertasPage> createState() => _AdminAlertasPageState();
}

class _AdminAlertasPageState extends State<AdminAlertasPage> {
  bool _soloNoLeidas = true;
  bool _marcando = false;

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    if (_soloNoLeidas) {
      return FirebaseFirestore.instance
          .collection('admin_alertas')
          .where('leida', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(150)
          .snapshots();
    }
    return FirebaseFirestore.instance
        .collection('admin_alertas')
        .orderBy('createdAt', descending: true)
        .limit(150)
        .snapshots();
  }

  Color _colorSeveridad(String s) {
    switch (s) {
      case 'critical':
        return Colors.redAccent;
      case 'warning':
        return Colors.orangeAccent;
      default:
        return AdminUi.accentGreen(context);
    }
  }

  Future<void> _marcarLeida(String id) async {
    try {
      await AdminDashboardService.marcarAlertaLeida(id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo marcar: $e')),
        );
      }
    }
  }

  Future<void> _marcarTodas() async {
    if (_marcando) return;
    setState(() => _marcando = true);
    try {
      final n = await AdminDashboardService.marcarTodasAlertasLeidas();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marcadas $n alertas como leídas')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _marcando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        title: Text('Alertas operativas',
            style: TextStyle(color: AdminUi.onCard(context))),
        actions: [
          IconButton(
            tooltip: 'Marcar todas leídas',
            onPressed: _marcando ? null : _marcarTodas,
            icon: _marcando
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AdminUi.iconStandard(context),
                    ),
                  )
                : Icon(Icons.done_all, color: AdminUi.iconStandard(context)),
          ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            title: Text('Solo no leídas',
                style: TextStyle(color: AdminUi.onCard(context))),
            value: _soloNoLeidas,
            onChanged: (v) => setState(() => _soloNoLeidas = v),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream(),
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
                    child: Text(
                      'Error: ${snap.error}',
                      style: TextStyle(color: AdminUi.secondary(context)),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'Sin alertas pendientes',
                      style: TextStyle(color: AdminUi.secondary(context)),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final d = docs[i];
                    final data = d.data();
                    final leida = data['leida'] == true;
                    final sev = (data['severidad'] ?? 'info').toString();
                    final titulo = (data['titulo'] ?? 'Alerta').toString();
                    final msg = (data['mensaje'] ?? '').toString();
                    final tipo = (data['tipo'] ?? '').toString();
                    final ts = data['createdAt'];
                    String cuando = '';
                    if (ts is Timestamp) {
                      final dt = ts.toDate().toLocal();
                      cuando =
                          '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                    }

                    return Material(
                      color: AdminUi.card(context),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: leida ? null : () => _marcarLeida(d.id),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: leida
                                  ? AdminUi.borderSubtle(context)
                                  : _colorSeveridad(sev).withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    leida ? Icons.mark_email_read : Icons.notifications_active,
                                    color: _colorSeveridad(sev),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      titulo,
                                      style: TextStyle(
                                        color: AdminUi.onCard(context),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (cuando.isNotEmpty)
                                    Text(cuando,
                                        style: TextStyle(
                                            color: AdminUi.muted(context),
                                            fontSize: 11)),
                                ],
                              ),
                              if (tipo.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(tipo,
                                    style: TextStyle(
                                        color: AdminUi.secondary(context),
                                        fontSize: 11)),
                              ],
                              if (msg.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  msg,
                                  maxLines: 6,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AdminUi.secondary(context),
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                              if (!leida) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Toca para marcar como leída',
                                  style: TextStyle(
                                    color: AdminUi.accentGreen(context),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
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
            ),
          ),
        ],
      ),
    );
  }
}
