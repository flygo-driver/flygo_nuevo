// lib/auth/login_admin.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';

class LoginAdmin extends StatefulWidget {
  const LoginAdmin({super.key});

  @override
  State<LoginAdmin> createState() => _LoginAdminState();
}

class _LoginAdminState extends State<LoginAdmin> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();

  bool _loadingEmail = false;
  bool _loadingGoogle = false;
  bool _obscurePass = true;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

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

  // ✅ Verifica admin sin cambiar campos (no pisa rol)
  Future<bool> _isAdminUid(String uid) async {
    final db = FirebaseFirestore.instance;

    try {
      final userSnap = await db.collection('usuarios').doc(uid).get();
      final u = userSnap.data() ?? <String, dynamic>{};
      final rolU = (u['rol'] ?? '').toString().trim().toLowerCase();
      final isAdminBool = (u['isAdmin'] == true);

      if (RolesService.esRolAdmin(rolU) || isAdminBool) return true;

      final rolSnap = await db.collection('roles').doc(uid).get();
      final r = rolSnap.data() ?? <String, dynamic>{};
      final rolR = (r['rol'] ?? '').toString().trim().toLowerCase();

      return RolesService.esRolAdmin(rolR);
    } catch (_) {
      return false;
    }
  }

  Future<void> _signOutAll() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  Future<void> _postLoginCheckAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _snack('No se obtuvo usuario.');
      return;
    }

    final ok = await _isAdminUid(uid);
    if (!ok) {
      await _signOutAll();
      _snack('No tienes permisos de administrador.');
      return;
    }

    // ✅ si es admin, deja que el gate central te mande a AdminGate/AdminHome
    _goAuthCheck();
  }

  Future<void> _loginEmailAdmin() async {
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
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );

      await FirebaseAuth.instance.currentUser?.reload();
      await _postLoginCheckAdmin();
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'user-not-found' => 'No existe una cuenta con ese correo.',
        'wrong-password' => 'Contraseña incorrecta.',
        'invalid-email' => 'Correo inválido.',
        'too-many-requests' => 'Demasiados intentos. Intenta más tarde.',
        _ => 'No se pudo iniciar sesión (${e.code}).',
      };
      _snack(msg);
    } catch (err) {
      _snack('Error: $err');
    } finally {
      if (mounted) setState(() => _loadingEmail = false);
    }
  }

  Future<void> _loginGoogleAdmin() async {
    if (_loadingGoogle || _loadingEmail) return;

    setState(() => _loadingGoogle = true);
    try {
      final g = GoogleSignIn(scopes: const ['email']);
      final acc = await g.signIn();
      if (acc == null) {
        // cancelado
        return;
      }
      final gAuth = await acc.authentication;
      final idToken = gAuth.idToken;
      final accessToken = gAuth.accessToken;

      if (idToken == null || accessToken == null) {
        _snack('Google no devolvió tokens. Intenta otra vez.');
        return;
      }

      final cred = GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: accessToken,
      );

      await FirebaseAuth.instance.signInWithCredential(cred);
      await _postLoginCheckAdmin();
    } on FirebaseAuthException catch (e) {
      _snack('No se pudo iniciar con Google (${e.code}).');
    } catch (err) {
      _snack('Error: $err');
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final onSurf = cs.onSurface;
    final muted = onSurf.withValues(alpha: 0.72);
    final border = cs.outline.withValues(alpha: isLight ? 0.45 : 0.35);
    final accentIcon = isLight ? cs.primary : Colors.greenAccent;
    final titleStyle = theme.textTheme.headlineSmall?.copyWith(
          color: onSurf,
          fontWeight: FontWeight.w900,
        ) ??
        TextStyle(fontSize: 24, color: onSurf, fontWeight: FontWeight.w900);

    final fieldDecoration = InputDecoration(
      filled: true,
      fillColor:
          cs.surfaceContainerHighest.withValues(alpha: isLight ? 0.55 : 0.35),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      labelStyle: TextStyle(color: muted),
      floatingLabelStyle: TextStyle(color: cs.primary),
    );

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: onSurf,
        elevation: 0,
        title: Text('Acceso Admin', style: titleStyle),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            children: [
              const SizedBox(height: 10),
              Text(
                'Entra solo si tu usuario ya tiene rol "admin" en Firestore.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _loadingGoogle
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cs.primary),
                        )
                      : Icon(Icons.account_circle_outlined, color: onSurf),
                  label: Text(
                      _loadingGoogle ? 'Conectando...' : 'Entrar con Google'),
                  onPressed: _loadingGoogle ? null : _loginGoogleAdmin,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: onSurf,
                    side: BorderSide(color: border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(child: Divider(color: border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child:
                        Text('o usa tu correo', style: TextStyle(color: muted)),
                  ),
                  Expanded(child: Divider(color: border)),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                style: TextStyle(color: onSurf),
                decoration: fieldDecoration.copyWith(
                  labelText: 'Correo',
                  prefixIcon: Icon(Icons.email, color: accentIcon),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty || !v.contains('@'))
                        ? 'Ingrese un correo válido'
                        : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pass,
                obscureText: _obscurePass,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _loginEmailAdmin(),
                style: TextStyle(color: onSurf),
                decoration: fieldDecoration.copyWith(
                  labelText: 'Contraseña',
                  prefixIcon: Icon(Icons.lock, color: accentIcon),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                      color: muted,
                    ),
                    tooltip: _obscurePass ? 'Mostrar' : 'Ocultar',
                  ),
                ),
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _sendResetPassword(_email.text),
                  child: Text('¿Olvidaste tu contraseña?',
                      style: TextStyle(color: cs.primary)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loadingEmail ? null : _loginEmailAdmin,
                  icon: _loadingEmail
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onPrimary,
                          ),
                        )
                      : Icon(Icons.admin_panel_settings, color: cs.onPrimary),
                  label:
                      Text(_loadingEmail ? 'Entrando...' : 'Entrar como Admin'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
