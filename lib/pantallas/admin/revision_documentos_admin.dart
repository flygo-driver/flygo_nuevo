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

class _RevisionDocumentosAdminState extends State<RevisionDocumentosAdmin> {
  final _db = FirebaseFirestore.instance;
  final Set<String> _uidsProcesando = <String>{};

  String _mensajeFirebase(FirebaseException e) {
    final m = e.message?.trim();
    if (m != null && m.isNotEmpty) return m;
    return e.code;
  }

  Map<String, dynamic> _docsMap(Map<String, dynamic> d) {
    final raw = d['docs'];
    if (raw is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  static bool _urlAbrible(String url) {
    final u = Uri.tryParse(url.trim());
    return u != null &&
        u.hasScheme &&
        (u.scheme == 'http' || u.scheme == 'https');
  }

  Future<void> _abrirUrl(BuildContext context, String url) async {
    final u = Uri.tryParse(url.trim());
    if (u == null ||
        !(u.hasScheme && (u.scheme == 'http' || u.scheme == 'https'))) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enlace no válido'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    try {
      final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el enlace'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el enlace'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

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
        const SnackBar(
          content: Text('Documentos aprobados'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensajeFirebase(e)),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _uidsProcesando.remove(uid));
    }
  }

  Future<void> _rechazar(String uid) async {
    if (_uidsProcesando.contains(uid)) return;

    final controller = TextEditingController();
    try {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            backgroundColor: AdminUi.dialogSurface(ctx),
            title: Text(
              'Rechazar documentos',
              style: TextStyle(color: AdminUi.onCard(ctx)),
            ),
            content: SingleChildScrollView(
              child: TextField(
                controller: controller,
                maxLines: 4,
                style: TextStyle(color: AdminUi.onCard(ctx)),
                decoration: InputDecoration(
                  hintText: 'Motivo del rechazo (obligatorio)',
                  hintStyle: TextStyle(
                      color: AdminUi.secondary(ctx).withValues(alpha: 0.85)),
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
      );

      if (ok != true) {
        return;
      }

      final motivo = controller.text.trim();
      if (motivo.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Escribe el motivo del rechazo antes de confirmar.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      setState(() => _uidsProcesando.add(uid));
      try {
        await _db.collection('usuarios').doc(uid).set({
          'docsEstado': 'rechazado',
          'estadoDocumentos': 'rechazado',
          'documentosCompletos': false,
          'puedeRecibirViajes': false,
          'disponible': false,
          'docsComentarioAdmin': motivo,
          'docsRevisadoEn': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documentos rechazados'),
            backgroundColor: Colors.orange,
          ),
        );
      } on FirebaseException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensajeFirebase(e)),
            backgroundColor: Colors.red,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) setState(() => _uidsProcesando.remove(uid));
      }
    } finally {
      controller.dispose();
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
        title: Text(
          'Revisión de documentos',
          style: TextStyle(color: AdminUi.onCard(context)),
        ),
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
              child: CircularProgressIndicator(
                  color: AdminUi.progressAccent(context)),
            );
          }

          if (snap.hasError) {
            final err = snap.error;
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
                      'No se pudieron cargar los expedientes.',
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

          final docs = (snap.data?.docs ??
              <QueryDocumentSnapshot<Map<String, dynamic>>>[])
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
              child: Text(
                'No hay expedientes en revisión.',
                style: TextStyle(color: AdminUi.secondary(context)),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (BuildContext context, int i) {
              final d = docs[i].data();
              final uid = docs[i].id;
              final nombre = (d['nombre'] ?? '').toString();
              final email = (d['email'] ?? '').toString();
              final map = _docsMap(d);
              final licenciaUrl = (map['licenciaUrl'] ?? '').toString();
              final matriculaUrl = (map['matriculaUrl'] ?? '').toString();
              final seguroUrl = (map['seguroUrl'] ?? '').toString();
              final fotoVehiculoUrl = (map['fotoVehiculoUrl'] ?? '').toString();
              final placaUrl = (map['placaUrl'] ?? '').toString();
              final bool procesando = _uidsProcesando.contains(uid);

              Widget thumb(String label, String url) {
                final bool okUrl = _urlAbrible(url);
                return Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AdminUi.inputFill(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AdminUi.borderSubtle(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AdminUi.secondary(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AspectRatio(
                          aspectRatio: 4 / 3,
                          child: GestureDetector(
                            onTap:
                                !okUrl ? null : () => _abrirUrl(context, url),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                color: AdminUi.card(context),
                                child: !okUrl
                                    ? Center(
                                        child: Icon(
                                          Icons.broken_image,
                                          color: AdminUi.muted(context),
                                        ),
                                      )
                                    : Image.network(
                                        url,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                            color: AdminUi.muted(context),
                                          ),
                                        ),
                                        loadingBuilder:
                                            (context, child, loadingProgress) {
                                          if (loadingProgress == null) {
                                            return child;
                                          }
                                          return Center(
                                            child: SizedBox(
                                              width: 28,
                                              height: 28,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AdminUi.progressAccent(
                                                    context),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          okUrl ? 'OK' : 'Falta',
                          style: TextStyle(
                            color: okUrl
                                ? AdminUi.progressAccent(context)
                                : const Color(0xFFFF5252),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Card(
                color: AdminUi.card(context),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AdminUi.muted(context), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
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
                          thumb('Foto vehículo', fotoVehiculoUrl),
                          const SizedBox(width: 10),
                          thumb('Placa', placaUrl),
                          const Spacer(),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  procesando ? null : () => _rechazar(uid),
                              icon: procesando
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFFF5252),
                                      ),
                                    )
                                  : const Icon(Icons.close),
                              label:
                                  Text(procesando ? 'Procesando…' : 'Rechazar'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFFF5252),
                                side:
                                    const BorderSide(color: Color(0xFFFF5252)),
                                textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed:
                                  procesando ? null : () => _aprobar(uid),
                              icon: procesando
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AdminUi.progressAccent(context),
                                      ),
                                    )
                                  : const Icon(Icons.check),
                              label:
                                  Text(procesando ? 'Procesando…' : 'Aprobar'),
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
