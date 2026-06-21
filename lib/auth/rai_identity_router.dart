import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/auth/rai_identity_resolve.dart';
import 'package:flygo_nuevo/auth/seleccion_usuario.dart';
import 'package:flygo_nuevo/legal/legal_acceptance_service.dart';
import 'package:flygo_nuevo/legal/terms_policy_screen.dart';
import 'package:flygo_nuevo/pantallas/taxista/bloqueado_por_pagos.dart';
import 'package:flygo_nuevo/pantallas/taxista/completar_registro_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/entry_taxista.dart';
import 'package:flygo_nuevo/servicios/app_flavor_rol_guard.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/servicios/taxista_registro_perfil_data.dart';
import 'package:flygo_nuevo/shell/cliente_shell.dart';
import 'package:flygo_nuevo/widgets/admin_gate.dart';
import 'package:flygo_nuevo/widgets/verify_email_gate.dart';

/// Splash unificado post-arranque nativo (misma imagen que [flutter_native_splash]).
class RaiIdentitySplash extends StatelessWidget {
  const RaiIdentitySplash({super.key, this.subtitle});

  static const String _splashAsset = 'assets/icon/splash_rai.png';

  final String? subtitle;

  static Widget scaffold({String? subtitle}) =>
      RaiIdentitySplash(subtitle: subtitle);

