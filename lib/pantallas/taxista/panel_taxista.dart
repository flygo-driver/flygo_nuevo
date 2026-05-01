// lib/pantallas/taxista/panel_taxista.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, debugPrint;
import 'viaje_disponible.dart';

// Firebase + picker
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

// Permisos
import 'package:permission_handler/permission_handler.dart';

// Avatar
import 'package:flygo_nuevo/widgets/avatar_circle.dart';

class PanelTaxista extends StatelessWidget {
  const PanelTaxista({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.greenAccent,
        title: const Text('RAI Driver — Taxista'),
        actions: [
          IconButton(
            tooltip: 'Mi perfil (cambiar foto)',
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PerfilFotoScreen()),
              );
            },
          ),
        ],
      ),
      body: const ViajeDisponible(),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.greenAccent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.edit),
        label: const Text('Cambiar foto'),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PerfilFotoScreen()),
          );
        },
      ),
    );
  }
}

/* ============================================================
   PERFIL: cambiar foto + botón de prueba de subida
   ============================================================ */

class PerfilFotoScreen extends StatefulWidget {
  const PerfilFotoScreen({super.key});
  @override
  State<PerfilFotoScreen> createState() => _PerfilFotoScreenState();
}

class _PerfilFotoScreenState extends State<PerfilFotoScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage =
      FirebaseStorage.instance; // bucket por defecto

  bool _subiendo = false;
  String? _cacheBuster;

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Inicia sesión para ver tu perfil')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de perfil'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.greenAccent,
      ),
      backgroundColor: Colors.black,
      body: StreamBuilder<DocumentSnapshot>(
        stream: _db.collection('usuarios').doc(uid).snapshots(),
        builder: (context, snap) {
          final data = (snap.data?.data() as Map<String, dynamic>?) ?? {};
          final nombre = (data['nombre'] ?? '') as String?;
          String? fotoUrl = (data['fotoUrl'] ?? '') as String?;
          if (fotoUrl != null && fotoUrl.isNotEmpty && _cacheBuster != null) {
            fotoUrl = '$fotoUrl?t=$_cacheBuster';
          }

          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _subiendo
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(
                            color: Colors.greenAccent),
                      )
                    : AvatarCircle(
                        imageUrl: fotoUrl,
                        name: nombre,
                        size: 120,
                        onTap: _elegirOrigenYSubir,
                      ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _subiendo ? null : _elegirOrigenYSubir,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Cambiar'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _subiendo ? null : _eliminarFoto,
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.greenAccent),
                  label: const Text('Eliminar foto',
                      style: TextStyle(color: Colors.greenAccent)),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 12),
                  // Boton de prueba solo en debug.
                  OutlinedButton.icon(
                    onPressed: _subiendo ? null : _pruebaSubidaSimple,
                    icon: const Icon(Icons.upload_file,
                        color: Colors.greenAccent),
                    label: const Text(
                      'PRUEBA SUBIDA (test.txt)',
                      style: TextStyle(color: Colors.greenAccent),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.greenAccent),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Cámara: pide [Permission.camera]. Galería en Android usa el selector del sistema
  /// (sin READ_MEDIA_*). En iOS se pide acceso a la fototeca.
  Future<bool> _ensurePermissionsForSource(ImageSource source) async {
    if (source == ImageSource.camera) {
      final camera = await Permission.camera.request();
      if (!camera.isGranted) {
        if (mounted) {
          _toast('Concede permiso de cámara para continuar');
        }
        return false;
      }
      return true;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final photos = await Permission.photos.request().onError((_, __) async {
        return PermissionStatus.granted;
      });
      if (!photos.isGranted && !photos.isLimited) {
        if (mounted) {
          _toast('Concede acceso a fotos para continuar');
        }
        return false;
      }
    }
    return true;
  }

  Future<void> _elegirOrigenYSubir() async {
    if (!mounted) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Cámara'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Galería'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (!mounted || source == null) return;
    final ok = await _ensurePermissionsForSource(source);
    if (!ok) return;
    await _subirImagen(source);
  }

  Future<void> _subirImagen(ImageSource source) async {
    final user = _auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      _toast('Sesión no válida');
      return;
    }

    try {
      setState(() => _subiendo = true);

      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) {
        if (!mounted) return;
        setState(() => _subiendo = false);
        return;
      }

      final bytes = await picked.readAsBytes();
      if (kDebugMode) {
        debugPrint('[UPLOAD] defaultBucket=${_storage.bucket}');
      }
      final path =
          'perfiles/${user.uid}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child(path);
      if (kDebugMode) {
        debugPrint(
            '[UPLOAD] path=$path  bucket(ref)=${ref.bucket}  size=${bytes.length}');
      }

      final snap = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final url = await snap.ref.getDownloadURL();

      await _db.collection('usuarios').doc(user.uid).set({
        'fotoUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _subiendo = false;
        _cacheBuster = DateTime.now().millisecondsSinceEpoch.toString();
      });
      _toast('✅ Foto actualizada');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _subiendo = false);
      if (kDebugMode) {
        debugPrint(
            '[UPLOAD][FirebaseException] code=${e.code} message=${e.message}');
      }
      _toast('Error subiendo foto: [${e.code}] ${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _subiendo = false);
      if (kDebugMode) {
        debugPrint('[UPLOAD][Error] $e');
      }
      _toast('Error: $e');
    }
  }

  // 🔧 Subida simple de prueba: escribe "hola" como test.txt
  Future<void> _pruebaSubidaSimple() async {
    final user = _auth.currentUser;
    if (user == null) {
      _toast('Sesión no válida');
      return;
    }
    try {
      setState(() => _subiendo = true);
      final path = 'perfiles/${user.uid}/test.txt';
      final ref = _storage.ref().child(path);
      if (kDebugMode) {
        debugPrint('[TEST] defaultBucket=${_storage.bucket}');
        debugPrint('[TEST] path=$path  bucket(ref)=${ref.bucket}');
      }

      final snap = await ref.putString(
        'hola ${DateTime.now()}',
        metadata: SettableMetadata(contentType: 'text/plain'),
      );

      final url = await snap.ref.getDownloadURL();
      if (kDebugMode) debugPrint('[TEST] OK url=$url');
      _toast('✅ Test subido. Revisa Storage → archivos.');
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[TEST][FirebaseException] code=${e.code} message=${e.message}');
      }
      _toast('Test falló: [${e.code}] ${e.message}');
    } catch (e) {
      if (kDebugMode) debugPrint('[TEST][Error] $e');
      _toast('Test error: $e');
    } finally {
      if (mounted) {
        setState(() => _subiendo = false);
      }
    }
  }

  Future<void> _eliminarFoto() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      setState(() => _subiendo = true);
      await _db.collection('usuarios').doc(user.uid).set({
        'fotoUrl': '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _subiendo = false;
        _cacheBuster = DateTime.now().millisecondsSinceEpoch.toString();
      });
      _toast('🗑️ Foto eliminada');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _subiendo = false);
      _toast('Firebase: ${e.code}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _subiendo = false);
      _toast('Error: $e');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }
}
