// lib/pantallas/auth/login_cliente.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:flygo_nuevo/servicios/auth_service.dart';
import 'package:flygo_nuevo/servicios/google_auth.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';

/// ================== FLAGS QA (modo flexible) ==================
/// En debug quedan true por default (porque !kReleaseMode == true).
const bool kQaFlexibleAccess =
    bool.fromEnvironment('QA_FLEX', defaultValue: !kReleaseMode);
const bool kQaAllowAnonOnCollision =
    bool.fromEnvironment('QA_ALLOW_ANON', defaultValue: !kReleaseMode);
const bool kQaAllowAnonOnAuthError =
    bool.fromEnvironment('QA_ALLOW_ANON_ERR', defaultValue: !kReleaseMode);

// Logger condicional para debug
void _log(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

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
  bool _obscurePass = true;
  StreamSubscription<User?>? _authSub;
  bool _autoRedirectDone = false;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || _autoRedirectDone) return;
      if (user != null) {
        _autoRedirectDone = true;
        _goAuthCheck();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
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

  /// ✅ Upsert “seguro” del doc usuarios/{uid} SIN tocar rol.
  Future<void> _safeUpsertUsuario({
    required String uid,
    required String email,
    bool includeNombreTelefono = false,
  }) async {
    try {
      final ref = FirebaseFirestore.instance.collection('usuarios').doc(uid);
      final snap = await ref.get();
      final nowTs = FieldValue.serverTimestamp();

      if (!snap.exists) {
        await ref.set({
          'uid': uid,
          'email': email.trim(),
          'nombre': includeNombreTelefono ? '' : FieldValue.delete(),
          'telefono': includeNombreTelefono ? '' : FieldValue.delete(),
          'fechaRegistro': nowTs,
          'lastLogin': nowTs,
          'updatedAt': nowTs,
          'actualizadoEn': nowTs,
        }, SetOptions(merge: true));
      } else {
        await ref.set({
          'email': email.trim(),
          'lastLogin': nowTs,
          'updatedAt': nowTs,
          'actualizadoEn': nowTs,
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> _loginAnonCliente() async {
    if (_loadingEmail || _loadingGoogle) return;
    final cred = await FirebaseAuth.instance.signInAnonymously();
    final uid = cred.user!.uid;

    await _safeUpsertUsuario(
      uid: uid,
      email: _email.text.trim(),
      includeNombreTelefono: true,
    );

    _goAuthCheck();
  }

  Future<void> _vincularContrasenaConGoogle() async {
    if (!mounted) return;
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

      await _safeUpsertUsuario(uid: user.uid, email: emailCuenta);

      _snack(
          'Listo: contraseña vinculada. Ya puedes entrar con correo y contraseña.');
      _goAuthCheck();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'aborted-by-user') return;

      if (e.code == 'google-token-null') {
        _snack(
          'No se pudo completar el inicio con Google. Inténtalo nuevamente.',
        );
        return;
      }

      String msg;
      switch (e.code) {
        case 'provider-already-linked':
        case 'credential-already-in-use':
        case 'email-already-in-use':
          msg =
              'Esta cuenta ya tiene contraseña. Entra con correo y contraseña.';
          break;
        case 'requires-recent-login':
          msg = 'Por seguridad, vuelve a entrar con Google e intenta de nuevo.';
          break;
        case 'account-exists-with-different-credential':
          msg =
              'Esta cuenta existe con otro método. Entra con ese método y luego vincula la contraseña.';
          break;
        default:
          msg = 'No se pudo vincular la contraseña en este momento.';
      }
      _snack(msg);
    } catch (_) {
      _snack('No pudimos completar la operación. Inténtalo nuevamente.');
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  Future<void> _loginEmail() async {
    if (!mounted) return;
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
      await AuthService().loginUser(email, pass);
      await FirebaseAuth.instance.currentUser?.reload();

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _safeUpsertUsuario(uid: uid, email: email);
      }

      _goAuthCheck();
    } on FirebaseAuthException catch (e) {
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

      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      final email = (user?.email ?? '').trim();

      // Navegación inmediata tras auth exitosa (tipo Uber).
      // Persistencia en segundo plano para no bloquear entrada.
      if (uid != null) {
        Future<void>(() async {
          await _safeUpsertUsuario(uid: uid, email: email);
        });
      }
      _goAuthCheck();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'aborted-by-user') return;

      if (e.code == 'google-token-null') {
        _snack(
          'No se pudo completar el inicio con Google. Inténtalo nuevamente.',
        );
        return;
      }

      if (kQaFlexibleAccess && kQaAllowAnonOnCollision && e.code != 'role-mismatch') {
        await _loginAnonCliente();
      } else {
        _snack(GoogleAuthService.friendlyAuthError(e, rol: 'cliente'));
      }
    } catch (err) {
      if (kQaFlexibleAccess && kQaAllowAnonOnAuthError) {
        await _loginAnonCliente();
      } else {
        _snack(GoogleAuthService.friendlyAuthError(err, rol: 'cliente'));
      }
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  // 🔥 MÉTODO DE PRUEBA PARA GOOGLE SIMPLE (solo debug)
  Future<void> _loginGoogleSimpleTest() async {
    if (_loadingGoogle || _loadingEmail) return;

    setState(() => _loadingGoogle = true);
    _log('TEST: Iniciando Google Sign-In simple');

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        _log('TEST: Usuario canceló');
        _snack('Cancelaste el inicio de sesión');
        return;
      }

      _log('TEST: Google user: ${googleUser.email}');

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);
      _log('TEST: Firebase auth exitoso: ${userCred.user?.email}');

      _snack('✅ Login Google exitoso! Usuario: ${userCred.user?.email}');
    } catch (e) {
      _log('TEST Error: $e');
      _snack('Error en test: $e');
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final divider = cs.outline.withOpacity(0.55);
    final muted = cs.onSurface.withOpacity(0.54);
    final muted70 = cs.onSurface.withOpacity(0.7);
    final onPrimaryContainer = cs.onPrimaryContainer;
    final primaryContainer = cs.primaryContainer;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: const RaiAppBar(
        title: 'Login Cliente',
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            children: [
              const SizedBox(height: 16),

              // 🔥 BOTÓN GOOGLE NORMAL
              Center(
                child: SizedBox(
                  width: 280,
                  child: OutlinedButton.icon(
                    icon: _loadingGoogle
                        ? SizedBox(
                            width: 20,
                            height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                          )
                        : const Icon(Icons.account_circle_outlined, size: 20),
                    label: Text(
                      _loadingGoogle ? 'Conectando...' : 'Continuar con Google',
                      style: TextStyle(color: cs.onSurface, fontSize: 14),
                    ),
                    onPressed: (_loadingGoogle) ? null : _loginGoogle,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      side: BorderSide(color: divider),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      minimumSize: const Size(200, 40),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Entra al instante con Google y pide viajes de inmediato. '
                  'Podrás completar nombre, teléfono y foto en tu perfil cuando quieras.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 12, height: 1.35),
                ),
              ),

              const SizedBox(height: 12),

              // 🔥 BOTÓN DE PRUEBA GOOGLE SIMPLE (solo visible en debug)
              if (kDebugMode)
                Center(
                  child: SizedBox(
                    width: 280,
                    child: ElevatedButton(
                      onPressed: _loginGoogleSimpleTest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: Text(
                        'TEST Google Simple',
                        style: TextStyle(color: cs.onError, fontSize: 14),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(child: Divider(color: divider)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('o entra con correo',
                        style: TextStyle(color: muted)),
                  ),
                  Expanded(child: Divider(color: divider)),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                style: TextStyle(color: cs.onSurface),
                decoration: InputDecoration(
                  labelText: 'Correo',
                  labelStyle: TextStyle(color: muted70),
                  prefixIcon: Icon(Icons.email, color: Colors.greenAccent),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty || !v.contains('@'))
                        ? 'Ingrese un correo válido'
                        : null,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pass,
                obscureText: _obscurePass,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _loginEmail(),
                style: TextStyle(color: cs.onSurface),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock, color: Colors.greenAccent),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                      color: muted70,
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
                  style: TextButton.styleFrom(foregroundColor: cs.primary),
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: (_loadingGoogle)
                      ? null
                      : _vincularContrasenaConGoogle,
                  style: TextButton.styleFrom(foregroundColor: cs.primary),
                  child:
                      const Text('Vincular contraseña a mi cuenta de Google'),
                ),
              ),
              if (kQaFlexibleAccess) ...[
                TextButton(
                  onPressed: _loginAnonCliente,
                  style: TextButton.styleFrom(foregroundColor: cs.primary),
                  child: const Text('Entrar rápido (QA)'),
                ),
              ],

              Center(
                child: SizedBox(
                  width: 280,
                  child: ElevatedButton.icon(
                    onPressed:
                        (_loadingEmail) ? null : _loginEmail,
                    icon: _loadingEmail
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: onPrimaryContainer,
                            ),
                          )
                        : Icon(Icons.login, size: 18, color: onPrimaryContainer),
                    label: Text(
                      _loadingEmail ? 'Entrando...' : 'Continuar',
                      style: TextStyle(fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryContainer,
                      foregroundColor: onPrimaryContainer,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
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
                      color: Colors.amber.shade700,
                      width: 3,
                    ),
                  ),
                ),
                child: TextButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/registro_cliente');
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
                        color: Colors.amber.shade700,
                        size: 24,
                      ),
                      Text(
                        'Crear cuenta con correo y contraseña',
                        style: TextStyle(
                          color: Colors.amber.shade700,
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
