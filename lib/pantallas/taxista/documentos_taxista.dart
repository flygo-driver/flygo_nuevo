import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flygo_nuevo/firebase_bootstrap.dart';
import 'package:flygo_nuevo/servicios/flygo_storage.dart';
import 'package:flygo_nuevo/servicios/taxista_operacion_gate.dart';
import 'package:flygo_nuevo/widgets/saldo_ganancias_chip.dart';
import 'package:flygo_nuevo/widgets/taxista_onboarding_acciones_footer.dart';

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
  const DocumentosTaxista({super.key, this.onboardingObligatorio = false});

  /// Tras registro: no volver atrás hasta enviar documentos a revisión.
  final bool onboardingObligatorio;

  @override
  State<DocumentosTaxista> createState() => _DocumentosTaxistaState();
}

class _DocumentosTaxistaState extends State<DocumentosTaxista> {
  final _picker = ImagePicker();

  bool _cargando = true;
  bool _subiendo = false;
  bool _escuchaAprobacionIniciada = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subUsuario;

  /// Evita doble navegación; detecta transición a apto para pool (docs + ADM).
  bool _ultimoPoolOk = false;

  /// Refleja si ADM ya aprobó y puede continuar al pool (onboarding).
  bool _aptoParaPool = false;

  String docsEstado = 'pendiente';
  String? comentarioAdmin;

  String? licenciaUrl;
  String? matriculaUrl;
  String? seguroUrl;
  String? fotoVehiculoUrl;
  String? placaUrl;

