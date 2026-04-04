import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_ui_theme.dart';

class RevisionDocumentosAdmin extends StatefulWidget {
  const RevisionDocumentosAdmin({super.key});

  @override
  State<RevisionDocumentosAdmin> createState() =>
      _RevisionDocumentosAdminState();
}

class _RevisionDocumentosAdminState
    extends State<RevisionDocumentosAdmin> {
  final _db = FirebaseFirestore.instance;
  final Set<String> _uidsProcesando = <String>{};

  Future<void> _aprobar(String uid) async {
    if (_uidsProcesando.contains(uid)) return;
    setState(() => _uidsProcesando.add(uid));
    try {
      await _db.collection('usuarios').doc(uid).set({
        'docsEstado': 'aprobado',
        'estadoDocumentos': 'aprobado',
        'documentosCompletos': true,
        'puedeRecibirViajes': true,
        'disponible': true,
        'docsComentarioAdmin': FieldValue.delete(),
        'docsVerificadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Aprobado')),
      );
    } finally {
      if (mounted) setState(() => _uidsProcesando.remove(uid));
    }
  }

  Future<void> _rechazar(String uid) async {
    if (_uidsProcesando.contains(uid)) return;
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: AdminUi.dialogSurface(ctx),
          title: Text('Rechazar documentos', style: TextStyle(color: AdminUi.onCard(ctx))),
          content: TextField(
            controller: controller,
            maxLines: 4,
            style: TextStyle(color: AdminUi.onCard(ctx)),
            decoration: InputDecoration(
              hintText: 'Escribe la razón del rechazo…',
              hintStyle: TextStyle(color: AdminUi.secondary(ctx).withValues(alpha: 0.85)),
              filled: true,
              fillColor: AdminUi.inputFill(ctx),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AdminUi.borderSubtle(ctx)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AdminUi.borderSubtle(ctx)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.primary, width: 1.4),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancelar', style: TextStyle(color: AdminUi.secondary(ctx)))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Rechazar'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    setState(() => _uidsProcesando.add(uid));
    try {
      await _db.collection('usuarios').doc(uid).set({
        'docsEstado': 'rechazado',
        'estadoDocumentos': 'rechazado',
        'documentosCompletos': false,
        'puedeRecibirViajes': false,
        'disponible': false,
        'docsComentarioAdmin': controller.text.trim(),
        'docsRevisadoEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Marcado como rechazado')),
      );
    } finally {
      if (mounted) setState(() => _uidsProcesando.remove(uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text('Revisión de documentos', style: TextStyle(color: AdminUi.onCard(context))),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db
            .collection('usuarios')
            .where('docsEstado', isEqualTo: 'en_revision')
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AdminUi.progressAccent(context)),
            );
          }
          final docs = (snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            ..sort((a, b) {
              final ta = (a.data()['docsEnviadosEn'] as Timestamp?)?.toDate() ??
                  (a.data()['actualizadoEn'] as Timestamp?)?.toDate() ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              final tb = (b.data()['docsEnviadosEn'] as Timestamp?)?.toDate() ??
                  (b.data()['actualizadoEn'] as Timestamp?)?.toDate() ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              return tb.compareTo(ta);
            });
          if (docs.isEmpty) {
            return Center(
              child: Text('No hay expedientes en revisión.',
                  style: TextStyle(color: AdminUi.secondary(context))),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: 12),
            itemBuilder: (BuildContext context, int i) {
              final d = docs[i].data();
              final uid = docs[i].id;
              final nombre = (d['nombre'] ?? '').toString();
              final email = (d['email'] ?? '').toString();
              final map = (d['docs'] as Map?) ?? {};
              final licenciaUrl = (map['licenciaUrl'] ?? '').toString();
              final matriculaUrl = (map['matriculaUrl'] ?? '').toString();
              final seguroUrl = (map['seguroUrl'] ?? '').toString();
              final fotoVehiculoUrl = (map['fotoVehiculoUrl'] ?? '').toString();
              final placaUrl = (map['placaUrl'] ?? '').toString();
              final bool procesando = _uidsProcesando.contains(uid);

              Widget thumb(String label, String url) => Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AdminUi.inputFill(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AdminUi.borderSubtle(context)),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AdminUi.secondary(context),
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
                                  color: AdminUi.card(context),
                                  child: url.isEmpty
                                      ? Center(
                                          child: Icon(
                                              Icons.broken_image,
                                              color: AdminUi.muted(context)))
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
                                    : AdminUi.progressAccent(context),
                              )),
                        ],
                      ),
                    ),
                  );

              return Card(
                color: AdminUi.card(context),
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
                              style: TextStyle(
                                  color: AdminUi.onCard(context),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AdminUi.muted(context), fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Primera fila: Licencia, Matrícula, Seguro
                      Row(
                        children: [
                          thumb('Licencia', licenciaUrl),
                          const SizedBox(width: 10),
                          thumb('Matrícula', matriculaUrl),
                          const SizedBox(width: 10),
                          thumb('Seguro', seguroUrl),
                        ],
                      ),

                      // Segunda fila: Foto vehículo, Placa
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          thumb('Foto vehículo', fotoVehiculoUrl),
                          const SizedBox(width: 10),
                          thumb('Placa', placaUrl),
                          const Spacer(), // Para mantener simetría
                        ],
                      ),

                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: procesando ? null : () => _rechazar(uid),
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
                              onPressed: procesando ? null : () => _aprobar(uid),
                              icon: procesando
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AdminUi.progressAccent(context)),
                                    )
                                  : const Icon(Icons.check),
                              label: Text(procesando ? 'Procesando...' : 'Aprobar'),
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