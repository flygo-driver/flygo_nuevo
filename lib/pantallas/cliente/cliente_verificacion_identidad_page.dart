import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Selfie obligatoria para renovar verificación de identidad del pasajero.
class ClienteVerificacionIdentidadPage extends StatefulWidget {
  const ClienteVerificacionIdentidadPage({super.key});

  @override
  State<ClienteVerificacionIdentidadPage> createState() =>
      _ClienteVerificacionIdentidadPageState();
}

class _ClienteVerificacionIdentidadPageState
    extends State<ClienteVerificacionIdentidadPage> {
  final _picker = ImagePicker();
  final FirebaseStorage _storage =
      FirebaseStorage.instanceFor(bucket: 'gs://flygo-rd.firebasestorage.app');

  bool _subiendo = false;

  Future<void> _tomarSelfie() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _subiendo = true);
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (picked == null) {
        return;
      }

      final bytes = await picked.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La foto pesa más de 5 MB.')),
        );
        return;
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage
          .ref()
          .child('perfiles')
          .child(uid)
          .child('verificacion_$ts.jpg');

      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));

      String? url;
      for (int i = 0; i < 3; i++) {
        try {
          url = await ref.getDownloadURL();
          break;
        } on FirebaseException catch (e) {
          if (e.code == 'object-not-found') {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            continue;
          }
          rethrow;
        }
      }
      if (url == null) {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'object-not-found',
          message: 'No se pudo obtener la URL de la selfie.',
        );
      }

      await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
        'verificacionIdentidadEn': FieldValue.serverTimestamp(),
        'verificacionIdentidadUrl': url,
        'fotoUrl': url,
        'actualizadoEn': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Verificación completada. Ya puedes pedir tu viaje.'),
        ),
      );
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al subir: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo completar: $e')),
      );
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !_subiendo,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0B1020) : const Color(0xFFF4F7FB),
        appBar: AppBar(
          title: const Text('Verificación de identidad'),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.face_retouching_natural_rounded,
                    size: 52,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Vamos a confirmar que eres tú',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Por seguridad, cada cierto tiempo (por defecto cada 30 días) '
                  'te pedimos una selfie rápida antes de pedir un viaje o reservar una gira.\n\n'
                  'No es en cada viaje: solo cuando vence el plazo desde la última verificación.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _subiendo ? null : _tomarSelfie,
                    icon: _subiendo
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.photo_camera_front_rounded),
                    label: Text(
                      _subiendo ? 'Subiendo selfie…' : 'Tomar selfie ahora',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _subiendo
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Ahora no'),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Debug: verificación obligatoria para pedir viajes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.outline, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
