// lib/servicios/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ================= Usuario actual =================
  User? getCurrentUser() => _auth.currentUser;

  // ================= Email/Password =================
  Future<void> loginUser(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = cred.user?.uid;
    if (uid != null) {
      await _db.collection('usuarios').doc(uid).set(
        {'lastLogin': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  // ================= Registro TAXISTA =================
  Future<void> registerUser(
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
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user!;
    await user.updateDisplayName(nombre);

    // 🔔 Enviar verificación de correo (no bloquea si falla)
    try {
      await user.sendEmailVerification();
    } catch (_) {}

    final uid = user.uid;

    await _db.collection('usuarios').doc(uid).set({
      'uid': uid,
      'email': email.trim(),
      'rol': rol.toLowerCase(), // "taxista" esperado aquí
      'nombre': nombre,
      'telefono': telefono,
      'direccion': direccion,

      // Vehículo
      'marca': marca,
      'modelo': modelo,
      'anio': anio,
      'color': color,
      'placa': placa,

      // Estados iniciales taxista
      if (rol.toLowerCase() == 'taxista') 'docsEstado': 'pendiente',
      if (rol.toLowerCase() == 'taxista') 'disponible': false,

      // Metadatos
      'fechaRegistro': FieldValue.serverTimestamp(),
      'lastLogin': FieldValue.serverTimestamp(),
      'authProvider': 'password',
    }, SetOptions(merge: true));
  }

  // ================= Registro CLIENTE =================
  Future<void> registerCliente({
    required String email,
    required String password,
    required String nombre,
    required String telefono,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user!;
    await user.updateDisplayName(nombre);

    // 🔔 Enviar verificación de correo (no bloquea si falla)
    try {
      await user.sendEmailVerification();
    } catch (_) {}

    final uid = user.uid;

    await _db.collection('usuarios').doc(uid).set({
      'uid': uid,
      'email': email.trim(),
      'rol': 'cliente',
      'nombre': nombre,
      'telefono': telefono,
      'fechaRegistro': FieldValue.serverTimestamp(),
      'lastLogin': FieldValue.serverTimestamp(),
      'authProvider': 'password',
    }, SetOptions(merge: true));
  }
}
