import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flygo_nuevo/widgets/taxista_drawer.dart';
import 'package:flygo_nuevo/widgets/saldo_ganancias_chip.dart';

/// Firestore:
/// usuarios/{uid} {
///   docs: { licenciaUrl?, matriculaUrl?, seguroUrl?, updatedAt },
///   docsEstado: 'pendiente' | 'en_revision' | 'aprobado' | 'rechazado',
///   documentosCompletos: bool,
///   docsComentarioAdmin?: string
/// }
/// Storage:
///   documentos_taxista/{uid}/{tipo}_{timestamp}.jpg
class DocumentosTaxista extends StatefulWidget {
  const DocumentosTaxista({super.key});

  @override
  State<DocumentosTaxista> createState() => _DocumentosTaxistaState();
}

class _DocumentosTaxistaState extends State<DocumentosTaxista> {
  final _picker = ImagePicker();

  bool _cargando = true;
  bool _subiendo = false;

  String docsEstado = 'pendiente';
  String? comentarioAdmin;

  String? licenciaUrl;
  String? matriculaUrl;
  String? seguroUrl;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) {
        if (mounted) setState(() => _cargando = false);
        return;
      }

      final snap =
          await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).get();
      final data = (snap.data() ?? <String, dynamic>{});
      final docs = (data['docs'] as Map?) ?? {};
      final estado = (data['docsEstado'] as String?)?.toLowerCase() ?? 'pendiente';

      if (!mounted) return;
      setState(() {
        docsEstado = estado;
        comentarioAdmin = (data['docsComentarioAdmin'] as String?);
        licenciaUrl = (docs['licenciaUrl'] as String?);
        matriculaUrl = (docs['matriculaUrl'] as String?);
        seguroUrl = (docs['seguroUrl'] as String?);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando documentos: $e')),
      );
    }
  }

  Future<void> _tomarFotoYSubir(String tipo) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final XFile? img = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (img == null) return;

    if (!mounted) return;
    setState(() => _subiendo = true);

    try {
      final Uint8List bytes = await img.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw 'El archivo excede 10 MB';
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'documentos_taxista/${u.uid}/${tipo}_$ts.jpg';
      final ref = FirebaseStorage.instance.ref(storagePath);

      await ref.putData(
        bytes,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {'uid': u.uid, 'tipo': tipo},
        ),
      );
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).set({
        'docs': {
          '${tipo}Url': url,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        if (docsEstado == 'aprobado') 'docsEstado': 'pendiente',
        'documentosCompletos': false, // se habilita SOLO al aprobar
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _cargar();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ $tipo subido.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error subiendo $tipo: $e')),
      );
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<void> _eliminar(String tipo, String? url) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || url == null || url.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title:
            const Text('Eliminar documento', style: TextStyle(color: Colors.white)),
        content: const Text('¿Seguro que deseas eliminar este documento?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final ref = FirebaseStorage.instance.refFromURL(url);
      await ref.delete();

      await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).set({
        'docs': {
          '${tipo}Url': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        if (docsEstado == 'aprobado') 'docsEstado': 'pendiente',
        'documentosCompletos': false,
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _cargar();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🗑️ $tipo eliminado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ No se pudo eliminar $tipo: $e')),
      );
    }
  }

  Future<void> _enviarRevision() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final tiene3 = (licenciaUrl?.isNotEmpty == true) &&
        (matriculaUrl?.isNotEmpty == true) &&
        (seguroUrl?.isNotEmpty == true);

    if (!tiene3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sube los 3 documentos antes de enviar.')),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).set({
        'docsEstado': 'en_revision',
        'documentosCompletos': false, // SOLO al aprobar
        'docsComentarioAdmin': FieldValue.delete(),
        'docsEnviadosEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _cargar();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📨 Enviado a revisión.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error al enviar: $e')),
      );
    }
  }

  Color _estadoColor(String e) {
    switch (e.toLowerCase()) {
      case 'aprobado':
        return const Color(0xFF00E676);
      case 'en_revision':
        return const Color(0xFFFFD54F);
      case 'rechazado':
        return const Color(0xFFFF5252);
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorEstado = _estadoColor(docsEstado);

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const TaxistaDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            tooltip: 'Menú',
          ),
        ),
        title: const Text('Documentos', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [SaldoGananciasChip()],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                  children: [
                    // Chip de estado
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          // ✅ sin deprecated: usamos withValues
                          color: colorEstado.withValues(alpha: 0.12),
                          border: Border.all(color: colorEstado.withValues(alpha: 0.65)),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, size: 18, color: colorEstado),
                            const SizedBox(width: 8),
                            Text(
                              'Estado: ${docsEstado.toUpperCase()}',
                              style: TextStyle(color: colorEstado, fontWeight: FontWeight.w700),
                            ),
                            if (_subiendo) ...[
                              const SizedBox(width: 10),
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.greenAccent,
                                ),
                              ),
                            ]
                          ],
                        ),
                      ),
                    ),

                    if (docsEstado.toLowerCase() == 'rechazado' &&
                        (comentarioAdmin?.isNotEmpty ?? false)) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2a1b1b),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFF5252)),
                        ),
                        child: Text(
                          'Observación del revisor: $comentarioAdmin',
                          style: const TextStyle(color: Colors.white70, height: 1.3),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    _DocItem(
                      nombre: 'Licencia de conducir',
                      url: licenciaUrl,
                      onSubirCamara: () => _tomarFotoYSubir('licencia'),
                      onEliminar: () => _eliminar('licencia', licenciaUrl),
                    ),
                    const SizedBox(height: 12),

                    _DocItem(
                      nombre: 'Matrícula del vehículo',
                      url: matriculaUrl,
                      onSubirCamara: () => _tomarFotoYSubir('matricula'),
                      onEliminar: () => _eliminar('matricula', matriculaUrl),
                    ),
                    const SizedBox(height: 12),

                    _DocItem(
                      nombre: 'Seguro',
                      url: seguroUrl,
                      onSubirCamara: () => _tomarFotoYSubir('seguro'),
                      onEliminar: () => _eliminar('seguro', seguroUrl),
                    ),

                    const SizedBox(height: 16),
                    const Text(
                      'Nota: si cambias un documento después de estar aprobado, el estado volverá a “pendiente”.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),

                // Botón fijo inferior
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _subiendo ? null : _enviarRevision,
                      icon: const Icon(Icons.send),
                      label: const Text('Enviar a revisión'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ---------------------------- Widgets ----------------------------

class _DocItem extends StatelessWidget {
  final String nombre;
  final String? url;
  final VoidCallback onSubirCamara;
  final VoidCallback onEliminar;

  const _DocItem({
    required this.nombre,
    required this.url,
    required this.onSubirCamara,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final tieneArchivo = url != null && url!.isNotEmpty;

    return Card(
      color: const Color(0xFF171717),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Preview (tap para ver)
            GestureDetector(
              onTap: tieneArchivo
                  ? () async {
                      await launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication);
                    }
                  : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 64,
                  height: 64,
                  color: const Color(0xFF262626),
                  child: tieneArchivo
                      ? Image.network(url!, fit: BoxFit.cover)
                      : const Icon(Icons.insert_drive_file, color: Colors.white38),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Título y estado
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(tieneArchivo ? Icons.check_circle : Icons.info_outline,
                          size: 16, color: tieneArchivo ? Colors.greenAccent : Colors.white60),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          tieneArchivo ? 'Archivo subido' : 'Sin archivo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tieneArchivo ? Colors.greenAccent : Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Acción: SOLO Cámara
            ElevatedButton.icon(
              onPressed: onSubirCamara,
              icon: const Icon(Icons.photo_camera, size: 18),
              label: const Text('Cámara'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 6),
            if (tieneArchivo)
              IconButton(
                tooltip: 'Borrar',
                onPressed: onEliminar,
                icon: const Icon(Icons.delete_outline, color: Colors.white70),
              ),
          ],
        ),
      ),
    );
  }
}
