// lib/auth/login_cliente.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/auth_service.dart';
import 'package:flygo_nuevo/servicios/google_auth.dart';

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

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _sendResetPassword(String email) async {
    final e = email.trim();
    if (e.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe tu correo para enviarte el reset.')),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Te enviamos un correo para restablecer tu contraseña.')),
      );
    } on FirebaseAuthException catch (er) {
      if (!mounted) return;
      final msg = switch (er.code) {
        'invalid-email' => 'Correo inválido.',
        'user-not-found' => 'No existe una cuenta con ese correo.',
        _ => 'No se pudo enviar el correo de restablecimiento.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<bool> _enforceClienteAfterEmailLogin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final ref = FirebaseFirestore.instance.collection('usuarios').doc(uid);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'uid': uid,
        'rol': 'cliente',
        'fechaRegistro': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    }

    final data = snap.data() ?? <String, dynamic>{};
    final rolActual = (data['rol'] ?? '').toString().trim().toLowerCase();

    if (rolActual.isEmpty) {
      await ref.set({'rol': 'cliente', 'actualizadoEn': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      return true;
    }

    if (rolActual != 'cliente') {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Esta cuenta está registrada como "$rolActual". Entra por "Login Taxista".')),
      );
      return false;
    }
    return true;
  }

  Future<void> _loginEmail() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _email.text.trim();
    final pass = _pass.text;

    setState(() => _loadingEmail = true);
    try {
      await AuthService().loginUser(email, pass);

      final ok = await _enforceClienteAfterEmailLogin();
      if (!mounted || !ok) return;

      Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Credenciales incorrectas'),
            content: Text(
              'Si te registraste con Google para $email, usa el botón "Continuar con Google". '
              'También puedes restablecer tu contraseña.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _sendResetPassword(email);
                },
                child: const Text('Restablecer contraseña'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loginGoogle();
                },
                child: const Text('Continuar con Google'),
              ),
            ],
          ),
        );
        return;
      }

      final msg = switch (e.code) {
        'invalid-email' => 'Correo inválido.',
        'user-disabled' => 'Cuenta deshabilitada.',
        'user-not-found' => 'No existe una cuenta con ese correo.',
        'too-many-requests' => 'Demasiados intentos. Intenta más tarde.',
        _ => 'Error al iniciar sesión.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error inesperado: $err')));
      }
    } finally {
      if (mounted) setState(() => _loadingEmail = false);
    }
  }

  Future<void> _loginGoogle() async {
    setState(() => _loadingGoogle = true);
    try {
      await GoogleAuthService.signInWithGoogleStrict(entradaRol: 'cliente');

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).set(
          {'rol': 'cliente', 'actualizadoEn': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'No se pudo iniciar con Google')),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error (Firestore/Conexión): $err')));
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
          child: ListView(
            children: [
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _loadingGoogle
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.account_circle_outlined),
                  label: Text(_loadingGoogle ? 'Conectando...' : 'Continuar con Google'),
                  onPressed: _loadingGoogle ? null : _loginGoogle,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                children: <Widget>[
                  Expanded(child: Divider(color: Colors.white24)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('o usa tu correo', style: TextStyle(color: Colors.white54)),
                  ),
                  Expanded(child: Divider(color: Colors.white24)),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Correo',
                  prefixIcon: Icon(Icons.email, color: Colors.greenAccent),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty || !v.contains('@')) ? 'Ingrese un correo válido' : null,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pass,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: Icon(Icons.lock, color: Colors.greenAccent),
                ),
                validator: (v) => (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                autofillHints: const [AutofillHints.password],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _sendResetPassword(_email.text),
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
              const SizedBox(height: 6),
              _loadingEmail
                  ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _loginEmail,
                        icon: const Icon(Icons.login),
                        label: const Text('Iniciar Sesión'),
                      ),
                    ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/registro_cliente'),
                  child: const Text('¿No tienes cuenta? Regístrate',
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
