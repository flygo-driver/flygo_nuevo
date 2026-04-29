// lib/pantallas/admin/aprobar_choferes_turismo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';

/// La solicitud (`solicitar_turismo`) guarda códigos en `vehiculosSolicitados`;
/// la asignación admin filtra por `vehiculos[].tipo`. Unificamos aquí sin nuevos campos.
List<Map<String, dynamic>> _vehiculosDesdeSolicitud(Map<String, dynamic> data) {
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

class AprobarChoferesTurismo extends StatefulWidget {
  const AprobarChoferesTurismo({super.key});

  @override
  State<AprobarChoferesTurismo> createState() => _AprobarChoferesTurismoState();
}

class _AprobarChoferesTurismoState extends State<AprobarChoferesTurismo> {
  final Set<String> _idsProcesando = <String>{};

  String _mensajeFirebase(FirebaseException e) {
    final m = e.message?.trim();
    if (m != null && m.isNotEmpty) return m;
    return e.code;
  }

  Future<void> _iniciarAprobar(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) async {
    if (_idsProcesando.contains(docId)) return;

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

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AdminUi.dialogSurface(ctx),
          title: Text(
            'Aprobar solicitud',
            style: TextStyle(color: AdminUi.onCard(ctx)),
          ),
          content: Text(
            'Se registrará al chofer en turismo y quedará disponible para asignación. '
            '¿Confirmas la aprobación?',
            style: TextStyle(color: AdminUi.secondary(ctx)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar',
                  style: TextStyle(color: AdminUi.secondary(ctx))),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700),
              child: const Text('Aprobar'),
            ),
          ],
        );
      },
    );
    if (ok != true || !context.mounted) return;

    await _commitAprobar(context, docId, data, uidChofer, vehiculos);
  }

  Future<void> _commitAprobar(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
    String uidChofer,
    List<Map<String, dynamic>> vehiculos,
  ) async {
    if (_idsProcesando.contains(docId)) return;
    setState(() => _idsProcesando.add(docId));

    try {
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
          content: Text('Chofer aprobado'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensajeFirebase(e)),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _idsProcesando.remove(docId));
    }
  }

  Future<void> _iniciarRechazar(BuildContext context, String docId) async {
    if (_idsProcesando.contains(docId)) return;

    final motivoCtrl = TextEditingController();
    try {
      final bool ok = await showDialog<bool>(
            context: context,
            builder: (ctx) {
              final cs = Theme.of(ctx).colorScheme;
              return AlertDialog(
                backgroundColor: AdminUi.dialogSurface(ctx),
                title: Text(
                  'Rechazar solicitud',
                  style: TextStyle(color: AdminUi.onCard(ctx)),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'El chofer podrá enviar una nueva solicitud más adelante.',
                        style: TextStyle(color: AdminUi.secondary(ctx)),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: motivoCtrl,
                        style: TextStyle(color: AdminUi.onCard(ctx)),
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Motivo (opcional, auditoría interna)',
                          hintStyle: TextStyle(
                              color: AdminUi.secondary(ctx)
                                  .withValues(alpha: 0.75)),
                          filled: true,
                          fillColor: AdminUi.inputFill(ctx),
                          border: OutlineInputBorder(
                            borderRadius:
                                const BorderRadius.all(Radius.circular(8)),
                            borderSide:
                                BorderSide(color: AdminUi.borderSubtle(ctx)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                const BorderRadius.all(Radius.circular(8)),
                            borderSide:
                                BorderSide(color: AdminUi.borderSubtle(ctx)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                const BorderRadius.all(Radius.circular(8)),
                            borderSide:
                                BorderSide(color: cs.primary, width: 1.4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('Cancelar',
                        style: TextStyle(color: AdminUi.secondary(ctx))),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700),
                    child: const Text('Rechazar'),
                  ),
                ],
              );
            },
          ) ??
          false;
      if (!ok || !context.mounted) return;

      setState(() => _idsProcesando.add(docId));
      final user = FirebaseAuth.instance.currentUser;
      final motivo = motivoCtrl.text.trim();
      final Map<String, dynamic> patch = {
        'estado': 'rechazado',
        'revisadoPor': user?.uid ?? '',
        'revisadoEn': FieldValue.serverTimestamp(),
      };
      if (motivo.isNotEmpty) {
        patch['motivoRechazo'] = motivo;
      }

      try {
        await FirebaseFirestore.instance
            .collection('solicitudes_turismo')
            .doc(docId)
            .update(patch);

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud rechazada'),
            backgroundColor: Colors.orange,
          ),
        );
      } on FirebaseException catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensajeFirebase(e)),
            backgroundColor: Colors.red,
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) setState(() => _idsProcesando.remove(docId));
      }
    } finally {
      motivoCtrl.dispose();
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
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text(
          'Solicitudes de choferes turismo',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AdminUi.onCard(context)),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('solicitudes_turismo')
            .where('estado', isEqualTo: 'pendiente')
            .orderBy('fechaSolicitud', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                  color: AdminUi.progressAccent(context)),
            );
          }

          if (snapshot.hasError) {
            final err = snapshot.error;
            final String msg = err is FirebaseException
                ? _mensajeFirebase(err)
                : err.toString();
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off_outlined,
                        size: 48, color: AdminUi.secondary(context)),
                    const SizedBox(height: 12),
                    Text(
                      'No se pudieron cargar las solicitudes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AdminUi.onCard(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      msg,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AdminUi.secondary(context), fontSize: 13),
                    ),
                  ],
                ),
              ),
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
              final data = doc.data();
              final List<Map<String, dynamic>> vehiculosVista =
                  _vehiculosDesdeSolicitud(data);
              final bool procesando = _idsProcesando.contains(doc.id);

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
                        data['nombre']?.toString() ?? 'Sin nombre',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AdminUi.onCard(context),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        data['email']?.toString() ?? '',
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
                              color: Theme.of(context).brightness ==
                                      Brightness.light
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
                              onPressed: procesando
                                  ? null
                                  : () =>
                                      _iniciarAprobar(context, doc.id, data),
                              icon: procesando
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color:
                                            Colors.white.withValues(alpha: 0.9),
                                      ),
                                    )
                                  : const Icon(Icons.check,
                                      color: Colors.white),
                              label: Text(
                                procesando ? 'Procesando…' : 'Aprobar',
                                style: const TextStyle(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: procesando
                                  ? null
                                  : () => _iniciarRechazar(context, doc.id),
                              icon:
                                  const Icon(Icons.close, color: Colors.white),
                              label: const Text('Rechazar',
                                  style: TextStyle(color: Colors.white)),
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
