import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/auth/rai_identity_router.dart';
import 'package:flygo_nuevo/legal/legal_acceptance_service.dart';
import 'package:flygo_nuevo/legal/terms_policy_screen.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_hub_page.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/servicios/google_auth.dart';
import 'package:flygo_nuevo/servicios/web_auth_bootstrap.dart';
import 'package:flygo_nuevo/widgets/rai_header_logo.dart';

/// Entrada corporativo en laptop/navegador.
/// Google pide elegir cuenta; también hay correo + contraseña.
class CorporativoWebEntry extends StatefulWidget {
  const CorporativoWebEntry({super.key});

  @override
  State<CorporativoWebEntry> createState() => _CorporativoWebEntryState();
}

class _CorporativoWebEntryState extends State<CorporativoWebEntry> {
  User? _sessionUser;
  bool _bootCargando = true;
  bool _forzarLogin = false;
  bool _continuarSesion = false;
  bool _googleCargando = false;
  bool _emailCargando = false;
  String? _error;

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    await WebAuthBootstrap.ensureGoogleRedirectHandled();
    final user = FirebaseAuth.instance.currentUser;
    if (!mounted) return;
    setState(() {
      _sessionUser = user;
      _bootCargando = false;
    });
  }

  Future<void> _entrarGoogle() async {
    if (_googleCargando || _emailCargando) return;
    setState(() {
      _googleCargando = true;
      _error = null;
    });
    try {
      final user = await GoogleAuthService.signInCorporativoLaptop();
      if (!mounted) return;
      setState(() {
        _sessionUser = user;
        _forzarLogin = false;
        _continuarSesion = true;
        _googleCargando = false;
      });
    } on FirebaseAuthException catch (e) {
      if (e.code == 'redirect-pending') return;
      if (!mounted) return;
      setState(() {
        _googleCargando = false;
        _error = GoogleAuthService.friendlyAuthError(e, rol: 'cliente');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _googleCargando = false;
        _error = GoogleAuthService.friendlyAuthError(e, rol: 'cliente');
      });
    }
  }

  Future<void> _entrarEmail() async {
    if (_googleCargando || _emailCargando) return;
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || !email.contains('@') || pass.length < 6) {
      setState(() {
        _error = 'Escribí un correo válido y contraseña (mín. 6 caracteres).';
      });
      return;
    }
    setState(() {
      _emailCargando = true;
      _error = null;
    });
    try {
      final user = await GoogleAuthService.signInCorporativoEmail(
        email: email,
        password: pass,
      );
      if (!mounted) return;
      setState(() {
        _sessionUser = user;
        _forzarLogin = false;
        _continuarSesion = true;
        _emailCargando = false;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'user-not-found' => 'No existe una cuenta con ese correo.',
        'wrong-password' || 'invalid-credential' => 'Correo o contraseña incorrectos.',
        'invalid-email' => 'Correo inválido.',
        'too-many-requests' => 'Demasiados intentos. Probá más tarde.',
        'user-disabled' => 'Esta cuenta está deshabilitada.',
        _ => e.message ?? 'No se pudo iniciar sesión (${e.code}).',
      };
      setState(() {
        _emailCargando = false;
        _error = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _emailCargando = false;
        _error = 'No se pudo iniciar sesión. $e';
      });
    }
  }

  Future<void> _usarOtraCuenta() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _sessionUser = null;
      _forzarLogin = true;
      _continuarSesion = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_bootCargando) {
      return RaiIdentitySplash.scaffold(
        subtitle: 'Corporativo RAI — cargando…',
      );
    }

    final user = _forzarLogin
        ? null
        : (_sessionUser ?? FirebaseAuth.instance.currentUser);

    if (user == null) {
      return _PantallaLoginCorporativo(
        googleCargando: _googleCargando,
        emailCargando: _emailCargando,
        error: _error,
        emailCtrl: _emailCtrl,
        passCtrl: _passCtrl,
        obscure: _obscure,
        onToggleObscure: () => setState(() => _obscure = !_obscure),
        onGoogle: _entrarGoogle,
        onEmail: _entrarEmail,
      );
    }

    if (!_continuarSesion) {
      return _PantallaSesionExistente(
        email: (user.email ?? '').trim(),
        onContinuar: () => setState(() => _continuarSesion = true),
        onOtraCuenta: _usarOtraCuenta,
      );
    }

    return _CorporativoSesionGate(user: user);
  }
}

class _PantallaSesionExistente extends StatelessWidget {
  const _PantallaSesionExistente({
    required this.email,
    required this.onContinuar,
    required this.onOtraCuenta,
  });

