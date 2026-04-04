import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flygo_nuevo/servicios/disponibilidad_service.dart';

class Roles {
  static const String cliente = 'cliente';
  static const String taxista = 'taxista';
  static const String admin   = 'admin';
}

class RolesService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _usuarios => _db.collection('usuarios');

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

  static Future<bool> isCliente(String uid) async => (await getRol(uid)) == Roles.cliente;

  static Future<void> setRol(String uid, String rol, {Map<String, dynamic>? extra}) async {
    await _usuarios.doc(uid).set({
      'rol': rol.toLowerCase().trim(),
      'actualizadoEn': FieldValue.serverTimestamp(),
      if (extra != null) ...extra,
    }, SetOptions(merge: true));
  }

  static Future<void> ensureUserDoc(String uid, {String defaultRol = Roles.cliente}) async {
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

  static Future<void> syncRolConColeccionRoles(String uid) async {
    final rolesDoc = await _db.collection('roles').doc(uid).get();
    if (!rolesDoc.exists) return;
    final r = (rolesDoc.data()?['rol'] as String?)?.toLowerCase().trim();
    if (r == null) return;
    if ([Roles.admin, Roles.taxista, Roles.cliente].contains(r)) {
      await _usuarios.doc(uid).set({'rol': r, 'actualizadoEn': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    }
  }

  /// Lee `disponible` de forma tolerante (bool / int legacy / string).
  static bool leerDisponibleDesdeUsuarioDoc(Map<String, dynamic>? data) {
    if (data == null) return false;
    final d = data['disponible'];
    if (d is bool) return d;
    if (d is int) return d != 0;
    if (d is num) return d != 0;
    if (d is String) {
      final s = d.toLowerCase().trim();
      return s == 'true' ||
          s == '1' ||
          s == 'si' ||
          s == 'sí' ||
          s == 'yes';
    }
    return false;
  }

  static Stream<bool> streamDisponibilidad(String uid) {
    return _usuarios.doc(uid).snapshots().map((snap) {
      return leerDisponibleDesdeUsuarioDoc(snap.data());
    });
  }

  static Future<bool> getDisponibilidad(String uid) async {
    final doc = await _usuarios.doc(uid).get();
    return leerDisponibleDesdeUsuarioDoc(doc.data());
  }

  static Future<void> setDisponibilidad(String uid, bool value) async {
    if (value) {
      await DisponibilidadService.activar(uid);
    } else {
      final ref = _usuarios.doc(uid);
      try {
        await ref.update({
          'disponible': false,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (e) {
        if (e.code == 'not-found') {
          await ref.set({
            'disponible': false,
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          rethrow;
        }
      }
    }
  }
}
