// Catálogo destinos turísticos — extras editables (Firestore + catálogo estático).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../servicios/turismo_catalogo_rd.dart';
import '../../servicios/turismo_destinos_repo.dart';
import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

class AdminTurismoDestinos extends StatefulWidget {
  const AdminTurismoDestinos({super.key});

  @override
  State<AdminTurismoDestinos> createState() => _AdminTurismoDestinosState();
}

class _AdminTurismoDestinosState extends State<AdminTurismoDestinos> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        title: Text('Destinos turismo',
            style: TextStyle(color: AdminUi.onCard(context))),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: AdminUi.iconStandard(context)),
            onPressed: () => _dialogoDestino(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AdminUi.infoFill(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminUi.infoBorder(context)),
            ),
            child: Text(
              'Catálogo base: ${TurismoCatalogoRD.lugares.length} destinos en código. '
              'Aquí agregas extras en Firestore (sin redeploy).',
              style: TextStyle(color: AdminUi.secondary(context), height: 1.35),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Destinos Firestore',
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('turismo_destinos')
                .orderBy('nombre')
                .limit(200)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: CircularProgressIndicator(
                      color: AdminUi.progressAccent(context),
                    ),
                  ),
                );
              }
              final docs = snap.data?.docs ?? const [];
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Sin destinos extra. Toca + para agregar.',
                    style: TextStyle(color: AdminUi.secondary(context)),
                  ),
                );
              }
              return Column(
                children: docs.map((d) {
                  final m = d.data();
                  final activo = m['activo'] != false;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdminUi.card(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AdminUi.borderSubtle(context)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (m['nombre'] ?? '').toString(),
                                style: TextStyle(
                                  color: AdminUi.onCard(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${m['ciudad']} · ${m['subtipo']}',
                                style: TextStyle(
                                  color: AdminUi.secondary(context),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: activo,
                          onChanged: (v) =>
                              TurismoDestinosRepo.setActivo(d.id, v),
                        ),
                        IconButton(
                          icon: Icon(Icons.edit,
                              color: AdminUi.iconStandard(context)),
                          onPressed: () => _dialogoDestino(context, docId: d.id, data: m),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _dialogoDestino(
    BuildContext context, {
    String? docId,
    Map<String, dynamic>? data,
  }) async {
    final idCtrl = TextEditingController(text: (data?['id'] ?? '').toString());
    final nombreCtrl =
        TextEditingController(text: (data?['nombre'] ?? '').toString());
    final ciudadCtrl =
        TextEditingController(text: (data?['ciudad'] ?? '').toString());
    final subtipoCtrl = TextEditingController(
        text: (data?['subtipo'] ?? TurismoCatalogoRD.playa).toString());
    final latCtrl =
        TextEditingController(text: (data?['lat'] ?? '').toString());
    final lonCtrl =
        TextEditingController(text: (data?['lon'] ?? '').toString());
    final descCtrl =
        TextEditingController(text: (data?['descripcion'] ?? '').toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminUi.dialogSurface(ctx),
        title: Text(
          docId == null ? 'Nuevo destino' : 'Editar destino',
          style: TextStyle(color: AdminUi.onCard(ctx)),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(labelText: 'ID único')),
              TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre')),
              TextField(
                  controller: ciudadCtrl,
                  decoration: const InputDecoration(labelText: 'Ciudad')),
              TextField(
                  controller: subtipoCtrl,
                  decoration: const InputDecoration(labelText: 'Subtipo')),
              TextField(
                  controller: latCtrl,
                  decoration: const InputDecoration(labelText: 'Latitud'),
                  keyboardType: TextInputType.number),
              TextField(
                  controller: lonCtrl,
                  decoration: const InputDecoration(labelText: 'Longitud'),
                  keyboardType: TextInputType.number),
              TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                  maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );

    if (ok != true) return;
    final lat = double.tryParse(latCtrl.text.trim());
    final lon = double.tryParse(lonCtrl.text.trim());
    if (lat == null || lon == null || nombreCtrl.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nombre, lat y lon son requeridos')),
        );
      }
      return;
    }

    final lugar = TurismoLugar(
      id: idCtrl.text.trim().isEmpty
          ? 'fs_${DateTime.now().millisecondsSinceEpoch}'
          : idCtrl.text.trim(),
      nombre: nombreCtrl.text.trim(),
      ciudad: ciudadCtrl.text.trim(),
      subtipo: subtipoCtrl.text.trim(),
      lat: lat,
      lon: lon,
      descripcion: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
    );

    try {
      await TurismoDestinosRepo.guardar(docId: docId, lugar: lugar);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Destino guardado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}
