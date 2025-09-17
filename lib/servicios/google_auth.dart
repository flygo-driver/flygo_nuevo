import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GoogleAuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Login ESTRICTO con Google:
  /// - Si el doc NO existe: lo crea con el rol de la pantalla (cliente/taxista)
  /// - Si existe SIN 'rol': fija el rol de la pantalla
  /// - Si existe CON otro rol ≠ entrada -> signOut() y lanza FirebaseAuthException('role-mismatch')
  /// - Si coincide el rol -> OK
  static Future<void> signInWithGoogleStrict({
    required String entradaRol, // 'cliente' | 'taxista'
  }) async {
    final rolEntrada = (entradaRol == 'taxista') ? 'taxista' : 'cliente';

    // 1) Autenticación Google
    final provider = GoogleAuthProvider();
    UserCredential cred;
    if (kIsWeb) {
      provider.setCustomParameters({'prompt': 'select_account'});
      cred = await _auth.signInWithPopup(provider);
    } else {
      cred = await _auth.signInWithProvider(provider);
    }

    final user = cred.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'No se pudo obtener el usuario de Google.',
      );
    }

    // 2) Documento /usuarios/{uid}
    final ref = _db.collection('usuarios').doc(user.uid);
    final snap = await ref.get();

    final baseMerge = <String, dynamic>{
      'uid': user.uid,
      'email': user.email ?? '',
      'nombre': user.displayName ?? '',
      'telefono': user.phoneNumber ?? '',
      'fotoUrl': user.photoURL ?? '',
      'proveedor': 'google',
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    // 3) Crear si no existe -> con rol de la pantalla
    if (!snap.exists) {
      await ref.set({
        ...baseMerge,
        'rol': rolEntrada,
        'fechaRegistro': FieldValue.serverTimestamp(),
        'phoneVerified': false,
      });
      return;
    }

    // 4) Existe: validar rol
    final data = snap.data() ?? <String, dynamic>{};
    final rolActual = (data['rol'] ?? '').toString().trim().toLowerCase();

    if (rolActual.isEmpty) {
      await ref.set({
        ...baseMerge,
        'rol': rolEntrada,
      }, SetOptions(merge: true));
      return;
    }

    if (rolActual != rolEntrada) {
      await _auth.signOut();
      throw FirebaseAuthException(
        code: 'role-mismatch',
        message: 'Esta cuenta está registrada como "$rolActual". Entra por "$rolActual".',
      );
    }

    await ref.set(baseMerge, SetOptions(merge: true));
  }

  static Future<void> signOut() async {
    await _auth.signOut();
  }
}
