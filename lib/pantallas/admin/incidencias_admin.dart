import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_ui_theme.dart';

class IncidenciasAdminPage extends StatefulWidget {
  const IncidenciasAdminPage({super.key});

  @override
  State<IncidenciasAdminPage> createState() => _IncidenciasAdminPageState();
}

class _IncidenciasAdminPageState extends State<IncidenciasAdminPage> {
  String _fEstado = 'todas';
  String _fPrioridad = 'todas';
  String _fTipo = 'todas';
  String _q = '';

  static const _prioridades = <String>['baja', 'media', 'alta'];
  static const _tipos = <String>['viaje', 'usuario', 'pago'];

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    return FirebaseFirestore.instance
        .collection('incidencias')
        .orderBy('createdAt', descending: true)
        .limit(300)
        .snapshots();
  }

  Future<void> _crearIncidencia() async {
    final tipo = ValueNotifier<String>('viaje');
    final prioridad = ValueNotifier<String>('media');
    final desc = TextEditingController();
    final refId = TextEditingController();
    final asignadoA = TextEditingController();
    final formKey = GlobalKey<FormState>();

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AdminUi.dialogSurface(ctx),
          title: Text('Nueva incidencia', style: TextStyle(color: AdminUi.onCard(ctx))),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<String>(
                    valueListenable: tipo,
                    builder: (_, v, __) => DropdownButtonFormField<String>(
                      value: v,
                      items: _tipos
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (nv) {
                        if (nv != null) tipo.value = nv;
                      },
                      decoration: const InputDecoration(labelText: 'Tipo'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<String>(
                    valueListenable: prioridad,
                    builder: (_, v, __) => DropdownButtonFormField<String>(
                      value: v,
                      items: _prioridades
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (nv) {
                        if (nv != null) prioridad.value = nv;
                      },
                      decoration: const InputDecoration(labelText: 'Prioridad'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: desc,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Descripcion',
                      hintText: 'Describe el problema y contexto operativo',
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.length < 8) return 'Minimo 8 caracteres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: refId,
                    decoration: const InputDecoration(
                      labelText: 'ID relacionado (opcional)',
                      hintText: 'viajeId / pagoId / uid',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: asignadoA,
                    decoration: const InputDecoration(
                      labelText: 'Asignar a UID (opcional)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('incidencias').add({
        'tipo': tipo.value,
        'descripcion': desc.text.trim(),
        'estado': 'abierta',
        'prioridad': prioridad.value,
        'creadoPor': uid,
        'asignadoA': asignadoA.text.trim().isEmpty ? null : asignadoA.text.trim(),
        'resueltoPor': null,
        'refId': refId.text.trim().isEmpty ? null : refId.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'resolvedAt': null,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incidencia creada')),
      );
    } finally {
      tipo.dispose();
      prioridad.dispose();
      desc.dispose();
      refId.dispose();
      asignadoA.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      appBar: AppBar(
        title: const Text('Incidencias (soporte)'),
        actions: [
          IconButton(
            tooltip: 'Crear incidencia',
            onPressed: _crearIncidencia,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterDrop(
                  label: 'Estado',
                  value: _fEstado,
                  items: const ['todas', 'abierta', 'en_proceso', 'resuelta'],
                  onChanged: (v) => setState(() => _fEstado = v),
                ),
                _FilterDrop(
                  label: 'Prioridad',
                  value: _fPrioridad,
                  items: const ['todas', 'baja', 'media', 'alta'],
                  onChanged: (v) => setState(() => _fPrioridad = v),
                ),
                _FilterDrop(
                  label: 'Tipo',
                  value: _fTipo,
                  items: const ['todas', 'viaje', 'usuario', 'pago'],
                  onChanged: (v) => setState(() => _fTipo = v),
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                    decoration: const InputDecoration(
                      hintText: 'Buscar descripcion / refId / UID',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Error cargando incidencias: ${snap.error}',
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final docs = (snap.data?.docs ?? []).where((d) {
                  final m = d.data();
                  final estado = (m['estado'] ?? '').toString().toLowerCase();
                  final prioridad = (m['prioridad'] ?? '').toString().toLowerCase();
                  final tipo = (m['tipo'] ?? '').toString().toLowerCase();
                  if (_fEstado != 'todas' && estado != _fEstado) return false;
                  if (_fPrioridad != 'todas' && prioridad != _fPrioridad) return false;
                  if (_fTipo != 'todas' && tipo != _fTipo) return false;
                  if (_q.isEmpty) return true;
                  final blob = '${m['descripcion'] ?? ''} ${m['refId'] ?? ''} ${m['creadoPor'] ?? ''} ${m['asignadoA'] ?? ''}'
                      .toLowerCase();
                  return blob.contains(_q);
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text('Sin incidencias para el filtro actual'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _IncidenciaTile(doc: docs[i]),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearIncidencia,
        icon: const Icon(Icons.add),
        label: const Text('Nueva incidencia'),
      ),
    );
  }
}

class _FilterDrop extends StatelessWidget {
  const _FilterDrop({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(labelText: label),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _IncidenciaTile extends StatefulWidget {
  const _IncidenciaTile({required this.doc});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  State<_IncidenciaTile> createState() => _IncidenciaTileState();
}

class _IncidenciaTileState extends State<_IncidenciaTile> {
  bool _busy = false;

  Future<void> _asignar() async {
    final ctrl = TextEditingController(
      text: (widget.doc.data()['asignadoA'] ?? '').toString(),
    );
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Asignar incidencia'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'UID admin'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      );
      if (ok != true) return;
      final uid = ctrl.text.trim();
      if (uid.isEmpty) return;
      setState(() => _busy = true);
      await widget.doc.reference.update({
        'asignadoA': uid,
        'estado': 'en_proceso',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } finally {
      ctrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolver() async {
    final nota = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Resolver incidencia'),
          content: TextField(
            controller: nota,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Nota de resolucion (opcional)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Resolver')),
          ],
        ),
      );
      if (ok != true) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      setState(() => _busy = true);
      await widget.doc.reference.update({
        'estado': 'resuelta',
        'resueltoPor': uid,
        'notaResolucion': nota.text.trim().isEmpty ? null : nota.text.trim(),
        'resolvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } finally {
      nota.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.doc.data();
    final estado = (d['estado'] ?? 'abierta').toString();
    final prioridad = (d['prioridad'] ?? 'media').toString();
    final tipo = (d['tipo'] ?? 'viaje').toString();
    final asignadoA = (d['asignadoA'] ?? '').toString();
    final createdAt = d['createdAt'];
    final dt = createdAt is Timestamp ? createdAt.toDate() : null;

    Color badgeColor;
    switch (prioridad) {
      case 'alta':
        badgeColor = Colors.redAccent;
        break;
      case 'baja':
        badgeColor = Colors.blueAccent;
        break;
      default:
        badgeColor = Colors.orangeAccent;
    }

    return Container(
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip(tipo, Colors.tealAccent.shade700),
                    _chip(estado, Colors.white70),
                    _chip(prioridad, badgeColor),
                  ],
                ),
              ),
              Text(dt == null ? '—' : dt.toString().substring(0, 16)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (d['descripcion'] ?? '').toString(),
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'refId: ${(d['refId'] ?? '—')} | creadoPor: ${(d['creadoPor'] ?? '—')} | asignadoA: ${asignadoA.isEmpty ? '—' : asignadoA}',
            style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _asignar,
                icon: const Icon(Icons.assignment_ind),
                label: const Text('Asignar'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _busy || estado == 'resuelta' ? null : _resolver,
                icon: _busy
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle),
                label: const Text('Resolver'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}
