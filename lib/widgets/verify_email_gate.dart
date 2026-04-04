// lib/widgets/verify_email_gate.dart
import 'package:flutter/material.dart';

class VerifyEmailGate extends StatelessWidget {
  final Widget childWhenVerified;
  const VerifyEmailGate({super.key, required this.childWhenVerified});

  @override
  Widget build(BuildContext context) {
    // 🔥 DESACTIVADO TOTAL
    // Entra SIEMPRE, debug y release
    return childWhenVerified;
  }
}
