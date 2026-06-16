import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:flygo_nuevo/servicios/app_flavor_rol_guard.dart';
import 'package:flygo_nuevo/servicios/google_auth.dart';

/// Flags QA compartidos por [AuthCheck] y resolución de rol.
const bool kQaFlexibleAccess =
    bool.fromEnvironment('QA_FLEX', defaultValue: !kReleaseMode);
const bool kQaAllowAnonOnAuthError =
    bool.fromEnvironment('QA_ALLOW_ANON_ERR', defaultValue: !kReleaseMode);

const bool kProductionStrict =
    bool.fromEnvironment('PROD_STRICT', defaultValue: true);

/// Resolución de rol Firestore (usuarios → roles → pending Google → flavor).
class RaiIdentityResolve {
  RaiIdentityResolve._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String sanitizeRol(String rol) {
    final r = rol.trim().toLowerCase();
    if (r == 'administrador') return 'admin';
    if (r == 'admin' || r == 'taxista' || r == 'cliente') return r;
    if (r == 'driver') return 'taxista';
    if (r == 'user') return 'cliente';
    return 'cliente';
  }

  static String rolDesdeUsuarioData(Map<String, dynamic> data) {
    var rol = (data['rol'] ?? '').toString().toLowerCase().trim();
    if (rol.isEmpty) rol = 'cliente';
    return sanitizeRol(rol);
  }

  static String _fallbackRolSiFirestoreFalla() =>
      AppFlavorRolGuard.rolEsperadoPorFlavor() ?? 'cliente';

  static Future<String> resolveRolSafe(User user) async {
    final uid = user.uid;
    String rolUsuarios = '';
    String rolRoles = '';

    try {
      final uSnap = await _db.collection('usuarios').doc(uid).get();
      if (uSnap.exists) {
        final dataUsuarios = uSnap.data();
        final rol =
            (dataUsuarios?['rol'] ?? '').toString().trim().toLowerCase();
        if (rol.isNotEmpty) {
          rolUsuarios = sanitizeRol(rol);
          _tryTouchUsuario(uid);
          return rolUsuarios;
        }
      }
    } on FirebaseException catch (e) {
      if (kProductionStrict && kReleaseMode) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: e.code,
          message: 'Firestore (/usuarios) bloqueó o falló: ${e.code}',
        );
      }
      return _fallbackRolSiFirestoreFalla();
    }

    try {
      final rSnap = await _db.collection('roles').doc(uid).get();
      if (rSnap.exists) {
        final rolRolesRaw =
            (rSnap.data()?['rol'] as String?)?.toLowerCase().trim();
        if ((rolRolesRaw ?? '').isNotEmpty) {
          rolRoles = sanitizeRol(rolRolesRaw ?? '');
        }
      }
    } on FirebaseException catch (e) {
      if (kProductionStrict && kReleaseMode) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: e.code,
          message: 'Firestore (/roles) bloqueó o falló: ${e.code}',
        );
      }
      return _fallbackRolSiFirestoreFalla();
    }

    String rolFinal = rolUsuarios.isNotEmpty
        ? rolUsuarios
        : (rolRoles.isNotEmpty ? rolRoles : '');

    if (rolFinal.isEmpty) {
      final pendingRaw = GoogleAuthService.consumePendingGoogleEntradaRol();
      if (pendingRaw != null) {
        final p = sanitizeRol(pendingRaw);
        if (p == 'taxista' || p == 'cliente') rolFinal = p;
      }
    }

    if (rolFinal.isEmpty) rolFinal = _fallbackRolSiFirestoreFalla();
    rolFinal = sanitizeRol(rolFinal);

    await _tryEnsureUsuarioDoc(
      uid,
      preferRol: rolFinal,
      email: user.email,
      displayName: user.displayName,
      phone: user.phoneNumber,
    );

    return rolFinal;
  }

  static void _tryTouchUsuario(String uid) {
    final now = FieldValue.serverTimestamp();
    _db.collection('usuarios').doc(uid).set(
      {'lastLogin': now, 'updatedAt': now, 'actualizadoEn': now},
      SetOptions(merge: true),
    ).catchError((_) {});
  }

  static Future<void> _tryEnsureUsuarioDoc(
    String uid, {
    required String preferRol,
    String? email,
    String? displayName,
    String? phone,
  }) async {
    final ref = _db.collection('usuarios').doc(uid);
    final now = FieldValue.serverTimestamp();

    try {
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set({
          'uid': uid,
          'email': email ?? '',
          'nombre': displayName ?? '',
          'telefono': phone ?? '',
          'rol': preferRol,
          'fechaRegistro': now,
          'actualizadoEn': now,
        });
        return;
      }

      final data = snap.data() ?? <String, dynamic>{};
      final hadRol = (data['rol'] ?? '').toString().trim().isNotEmpty;

      if (!hadRol) {
        await ref.set(
          {'rol': preferRol, 'updatedAt': now, 'actualizadoEn': now},
          SetOptions(merge: true),
        );
      } else {
        await ref.set(
          {'lastLogin': now, 'updatedAt': now, 'actualizadoEn': now},
          SetOptions(merge: true),
        );
      }
    } catch (_) {}
  }
}
