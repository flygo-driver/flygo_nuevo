import 'package:cloud_firestore/cloud_firestore.dart';

class Roles {
  static const String cliente = 'cliente';
  static const String taxista = 'taxista';
  static const String admin = 'admin';
}

class RolesService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _usuarios =>
      _db.collection('usuarios');

  static Future<String?> getRol(String uid) async {
    final doc = await _usuarios.doc(uid).get();
    if (!doc.exists) return null;
    final rol = (doc.data()?['rol'] as String?)?.toLowerCase().trim();
    return (rol?.isNotEmpty ?? false) ? rol : null;
  }

  static Stream<String?> streamRol(String uid) {
    return _usuarios.doc(uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      final rol = (snap.data()?['rol'] as String?)?.toLowerCase().trim();
      return (rol?.isNotEmpty ?? false) ? rol : null;
    });
  }

  static Future<bool> isCliente(String uid) async {
    final r = await getRol(uid);
    return (r ?? '').toLowerCase() == Roles.cliente;
  }

  static Future<void> setRol(
    String uid,
    String rol, {
    Map<String, dynamic>? extra,
  }) async {
    await _usuarios.doc(uid).set({
      'rol': rol.toLowerCase().trim(),
      'actualizadoEn': FieldValue.serverTimestamp(),
      if (extra != null) ...extra,
    }, SetOptions(merge: true));
  }

  static Future<void> ensureUserDoc(
    String uid, {
    String defaultRol = Roles.cliente,
  }) async {
    final ref = _usuarios.doc(uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'rol': defaultRol.toLowerCase(),
        'disponible': false,
        'documentosCompletos': false,
        'docsEstado': 'pendiente',
        'creadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // --------- Disponibilidad ---------
  static Stream<bool?> streamDisponibilidad(String uid) {
    return _usuarios.doc(uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      final d = snap.data()?['disponible'];
      return (d is bool) ? d : null;
    });
  }

  static Future<bool?> getDisponibilidad(String uid) async {
    final doc = await _usuarios.doc(uid).get();
    if (!doc.exists) return null;
    final d = doc.data()?['disponible'];
    return (d is bool) ? d : null;
  }

  static Future<void> setDisponibilidad(String uid, bool disponible) async {
    await _usuarios.doc(uid).set({
      'disponible': disponible,
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // --------- Verificación documentos ---------
  static Future<void> setDocumentosCompletos(String uid, bool completos) async {
    await _usuarios.doc(uid).set({
      'documentosCompletos': completos,
      'docsEstado': completos ? 'aprobado' : 'pendiente',
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> setDocsEstado(String uid, String estado) async {
    await _usuarios.doc(uid).set({
      'docsEstado': estado.toLowerCase().trim(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
