import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/widgets/avatar_circle.dart';

class ConfiguracionPerfil extends StatefulWidget {
  const ConfiguracionPerfil({super.key});

  @override
  State<ConfiguracionPerfil> createState() => _ConfiguracionPerfilState();
}

class _ConfiguracionPerfilState extends State<ConfiguracionPerfil> {
  final _picker = ImagePicker();
  final _nombreCtrl = TextEditingController();

  // ✅ Forzamos el bucket correcto (ajústalo si tu bucket es distinto)
  final FirebaseStorage _storage =
      FirebaseStorage.instanceFor(bucket: 'gs://flygo-rd.firebasestorage.app');

  bool _guardando = false;
  bool _subiendo = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _cambiarFoto(String uid) async {
    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44, height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.photo_camera, color: Colors.white),
              title: const Text('Tomar foto', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text('Elegir de galería', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return;

    if (!mounted) return;
    setState(() => _subiendo = true);

    try {
      final Uint8List bytes = await picked.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La imagen pesa más de 5MB')),
        );
        setState(() => _subiendo = false);
        return;
      }

      // Nombre único para evitar cache y colisiones
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref()
          .child('perfiles')
          .child(uid)
          .child('avatar_$ts.jpg');

      // Sube la imagen (contentType que cumple tus reglas: image/*)
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));

      // 🔁 Intentamos conseguir la URL con reintentos
      String? url;
      for (int i = 0; i < 3; i++) {
        try {
          url = await ref.getDownloadURL();
          break; // salió bien
        } on FirebaseException catch (e) {
          if (e.code == 'object-not-found') {
            await Future.delayed(const Duration(milliseconds: 300));
            continue; // reintenta
          }
          rethrow; // otro error: lo lanzamos
        }
      }

      if (url == null) {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'object-not-found',
          message: 'No se pudo obtener la URL luego de subir.',
        );
      }

      // Guarda en Firestore
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'fotoUrl': url,
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('✅ Foto actualizada.')));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Storage: [${e.code}] ${e.message ?? ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _subiendo = false);
      }
    }
  }

  Future<void> _eliminarFoto(String uid) async {
    setState(() => _subiendo = true);
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'fotoUrl': '',
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Foto eliminada.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    } finally {
      if (mounted) {
        setState(() => _subiendo = false);
      }
    }
  }

  Future<void> _guardarNombre(String uid) async {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nombre demasiado corto.')));
      return;
    }
    setState(() => _guardando = true);
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'nombre': nombre,
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('✅ Nombre actualizado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('❌ Error guardando: $e')));
    } finally {
      if (mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  Future<void> _pruebaSubida(String uid) async {
    setState(() => _subiendo = true);
    try {
      final ref = _storage.ref().child('perfiles').child(uid).child('test.txt');
      await ref.putString(
        'hola ${DateTime.now()}',
        metadata: SettableMetadata(contentType: 'text/plain'),
      );

      // también probamos URL con retry
      String? url;
      for (int i = 0; i < 3; i++) {
        try {
          url = await ref.getDownloadURL();
          break;
        } on FirebaseException catch (e) {
          if (e.code == 'object-not-found') {
            await Future.delayed(const Duration(milliseconds: 300));
            continue;
          }
          rethrow;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Test subido. ${url ?? ''}')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Test Storage: [${e.code}] ${e.message ?? ''}')),
      );
    } finally {
      if (mounted) {
        setState(() => _subiendo = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text('No has iniciado sesión', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final docRef = FirebaseFirestore.instance.collection('usuarios').doc(user.uid);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Configuración de perfil')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
          }

          final data = snap.data?.data() ?? {};
          final fotoUrl = (data['fotoUrl'] ?? '').toString();
          final nombre = (data['nombre'] ?? '').toString();

          if (_nombreCtrl.text.isEmpty && nombre.isNotEmpty) {
            _nombreCtrl.text = nombre;
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AvatarCircle(
                      imageUrl: fotoUrl,
                      name: nombre,
                      size: 112,
                    ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: ElevatedButton.icon(
                        onPressed: _subiendo ? null : () => _cambiarFoto(user.uid),
                        icon: _subiendo
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.camera_alt, color: Colors.green),
                        label: Text(_subiendo ? 'Subiendo…' : 'Cambiar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (fotoUrl.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _eliminarFoto(user.uid),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar foto'),
                ),
              const SizedBox(height: 24),
              const Text('Nombre', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              TextField(
                controller: _nombreCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Tu nombre',
                  hintStyle: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _guardando ? null : () => _guardarNombre(user.uid),
                  icon: _guardando
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save, color: Colors.green),
                  label: Text(_guardando ? 'Guardando…' : 'Guardar cambios'),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _subiendo ? null : () => _pruebaSubida(user.uid),
                icon: const Icon(Icons.upload_file, color: Colors.greenAccent),
                label: const Text('PRUEBA SUBIDA (test.txt)',
                    style: TextStyle(color: Colors.greenAccent)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.greenAccent),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
