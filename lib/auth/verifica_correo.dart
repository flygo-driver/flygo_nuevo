// lib/auth/verifica_correo.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VerificaCorreoPage extends StatefulWidget {
  const VerificaCorreoPage({super.key});

  @override
  State<VerificaCorreoPage> createState() => _VerificaCorreoPageState();
}

class _VerificaCorreoPageState extends State<VerificaCorreoPage> {
  bool _sending = false;
  bool _checking = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  bool _isGoogle(User u) =>
      u.providerData.any((p) => p.providerId == 'google.com');

  bool get _needsVerification {
    final u = _user;
    if (u == null) return false;

    // si es anónimo no verifica
    if (u.isAnonymous) return false;

    // si es google, NO lo obligues (google normalmente ya viene verificado)
    if (_isGoogle(u)) return false;

    // si no hay email
    if ((u.email ?? '').trim().isEmpty) return false;

    return !u.emailVerified;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _goAuthCheck() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
  }

  void _goLogin() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
  }

  void _autoRedirectIfNotNeeded() {
    // ✅ NO uses Navigator en build.
    // Esto corre después del primer frame y sin warning.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final u = _user;
      // si no hay usuario -> login
      if (u == null) {
        _goLogin();
        return;
      }

      // si NO necesita verificación -> auth_check
      if (!_needsVerification) {
        _goAuthCheck();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _autoRedirectIfNotNeeded();
  }

  // Por si el usuario vuelve a esta pantalla desde backstack,
  // o cambia el estado, aquí también re-evaluamos.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _autoRedirectIfNotNeeded();
  }

  Future<void> _sendVerification() async {
    final u = _user;
    if (u == null) {
      _snack('No hay usuario activo.');
      return;
    }
    final email = (u.email ?? '').trim();
    if (email.isEmpty) {
      _snack('Esta cuenta no tiene correo para verificar.');
      return;
    }
    if (_isGoogle(u)) {
      _snack('Cuentas Google no requieren verificación.');
      return;
    }
    if (u.emailVerified) {
      _snack('Tu correo ya está verificado.');
      return;
    }

    if (_sending) return;
    setState(() => _sending = true);

    try {
      await u.sendEmailVerification();
      if (!mounted) return;
      _snack('Te enviamos el correo de verificación.');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _snack('No se pudo enviar (${e.code}).');
    } catch (e) {
      if (!mounted) return;
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _checkVerified() async {
    final u = _user;
    if (u == null) {
      _snack('No hay usuario activo.');
      return;
    }

    if (_checking) return;
    setState(() => _checking = true);

    try {
      await u.reload();
      final refreshed = FirebaseAuth.instance.currentUser;

      if (!mounted) return;

      if (refreshed == null) {
        _snack('Sesión cerrada.');
        _goLogin();
        return;
      }

      // google no se bloquea aquí
      if (_isGoogle(refreshed)) {
        _goAuthCheck();
        return;
      }

      if (refreshed.emailVerified) {
        _goAuthCheck();
      } else {
        _snack('Aún no está verificado. Abre el correo y verifica.');
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    final email = (u?.email ?? '').trim();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Verifica tu correo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 18),
            const Text(
              'Para usar todas las funciones, verifica tu email.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              'Correo: ${email.isEmpty ? '(sin correo)' : email}',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _sendVerification,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.mark_email_unread),
                label: Text(_sending ? 'Enviando...' : 'Enviar verificación'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _checking ? null : _checkVerified,
                icon: _checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label:
                    Text(_checking ? 'Comprobando...' : 'Ya verifiqué, comprobar'),
              ),
            ),
            const Spacer(),
            const Text(
              'Puedes seguir navegando, pero aceptar/completar viajes y pagos se bloquean hasta verificar.',
              style: TextStyle(color: Colors.white38),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
