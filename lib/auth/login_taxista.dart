// lib/auth/login_taxista.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/auth_service.dart';
import 'package:flygo_nuevo/servicios/google_auth.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

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
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/auth_check', (r) => false);
      }
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _sendResetPassword(String email) async {
    final e = email.trim();
    if (e.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Escribe tu correo para enviarte el reset.')),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Te enviamos un correo para restablecer tu contraseña.')),
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
    _suppressAuthRedirect = true;
    try {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      final uid = cred.user!.uid;
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'uid': uid,
        'rol': 'taxista',
        'email': _email.text.trim(),
        'nombre': '',
        'telefono': '',
        'disponible': false,
        'docsEstado': 'pendiente',
        'estadoDocumentos': 'pendiente',
        'documentosCompletos': false,
        'puedeRecibirViajes': false,
        'fechaRegistro': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      await ViajesRepo.reconciliarActivosTaxista(uid);
      if (!mounted) return;
      _autoRedirectDone = true;
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/auth_check', (r) => false);
    } finally {
      _suppressAuthRedirect = false;
    }
  }

  Future<void> _loginEmail() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _email.text.trim();
    final pass = _pass.text;

    setState(() {
      _loadingEmail = true;
      _suppressAuthRedirect = true;
    });
    try {
      await AuthService().loginUser(email, pass);

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final ref = FirebaseFirestore.instance.collection('usuarios').doc(uid);
        final snap = await ref.get();
        final nowTs = FieldValue.serverTimestamp();

        if (!snap.exists) {
          await ref.set({
            'uid': uid,
            'rol': 'taxista',
            'email': email,
            'disponible': false,
            'docsEstado': 'pendiente',
            'estadoDocumentos': 'pendiente',
            'documentosCompletos': false,
            'puedeRecibirViajes': false,
            'fechaRegistro': nowTs,
            'actualizadoEn': nowTs,
          }, SetOptions(merge: true));
        } else {
          final data = snap.data() ?? <String, dynamic>{};
          final rolActual = (data['rol'] ?? '').toString().trim().toLowerCase();

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

          await ref.set(
            {
              'lastLogin': nowTs,
              'updatedAt': nowTs,
              'actualizadoEn': nowTs,
            },
            SetOptions(merge: true),
          );
        }
      }

      if (!mounted) return;
      if (uid != null) {
        await ViajesRepo.reconciliarActivosTaxista(uid);
      }
      if (!mounted) return;
      _autoRedirectDone = true;
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/auth_check', (r) => false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

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
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar')),
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
    } catch (_) {
      if (mounted) {
        if (kQaFlexibleAccess && kQaAllowAnonOnAuthError) {
          await _loginAnonTaxista();
          return;
        }
        _snack(
            'No se pudo iniciar sesión en este momento. Inténtalo de nuevo.');
      }
    } finally {
      _suppressAuthRedirect = false;
      if (mounted) setState(() => _loadingEmail = false);
    }
  }

  Future<void> _loginGoogle() async {
    if (_loadingGoogle || _loadingEmail) return;
    setState(() {
      _loadingGoogle = true;
      _suppressAuthRedirect = true;
    });
    try {
      await GoogleAuthService.signInWithGoogleStrict(entradaRol: 'taxista');

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final nowTs = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).set(
          {
            'lastLogin': nowTs,
            'updatedAt': nowTs,
            'actualizadoEn': nowTs,
          },
          SetOptions(merge: true),
        );
        await ViajesRepo.reconciliarActivosTaxista(uid);
      }
      if (!mounted) return;
      _autoRedirectDone = true;
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/auth_check', (r) => false);
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        debugPrint('[LOGIN_GOOGLE][taxista] code=${e.code} msg=${e.message}');
      }
      if (e.code == 'aborted-by-user') return;
      if (e.code == 'google-token-null') {
        _snack(
            'No se pudo completar el inicio con Google. Inténtalo nuevamente.');
        return;
      }
      _snack(GoogleAuthService.friendlyAuthError(e, rol: 'taxista'));
    } catch (err) {
      if (kDebugMode) {
        debugPrint('[LOGIN_GOOGLE][taxista] error=$err');
      }
      _snack(GoogleAuthService.friendlyAuthError(err, rol: 'taxista'));
    } finally {
      _suppressAuthRedirect = false;
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  InputDecoration _inputDec(BuildContext context, String label, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    final divider = cs.outline.withValues(alpha: 0.6);
    final labelColor = cs.onSurface.withValues(alpha: 0.7);

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: labelColor),
      prefixIcon: Icon(icon, color: cs.primary),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: divider),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.primary, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final divider = cs.outline.withValues(alpha: 0.55);
    final muted38 = cs.onSurface.withValues(alpha: 0.38);
    final muted54 = cs.onSurface.withValues(alpha: 0.54);
    final primaryContainer = cs.primaryContainer;
    final onPrimaryContainer = cs.onPrimaryContainer;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: const RaiAppBar(
        title: 'Login Taxista',
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Icon(Icons.local_taxi, size: 90, color: Colors.greenAccent),
              const SizedBox(height: 20),

              // 🔥 BOTÓN GOOGLE - CENTRADO Y RESPONSIVE
              Center(
                child: SizedBox(
                  width: 280,
                  child: OutlinedButton.icon(
                    icon: _loadingGoogle
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.account_circle_outlined, size: 20),
                    label: Text(
                      _loadingGoogle ? 'Conectando...' : 'Continuar con Google',
                      style: const TextStyle(fontSize: 14),
                    ),
                    onPressed: (_loadingGoogle) ? null : _loginGoogle,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      side: BorderSide(color: divider),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      minimumSize: const Size(200, 40),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Entra rápido con Google o correo. La habilitación operativa de viajes se valida dentro del flujo de taxista.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted38, fontSize: 11),
                ),
              ),

              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(child: Divider(color: divider)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('o usa tu correo',
                        style: TextStyle(color: muted54)),
                  ),
                  Expanded(child: Divider(color: divider)),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: cs.onSurface),
                decoration:
                    _inputDec(context, 'Correo electrónico', Icons.email),
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Correo inválido' : null,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _pass,
                obscureText: true,
                style: TextStyle(color: cs.onSurface),
                decoration: _inputDec(context, 'Contraseña', Icons.lock),
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                autofillHints: const [AutofillHints.password],
              ),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _sendResetPassword(_email.text),
                  style: TextButton.styleFrom(foregroundColor: cs.primary),
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
              if (kQaFlexibleAccess) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loginAnonTaxista,
                  child: const Text('Entrar rápido (QA)'),
                ),
              ],

              const SizedBox(height: 8),

              // 🔥 BOTÓN INICIAR SESIÓN - CENTRADO Y RESPONSIVE
              Center(
                child: SizedBox(
                  width: 280,
                  child: _loadingEmail
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Colors.greenAccent))
                      : ElevatedButton.icon(
                          onPressed: _loginEmail,
                          icon: Icon(Icons.login,
                              size: 18, color: onPrimaryContainer),
                          label: Text(
                            'Continuar',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: onPrimaryContainer),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryContainer,
                            foregroundColor: onPrimaryContainer,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            minimumSize: const Size(200, 40),
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // 🔥 BOTÓN DE REGISTRO DESTACADO - RESPONSIVE CON WRAP
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.red.shade700,
                      width: 3,
                    ),
                  ),
                ),
                child: TextButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/registro_taxista');
                  },
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      Icon(
                        Icons.person_add_alt_1,
                        color: Colors.red.shade700,
                        size: 24,
                      ),
                      Text(
                        '¿NO TIENES CUENTA? REGÍSTRATE AQUÍ',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
