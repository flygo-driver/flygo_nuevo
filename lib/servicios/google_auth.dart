// lib/servicios/google_auth.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Login estricto con Google:
  /// - Crea /usuarios/{uid} con el rol indicado si no existe.
  /// - Si existe y no tiene 'rol', lo fija al rol indicado.
  /// - Si existe con otro rol, cierra sesión y lanza 'role-mismatch'.
  static Future<UserCredential> signInWithGoogleStrict({
    required String entradaRol, // 'cliente' | 'taxista'
  }) async {
    final rolEntrada =
        (entradaRol.trim().toLowerCase() == 'taxista') ? 'taxista' : 'cliente';

    UserCredential cred;

    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');
      cred = await _auth.signInWithPopup(provider);
    } else {
      final googleSignIn = GoogleSignIn(scopes: const ['email']);
      final GoogleSignInAccount? gUser = await googleSignIn.signIn();
      if (gUser == null) {
        throw FirebaseAuthException(
          code: 'aborted-by-user',
          message: 'Inicio de sesión cancelado.',
        );
      }
      final gAuth = await gUser.authentication;
      final oauth = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );
      cred = await _auth.signInWithCredential(oauth);
    }

    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'No se pudo obtener el usuario de Google.',
      );
    }

    final uid = user.uid;
    final ref = _db.collection('usuarios').doc(uid);
    final snap = await ref.get();
    final nowTs = FieldValue.serverTimestamp();

    if (!snap.exists) {
      await ref.set({
        'uid': uid,
        'email': user.email ?? '',
        'nombre': user.displayName ?? '',
        'telefono': user.phoneNumber ?? '',
        'fotoUrl': user.photoURL ?? '',
        'proveedor': 'google',
        'rol': rolEntrada,
        'fechaRegistro': nowTs,
        'actualizadoEn': nowTs,
      });
      return cred;
    }

    final data = snap.data() ?? <String, dynamic>{};
    final rolActual = (data['rol'] ?? '').toString().trim().toLowerCase();

    if (rolActual.isEmpty) {
      await ref.set(
        {
          'rol': rolEntrada,
          'updatedAt': nowTs,
          'actualizadoEn': nowTs,
        },
        SetOptions(merge: true),
      );
    } else if (rolActual != rolEntrada) {
      await signOut();
      throw FirebaseAuthException(
        code: 'role-mismatch',
        message: 'Esta cuenta está registrada como "$rolActual". Entra por "$rolActual".',
      );
    }

    await ref.set(
      {
        'nombre': user.displayName ?? (data['nombre'] ?? ''),
        'fotoUrl': user.photoURL ?? (data['fotoUrl'] ?? ''),
        'updatedAt': nowTs,
        'actualizadoEn': nowTs,
      },
      SetOptions(merge: true),
    );

    return cred;
  }

  /// Cierre de sesión “limpio”: sale de Google (móvil) y de Firebase.
  static Future<void> signOut() async {
    try {
      // En Android/iOS, cierra sesión del proveedor Google para forzar el selector de cuentas
      await GoogleSignIn().signOut();
    } catch (_) {
      // Ignorar si no aplica (web) o si no estaba conectado por Google
    }

    await FirebaseAuth.instance.signOut();
  }
}
