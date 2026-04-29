import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  static final FirebaseStorage _st = FirebaseStorage.instance;

  // ─────────── AVATAR ───────────
  static Future<String> uploadAvatar({
    required String uid,
    required Uint8List bytes,
  }) async {
    final ref = _st.ref('users/$uid/profile.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  static Future<void> deleteAvatar(String uid) async {
    final ref = _st.ref('users/$uid/profile.jpg');
    try {
      await ref.delete();
    } catch (_) {}
  }

  // ─────────── DOCUMENTOS ───────────
  // tipo: 'licencia' | 'matricula' | 'seguro'
  static Future<String> uploadDocumento({
    required String uid,
    required String tipo,
    required Uint8List bytes,
  }) async {
    final ref = _st.ref('users/$uid/docs/$tipo.jpg');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  static Future<void> deleteDocumento({
    required String uid,
    required String tipo,
  }) async {
    final ref = _st.ref('users/$uid/docs/$tipo.jpg');
    try {
      await ref.delete();
    } catch (_) {}
  }
}
