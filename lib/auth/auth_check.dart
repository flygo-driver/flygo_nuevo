// lib/auth/auth_check.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/auth/rai_identity_resolve.dart'
    show RaiIdentityResolve, kQaAllowAnonOnAuthError, kQaFlexibleAccess;
import 'package:flygo_nuevo/auth/rai_identity_router.dart';
import 'package:flygo_nuevo/auth/seleccion_usuario.dart';
import 'package:flygo_nuevo/pantallas/corporativo/corporativo_hub_page.dart';
import 'package:flygo_nuevo/servicios/post_auth_navigation.dart';
import 'package:flygo_nuevo/shell/cliente_shell.dart';
import 'package:flygo_nuevo/widgets/rai_linear_loading_body.dart';
import 'package:flygo_nuevo/widgets/verify_email_gate.dart';

import 'package:flygo_nuevo/servicios/app_flavor_rol_guard.dart';
import 'package:flygo_nuevo/legal/legal_acceptance_service.dart';
import 'package:flygo_nuevo/legal/terms_policy_screen.dart';

class AuthCheck extends StatefulWidget {
  const AuthCheck({super.key});
  @override
  State<AuthCheck> createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _navigated = false;
  bool _busy = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _go(Widget page) {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => page),
      (route) => false,
    );
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _errorMsg = null;
    });

    try {
      final user = _auth.currentUser;

      if (user == null) {
        _go(const SeleccionUsuario());
        return;
      }

      final accepted = await LegalAcceptanceService.hasAccepted(user.uid);
      if (!accepted) {
        _go(
          TermsPolicyScreen(
            requireAcceptance: true,
            onAccepted: () {
              if (!mounted) return;
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/auth_check', (r) => false);
            },
          ),
        );
        return;
      }

      final dest = await RaiIdentityRouter.buildDestinationForAuthCheck(user);
      if (!mounted) return;

      final postRoute = await PostAuthNavigation.consumeRoute();
      if (postRoute == '/corporativo') {
        _go(
          const VerifyEmailGate(
            childWhenVerified: CorporativoHubPage(),
          ),
        );
        return;
      }

      _go(dest);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'role-mismatch') {
        await AppFlavorRolGuard.cerrarSesionTrasRechazo();
        if (!mounted) return;
        _go(
          AppFlavorRolMismatchWall(
            rolFirestore: AppFlavorRolGuard.rolEsperadoPorFlavor() == 'taxista'
                ? 'cliente'
                : 'taxista',
            email: _auth.currentUser?.email,
            onElegirOtraCuenta: () {
              if (!mounted) return;
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/auth_check', (r) => false);
            },
          ),
        );
        return;
      }
      await _handleFatal('Auth: ${e.code}');
    } catch (e) {
      await _handleFatal('AuthCheck: $e');
    } finally {
      if (mounted && !_navigated) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _handleFatal(String msg) async {
    final bool allowQaFallback =
        kQaFlexibleAccess && kQaAllowAnonOnAuthError;

    if (allowQaFallback) {
      try {
        final cred = await _auth.signInAnonymously();
        final u = cred.user;
        if (u != null) {
          await RaiIdentityResolve.resolveRolSafe(u);
        }
        if (!mounted) return;
        _go(const ClienteShell());
        return;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _errorMsg = msg;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_busy && _errorMsg == null) {
      return const RaiLinearLoadingBody(backgroundColor: Colors.black);
    }

    if (_errorMsg != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Problema de inicio de sesión'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Text(
                'No pudimos validar tu cuenta ahora mismo.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Esto suele pasar por conexión, configuración del proyecto Firebase o reglas de Firestore.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              Text(
                _errorMsg!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _run,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _go(const SeleccionUsuario()),
                  child: const Text('Volver'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () async {
                    await _auth.signOut();
                    if (!mounted) return;
                    _go(const SeleccionUsuario());
                  },
                  child: const Text('Cerrar sesión'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const RaiLinearLoadingBody(backgroundColor: Colors.black);
  }
}
