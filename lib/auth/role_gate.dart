// DEPRECATED: usar AuthGatePublic / RaiIdentityRouter. Este widget solo redirige
// al router por compatibilidad (misma puerta que main.dart y /auth_check).
//
// lib/auth/role_gate.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/auth/rai_identity_router.dart';
import 'package:flygo_nuevo/auth/seleccion_usuario.dart';

/// Compatibilidad legacy → [RaiIdentityRouter.buildGateForUsuarioData].
class RoleGate extends StatelessWidget {
  const RoleGate({super.key});

  static Future<void> _ensureUsuarioDoc(User user) async {
    final db = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();
    final uRef = db.collection('usuarios').doc(user.uid);
    final rRef = db.collection('roles').doc(user.uid);

    DocumentSnapshot<Map<String, dynamic>> uSnap = await uRef.get();
    if (uSnap.exists) {
      final data = uSnap.data() ?? <String, dynamic>{};
      final rol = (data['rol'] ?? '').toString().trim().toLowerCase();
      if (rol.isNotEmpty) return;
    }

    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 90));
      uSnap = await uRef.get();
      if (uSnap.exists) {
        final data = uSnap.data() ?? <String, dynamic>{};
        final rol = (data['rol'] ?? '').toString().trim().toLowerCase();
        if (rol.isNotEmpty) return;
      }
    }

    String rol = 'cliente';
    try {
      final rSnap = await rRef.get();
      final rolRoles =
          (rSnap.data()?['rol'] ?? '').toString().trim().toLowerCase();
      if (rolRoles == 'taxista' ||
          rolRoles == 'admin' ||
          rolRoles == 'cliente') {
        rol = rolRoles;
      }
    } catch (_) {}

    await uRef.set({
      'uid': user.uid,
      'email': (user.email ?? '').toString(),
      'nombre': (user.displayName ?? '').toString(),
      'telefono': (user.phoneNumber ?? '').toString(),
      'fotoUrl': (user.photoURL ?? '').toString(),
      'rol': rol,
      'updatedAt': now,
      'actualizadoEn': now,
      'lastLogin': now,
      'fechaRegistro': now,
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data ?? FirebaseAuth.instance.currentUser;
        if (authSnap.connectionState == ConnectionState.waiting &&
            user == null) {
          return RaiIdentitySplash.scaffold();
        }
        if (authSnap.hasError) {
          debugPrint('[RAI_IDENTITY] RoleGate auth error=${authSnap.error}');
          return _errorScaffold('Error de autenticación:\n${authSnap.error}');
        }
        if (user == null) {
          return const SeleccionUsuario();
        }

        final doc =
            FirebaseFirestore.instance.collection('usuarios').doc(user.uid);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: doc.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return RaiIdentitySplash.scaffold();
            }

            if (!snap.hasData || !snap.data!.exists) {
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: () async {
                  await _ensureUsuarioDoc(user);
                  return doc.get();
                }(),
                builder: (context, ensured) {
                  if (ensured.connectionState != ConnectionState.done) {
                    return RaiIdentitySplash.scaffold();
                  }
                  if (ensured.hasError) {
                    debugPrint(
                      '[RAI_IDENTITY] RoleGate ensure error=${ensured.error}',
                    );
                    return _errorScaffold(
                      'No pudimos preparar tu perfil.\n${ensured.error}',
                    );
                  }
                  final fresh = ensured.data;
                  if (fresh == null || !fresh.exists) {
                    return const SeleccionUsuario();
                  }
                  return RaiIdentityRouter.buildGateForUsuarioData(
                    context,
                    user,
                    fresh.data() ?? {},
                  );
                },
              );
            }

            return RaiIdentityRouter.buildGateForUsuarioData(
              context,
              user,
              snap.data!.data() ?? {},
            );
          },
        );
      },
    );
  }

  static Widget _errorScaffold(String texto) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}
