import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';
import 'package:flygo_nuevo/widgets/saldo_ganancias_chip.dart';

/// Firestore:
/// usuarios/{uid} {
///   docs: {
///     licenciaUrl?,
///     matriculaUrl?,
///     seguroUrl?,
///     fotoVehiculoUrl?,
///     placaUrl?,
///     updatedAt
///   },
///   docsEstado: 'pendiente' | 'en_revision' | 'aprobado' | 'rechazado',
///   documentosCompletos: bool,   // solo admin modifica
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
  bool _escuchaAprobacionIniciada = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subUsuario;

  /// Último estado de docs conocido (evita saltar al pool si ya estaba aprobado y abrió esta pantalla desde el menú).
  String? _ultimoEstadoDocs;

  String docsEstado = 'pendiente';
  String? comentarioAdmin;

  String? licenciaUrl;
  String? matriculaUrl;
  String? seguroUrl;
  String? fotoVehiculoUrl;
  String? placaUrl;

  /// Aprobado en Firestore pero fuera del plazo de renovación (~6 meses).
  bool _renovacionObligatoria = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _restaurarBarrasSistema());
    _cargar();
  }

  @override
  void dispose() {
    _subUsuario?.cancel();
    _restaurarBarrasSistema();
    super.dispose();
  }

  /// La cámara / galería a veces deja el modo inmersivo y ocultan barra de navegación y gestos.
  void _restaurarBarrasSistema() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black87,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  /// Cuando el admin aprueba documentos en vivo: contrato (una vez) o pool. No confundir con bloqueo por comisión RD\$500.
  void _iniciarEscuchaAprobacionAdmin() {
    if (_escuchaAprobacionIniciada) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    _escuchaAprobacionIniciada = true;
    _subUsuario = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(u.uid)
        .snapshots()
        .listen((DocumentSnapshot<Map<String, dynamic>> snap) {
      final data = snap.data() ?? <String, dynamic>{};
      final e = taxistaDocsEstadoDesdeUsuario(data);
      if (!taxistaAprobadoParaOperarPool(data)) {
        _ultimoEstadoDocs = e;
        if (mounted) {
          setState(() {
            docsEstado = e;
            _renovacionObligatoria = taxistaRequiereRenovacionDocumentos(data);
          });
        }
        return;
      }
      final prev = (_ultimoEstadoDocs ?? docsEstado).toLowerCase().trim();
      _ultimoEstadoDocs = e;
      if (mounted) {
        setState(() {
          docsEstado = e;
          _renovacionObligatoria = false;
        });
      }
      final pasoAAprobado = prev != 'aprobado' && e == 'aprobado';
      if (!pasoAAprobado || !mounted) return;
      // Una sola decisión: [TaxistaEntry] → contrato (once) o pool. No mezclar aquí con bloqueo RD\$500.
      _continuarTrasAprobacionAdmin();
    });
  }

  void _continuarTrasAprobacionAdmin() {
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil('/taxista_entry', (route) => false);
  }

  Future<void> _cargar() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) {
        if (mounted) setState(() => _cargando = false);
        return;
      }

      // Forzar refresco del token
      await u.getIdToken(true);

      final snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .get();
      final data = (snap.data() ?? <String, dynamic>{});
      final docs = (data['docs'] as Map?) ?? {};
      final rawEstado =
          (data['docsEstado'] ?? data['estadoDocumentos'] ?? 'pendiente')
              .toString()
              .trim();
      final estado = rawEstado.isEmpty ? 'pendiente' : rawEstado.toLowerCase();

      if (!mounted) return;
      setState(() {
        docsEstado = estado;
        _ultimoEstadoDocs = estado;
        _renovacionObligatoria = taxistaRequiereRenovacionDocumentos(data);
        comentarioAdmin = (data['docsComentarioAdmin'] as String?);
        licenciaUrl = (docs['licenciaUrl'] as String?);
        matriculaUrl = (docs['matriculaUrl'] as String?);
        seguroUrl = (docs['seguroUrl'] as String?);
        fotoVehiculoUrl = (docs['fotoVehiculoUrl'] as String?);
        placaUrl = (docs['placaUrl'] as String?);
        _cargando = false;
      });
      _iniciarEscuchaAprobacionAdmin();
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando documentos: $e')),
      );
    }
  }

  Future<void> _seleccionarFotoYSubir(String tipo, ImageSource source) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    // Forzar refresco del token
    await u.getIdToken(true);

    final XFile? img = await _picker.pickImage(
      source: source,
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

      final Map<String, dynamic> updateData = {
        'docs.${tipo}Url': url,
        'docs.updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      };
      // Si el estado estaba aprobado, lo ponemos en pendiente (para nueva revisión)
      if (docsEstado == 'aprobado') {
        updateData['docsEstado'] = 'pendiente';
        updateData['estadoDocumentos'] = 'pendiente';
      }

      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .update(updateData);

      await _cargar();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ $tipo subido.')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      String msg = '❌ Error subiendo $tipo: ${e.message}';
      if (e.code == 'permission-denied') {
        msg = 'No tienes permisos para subir documentos. Contacta al soporte.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error subiendo $tipo: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _subiendo = false);
        _restaurarBarrasSistema();
      }
    }
  }

  Future<void> _elegirFuenteYSubir(String tipo) async {
    if (_subiendo) return;
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Selecciona fuente',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.white),
                title:
                    const Text('Cámara', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.white),
                title: const Text('Galería',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (source == null) return;
    await _seleccionarFotoYSubir(tipo, source);
  }

  Future<void> _eliminar(String tipo, String? url) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || url == null || url.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('Eliminar documento',
            style: TextStyle(color: Colors.white)),
        content: const Text('¿Seguro que deseas eliminar este documento?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
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

      final Map<String, dynamic> updateData = {
        'docs.${tipo}Url': FieldValue.delete(),
        'docs.updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      };
      if (docsEstado == 'aprobado') {
        updateData['docsEstado'] = 'pendiente';
        updateData['estadoDocumentos'] = 'pendiente';
      }

      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .update(updateData);

      await _cargar();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🗑️ $tipo eliminado.')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ No se pudo eliminar $tipo: ${e.message}')),
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

    // Verificar que los 5 documentos estén subidos
    final tiene5 = (licenciaUrl?.isNotEmpty == true) &&
        (matriculaUrl?.isNotEmpty == true) &&
        (seguroUrl?.isNotEmpty == true) &&
        (fotoVehiculoUrl?.isNotEmpty == true) &&
        (placaUrl?.isNotEmpty == true);

    if (!tiene5) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sube los 5 documentos antes de enviar.')),
      );
      return;
    }

    // Forzar refresco del token
    await u.getIdToken(true);

    try {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .update({
        'docsEstado': 'en_revision',
        'estadoDocumentos': 'en_revision',
        'docsEnviadosEn': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

      await _cargar();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📨 Enviado a revisión.')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      String msg = '❌ Error al enviar: ${e.message}';
      if (e.code == 'permission-denied') {
        msg =
            'No tienes permisos para modificar el estado. Verifica las reglas de Firestore.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
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
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Documentos', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [SaldoGananciasChip()],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent))
          : Stack(
              children: [
                ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    110 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    if (_renovacionObligatoria) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1a2a1a),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.greenAccent.withValues(alpha: 0.6)),
                        ),
                        child: const Text(
                          'Renovación de documentos: han pasado unos 6 meses desde la última '
                          'aprobación. Sube de nuevo las fotos y envía a revisión para seguir operando.',
                          style: TextStyle(color: Colors.white70, height: 1.35),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Chip de estado
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorEstado.withValues(alpha: 0.12),
                          border: Border.all(
                              color: colorEstado.withValues(alpha: 0.65)),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, size: 18, color: colorEstado),
                            const SizedBox(width: 8),
                            Text(
                              'Estado: ${docsEstado.toUpperCase()}',
                              style: TextStyle(
                                  color: colorEstado,
                                  fontWeight: FontWeight.w700),
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
                          style: const TextStyle(
                              color: Colors.white70, height: 1.3),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    _DocItem(
                      nombre: 'Licencia de conducir',
                      url: licenciaUrl,
                      onSubir: () => _elegirFuenteYSubir('licencia'),
                      onEliminar: () => _eliminar('licencia', licenciaUrl),
                    ),
                    const SizedBox(height: 12),

                    _DocItem(
                      nombre: 'Matrícula del vehículo',
                      url: matriculaUrl,
                      onSubir: () => _elegirFuenteYSubir('matricula'),
                      onEliminar: () => _eliminar('matricula', matriculaUrl),
                    ),
                    const SizedBox(height: 12),

                    _DocItem(
                      nombre: 'Seguro',
                      url: seguroUrl,
                      onSubir: () => _elegirFuenteYSubir('seguro'),
                      onEliminar: () => _eliminar('seguro', seguroUrl),
                    ),
                    const SizedBox(height: 12),

                    _DocItem(
                      nombre: 'Foto del vehículo',
                      url: fotoVehiculoUrl,
                      onSubir: () => _elegirFuenteYSubir('fotoVehiculo'),
                      onEliminar: () =>
                          _eliminar('fotoVehiculo', fotoVehiculoUrl),
                    ),
                    const SizedBox(height: 12),

                    _DocItem(
                      nombre: 'Foto de la placa',
                      url: placaUrl,
                      onSubir: () => _elegirFuenteYSubir('placa'),
                      onEliminar: () => _eliminar('placa', placaUrl),
                    ),

                    const SizedBox(height: 16),
                    const Text(
                      'Nota: si cambias un documento después de estar aprobado, el estado volverá a “pendiente”.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),

                // Botón fijo inferior (SafeArea: no tapa ni queda bajo la barra/gestos del sistema)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _subiendo ? null : _enviarRevision,
                        icon: const Icon(Icons.send),
                        label: const Text('Enviar a revisión'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16),
                        ),
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
  final VoidCallback onSubir;
  final VoidCallback onEliminar;

  const _DocItem({
    required this.nombre,
    required this.url,
    required this.onSubir,
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
                      await launchUrl(Uri.parse(url!),
                          mode: LaunchMode.externalApplication);
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
                      : const Icon(Icons.insert_drive_file,
                          color: Colors.white38),
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
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                          tieneArchivo
                              ? Icons.check_circle
                              : Icons.info_outline,
                          size: 16,
                          color: tieneArchivo
                              ? Colors.greenAccent
                              : Colors.white60),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          tieneArchivo ? 'Archivo subido' : 'Sin archivo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tieneArchivo
                                ? Colors.greenAccent
                                : Colors.white70,
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

            // Acción: Cámara o Galería
            ElevatedButton.icon(
              onPressed: onSubir,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Subir'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.green,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
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
