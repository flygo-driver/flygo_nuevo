// lib/pantallas/admin/revision_documentos_admin.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class RevisionDocumentosAdmin extends StatefulWidget {
  const RevisionDocumentosAdmin({super.key});

  @override
  State<RevisionDocumentosAdmin> createState() =>
      _RevisionDocumentosAdminState();
}

class _RevisionDocumentosAdminState
    extends State<RevisionDocumentosAdmin> {
  final _db = FirebaseFirestore.instance;

  Future<void> _aprobar(String uid) async {
    await _db.collection('usuarios').doc(uid).set({
      'docsEstado': 'aprobado',
      'documentosCompletos': true,
      'docsComentarioAdmin': FieldValue.delete(),
      'docsVerificadoEn': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Aprobado')),
    );
  }

  Future<void> _rechazar(String uid) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Rechazar documentos',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Escribe la razón del rechazo…',
            hintStyle: TextStyle(color: Colors.white54),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _db.collection('usuarios').doc(uid).set({
      'docsEstado': 'rechazado',
      'documentosCompletos': false,
      'docsComentarioAdmin': controller.text.trim(),
      'docsRevisadoEn': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('❌ Marcado como rechazado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Revisión de documentos',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db
            .collection('usuarios')
            .where('docsEstado', isEqualTo: 'en_revision')
            .orderBy('docsEnviadosEn', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child:
                  CircularProgressIndicator(color: Colors.greenAccent),
            );
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No hay expedientes en revisión.',
                  style: TextStyle(color: Colors.white70)),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final d = docs[i].data();
              final uid = docs[i].id;
              final nombre = (d['nombre'] ?? '').toString();
              final email = (d['email'] ?? '').toString();
              final map = (d['docs'] as Map?) ?? {};
              final licenciaUrl =
                  (map['licenciaUrl'] ?? '').toString();
              final matriculaUrl =
                  (map['matriculaUrl'] ?? '').toString();
              final seguroUrl =
                  (map['seguroUrl'] ?? '').toString();

              Widget thumb(String label, String url) => Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171717),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          AspectRatio(
                            aspectRatio: 4 / 3,
                            child: GestureDetector(
                              onTap: url.isEmpty
                                  ? null
                                  : () async {
                                      await launchUrl(Uri.parse(url),
                                          mode: LaunchMode
                                              .externalApplication);
                                    },
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(8),
                                child: Container(
                                  color: const Color(0xFF262626),
                                  child: url.isEmpty
                                      ? const Center(
                                          child: Icon(
                                              Icons.broken_image,
                                              color:
                                                  Colors.white24))
                                      : Image.network(url,
                                          fit: BoxFit.cover),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(url.isEmpty ? 'Falta' : 'OK',
                              style: TextStyle(
                                color: url.isEmpty
                                    ? const Color(0xFFFF5252)
                                    : Colors.greenAccent,
                              )),
                        ],
                      ),
                    ),
                  );

              return Card(
                color: const Color(0xFF121212),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              nombre.isNotEmpty ? nombre : uid,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Thumbnails
                      Row(
                        children: [
                          thumb('Licencia', licenciaUrl),
                          const SizedBox(width: 10),
                          thumb('Matrícula', matriculaUrl),
                          const SizedBox(width: 10),
                          thumb('Seguro', seguroUrl),
                        ],
                      ),

                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _rechazar(uid),
                              icon: const Icon(Icons.close),
                              label: const Text('Rechazar'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    const Color(0xFFFF5252),
                                side: const BorderSide(
                                    color: Color(0xFFFF5252)),
                                textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _aprobar(uid),
                              icon: const Icon(Icons.check),
                              label: const Text('Aprobar'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.green,
                                textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700),
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
