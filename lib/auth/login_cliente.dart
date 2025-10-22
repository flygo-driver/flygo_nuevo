import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/auth_service.dart';
import 'package:flygo_nuevo/servicios/google_auth.dart';

/// ================== FLAGS QA (modo flexible) ==================
/// En debug quedan true por default (porque !kReleaseMode == true).
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
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();

  bool _loadingEmail = false;
  bool _loadingGoogle = false;
  bool _obscurePass = true; // 👁️ toggle ver/ocultar

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  // ===== Helpers =====
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _goAuthCheck() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
  }

  Future<void> _sendResetPassword(String email) async {
    final e = email.trim();
    if (e.isEmpty) {
      _snack('Escribe tu correo para enviarte el reset.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: e);
      _snack('Te enviamos un correo para restablecer tu contraseña.');
    } on FirebaseAuthException catch (er) {
      final msg = switch (er.code) {
        'invalid-email' => 'Correo inválido.',
        'user-not-found' => 'No existe una cuenta con ese correo.',
        _ => 'No se pudo enviar el correo de restablecimiento.',
      };
      _snack(msg);
    }
  }

  Future<void> _loginAnonCliente() async {
    if (_loadingEmail || _loadingGoogle) return;
    final cred = await FirebaseAuth.instance.signInAnonymously();
    final uid = cred.user!.uid;
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'uid': uid,
        'rol': 'cliente',
        'email': _email.text.trim(),
        'nombre': '',
        'telefono': '',
        'fechaRegistro': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {/* no bloquea navegación */}
    _goAuthCheck();
  }

  /// Vincula una contraseña a una cuenta que actualmente entra con Google.
  Future<void> _vincularContrasenaConGoogle() async {
    if (_loadingGoogle || _loadingEmail) return;
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    final emailTyped = _email.text.trim();
    final passTyped = _pass.text;

    setState(() => _loadingGoogle = true);
    try {
      final cred =
          await GoogleAuthService.signInWithGoogleStrict(entradaRol: 'cliente');
      if (!mounted) return;
      final user = cred.user!;
      final emailCuenta = (user.email ?? '').toLowerCase();

      if (emailTyped.toLowerCase() != emailCuenta) {
        _snack(
            'Tu cuenta de Google es $emailCuenta. Usaremos ese correo para vincular la contraseña.');
      }

      final emailCred = EmailAuthProvider.credential(
        email: emailCuenta,
        password: passTyped,
      );
      await user.linkWithCredential(emailCred);

      try {
        final nowTs = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(user.uid)
            .set({'updatedAt': nowTs, 'actualizadoEn': nowTs},
                SetOptions(merge: true));
      } catch (_) {}

      _snack(
          'Listo: contraseña vinculada. Ya puedes entrar con correo y contraseña.');
      _goAuthCheck();
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'provider-already-linked':
        case 'credential-already-in-use':
        case 'email-already-in-use':
          msg =
              'Esta cuenta ya tiene contraseña. Entra con correo y contraseña.';
          break;
        case 'requires-recent-login':
          msg =
              'Por seguridad, vuelve a entrar con Google e intenta de nuevo.';
          break;
        case 'account-exists-with-different-credential':
          msg =
              'Esta cuenta existe con otro método. Entra con ese método y luego vincula la contraseña.';
          break;
        default:
          msg = 'No se pudo vincular la contraseña (${e.code}).';
      }
      _snack(msg);
    } catch (err) {
      _snack('Error: $err');
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  Future<void> _loginEmail() async {
    if (_loadingEmail || _loadingGoogle) return;
    if (!_formKey.currentState!.validate()) {
      _snack('Revisa los campos.');
      return;
    }

    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    final pass = _pass.text;

    setState(() => _loadingEmail = true);
    try {
      // 1) Sign in
      await AuthService().loginUser(email, pass);
      await FirebaseAuth.instance.currentUser?.reload();

      // 2) /usuarios (no bloquea navegación si falla)
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          final ref =
              FirebaseFirestore.instance.collection('usuarios').doc(uid);
          final snap = await ref.get();
          final nowTs = FieldValue.serverTimestamp();

          if (!snap.exists) {
            await ref.set({
              'uid': uid,
              'rol': 'cliente',
              'email': email,
              'fechaRegistro': nowTs,
              'actualizadoEn': nowTs,
            }, SetOptions(merge: true));
          } else {
            final data = snap.data() ?? <String, dynamic>{};
            final rolActual =
                (data['rol'] ?? '').toString().trim().toLowerCase();

            if (rolActual.isEmpty) {
              await ref.set(
                {'rol': 'cliente', 'updatedAt': nowTs, 'actualizadoEn': nowTs},
                SetOptions(merge: true),
              );
            }
            await ref.set(
              {'lastLogin': nowTs, 'updatedAt': nowTs, 'actualizadoEn': nowTs},
              SetOptions(merge: true),
            );
          }
        } catch (_) {}
      }

      // 3) Gate central
      _goAuthCheck();
    } on FirebaseAuthException catch (e) {
      // === FLEX QA: si falla y está permitido, caer a anónimo ===
      if (kQaFlexibleAccess && kQaAllowAnonOnAuthError) {
        const codesForAnon = {
          'user-not-found',
          'wrong-password',
          'invalid-credential',
          'too-many-requests',
          'network-request-failed',
        };
        if (codesForAnon.contains(e.code)) {
          await _loginAnonCliente();
          return;
        }
      }

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No se pudo iniciar sesión'),
          content: Text(
            'Revisa tus credenciales o elige otra opción para $email:\n\n'
            '• Restablecer contraseña.\n'
            '• Continuar con Google.\n'
            '• Vincular una contraseña (si usas Google).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _sendResetPassword(email);
              },
              child: const Text('Restablecer contraseña'),
            ),
            TextButton(
              onPressed: _loadingGoogle
                  ? null
                  : () async {
                      Navigator.of(context).pop();
                      await _vincularContrasenaConGoogle();
                    },
              child: const Text('Vincular contraseña (Google)'),
            ),
            ElevatedButton(
              onPressed: _loadingGoogle
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      _loginGoogle();
                    },
              child: const Text('Continuar con Google'),
            ),
          ],
        ),
      );
    } catch (err) {
      if (kQaFlexibleAccess && kQaAllowAnonOnAuthError) {
        await _loginAnonCliente();
        return;
      }
      _snack('Error inesperado: $err');
    } finally {
      if (mounted) setState(() => _loadingEmail = false);
    }
  }

  Future<void> _loginGoogle() async {
    if (_loadingGoogle || _loadingEmail) return;

    setState(() => _loadingGoogle = true);
    try {
      await GoogleAuthService.signInWithGoogleStrict(entradaRol: 'cliente');

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          final nowTs = FieldValue.serverTimestamp();
          await FirebaseFirestore.instance.collection('usuarios').doc(uid).set(
                {'updatedAt': nowTs, 'actualizadoEn': nowTs},
                SetOptions(merge: true),
              );
        } catch (_) {}
      }

      _goAuthCheck();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'role-mismatch') {
        _snack(e.message ?? 'Rol no coincide.');
      } else {
        if (kQaFlexibleAccess && kQaAllowAnonOnCollision) {
          await _loginAnonCliente();
        } else {
          _snack('No se pudo iniciar con Google (${e.code}).');
        }
      }
    } catch (err) {
      if (kQaFlexibleAccess && kQaAllowAnonOnAuthError) {
        await _loginAnonCliente();
      } else {
        _snack('Error (Firestore/Conexión): $err');
      }
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const titleStyle = TextStyle(
      fontSize: 26,
      color: Colors.greenAccent,
      fontWeight: FontWeight.bold,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Login Cliente', style: titleStyle),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            children: [
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _loadingGoogle
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.account_circle_outlined),
                  label: Text(
                      _loadingGoogle ? 'Conectando...' : 'Continuar con Google'),
                  onPressed: _loadingGoogle ? null : _loginGoogle,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                children: <Widget>[
                  Expanded(child: Divider(color: Colors.white24)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('o usa tu correo',
                        style: TextStyle(color: Colors.white54)),
                  ),
                  Expanded(child: Divider(color: Colors.white24)),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Correo',
                  prefixIcon: Icon(Icons.email, color: Colors.greenAccent),
                ),
                validator: (v) => (v == null ||
                        v.trim().isEmpty ||
                        !v.contains('@'))
                    ? 'Ingrese un correo válido'
                    : null,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pass,
                obscureText: _obscurePass,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _loginEmail(), // Enter dispara login
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon:
                      const Icon(Icons.lock, color: Colors.greenAccent),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white70,
                    ),
                    tooltip: _obscurePass ? 'Mostrar' : 'Ocultar',
                  ),
                ),
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                autofillHints: const [AutofillHints.password],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _sendResetPassword(_email.text),
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed:
                      _loadingGoogle ? null : _vincularContrasenaConGoogle,
                  child:
                      const Text('Vincular contraseña a mi cuenta de Google'),
                ),
              ),
              const SizedBox(height: 6),

              // 🔰 Botón QA visible en debug (flex)
              if (kQaFlexibleAccess) ...[
                TextButton(
                  onPressed: _loginAnonCliente,
                  child: const Text('Entrar rápido (QA)'),
                ),
              ],

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loadingEmail ? null : _loginEmail,
                  icon: _loadingEmail
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: Text(_loadingEmail ? 'Entrando...' : 'Iniciar Sesión'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/registro_cliente'),
                  child: const Text(
                    '¿No tienes cuenta? Regístrate',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
