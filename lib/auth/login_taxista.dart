// lib/auth/login_taxista.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/auth/seleccion_usuario.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

const bool kQaFlexibleAccess =
    bool.fromEnvironment('QA_FLEX', defaultValue: !kReleaseMode);

/// Misma bienvenida TikTok; abre con pestaña Conductor seleccionada.
class LoginTaxista extends StatefulWidget {
  const LoginTaxista({super.key});
  @override
  State<LoginTaxista> createState() => _LoginTaxistaState();
}

class _LoginTaxistaState extends State<LoginTaxista> {
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
        unawaited(_irAuthCheck());
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _loginAnonTaxista() async {
    _suppressAuthRedirect = true;
    try {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      final uid = cred.user!.uid;
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'uid': uid,
        'rol': 'taxista',
        'registroTaxistaCompleto': false,
        'disponible': false,
        'docsEstado': 'pendiente',
        'fechaRegistro': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await ViajesRepo.reconciliarActivosTaxista(uid);
      if (!mounted) return;
      _autoRedirectDone = true;
      await _irAuthCheck();
    } finally {
      _suppressAuthRedirect = false;
    }
  }

  Future<void> _irAuthCheck() async {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const SeleccionUsuario(
          initialRol: 'taxista',
          showBackButton: true,
        ),
        if (kQaFlexibleAccess)
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: SafeArea(
              child: TextButton(
                onPressed: _loginAnonTaxista,
                child: const Text('Entrar rápido conductor (QA)'),
              ),
            ),
          ),
      ],
    );
  }
}
