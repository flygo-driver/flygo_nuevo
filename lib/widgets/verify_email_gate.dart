// lib/widgets/verify_email_gate.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VerifyEmailGate extends StatefulWidget {
  final Widget childWhenVerified;
  const VerifyEmailGate({super.key, required this.childWhenVerified});

  @override
  State<VerifyEmailGate> createState() => _VerifyEmailGateState();
}

class _VerifyEmailGateState extends State<VerifyEmailGate> {
  bool _sending = false;
  bool _checking = false;

  User get _user => FirebaseAuth.instance.currentUser!;

  Future<void> _sendVerification() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _sending = true);
    try {
      await _user.sendEmailVerification();
      messenger?.showSnackBar(
        const SnackBar(content: Text('Enviamos el correo de verificación. Revisa tu bandeja.')),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('No se pudo enviar la verificación: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      await _user.reload();
    } catch (_) {
      // opcional: log/snack
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;
    if (verified) return widget.childWhenVerified;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Verifica tu correo')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Para usar todas las funciones, verifica tu email.',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 12),
            Text('Correo: ${_user.email ?? ''}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _sending ? null : _sendVerification,
              icon: const Icon(Icons.mark_email_read),
              label: Text(_sending ? 'Enviando...' : 'Enviar verificación'),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _checking ? null : _check,
              icon: const Icon(Icons.refresh),
              label: Text(_checking ? 'Comprobando...' : 'Ya verifiqué, comprobar'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Puedes seguir navegando, pero aceptar/completar viajes y pagos '
              'se bloquean hasta verificar.',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
