// lib/pantallas/admin/aprobar_choferes_turismo.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

class AprobarChoferesTurismo extends StatelessWidget {
  const AprobarChoferesTurismo({super.key});

  /// La solicitud (`solicitar_turismo`) guarda códigos en `vehiculosSolicitados`;
  /// la asignación admin filtra por `vehiculos[].tipo`. Unificamos aquí sin nuevos campos.
  static List<Map<String, dynamic>> _vehiculosDesdeSolicitud(Map<String, dynamic> data) {
    const Map<String, String> labels = <String, String>{
      'carro': 'Carro Turismo',
      'jeepeta': 'Jeepeta Turismo',
      'minivan': 'Minivan Turismo',
      'bus': 'Bus Turismo',
    };

    final List<dynamic> vehiculosRaw = data['vehiculos'] as List? ?? [];
    if (vehiculosRaw.isNotEmpty) {
      return vehiculosRaw.map((dynamic v) {
        if (v is Map) {
          final String t = (v['tipo'] ?? '').toString().toLowerCase();
          return {
            'tipo': t,
            'tipoLabel': (v['tipoLabel'] ?? '').toString().isNotEmpty
                ? v['tipoLabel']
                : (labels[t] ?? v['tipo'] ?? t),
            'marca': v['marca'] ?? '',
            'modelo': v['modelo'] ?? '',
            'color': v['color'] ?? '',
            'placa': v['placa'] ?? '',
            'anio': v['anio'] ?? 0,
            'fotoUrl': v['fotoUrl'],
          };
        }
        return {
          'tipo': v.toString().toLowerCase(),
          'tipoLabel': v.toString(),
          'marca': '',
          'modelo': '',
          'color': '',
          'placa': '',
          'anio': 0,
        };
      }).toList();
    }

    final List<dynamic> codigos = data['vehiculosSolicitados'] as List? ?? [];
    return codigos.map((dynamic c) {
      final String t = c.toString().toLowerCase();
      return <String, dynamic>{
        'tipo': t,
        'tipoLabel': labels[t] ?? t,
        'marca': '',
        'modelo': '',
        'color': '',
        'placa': '',
        'anio': 0,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text(
          'Solicitudes de choferes turismo',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AdminUi.onCard(context)),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('solicitudes_turismo')
            .where('estado', isEqualTo: 'pendiente')
            .orderBy('fechaSolicitud', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AdminUi.progressAccent(context)),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No hay solicitudes pendientes',
                style: TextStyle(color: AdminUi.secondary(context)),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final List<Map<String, dynamic>> vehiculosVista =
                  _vehiculosDesdeSolicitud(data);

              return Card(
                color: AdminUi.card(context),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AdminUi.borderSubtle(context)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Text(
                        data['nombre'] ?? 'Sin nombre',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AdminUi.onCard(context),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      Text(
                        data['email'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AdminUi.secondary(context)),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Vehículos:',
                        style: TextStyle(
                          color: AdminUi.secondary(context),
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 4),

                      if (vehiculosVista.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 4),
                          child: Text(
                            '• Sin tipos de vehículo en la solicitud',
                            style: TextStyle(
                              color: Theme.of(context).brightness == Brightness.light
                                  ? Colors.deepOrange.shade800
                                  : Colors.orangeAccent,
                              fontSize: 12,
                            ),
                          ),
                        )
                      else
                        ...vehiculosVista.map((Map<String, dynamic> v) {
                          return Padding(
                            padding: const EdgeInsets.only(left: 8, bottom: 4),
                            child: Text(
                              '• ${v['tipoLabel'] ?? v['tipo']}: ${v['marca']} ${v['modelo']} ${v['anio']} (${v['color']}) - Placa: ${v['placa']}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AdminUi.muted(context),
                                fontSize: 12,
                              ),
                            ),
                          );
                        }),

                      const SizedBox(height: 8),

                      _EnlacesDocumentosTurismo(
                        documentos: data['documentos'],
                        color: AdminUi.muted(context),
                      ),

                      Text(
                        'Tel: ${data['telefono'] ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AdminUi.secondary(context)),
                      ),

                      const SizedBox(height: 12),

                      Row(
                        children: [

                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _aprobar(context, doc.id, data),
                              icon: const Icon(Icons.check, color: Colors.white),
                              label: const Text('Aprobar', style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _rechazar(context, doc.id),
                              icon: const Icon(Icons.close, color: Colors.white),
                              label: const Text('Rechazar', style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                              ),
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
    );
  }

  Future<void> _aprobar(
      BuildContext context,
      String docId,
      Map<String, dynamic> data) async {
    try {
      final String uidChofer = (data['uidChofer'] ?? '').toString().trim();
      if (uidChofer.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud inválida: falta uid del chofer.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      final user = FirebaseAuth.instance.currentUser;

      final solicitudRef = FirebaseFirestore.instance
          .collection('solicitudes_turismo')
          .doc(docId);

      batch.update(solicitudRef, {
        'estado': 'aprobado',
        'revisadoPor': user?.uid ?? '',
        'revisadoEn': FieldValue.serverTimestamp(),
      });

      final List<Map<String, dynamic>> vehiculos = _vehiculosDesdeSolicitud(data);
      if (vehiculos.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La solicitud no incluye tipos de vehículo.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final choferRef = FirebaseFirestore.instance
          .collection('choferes_turismo')
          .doc(uidChofer);

      batch.set(
        choferRef,
        {
          'uid': uidChofer,
          'nombre': data['nombre'],
          'email': data['email'],
          'telefono': data['telefono'],
          'vehiculos': vehiculos,
          'documentos': data['documentos'] ?? {},
          'estado': 'aprobado',
          'disponible': true,
          'calificacion': 0.0,
          'viajesCompletados': 0,
          'zonas': [],
          'fechaRegistro': FieldValue.serverTimestamp(),
          'verificadoPor': user?.uid ?? '',
          'verificadoEn': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Chofer aprobado'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
        ),
      );
    }
  }

  Future<void> _rechazar(
      BuildContext context,
      String docId) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: const Text(
          '¿Seguro que deseas rechazar esta solicitud? El chofer podrá enviar una nueva más adelante.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection('solicitudes_turismo')
          .doc(docId)
          .update({
        'estado': 'rechazado',
        'revisadoPor': user?.uid ?? '',
        'revisadoEn': FieldValue.serverTimestamp(),
      });

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solicitud rechazada'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
        ),
      );
    }
  }
}

class _EnlacesDocumentosTurismo extends StatelessWidget {
  final dynamic documentos;
  final Color color;

  const _EnlacesDocumentosTurismo({
    required this.documentos,
    required this.color,
  });

  static Future<void> _abrir(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (documentos is! Map) return const SizedBox.shrink();
    final Map<String, dynamic> m = Map<String, dynamic>.from(documentos as Map);
    final List<Widget> chips = [];
    void addChip(String label, String key) {
      final v = m[key]?.toString() ?? '';
      if (v.startsWith('http://') || v.startsWith('https://')) {
        chips.add(
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: ActionChip(
              label: Text(label),
              onPressed: () => _abrir(v),
            ),
          ),
        );
      }
    }

    addChip('Licencia', 'licencia');
    addChip('Seguro', 'seguro');
    addChip('Foto vehículo', 'fotoVehiculo');

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Documentos:',
            style: TextStyle(
              color: color.withValues(alpha: 0.95),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          Wrap(children: chips),
        ],
      ),
    );
  }
}