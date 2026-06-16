import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Subida de foto de documento taxista — copia de [DocumentosTaxista].
abstract final class TaxistaFotoVehiculoPicker {
  TaxistaFotoVehiculoPicker._();

  static const int maxBytes = 10 * 1024 * 1024;
  static const String tipoFotoVehiculo = 'fotoVehiculo';

  static void restaurarBarrasSistema() {
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

  static double scrollBottomPad(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final double sys = mq.viewPadding.bottom > mq.padding.bottom
        ? mq.viewPadding.bottom
        : mq.padding.bottom;
    return sys + 48;
  }

  /// Igual que `_elegirFuenteYSubir` en documentos_taxista.
  static Future<ImageSource?> elegirFuente(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext ctx) {
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
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.white),
                title: const Text(
                  'Cámara',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.white),
                title: const Text(
                  'Galería',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// Copia literal de `_seleccionarFotoYSubir` en documentos_taxista.
  ///
  /// [modoRegistro]: usa `set(merge)` en Firestore (el doc puede no existir aún
  /// en onboarding); documentos usa `update` porque el perfil ya está creado.
  static Future<String?> subirDocumentoTaxista({
    required String tipo,
    required ImageSource source,
    required ImagePicker picker,
    VoidCallback? onInicioSubida,
    bool modoRegistro = false,
  }) async {
    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      return null;
    }

    await u.getIdToken(true);

    final XFile? img = await picker.pickImage(
      source: source,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (img == null) {
      return null;
    }

    onInicioSubida?.call();

    try {
      final Uint8List bytes = await img.readAsBytes();
      if (bytes.length > maxBytes) {
        throw Exception('El archivo excede 10 MB');
      }

      final int ts = DateTime.now().millisecondsSinceEpoch;
      final String storagePath = 'documentos_taxista/${u.uid}/${tipo}_$ts.jpg';
      final Reference ref = FirebaseStorage.instance.ref(storagePath);

      if (kDebugMode) {
        debugPrint('[DocTaxista] subiendo tipo=$tipo path=$storagePath');
      }

      await ref.putData(
        bytes,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: <String, String>{'uid': u.uid, 'tipo': tipo},
        ),
      );
      final String url = await ref.getDownloadURL();

      if (modoRegistro) {
        await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).set(
          <String, dynamic>{
            'fotoVehiculoUrl': url,
            'docs': <String, dynamic>{
              'fotoVehiculoUrl': url,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            'actualizadoEn': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } else {
        await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).update(
          <String, dynamic>{
            'docs.${tipo}Url': url,
            'docs.updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          },
        );
      }

      if (kDebugMode) {
        debugPrint('[DocTaxista] OK tipo=$tipo url=$url');
      }
      return url;
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('[DocTaxista] FirebaseException ${e.code}: ${e.message}');
      }
      rethrow;
    }
  }

  static Future<String?> elegirYSubirFotoVehiculo({
    required BuildContext context,
    required ImagePicker picker,
    VoidCallback? onInicioSubida,
    bool modoRegistro = false,
  }) async {
    final ImageSource? source = await elegirFuente(context);
    if (source == null) {
      return null;
    }
    return subirDocumentoTaxista(
      tipo: tipoFotoVehiculo,
      source: source,
      picker: picker,
      onInicioSubida: onInicioSubida,
      modoRegistro: modoRegistro,
    );
  }

  static String mensajeErrorSubida(Object e) {
    if (e is FirebaseException) {
      if (e.code == 'permission-denied') {
        return 'No tienes permisos para subir la foto. Contacta al soporte.';
      }
      if (e.code == 'unauthenticated') {
        return 'Sesión expirada. Vuelve a iniciar sesión e intenta otra vez.';
      }
      if (e.code == 'not-found') {
        return 'No se encontró tu perfil. Guarda el registro o vuelve a entrar.';
      }
      final String det = (e.message ?? e.code).trim();
      return 'No se pudo subir la foto ($det).';
    }
    final String s = e.toString().replaceFirst('Exception: ', '');
    return 'No se pudo subir la foto: $s';
  }
}
