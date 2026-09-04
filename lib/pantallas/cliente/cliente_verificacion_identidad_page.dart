import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flygo_nuevo/servicios/cliente_verificacion_identidad_service.dart';
import 'package:flygo_nuevo/servicios/flygo_storage.dart';

/// Galería solo en QA: en release la selfie tiene que salir de la cámara, si no
/// cualquiera sube la foto de otra persona y la verificación no verifica nada.
const bool _kSelfieDesdeGaleriaPrueba = !kReleaseMode;

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
  bool _subiendo = false;
  String? _motivoRechazo;

  @override
  void initState() {
    super.initState();
    _cargarMotivoRechazo();
  }

  /// Si el ADM rechazó la anterior, el pasajero merece saber por qué antes de
  /// repetirla; si no, vuelve a fallar por lo mismo.
  Future<void> _cargarMotivoRechazo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      final motivo = ClienteVerificacionIdentidadService.motivoRechazoDesde(
        snap.data() ?? const <String, dynamic>{},
      );
      if (!mounted || motivo == null) return;
      setState(() => _motivoRechazo = motivo);
    } catch (_) {
      // Sin conexión: la pantalla igual sirve para tomar la selfie.
    }
  }

  String _mensajeError(Object e) {
    if (e is FirebaseException) {
      final code = e.code.toLowerCase();
      if (code == 'permission-denied' || code == 'permission_denied') {
        return 'Sin permiso para subir la selfie. Cierra la app, vuelve a entrar e intenta otra vez.';
      }
      if (code == 'unauthenticated') {
        return 'Tu sesión expiró. Cierra sesión, entra de nuevo e intenta la selfie.';
      }
      if (code == 'storage-billing') {
        return 'El almacenamiento no está disponible. Se guardó un respaldo; si persiste, contacta soporte.';
      }
      final msg = (e.message ?? '').trim();
      if (msg.isNotEmpty) return 'Error al subir: $msg';
      return 'Error al subir la selfie ($code).';
    }
    return 'No se pudo completar: $e';
  }

  Future<void> _subirSelfieDesde(ImageSource source) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _subiendo = true);
    try {
      final XFile? picked = source == ImageSource.camera
          ? await _picker.pickImage(
              source: ImageSource.camera,
              preferredCameraDevice: CameraDevice.front,
              imageQuality: 85,
              maxWidth: 1024,
              maxHeight: 1024,
            )
          : await _picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
              maxWidth: 1024,
              maxHeight: 1024,
            );
      if (picked == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              source == ImageSource.gallery
                  ? 'No elegiste ninguna foto de la galería.'
                  : 'No se tomó la foto. Podés intentar de nuevo.',
            ),
          ),
        );
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

      final String url = await FlygoStorage.uploadSelfieVerificacionCliente(
        user: user,
        bytes: bytes,
      );

      await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set(
        <String, dynamic>{
          'verificacionIdentidadEn': FieldValue.serverTimestamp(),
          'verificacionIdentidadUrl': url,
          // Vuelve a la cola del ADM y limpia un rechazo anterior.
          ClienteVerificacionIdentidadService.campoRevision:
              ClienteVerificacionIdentidadService.revisionPendiente,
          ClienteVerificacionIdentidadService.campoMotivoRechazo: '',
          'actualizadoEn': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Confirmación completada. Ya puedes pedir tu viaje.'),
        ),
      );
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensajeError(e))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensajeError(e))),
      );
    } finally {
      if (mounted) setState(() => _subiendo = false);
    }
  }

  Future<void> _tomarSelfie() => _subirSelfieDesde(ImageSource.camera);

  Future<void> _elegirSelfieGaleria() =>
      _subirSelfieDesde(ImageSource.gallery);

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
          title: const Text('Confirmación de identidad'),
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
                  'Es una confirmación periódica, no una verificación con documento.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                    fontSize: 15,
                  ),
                ),
                if (_motivoRechazo != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Tu selfie anterior no fue aceptada: $_motivoRechazo\n'
                      'Tomá una nueva para poder seguir viajando.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onErrorContainer,
                        height: 1.4,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
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
                if (_kSelfieDesdeGaleriaPrueba) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _subiendo ? null : _elegirSelfieGaleria,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Elegir foto de galería (prueba)'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Opción temporal para probar sin usar la cámara.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.outline,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
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
