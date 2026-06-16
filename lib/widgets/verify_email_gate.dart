import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/email_verification_policy.dart';
import 'package:flygo_nuevo/widgets/verifica_correo_screen.dart';

/// Bloquea solo cuentas email/password sin [User.emailVerified].
/// Google entra directo al [childWhenVerified].
class VerifyEmailGate extends StatefulWidget {
  const VerifyEmailGate({super.key, required this.childWhenVerified});

  final Widget childWhenVerified;

  @override
  State<VerifyEmailGate> createState() => _VerifyEmailGateState();
}

class _VerifyEmailGateState extends State<VerifyEmailGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, _) {
        final user = FirebaseAuth.instance.currentUser;
        if (!EmailVerificationPolicy.needsVerification(user)) {
          return widget.childWhenVerified;
        }
        return VerificaCorreoScreen(
          onVerified: () {
            if (mounted) setState(() {});
          },
        );
      },
    );
  }
}
