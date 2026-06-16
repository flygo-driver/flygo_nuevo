import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/servicios/google_auth.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';

/// Cruza [AppFlavor] (APK instalada) con `usuarios.rol` / `roles.rol`.
class AppFlavorRolGuard {
  AppFlavorRolGuard._();

  static const String playStorePasajeroPackage = 'com.flygo.rd2';
  static const String playStoreConductorPackage = 'com.flygo.rd2.conductor';

  /// Rol que exige la app instalada; `null` en flavor `all` (debug).
  static String? rolEsperadoPorFlavor() {
    if (isClienteFlavor) return 'cliente';
    if (isConductorFlavor) return 'taxista';
    return null;
  }

  static String _canon(String raw) {
    final r = raw.trim().toLowerCase();
    if (r == 'administrador') return 'admin';
    if (r == 'driver') return 'taxista';
    if (r == 'user') return 'cliente';
    if (r == 'admin' || r == 'taxista' || r == 'cliente') return r;
    return '';
  }

  /// Lee rol desde mapas de Firestore (usuarios primero, luego roles).
  static String rolCanonicoDesdeMaps({
    Map<String, dynamic>? usuario,
    Map<String, dynamic>? roles,
  }) {
    final u = _canon((usuario?['rol'] ?? '').toString());
    if (u.isNotEmpty) return u;
    return _canon((roles?['rol'] ?? '').toString());
  }

  static bool esRolOperativo(String rol) {
    final r = _canon(rol);
    return r == 'cliente' || r == 'taxista';
  }

  static bool esAdmin(String rol) => RolesService.esRolAdmin(_canon(rol));

  /// `true` si el rol de Firestore puede usar esta APK (o flavor `all`).
  static bool rolCompatibleConFlavor(String rolFirestore) {
    final esperado = rolEsperadoPorFlavor();
    if (esperado == null) return true;
    final rol = _canon(rolFirestore);
    if (rol.isEmpty) return true;
    if (esAdmin(rol)) return true;
    return rol == esperado;
  }

  static String mensajeMismatch({
    required String rolFirestore,
    String? email,
  }) {
    final rol = _canon(rolFirestore);
    final mail = (email ?? '').trim();
    final sufijo = mail.isNotEmpty ? '\n\nCorreo: $mail' : '';

    if (isConductorFlavor && rol == 'cliente') {
      return 'Esta cuenta es de pasajero. Abrí RAI Pasajero (Google Play) '
          'o iniciá sesión con el correo de conductor.$sufijo';
    }
    if (isClienteFlavor && rol == 'taxista') {
      return 'Esta cuenta es de conductor. Abrí RAI Conductor o usá '
          'otro correo de pasajero.$sufijo';
    }
    return 'Esta cuenta no corresponde a esta aplicación.$sufijo';
  }

  static String tituloMismatch(String rolFirestore) {
    final rol = _canon(rolFirestore);
    if (isConductorFlavor && rol == 'cliente') {
      return 'Cuenta de pasajero';
    }
    if (isClienteFlavor && rol == 'taxista') {
      return 'Cuenta de conductor';
    }
    return 'Cuenta no compatible';
  }

  /// Lanza [FirebaseAuthException] `role-mismatch` si el rol guardado ≠ app/login.
  static void assertRolEntradaPermitida({
    required String rolFirestore,
    required String entradaRol,
    String? email,
  }) {
    final actual = _canon(rolFirestore);
    final entrada = _canon(entradaRol);
    if (actual.isEmpty || esAdmin(actual)) return;
    if (!esRolOperativo(actual)) return;
    if (entrada.isEmpty) return;
    if (actual == entrada) return;

    throw FirebaseAuthException(
      code: 'role-mismatch',
      message: mensajeMismatch(rolFirestore: actual, email: email),
    );
  }

  /// Cierra sesión Auth + Google tras rechazo.
  static Future<void> cerrarSesionTrasRechazo() async {
    try {
      await GoogleAuthService.signOut();
    } catch (_) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
    }
  }

  static Future<void> rechazarSesionRolIncorrecto({
    required String rolFirestore,
    String? email,
  }) async {
    await cerrarSesionTrasRechazo();
    throw FirebaseAuthException(
      code: 'role-mismatch',
      message: mensajeMismatch(rolFirestore: rolFirestore, email: email),
    );
  }
}

/// Pantalla bloqueo cuando la sesión activa no coincide con la APK.
class AppFlavorRolMismatchWall extends StatelessWidget {
  const AppFlavorRolMismatchWall({
    super.key,
    required this.rolFirestore,
    this.email,
    this.onElegirOtraCuenta,
  });

  final String rolFirestore;
  final String? email;
  final VoidCallback? onElegirOtraCuenta;

  Future<void> _cerrar(BuildContext context) async {
    await AppFlavorRolGuard.cerrarSesionTrasRechazo();
    if (!context.mounted) return;
    if (onElegirOtraCuenta != null) {
      onElegirOtraCuenta!();
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/auth_check', (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.swap_horiz_rounded, size: 56, color: cs.primary),
              const SizedBox(height: 20),
              Text(
                AppFlavorRolGuard.tituloMismatch(rolFirestore),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppFlavorRolGuard.mensajeMismatch(
                  rolFirestore: rolFirestore,
                  email: email,
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => _cerrar(context),
                child: const Text('Cerrar sesión y elegir otra cuenta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
