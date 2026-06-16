import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:flygo_nuevo/firebase_bootstrap.dart';

/// URLs sentinel cuando la imagen vive en Firestore (Storage no disponible).
class RaiDocUrl {
  RaiDocUrl._();

  static const String prefix = 'rai-doc://';

  static String forTipo(String tipo) => '$prefix$tipo';

  static bool isFirestoreDoc(String? url) =>
      url != null && url.startsWith(prefix);

  static String tipoFromUrl(String url) => url.replaceFirst(prefix, '');
}

/// Storage con bucket explícito + respaldo Firestore si Storage falla (402/unknown).
class FlygoStorage {
  static const String bucketGs = 'gs://flygo-rd.firebasestorage.app';
  static const String bucketName = 'flygo-rd.firebasestorage.app';

  static FirebaseStorage get instance => FirebaseStorage.instanceFor(
        app: Firebase.app(),
        bucket: bucketGs,
      );

  static void log(String msg) {
    debugPrint('[FlygoStorage] $msg');
  }

  static Future<void> logDiagnostics() async {
    await FirebaseBootstrap.ensureInitialized();
    final FirebaseApp app = Firebase.app();
    log(
      'appId=${app.options.appId} project=${app.options.projectId} '
      'bucketCfg=${app.options.storageBucket} bucketSdk=${instance.bucket}',
    );
  }

  /// Carga bytes de documento guardado en Firestore (respaldo).
  static Future<Uint8List?> cargarDocImagen({
    required String uid,
    required String tipo,
  }) async {
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid)
            .collection('docs_imagenes')
            .doc(tipo)
            .get();
    final String? b64 = snap.data()?['b64'] as String?;
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  static Future<String> uploadDocumentoTaxista({
    required User user,
    required String tipo,
    required Uint8List bytes,
    String? localFilePath,
  }) async {
    await FirebaseBootstrap.ensureInitialized();
    await logDiagnostics();
    await user.getIdToken(true);

    final int ts = DateTime.now().millisecondsSinceEpoch;
    final String storagePath =
        'documentos_taxista/${user.uid}/${tipo}_$ts.jpg';
    final Reference ref = instance.ref(storagePath);
    final SettableMetadata meta = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: <String, String>{'uid': user.uid, 'tipo': tipo},
    );

    log(
      'upload tipo=$tipo path=$storagePath bytes=${bytes.length} '
      'localFilePath=$localFilePath',
    );

    if (localFilePath != null && localFilePath.isNotEmpty) {
      try {
        final File file = File(localFilePath);
        if (await file.exists()) {
          final int len = await file.length();
          log('putFile intento len=$len');
          await ref.putFile(file, meta);
          final String url = await ref.getDownloadURL();
          log('putFile OK tipo=$tipo');
          return url;
        }
        log('putFile omitido: archivo no existe');
      } on FirebaseException catch (e) {
        log('putFile error code=${e.code} msg=${e.message}');
      }
    }

    Future<String> putDataIntento() async {
      await user.getIdToken(true);
      log('putData intento bytes=${bytes.length}');
      await ref.putData(bytes, meta);
      final String url = await ref.getDownloadURL();
      log('putData OK tipo=$tipo');
      return url;
    }

    try {
      return await putDataIntento();
    } on FirebaseException catch (e) {
      log(
        'putData error code=${e.code} msg=${e.message} '
        '(permission-denied=reglas, unauthenticated=sesión, '
        'bucket-not-found=config, unknown=nativo/red/API-key)',
      );
      if (e.code == 'unauthenticated' ||
          e.code == 'unknown' ||
          (e.message ?? '').toLowerCase().contains('auth')) {
        log('reintento putData tras ${e.code}');
        await Future<void>.delayed(const Duration(milliseconds: 600));
        try {
          return await putDataIntento();
        } on FirebaseException catch (e2) {
          log('putData reintento falló code=${e2.code} msg=${e2.message}');
          if (e2.code == 'unknown' || e.code == 'unknown') {
            return _fallbackTrasStorageFallido(
              user: user,
              tipo: tipo,
              storagePath: storagePath,
              bytes: bytes,
            );
          }
          rethrow;
        }
      }
      if (e.code == 'unknown') {
        return _fallbackTrasStorageFallido(
          user: user,
          tipo: tipo,
          storagePath: storagePath,
          bytes: bytes,
        );
      }
      rethrow;
    }
  }

  static Future<String> _fallbackTrasStorageFallido({
    required User user,
    required String tipo,
    required String storagePath,
    required Uint8List bytes,
  }) async {
    try {
      return await _uploadViaRestApi(
        user: user,
        storagePath: storagePath,
        bytes: bytes,
        tipo: tipo,
      );
    } on FirebaseException catch (e) {
      log('REST falló code=${e.code} msg=${e.message} → firestore fallback');
      return _uploadViaFirestoreFallback(
        user: user,
        tipo: tipo,
        bytes: bytes,
      );
    }
  }

  static Future<String> _uploadViaRestApi({
    required User user,
    required String storagePath,
    required Uint8List bytes,
    required String tipo,
  }) async {
    final String? token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'unauthenticated',
        message: 'Sin token de sesión.',
      );
    }

    final Uri uri = Uri.parse(
      'https://firebasestorage.googleapis.com/v0/b/$bucketName/o'
      '?uploadType=media&name=${Uri.encodeComponent(storagePath)}',
    );

    log('REST upload tipo=$tipo bytes=${bytes.length}');

    final http.Response response = await http
        .post(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'image/jpeg',
          },
          body: bytes,
        )
        .timeout(const Duration(seconds: 120));

    log('REST status=${response.statusCode}');

    if (response.statusCode == 401) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'unauthenticated',
        message: response.body,
      );
    }
    if (response.statusCode == 403) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'permission-denied',
        message: response.body,
      );
    }
    if (response.statusCode == 402) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'storage-billing',
        message: 'Storage bloqueado (facturación Google). Usando respaldo.',
      );
    }
    if (response.statusCode != 200) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'unknown',
        message: 'REST ${response.statusCode}: ${response.body}',
      );
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'unknown',
        message: 'REST respuesta inválida.',
      );
    }

    final String tokens = decoded['downloadTokens']?.toString() ?? '';
    if (tokens.isNotEmpty) {
      final String downloadToken = tokens.split(',').first.trim();
      final String encodedPath = Uri.encodeComponent(storagePath);
      final String url =
          'https://firebasestorage.googleapis.com/v0/b/$bucketName/o/$encodedPath?alt=media&token=$downloadToken';
      log('REST OK tipo=$tipo');
      return url;
    }

    final String url = await instance.ref(storagePath).getDownloadURL();
    log('REST OK (getDownloadURL) tipo=$tipo');
    return url;
  }

  /// Guarda en usuarios/{uid}/docs_imagenes/{tipo} cuando Storage no responde.
  static Future<String> _uploadViaFirestoreFallback({
    required User user,
    required String tipo,
    required Uint8List bytes,
  }) async {
    if (bytes.length > 900 * 1024) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'invalid-argument',
        message: 'La imagen es demasiado grande (máx. 900 KB en modo respaldo).',
      );
    }

    log('firestore fallback tipo=$tipo bytes=${bytes.length}');
    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .collection('docs_imagenes')
        .doc(tipo)
        .set(<String, dynamic>{
      'b64': base64Encode(bytes),
      'contentType': 'image/jpeg',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    log('firestore fallback OK tipo=$tipo');
    return RaiDocUrl.forTipo(tipo);
  }
}
