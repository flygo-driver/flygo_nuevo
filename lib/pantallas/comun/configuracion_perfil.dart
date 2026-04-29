import 'package:flutter/foundation.dart';
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
  final _telefonoCtrl = TextEditingController();

  // ✅ Forzamos el bucket correcto (ajústalo si tu bucket es distinto)
  final FirebaseStorage _storage =
      FirebaseStorage.instanceFor(bucket: 'gs://flygo-rd.firebasestorage.app');

  bool _guardando = false;
  bool _subiendo = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cambiarFoto(String uid) async {
    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bcs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: bcs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(Icons.photo_camera, color: bcs.primary),
                title:
                    Text('Tomar foto', style: TextStyle(color: bcs.onSurface)),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: bcs.primary),
                title: Text('Elegir de galería',
                    style: TextStyle(color: bcs.onSurface)),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
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
      final ref =
          _storage.ref().child('perfiles').child(uid).child('avatar_$ts.jpg');

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

  /// Sincroniza nombre y teléfono con Firestore. Si ambos son válidos, marca el registro de cliente como completo.
  Future<void> _guardarDatosPerfil(String uid) async {
    final nombre = _nombreCtrl.text.trim();
    final telefono = _telefonoCtrl.text.trim().replaceAll(RegExp(r'\s'), '');

    if (nombre.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nombre demasiado corto.')));
      return;
    }
    if (telefono.length < 7) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Indica un teléfono válido (mínimo 7 dígitos) para completar el registro.'),
        ),
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'nombre': nombre,
        'telefono': telefono,
        'registroClienteCompleto': true,
        'actualizadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('✅ Datos guardados y registro sincronizado.')),
      );
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
        SnackBar(
            content: Text('❌ Test Storage: [${e.code}] ${e.message ?? ''}')),
      );
    } finally {
      if (mounted) {
        setState(() => _subiendo = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: Center(
          child: Text(
            'No has iniciado sesión',
            style: TextStyle(color: cs.onSurface),
          ),
        ),
      );
    }

    final docRef =
        FirebaseFirestore.instance.collection('usuarios').doc(user.uid);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(
          'Configuración de perfil',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: cs.primary));
          }

          final data = snap.data?.data() ?? {};
          final fotoUrl = (data['fotoUrl'] ?? '').toString();
          final nombre = (data['nombre'] ?? '').toString();
          final telefono = (data['telefono'] ?? '').toString();

          if (_nombreCtrl.text.isEmpty && nombre.isNotEmpty) {
            _nombreCtrl.text = nombre;
          }
          if (_telefonoCtrl.text.isEmpty && telefono.isNotEmpty) {
            _telefonoCtrl.text = telefono;
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Tu foto y datos son opcionales: puedes pedir viajes sin completar esta pantalla.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 16),
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
                        onPressed:
                            _subiendo ? null : () => _cambiarFoto(user.uid),
                        icon: _subiendo
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onPrimary,
                                ),
                              )
                            : Icon(Icons.camera_alt, color: cs.onPrimary),
                        label: Text(_subiendo ? 'Subiendo…' : 'Cambiar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
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
                  icon: Icon(Icons.delete_outline, color: cs.error),
                  label:
                      Text('Eliminar foto', style: TextStyle(color: cs.error)),
                ),
              const SizedBox(height: 24),
              Text(
                'Datos de registro',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text('Nombre', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              TextField(
                controller: _nombreCtrl,
                style: TextStyle(color: cs.onSurface),
                cursorColor: cs.primary,
                decoration: InputDecoration(
                  hintText: 'Tu nombre',
                  hintStyle: TextStyle(color: cs.onSurfaceVariant),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.45
                        : 0.65,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Teléfono', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              TextField(
                controller: _telefonoCtrl,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: cs.onSurface),
                cursorColor: cs.primary,
                decoration: InputDecoration(
                  hintText: 'Ej. 8091234567',
                  hintStyle: TextStyle(color: cs.onSurfaceVariant),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.45
                        : 0.65,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: cs.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      _guardando ? null : () => _guardarDatosPerfil(user.uid),
                  icon: _guardando
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onPrimary,
                          ),
                        )
                      : Icon(Icons.save, color: cs.onPrimary),
                  label: Text(
                      _guardando ? 'Guardando…' : 'Guardar datos de registro'),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _subiendo ? null : () => _pruebaSubida(user.uid),
                  icon: Icon(Icons.upload_file, color: cs.primary),
                  label: Text(
                    'PRUEBA SUBIDA (test.txt)',
                    style: TextStyle(color: cs.primary),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: cs.primary),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
