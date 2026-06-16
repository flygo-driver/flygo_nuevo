// Operaciones Bola Pueblo / Bola Ahorro — moderación ADM en tiempo real.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

class AdminBolaPuebloOps extends StatefulWidget {
  const AdminBolaPuebloOps({super.key});

  @override
  State<AdminBolaPuebloOps> createState() => _AdminBolaPuebloOpsState();
}

class _AdminBolaPuebloOpsState extends State<AdminBolaPuebloOps>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream(String filtro) {
    switch (filtro) {
      case 'abiertas':
        return _db
            .collection('bolas_pueblo')
            .where('estado', whereIn: ['abierta', 'acordada'])
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots();
      case 'en_curso':
        return _db
            .collection('bolas_pueblo')
            .where('estado', isEqualTo: 'en_curso')
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots();
      case 'transferencias':
        return _db
            .collection('bolas_pueblo')
            .where('estado', isEqualTo: 'finalizada')
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots();
      default:
        return _db
            .collection('bolas_pueblo')
            .orderBy('createdAt', descending: true)
            .limit(100)
            .snapshots();
    }
  }

  bool _esTransferenciaPendiente(Map<String, dynamic> d) {
    final metodo = (d['metodoPago'] ?? '').toString().toLowerCase();
    if (metodo != 'transferencia') return false;
    return d['transferenciaConfirmada'] != true;
  }

  @override
  Widget build(BuildContext context) {
    final filtros = ['abiertas', 'en_curso', 'transferencias', 'todas'];
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        title: Text('Bola Pueblo — Operaciones',
            style: TextStyle(color: AdminUi.onCard(context))),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: AdminUi.accentGreen(context),
          unselectedLabelColor: AdminUi.tabUnselected(context),
          indicatorColor: AdminUi.accentGreen(context),
          tabs: const [
            Tab(text: 'Abiertas'),
            Tab(text: 'En ruta'),
            Tab(text: 'Transferencias'),
            Tab(text: 'Recientes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: filtros.map((f) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stream(f),
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
                      'Error: ${snap.error}\nSi falta índice, despliega firestore.indexes.json',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AdminUi.secondary(context)),
                    ),
                  ),
                );
              }
              var docs = snap.data?.docs ?? const [];
              if (f == 'transferencias') {
                docs = docs.where((d) => _esTransferenciaPendiente(d.data())).toList();
              }
              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    'Sin publicaciones en esta cola',
                    style: TextStyle(color: AdminUi.secondary(context)),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _BolaTile(id: docs[i].id, data: docs[i].data()),
              );
            },
          );
        }).toList(),
      ),
    );
  }
}

class _BolaTile extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;

  const _BolaTile({required this.id, required this.data});

  @override
  Widget build(BuildContext context) {
    final estado = (data['estado'] ?? '').toString();
    final origen = (data['origen'] ?? '—').toString();
    final destino = (data['destino'] ?? '—').toString();
    final monto = (data['montoAcordadoRd'] ?? data['montoSugeridoRd'] ?? 0) as num;
    final tipo = (data['tipo'] ?? '').toString();

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
              Text(
                estado.toUpperCase(),
                style: TextStyle(
                  color: AdminUi.accentGreen(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              if (tipo.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(tipo, style: TextStyle(color: AdminUi.secondary(context), fontSize: 12)),
              ],
              const Spacer(),
              Text(
                'RD\$ ${monto.toStringAsFixed(0)}',
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('$origen → $destino',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AdminUi.onCard(context))),
          const SizedBox(height: 6),
          Text(
            'ID ${id.length > 8 ? id.substring(0, 8) : id}',
            style: TextStyle(color: AdminUi.muted(context), fontSize: 11),
          ),
        ],
      ),
    );
  }
}
