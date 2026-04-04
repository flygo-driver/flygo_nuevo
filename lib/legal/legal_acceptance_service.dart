import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/legal/terms_data.dart';

class LegalAcceptanceService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<bool> hasAccepted(String uid) async {
    try {
      final snap = await _db.collection('usuarios').doc(uid).get();
      final data = snap.data();
      final aceptacion = data?['aceptacionTerminos'];
      return aceptacion is Map &&
          (aceptacion['version'] ?? '').toString().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveAcceptance({
    required String uid,
    String version = kTermsVersion,
  }) async {
    final now = Timestamp.now();
    await _db.collection('usuarios').doc(uid).set(
      {
        'aceptacionTerminos': {
          'fecha': now,
          'version': version,
        },
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> saveAcceptanceForCurrentUser(
      {String version = kTermsVersion}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await saveAcceptance(uid: uid, version: version);
  }
}
