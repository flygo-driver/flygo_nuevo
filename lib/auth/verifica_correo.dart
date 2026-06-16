// lib/auth/verifica_correo.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flygo_nuevo/servicios/email_verification_policy.dart';
import 'package:flygo_nuevo/widgets/verifica_correo_screen.dart';

class VerificaCorreoPage extends StatefulWidget {
  const VerificaCorreoPage({super.key});

  @override
  State<VerificaCorreoPage> createState() => _VerificaCorreoPageState();
}

class _VerificaCorreoPageState extends State<VerificaCorreoPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirectSiNoHaceFalta());
  }

  void _goAuthCheck() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
  }

  void _goLogin() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
  }

  void _redirectSiNoHaceFalta() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      _goLogin();
      return;
    }
    if (!EmailVerificationPolicy.needsVerification(u)) {
      _goAuthCheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!EmailVerificationPolicy.needsVerification(u)) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return VerificaCorreoScreen(onVerified: _goAuthCheck);
  }
}
