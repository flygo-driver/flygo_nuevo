import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/auth_service.dart';
import 'package:flygo_nuevo/servicios/google_auth.dart';

/// ================== FLAGS QA (modo flexible) ==================
const bool kQaFlexibleAccess =
    bool.fromEnvironment('QA_FLEX', defaultValue: !kReleaseMode);
const bool kQaAllowAnonOnCollision =
    bool.fromEnvironment('QA_ALLOW_ANON', defaultValue: !kReleaseMode);
const bool kQaAllowAnonOnAuthError =
    bool.fromEnvironment('QA_ALLOW_ANON_ERR', defaultValue: !kReleaseMode);

class LoginTaxista extends StatefulWidget {
  const LoginTaxista({super.key});
  @override
  State<LoginTaxista> createState() => _LoginTaxistaState();
}

class _LoginTaxistaState extends State<LoginTaxista> {
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

  Future<void> _loginAnonTaxista() async {
    final cred = await FirebaseAuth.instance.signInAnonymously();
    final uid = cred.user!.uid;
    await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
      'uid': uid,
      'rol': 'taxista',
      'email': _email.text.trim(),
      'nombre': '',
      'telefono': '',
      'disponible': true, // para poder aceptar en QA
      'docsEstado': 'pendiente',
      'documentosCompletos': false,
      'fechaRegistro': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
  }

  Future<void> _loginEmail() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _email.text.trim();
    final pass = _pass.text;

    setState(() => _loadingEmail = true);
    try {
      await AuthService().loginUser(email, pass);

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final ref = FirebaseFirestore.instance.collection('usuarios').doc(uid);
        final snap = await ref.get();
        final nowTs = FieldValue.serverTimestamp();

        if (!snap.exists) {
          // CREATE: se permite poner rol/email/etc.
          await ref.set({
            'uid': uid,
            'rol': 'taxista',
            'email': email,
            'disponible': true,
            'docsEstado': 'pendiente',
            'documentosCompletos': false,
            'fechaRegistro': nowTs,
            'actualizadoEn': nowTs,
          }, SetOptions(merge: true));
        } else {
          // UPDATE: cumplir reglas (NO tocar email/docsEstado/documentosCompletos aquí)
          final data = snap.data() ?? <String, dynamic>{};
          final rolActual = (data['rol'] ?? '').toString().trim().toLowerCase();

          // Si no tenía rol, solo 'rol' + timestamps (regla especial)
          if (rolActual.isEmpty) {
            await ref.set(
              {
                'rol': 'taxista',
                'updatedAt': nowTs,
                'actualizadoEn': nowTs,
              },
              SetOptions(merge: true),
            );
          }

          // Campos permitidos en update
          await ref.set(
            {
              'disponible': true,
              'lastLogin': nowTs,
              'updatedAt': nowTs,
              'actualizadoEn': nowTs,
            },
            SetOptions(merge: true),
          );
        }
      }

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      // Modo flexible: pase anónimo ante errores frecuentes
      if (kQaFlexibleAccess && kQaAllowAnonOnAuthError) {
        const codesForAnon = {
          'user-not-found',
          'wrong-password',
          'invalid-credential',
          'too-many-requests',
          'network-request-failed',
        };
        if (codesForAnon.contains(e.code)) {
          await _loginAnonTaxista();
          return;
        }
      }

      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Credenciales incorrectas'),
            content: Text(
              'Si te registraste con Google para $email, usa "Continuar con Google". '
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
        'role-mismatch' => e.message ?? 'Rol no coincide.',
        _ => 'Error al iniciar sesión.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (err) {
      if (mounted) {
        if (kQaFlexibleAccess && kQaAllowAnonOnAuthError) {
          await _loginAnonTaxista();
          return;
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error inesperado: $err')));
      }
    } finally {
      if (mounted) setState(() => _loadingEmail = false);
    }
  }

  Future<void> _loginGoogle() async {
    setState(() => _loadingGoogle = true);
    try {
      await GoogleAuthService.signInWithGoogleStrict(entradaRol: 'taxista');

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final nowTs = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).set(
          {
            // En UPDATE solo lo permitido:
            'disponible': true,
            'updatedAt': nowTs,
            'actualizadoEn': nowTs,
          },
          SetOptions(merge: true),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
    } on FirebaseAuthException catch (e) {
      // Manejo claro para rol distinto
      if (e.code == 'role-mismatch') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Rol no coincide.')),
          );
        }
      } else {
        // Fallback anónimo si está permitido en QA
        if (kQaFlexibleAccess && kQaAllowAnonOnCollision) {
          await _loginAnonTaxista();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No se pudo iniciar con Google (${e.code}).')),
            );
          }
        }
      }
    } catch (err) {
      if (kQaFlexibleAccess && kQaAllowAnonOnAuthError) {
        await _loginAnonTaxista();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error (Firestore/Conexión): $err')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  InputDecoration _inputDec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.greenAccent),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white24),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.greenAccent, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
    );
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
        title: const Text('Login Taxista', style: titleStyle),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Icon(Icons.local_taxi, size: 90, color: Colors.greenAccent),
              const SizedBox(height: 20),
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
                decoration: _inputDec('Correo electrónico', Icons.email),
                validator: (v) => (v == null || !v.contains('@')) ? 'Correo inválido' : null,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pass,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDec('Contraseña', Icons.lock),
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

              // 🔰 Botón QA visible en debug (flex)
              if (kQaFlexibleAccess) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loginAnonTaxista,
                  child: const Text('Entrar rápido (QA)'),
                ),
              ],

              const SizedBox(height: 8),
              _loadingEmail
                  ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _loginEmail,
                        icon: const Icon(Icons.login, color: Colors.green),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.0),
                          child: Text('Iniciar Sesión',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/registro_taxista'),
                child: const Text('¿No tienes cuenta? Regístrate',
                    style: TextStyle(color: Colors.white70, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
