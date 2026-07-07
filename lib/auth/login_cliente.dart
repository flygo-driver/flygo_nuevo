// lib/auth/login_cliente.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/auth/seleccion_usuario.dart';

const bool kQaFlexibleAccess =
    bool.fromEnvironment('QA_FLEX', defaultValue: !kReleaseMode);
const bool kQaAllowAnonOnCollision =
    bool.fromEnvironment('QA_ALLOW_ANON', defaultValue: !kReleaseMode);
const bool kQaAllowAnonOnAuthError =
    bool.fromEnvironment('QA_ALLOW_ANON_ERR', defaultValue: !kReleaseMode);

class LoginCliente extends StatefulWidget {
  const LoginCliente({super.key});
  @override
  State<LoginCliente> createState() => _LoginClienteState();
}

class _LoginClienteState extends State<LoginCliente> {
  StreamSubscription<User?>? _authSub;
  bool _autoRedirectDone = false;
  bool _suppressAuthRedirect = false;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || _autoRedirectDone || _suppressAuthRedirect) return;
      if (user != null) {
        _autoRedirectDone = true;
        _goAuthCheck();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _goAuthCheck() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
  }

  Future<void> _safeUpsertUsuarioCliente(String uid) async {
    try {
      final ref = FirebaseFirestore.instance.collection('usuarios').doc(uid);
      final snap = await ref.get();
      final nowTs = FieldValue.serverTimestamp();
      if (!snap.exists) {
        await ref.set({
          'uid': uid,
          'rol': 'cliente',
          'registroClienteCompleto': false,
          'nombre': '',
          'telefono': '',
          'fechaRegistro': nowTs,
          'lastLogin': nowTs,
          'updatedAt': nowTs,
          'actualizadoEn': nowTs,
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> _loginAnonCliente() async {
    _suppressAuthRedirect = true;
    try {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      await _safeUpsertUsuarioCliente(cred.user!.uid);
      if (!mounted) return;
      _autoRedirectDone = true;
      _goAuthCheck();
    } finally {
      _suppressAuthRedirect = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const SeleccionUsuario(
          initialRol: 'cliente',
          showBackButton: true,
        ),
        if (kQaFlexibleAccess)
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: SafeArea(
              child: TextButton(
                onPressed: _loginAnonCliente,
                child: const Text('Entrar rápido pasajero (QA)'),
              ),
            ),
          ),
      ],
    );
  }
}