  final String email;
  final VoidCallback onContinuar;
  final Future<void> Function() onOtraCuenta;

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    return corporativoResponsive(
      child: Scaffold(
        backgroundColor: p.scaffold,
        body: Container(
          width: double.infinity,
          decoration: BoxDecoration(gradient: p.heroGrad),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: corporativoCard(
                    context,
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    borderColor: p.primary.withValues(alpha: 0.3),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const RaiHeaderLogo(height: 56),
                        const SizedBox(height: 18),
                        Text(
                          'Sesión activa',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: p.onCard,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          email.isEmpty
                              ? 'Hay una cuenta iniciada en este navegador.'
                              : 'Estás como:\n$email',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: p.muted,
                            height: 1.4,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: onContinuar,
                          style: FilledButton.styleFrom(
                            backgroundColor: p.ctaBg,
                            foregroundColor: p.ctaFg,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Continuar con esta cuenta',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => onOtraCuenta(),
                          icon: const Icon(Icons.switch_account),
                          label: const Text('Usar otra cuenta'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: p.onCard,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PantallaLoginCorporativo extends StatelessWidget {
  const _PantallaLoginCorporativo({
    required this.googleCargando,
    required this.emailCargando,
    required this.onGoogle,
    required this.onEmail,
    required this.emailCtrl,
    required this.passCtrl,
    required this.obscure,
    required this.onToggleObscure,
    this.error,
  });

  final bool googleCargando;
  final bool emailCargando;
  final String? error;
  final VoidCallback onGoogle;
  final VoidCallback onEmail;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;

  bool get _busy => googleCargando || emailCargando;

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    return corporativoResponsive(
      child: Scaffold(
        backgroundColor: p.scaffold,
        body: Container(
          width: double.infinity,
          decoration: BoxDecoration(gradient: p.heroGrad),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: corporativoCard(
                    context,
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    borderColor: p.primary.withValues(alpha: 0.3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const RaiHeaderLogo(height: 64),
                        const SizedBox(height: 22),
                        Text(
                          'RAI Corporativo',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: p.onCard,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Entrá con tu correo y contraseña de RAI.\n'
                          'O usá Google y elegí la cuenta correcta.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: p.muted,
                            height: 1.45,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          enabled: !_busy,
                          style: TextStyle(color: p.onCard),
                          decoration: InputDecoration(
                            labelText: 'Correo',
                            hintText: 'tu@correo.com',
                            prefixIcon: Icon(Icons.email_outlined,
                                color: p.primary),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: passCtrl,
                          obscureText: obscure,
                          textInputAction: TextInputAction.done,
                          enabled: !_busy,
                          onSubmitted: (_) => onEmail(),
                          style: TextStyle(color: p.onCard),
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon:
                                Icon(Icons.lock_outline, color: p.primary),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: onToggleObscure,
                              icon: Icon(
                                obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: p.muted,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _busy ? null : onEmail,
                          icon: emailCargando
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login_rounded),
                          label: Text(
                            emailCargando
                                ? 'Entrando…'
                                : 'Entrar con correo y contraseña',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: p.ctaBg,
                            foregroundColor: p.ctaFg,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(child: Divider(color: p.cardBorder)),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                'o',
                                style: TextStyle(color: p.muted, fontSize: 12),
                              ),
                            ),
                            Expanded(child: Divider(color: p.cardBorder)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _busy ? null : onGoogle,
                          icon: googleCargando
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.g_mobiledata_rounded, size: 28),
                          label: Text(
                            googleCargando
                                ? 'Conectando…'
                                : 'Entrar con Google (elegir cuenta)',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF4285F4),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFF4285F4)
                                .withValues(alpha: 0.55),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        if (error != null && error!.trim().isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: p.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: p.danger.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: p.onCard,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CorporativoSesionGate extends StatefulWidget {
  const _CorporativoSesionGate({required this.user});

  final User user;

  @override
  State<_CorporativoSesionGate> createState() => _CorporativoSesionGateState();
}

class _CorporativoSesionGateState extends State<_CorporativoSesionGate> {
  late Future<bool> _legalFuture;

  @override
  void initState() {
    super.initState();
    _legalFuture = LegalAcceptanceService.hasAccepted(widget.user.uid);
  }

  @override
  void didUpdateWidget(covariant _CorporativoSesionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _legalFuture = LegalAcceptanceService.hasAccepted(widget.user.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _legalFuture,
      builder: (context, legalSnap) {
        if (legalSnap.connectionState == ConnectionState.waiting) {
          return RaiIdentitySplash.scaffold();
        }

        if (legalSnap.data != true) {
          return TermsPolicyScreen(
            requireAcceptance: true,
            onAccepted: () {
              if (!mounted) return;
              setState(() {
                _legalFuture = Future<bool>.value(true);
              });
            },
          );
        }

        return const CorporativoHubPage();
      },
    );
  }
}