  /// Vista previa cuando la imagen está en Firestore (rai-doc://).
  final Map<String, Uint8List?> _docPreviews = <String, Uint8List?>{};

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
      final poolOk = taxistaAprobadoParaOperarPool(data);
      if (!poolOk) {
        _ultimoPoolOk = false;
        if (mounted) {
          setState(() {
            docsEstado = e;
            _aptoParaPool = false;
            _renovacionObligatoria = taxistaRequiereRenovacionDocumentos(data);
          });
        }
        return;
      }
      final pasoAPool = !_ultimoPoolOk;
      _ultimoPoolOk = true;
      if (mounted) {
        setState(() {
          docsEstado = e;
          _aptoParaPool = true;
          _renovacionObligatoria = false;
        });
      }
      if (!pasoAPool || !mounted) return;
      // [TaxistaEntry] → contrato (una vez) o pool en vivo.
      _maybeContinuarTrasAprobacion(data);
    });
  }

  void _continuarTrasAprobacionAdmin() {
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil('/taxista_entry', (route) => false);
  }

  /// Solo en onboarding obligatorio: ADM aprobó → contrato o pool vía [TaxistaEntry].
  void _maybeContinuarTrasAprobacion(Map<String, dynamic> data) {
    if (!widget.onboardingObligatorio) return;
    if (!taxistaAprobadoParaOperarPool(data)) return;
    _continuarTrasAprobacionAdmin();
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

      final String? lic = docs['licenciaUrl'] as String?;
      final String? mat = docs['matriculaUrl'] as String?;
      final String? seg = docs['seguroUrl'] as String?;
      final String? foto = docs['fotoVehiculoUrl'] as String?;
      final String? pla = docs['placaUrl'] as String?;

      _docPreviews.clear();
      for (final MapEntry<String, String?> e in <MapEntry<String, String?>>[
        MapEntry<String, String?>('licencia', lic),
        MapEntry<String, String?>('matricula', mat),
        MapEntry<String, String?>('seguro', seg),
        MapEntry<String, String?>('fotoVehiculo', foto),
        MapEntry<String, String?>('placa', pla),
      ]) {
        if (RaiDocUrl.isFirestoreDoc(e.value)) {
          _docPreviews[e.key] = await FlygoStorage.cargarDocImagen(
            uid: u.uid,
            tipo: e.key,
          );
        }
      }

      if (!mounted) return;
      final poolOk = taxistaAprobadoParaOperarPool(data);
      setState(() {
        docsEstado = estado;
        _ultimoPoolOk = poolOk;
        _aptoParaPool = poolOk;
        _renovacionObligatoria = taxistaRequiereRenovacionDocumentos(data);
        comentarioAdmin = (data['docsComentarioAdmin'] as String?);
        licenciaUrl = lic;
        matriculaUrl = mat;
        seguroUrl = seg;
        fotoVehiculoUrl = foto;
        placaUrl = pla;
        _cargando = false;
      });
      _iniciarEscuchaAprobacionAdmin();
      if (poolOk) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _maybeContinuarTrasAprobacion(data);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando documentos: $e')),
      );
    }
  }

  void _logDocUpload(String msg) {
    // ignore: avoid_print
    print('[DocTaxista] $msg');
  }

  Future<void> _refrescarTokenUsuario(User u) async {
    await FirebaseBootstrap.ensureInitialized();
    await u.getIdToken(true);
    _logDocUpload('token refrescado uid=${u.uid}');
  }

  String _mensajeErrorSubida(String tipo, FirebaseException e) {
    _logDocUpload(
      'storage/firestore error tipo=$tipo plugin=${e.plugin} code=${e.code} msg=${e.message}',
    );
    switch (e.code) {
      case 'permission-denied':
        return '❌ $tipo [permission-denied]: no tienes permiso en Storage/Firestore. ${e.message ?? ''}';
      case 'unauthenticated':
        return '❌ $tipo [unauthenticated]: sesión expirada. ${e.message ?? ''}';
      case 'bucket-not-found':
        return '❌ $tipo [bucket-not-found]: bucket Storage no configurado. ${e.message ?? ''}';
      case 'unknown':
        return '❌ $tipo [unknown]: ${e.message ?? 'error desconocido en Storage'}';
      case 'not-found':
        return '❌ $tipo: no se pudo subir. Reintenta (Storage/Firestore).';
      case 'storage-billing':
        return '❌ $tipo: Storage bloqueado por facturación Google.';
      default:
        return '❌ $tipo [${e.code}]: ${e.message ?? e.plugin}';
    }
  }

  Future<void> _seleccionarFotoYSubir(String tipo, ImageSource source) async {
    if (_subiendo) return;

    await FirebaseBootstrap.ensureInitialized();

    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      _logDocUpload('sin sesión al iniciar subida tipo=$tipo');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inicia sesión para subir documentos.')),
        );
      }
      return;
    }

    await _refrescarTokenUsuario(u);

    final XFile? img = source == ImageSource.camera
        ? await _picker.pickImage(
            source: source,
            imageQuality: 80,
            maxWidth: 1920,
            maxHeight: 1920,
            preferredCameraDevice: CameraDevice.rear,
          )
        : await _picker.pickImage(
            source: source,
            imageQuality: 80,
            maxWidth: 1920,
            maxHeight: 1920,
          );
    if (img == null) return;

    if (!mounted) return;
    setState(() => _subiendo = true);

    try {
      final Uint8List bytes = await img.readAsBytes();
      if (bytes.isEmpty) {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'invalid-argument',
          message: 'No se pudo leer la imagen.',
        );
      }
      if (bytes.length > 10 * 1024 * 1024) {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'invalid-argument',
          message: 'El archivo excede 10 MB',
        );
      }

      final String url = await FlygoStorage.uploadDocumentoTaxista(
        user: u,
        tipo: tipo,
        bytes: bytes,
        localFilePath: img.path,
      );
      _logDocUpload('storage OK tipo=$tipo');

      final Map<String, dynamic> updateData = {
        'docs.${tipo}Url': url,
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
      _logDocUpload('firestore OK tipo=$tipo');

      if (RaiDocUrl.isFirestoreDoc(url) && mounted) {
        setState(() => _docPreviews[tipo] = bytes);
      }

      await _cargar();

      if (!mounted) return;
      final bool respaldo = RaiDocUrl.isFirestoreDoc(url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            respaldo
                ? '✅ $tipo guardado (respaldo Firestore).'
                : '✅ $tipo subido.',
          ),
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensajeErrorSubida(tipo, e))),
      );
    } catch (e) {
      _logDocUpload('error general tipo=$tipo: $e');
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
      if (RaiDocUrl.isFirestoreDoc(url)) {
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(u.uid)
            .collection('docs_imagenes')
            .doc(tipo)
            .delete();
      } else {
        try {
          final Reference ref = FirebaseStorage.instance.refFromURL(url);
          await ref.delete();
        } catch (_) {}
      }

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
    bool docOk(String? url) => url != null && url.trim().isNotEmpty;

    final tiene5 = docOk(licenciaUrl) &&
        docOk(matriculaUrl) &&
        docOk(seguroUrl) &&
        docOk(fotoVehiculoUrl) &&
        docOk(placaUrl);

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
        const SnackBar(
          content: Text(
            '📨 Enviado a revisión. Cuando administración apruebe, entrarás al pool automáticamente.',
          ),
        ),
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
    final bool onboardingSalida =
        widget.onboardingObligatorio && !_renovacionObligatoria;
    final estadoL = docsEstado.toLowerCase();
    const double footerReserva = 118;

    final scaffold = Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        automaticallyImplyLeading: !widget.onboardingObligatorio,
        title: const Text('Documentos', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [SaldoGananciasChip()],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent))
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                footerReserva + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                    if (widget.onboardingObligatorio && !_renovacionObligatoria) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1a1f2e),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.greenAccent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Text(
                          'Paso obligatorio: sube tus 5 documentos y pulsa '
                          '«Enviar a revisión». Administración validará tu cuenta '
                          'antes de que puedas operar en el pool.',
                          style: TextStyle(color: Colors.white70, height: 1.35),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
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

                    if (estadoL == 'en_revision') ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2a2410),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFFFD54F).withValues(alpha: 0.6),
                          ),
                        ),
                        child: const Text(
                          'En revisión por administración. Al aprobar, entrarás al pool en vivo '
                          '(o al contrato si falta firmarlo).',
                          style: TextStyle(color: Colors.white70, height: 1.35),
                        ),
                      ),
                    ],
                    if (_aptoParaPool && widget.onboardingObligatorio) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1a2a1a),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF00E676).withValues(alpha: 0.6),
                          ),
                        ),
                        child: const Text(
                          'Documentos aprobados. Pulsa «Continuar al pool» para operar.',
                          style: TextStyle(color: Colors.white70, height: 1.35),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    _DocItem(
                      nombre: 'Licencia de conducir',
                      url: licenciaUrl,
                      previewBytes: _docPreviews['licencia'],
                      onSubir: () => _elegirFuenteYSubir('licencia'),
                      onEliminar: () => _eliminar('licencia', licenciaUrl),
                    ),
                    const SizedBox(height: 12),

                    _DocItem(
                      nombre: 'Matrícula del vehículo',
                      url: matriculaUrl,
                      previewBytes: _docPreviews['matricula'],
                      onSubir: () => _elegirFuenteYSubir('matricula'),
                      onEliminar: () => _eliminar('matricula', matriculaUrl),
                    ),
                    const SizedBox(height: 12),

                    _DocItem(
                      nombre: 'Seguro',
                      url: seguroUrl,
                      previewBytes: _docPreviews['seguro'],
                      onSubir: () => _elegirFuenteYSubir('seguro'),
                      onEliminar: () => _eliminar('seguro', seguroUrl),
                    ),
                    const SizedBox(height: 12),

                    _DocItem(
                      nombre: 'Foto del vehículo',
                      url: fotoVehiculoUrl,
                      previewBytes: _docPreviews['fotoVehiculo'],
                      onSubir: () => _elegirFuenteYSubir('fotoVehiculo'),
                      onEliminar: () =>
                          _eliminar('fotoVehiculo', fotoVehiculoUrl),
                    ),
                    const SizedBox(height: 12),

                    _DocItem(
                      nombre: 'Foto de la placa',
                      url: placaUrl,
                      previewBytes: _docPreviews['placa'],
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
      bottomNavigationBar: _cargando
          ? null
          : TaxistaOnboardingAccionesFooter(
              primaryLabel: _aptoParaPool && widget.onboardingObligatorio
                  ? 'Continuar al pool'
                  : 'Enviar a revisión',
              primaryIcon: _aptoParaPool && widget.onboardingObligatorio
                  ? Icons.check_circle_outline
                  : Icons.send_rounded,
              busy: _subiendo,
              onPrimary: _aptoParaPool && widget.onboardingObligatorio
                  ? _continuarTrasAprobacionAdmin
                  : _enviarRevision,
              mostrarSalirInicio: onboardingSalida,
              fondoOscuro: true,
              primaryClaroSobreOscuro: true,
            ),
    );

    if (!widget.onboardingObligatorio) return scaffold;

    return PopScope(
      canPop: false,
      child: scaffold,
    );
  }
}

// ---------------------------- Widgets ----------------------------

class _DocItem extends StatelessWidget {
  final String nombre;
  final String? url;
  final Uint8List? previewBytes;
  final VoidCallback onSubir;
  final VoidCallback onEliminar;

  const _DocItem({
    required this.nombre,
    required this.url,
    this.previewBytes,
    required this.onSubir,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final tieneArchivo = url != null && url!.isNotEmpty;
    final bool esRed = tieneArchivo && !RaiDocUrl.isFirestoreDoc(url);

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
              onTap: esRed
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
                  child: previewBytes != null && previewBytes!.isNotEmpty
                      ? Image.memory(previewBytes!, fit: BoxFit.cover)
                      : tieneArchivo && esRed
                          ? Image.network(url!, fit: BoxFit.cover)
                          : tieneArchivo
                              ? const Icon(Icons.cloud_done,
                                  color: Colors.greenAccent)
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
