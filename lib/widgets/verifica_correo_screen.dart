import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/logout.dart';

/// Pantalla amable de verificación (email/password). Reutilizable en gate y rutas.
class VerificaCorreoScreen extends StatefulWidget {
  const VerificaCorreoScreen({
    super.key,
    this.onVerified,
  });

  /// Tras confirmar verificación (p. ej. gate hace setState).
  final VoidCallback? onVerified;

  @override
  State<VerificaCorreoScreen> createState() => _VerificaCorreoScreenState();
}

class _VerificaCorreoScreenState extends State<VerificaCorreoScreen> {
  bool _sending = false;
  bool _checking = false;
  bool _cerrandoSesion = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _sendVerification() async {
    final u = _user;
    if (u == null) return;
    if (u.emailVerified) {
      widget.onVerified?.call();
      return;
    }
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await u.sendEmailVerification();
      _snack('Te enviamos el enlace a tu correo. Revisa también spam.');
    } on FirebaseAuthException catch (e) {
      _snack('No se pudo enviar (${e.code}).');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _checkVerified() async {
    final u = _user;
    if (u == null) return;
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await u.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      if (!mounted) return;
      if (refreshed?.emailVerified == true) {
        widget.onVerified?.call();
        setState(() {});
      } else {
        _snack('Aún no aparece verificado. Abre el enlace del correo e inténtalo de nuevo.');
      }
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _cerrarSesion() async {
    if (_cerrandoSesion) return;
    setState(() => _cerrandoSesion = true);
    try {
      await cerrarSesion(context);
    } finally {
      if (mounted) setState(() => _cerrandoSesion = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    final email = (u?.email ?? '').trim();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Revisa tu correo'),
        actions: [
          TextButton(
            onPressed: _cerrandoSesion ? null : _cerrarSesion,
            child: Text(_cerrandoSesion ? '...' : 'Cerrar sesión'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.mark_email_read_outlined, size: 56, color: cs.primary),
              const SizedBox(height: 20),
              Text(
                'Un paso rápido para proteger tu cuenta',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Enviamos un enlace a:\n${email.isEmpty ? '(tu correo)' : email}\n\n'
                'Ábrelo y vuelve aquí con «Ya verifiqué».',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.75),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _sending ? null : _sendVerification,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(_sending ? 'Enviando...' : 'Reenviar enlace'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _checking ? null : _checkVerified,
                icon: _checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_checking ? 'Comprobando...' : 'Ya verifiqué'),
              ),
              const Spacer(),
              Text(
                'Con Google no necesitas este paso. '
                'Hasta verificar el correo no podrás pedir viajes ni usar el pool.',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
