// lib/servicios/auth_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _ensureUserDoc({
    required User user,
    required String rolSiFalta,
    Map<String, dynamic>? extra,
  }) async {
    final uid = user.uid;
    final ref = _db.collection('usuarios').doc(uid);
    final snap = await ref.get();

    final base = <String, dynamic>{
      'uid': uid,
      'email': user.email ?? '',
      'nombre': user.displayName ?? '',
      'lastLogin': FieldValue.serverTimestamp(),
      'authProvider': user.providerData.isNotEmpty
          ? user.providerData.first.providerId
          : 'password',
      'updatedAt': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    if (!snap.exists) {
      await ref.set({
        ...base,
        'rol': rolSiFalta,
        'fechaRegistro': FieldValue.serverTimestamp(),
        if (extra != null) ...extra,
      }, SetOptions(merge: true));
    } else {
      final current = snap.data()!;
      final rolActual = (current['rol'] ?? '').toString();
      await ref.set({
        ...base,
        if (rolActual.isEmpty) 'rol': rolSiFalta,
        if (extra != null) ...extra,
      }, SetOptions(merge: true));
    }
  }

  User? getCurrentUser() => _auth.currentUser;

  Future<void> logout() async {
    try { await GoogleSignIn().signOut(); } catch (_) {}
    await _auth.signOut();
  }

  Future<User> loginUser(
    String email,
    String password, {
    String? rolSiFalta,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user!;
    await _ensureUserDoc(user: user, rolSiFalta: rolSiFalta ?? 'cliente');
    return user;
  }

  // Google sin fetchSignInMethodsForEmail (sin warning)
  Future<User> signInWithGoogle({required String rol}) async {
    final gUser = await GoogleSignIn(scopes: ['email']).signIn();
    if (gUser == null) {
      throw FirebaseAuthException(code: 'sign_in_canceled', message: 'Inicio cancelado.');
    }
    final gAuth = await gUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: gAuth.accessToken,
      idToken: gAuth.idToken,
    );

    try {
      final cred = await _auth.signInWithCredential(credential);
      final user = cred.user!;
      await _ensureUserDoc(user: user, rolSiFalta: rol);
      return user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        // No enumeramos métodos (mejor práctica). Mensaje claro y listo.
        throw FirebaseAuthException(
          code: 'use-existing-method',
          message:
              'Este correo ya tiene una cuenta con otro método. Inicia sesión con tu método existente (correo/contraseña o el que ya usabas) y luego podrás vincular Google desde tu perfil.',
        );
      }
      rethrow;
    }
  }

  Future<User> registerUser(
    String email,
    String password,
    String rol, {
    required String nombre,
    required String telefono,
    required String direccion,
    required String marca,
    required String modelo,
    required String anio,
    required String color,
    required String placa,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user!;
      await user.updateDisplayName(nombre);
      try { await user.sendEmailVerification(); } catch (_) {}

      await _ensureUserDoc(
        user: user,
        rolSiFalta: rol.toLowerCase(),
        extra: {
          'telefono': telefono,
          'direccion': direccion,
          'marca': marca,
          'modelo': modelo,
          'anio': anio,
          'color': color,
          'placa': placa,
          'docsEstado': 'pendiente',
          'disponible': false,
        },
      );
      return user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        try {
          final u = await loginUser(email, password, rolSiFalta: rol);
          await _db.collection('usuarios').doc(u.uid).set({
            'telefono': telefono,
            'direccion': direccion,
            'marca': marca,
            'modelo': modelo,
            'anio': anio,
            'color': color,
            'placa': placa,
            'docsEstado': 'pendiente',
            'disponible': false,
          }, SetOptions(merge: true));
          return u;
        } on FirebaseAuthException catch (_) {
          throw FirebaseAuthException(
            code: 'email-already-in-use',
            message:
                'Este correo ya está registrado. Entra con tu método existente y completa tu perfil.',
          );
        }
      }
      rethrow;
    }
  }

  Future<User> registerCliente({
    required String email,
    required String password,
    required String nombre,
    required String telefono,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user!;
      await user.updateDisplayName(nombre);
      try { await user.sendEmailVerification(); } catch (_) {}
      await _ensureUserDoc(
        user: user,
        rolSiFalta: 'cliente',
        extra: {'telefono': telefono},
      );
      return user;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        // Sin enumerar métodos: pide usar el método con el que ya creó su cuenta
        throw FirebaseAuthException(
          code: 'email-already-in-use',
          message:
              'Este correo ya tiene una cuenta. Inicia sesión con tu método existente (correo/contraseña o Google).',
        );
      }
      rethrow;
    }
  }

  Future<void> sendResetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());
}