  @override
  Widget build(BuildContext context) {
    final double logoWidth =
        (MediaQuery.sizeOf(context).width * 0.72).clamp(200.0, 340.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            height: 3,
            child: LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              color: Colors.greenAccent,
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    _splashAsset,
                    width: logoWidth,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Escritorio: solo administración.
class RaiDesktopNonAdminWall extends StatelessWidget {
  const RaiDesktopNonAdminWall({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.desktop_windows_outlined,
                  size: 56, color: Colors.white54),
              const SizedBox(height: 24),
              Text(
                'RAI en escritorio: solo administración',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'Pasajero y conductor deben usar teléfono o tablet.\n'
                'Cierra sesión e inicia con una cuenta de admin.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  height: 1.45,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (!context.mounted) return;
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/login_admin', (r) => false);
                },
                child: const Text('Ir a login administración'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Puerta taxista: prepago/deuda → email → [child] (p. ej. [TaxistaEntry]).
class RaiTaxistaAccessGate extends StatefulWidget {
  const RaiTaxistaAccessGate({super.key, required this.child});

  final Widget child;

  @override
  State<RaiTaxistaAccessGate> createState() => _RaiTaxistaAccessGateState();
}

class _RaiTaxistaAccessGateState extends State<RaiTaxistaAccessGate> {
  late final Future<bool> _puedeTrabajarFuture;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _puedeTrabajarFuture = _resolverAcceso(_uid);
  }

  static Future<bool> _resolverAcceso(String? uid) async {
    final u = (uid ?? '').trim();
    if (u.isEmpty) return false;
    try {
      await PagosTaxistaRepo.sincronizarBloqueoOperativo(u);
      return await PagosTaxistaRepo.puedeTrabajar(u);
    } catch (e) {
      debugPrint('[RAI_IDENTITY] resolverAcceso error=$e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      return const SeleccionUsuario();
    }

    return FutureBuilder<bool>(
      future: _puedeTrabajarFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return RaiIdentitySplash.scaffold();
        }

        final bool puedeTrabajar = snapshot.data == true;
        debugPrint(
          '[RAI_IDENTITY] taxista uid=$uid puedeTrabajar=$puedeTrabajar '
          'err=${snapshot.hasError}',
        );

        if (!puedeTrabajar) {
          return const BloqueadoPorPagos();
        }

        return VerifyEmailGate(childWhenVerified: widget.child);
      },
    );
  }
}

/// Router único post-login: legal → flavor → rol → destino.
class RaiIdentityRouter {
  RaiIdentityRouter._();

  static bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Evita parpadeo: el [FutureBuilder] de términos no se recrea en cada
  /// snapshot de `usuarios/{uid}` (p. ej. lastLogin, tienePagoPendiente).
  static Widget buildGateForUsuarioData(
    BuildContext context,
    User user,
    Map<String, dynamic> data,
  ) {
    return RaiUsuarioIdentityGate(user: user, data: data);
  }

  static Widget _buildAfterLegal(
    BuildContext context,
    User user,
    Map<String, dynamic> data,
    String rol,
  ) {
    final bool esAdmin = rol == 'admin';

    if (_isDesktop && !esAdmin) {
      return const RaiDesktopNonAdminWall();
    }

    if (!AppFlavorRolGuard.rolCompatibleConFlavor(rol) && !esAdmin) {
      return AppFlavorRolMismatchWall(
        rolFirestore: rol,
        email: user.email,
      );
    }

    if (esAdmin) {
      return const AdminGate();
    }

    if (rol == 'taxista') {
      if (!TaxistaRegistroPerfilData.taxistaRegistroPerfilCompleto(data)) {
        return const CompletarRegistroTaxista();
      }
      return const RaiTaxistaAccessGate(child: TaxistaEntry());
    }

    if (rol == 'cliente') {
      return const VerifyEmailGate(
        childWhenVerified: ClienteShellWithDeepLink(),
      );
    }

    return const SeleccionUsuario();
  }

  /// Flujo [AuthCheck]: resuelve rol y devuelve widget destino (sin StreamBuilder de usuario).
  static Future<Widget> buildDestinationForAuthCheck(User user) async {
    final accepted = await LegalAcceptanceService.hasAccepted(user.uid);
    if (!accepted) {
      return TermsPolicyScreen(
        requireAcceptance: true,
        onAccepted: () {},
      );
    }

    final rol = await RaiIdentityResolve.resolveRolSafe(user);
    debugPrint('[RAI_IDENTITY] auth_check uid=${user.uid} rol=$rol');

    if (!AppFlavorRolGuard.rolCompatibleConFlavor(rol) &&
        !AppFlavorRolGuard.esAdmin(rol)) {
      return AppFlavorRolMismatchWall(
        rolFirestore: rol,
        email: user.email,
      );
    }

    if (rol == 'admin') {
      return const AdminGate();
    }

    if (rol == 'taxista') {
      final uSnap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();
      final data = uSnap.data() ?? <String, dynamic>{};
      if (!TaxistaRegistroPerfilData.taxistaRegistroPerfilCompleto(data)) {
        return const CompletarRegistroTaxista();
      }
      return const RaiTaxistaAccessGate(child: TaxistaEntry());
    }

    if (rol == 'cliente') {
      return const VerifyEmailGate(
        childWhenVerified: ClienteShellWithDeepLink(),
      );
    }

    return const SeleccionUsuario();
  }
}

/// Puerta legal + rol estable ante actualizaciones Firestore del perfil.
class RaiUsuarioIdentityGate extends StatefulWidget {
  const RaiUsuarioIdentityGate({
    super.key,
    required this.user,
    required this.data,
  });

  final User user;
  final Map<String, dynamic> data;

  @override
  State<RaiUsuarioIdentityGate> createState() => _RaiUsuarioIdentityGateState();
}

class _RaiUsuarioIdentityGateState extends State<RaiUsuarioIdentityGate> {
  late Future<bool> _legalFuture;

  @override
  void initState() {
    super.initState();
    _legalFuture = LegalAcceptanceService.hasAccepted(widget.user.uid);
  }

  @override
  void didUpdateWidget(RaiUsuarioIdentityGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _legalFuture = LegalAcceptanceService.hasAccepted(widget.user.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rol = RaiIdentityResolve.rolDesdeUsuarioData(widget.data);
    debugPrint('[RAI_IDENTITY] gate uid=${widget.user.uid} rol=$rol');

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
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/auth_check', (r) => false);
            },
          );
        }

        return RaiIdentityRouter._buildAfterLegal(
          context,
          widget.user,
          widget.data,
          rol,
        );
      },
    );
  }
}
