import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/app_flavor.dart';
import 'package:flygo_nuevo/servicios/logout.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';

/// Cruza [AppFlavor] (APK instalada) con `usuarios.rol` / `roles.rol`.
///
/// Play unificado (`com.flygo.rd2` → flavor `all`): acepta cliente y taxista.
/// Split futuro: `com.flygo.rd2` solo cliente, `com.flygo.rd2.conductor` solo taxista.
class AppFlavorRolGuard {
  AppFlavorRolGuard._();

  static const String playStorePasajeroPackage = 'com.flygo.rd2';
  static const String playStoreConductorPackage = 'com.flygo.rd2.conductor';

  /// Motivo del último rechazo (login se remonta al cerrar sesión).
  static String? _motivoRechazoPendiente;

  static void guardarMotivoRechazo(String msg) {
    final t = msg.trim();
    if (t.isEmpty) return;
    _motivoRechazoPendiente = t;
  }

  /// Consume y limpia el mensaje pendiente (una sola vez).
  static String? consumirMotivoRechazo() {
    final m = _motivoRechazoPendiente;
    _motivoRechazoPendiente = null;
    return m;
  }

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

  /// Cuentas operativas fijas (como en Play Store):
  /// - open07service → pasajero
  /// - ventasopenask → conductor
  static String? rolFijoPorEmail(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    if (e == 'open07service@gmail.com') return 'cliente';
    if (e == 'ventasopenask@gmail.com') return 'taxista';
    return null;
  }

  /// Si el correo tiene rol fijo y la pestaña no coincide, lanza mismatch claro.
  static void assertEntradaRespetaEmailFijo({
    required String? email,
    required String entradaRol,
  }) {
    final fijo = rolFijoPorEmail(email);
    if (fijo == null) return;
    final entrada = _canon(entradaRol);
    if (entrada.isEmpty || fijo == entrada) return;

    final mail = (email ?? '').trim();
    final msg = fijo == 'taxista'
        ? 'No puedes entrar como pasajero.\n\n'
            'Motivo: $mail es cuenta de CONDUCTOR (como en Play).\n\n'
            'Qué hacer: en inicio tocá la pestaña «Conductor» y volvé a entrar.'
        : 'No puedes entrar como conductor.\n\n'
            'Motivo: $mail es cuenta de PASAJERO (como en Play).\n\n'
            'Qué hacer: en inicio tocá la pestaña «Pasajero» y volvé a entrar.';

    guardarMotivoRechazo(msg);
    throw FirebaseAuthException(code: 'role-mismatch', message: msg);
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

  static String _sufijoContacto({String? email, String? telefono}) {
    final mail = (email ?? '').trim();
    if (mail.isNotEmpty) return '\n\nCorreo: $mail';
    final tel = (telefono ?? '').trim();
    if (tel.isNotEmpty) return '\n\nTeléfono: $tel';
    return '';
  }

  static String mensajeMismatch({
    required String rolFirestore,
    String? email,
    String? telefono,
  }) {
    final rol = _canon(rolFirestore);
    final sufijo = _sufijoContacto(email: email, telefono: telefono);

    if (isConductorFlavor && rol == 'cliente') {
      return 'No puedes entrar en RAI Conductor con esta cuenta.\n\n'
          'Motivo: $email es una cuenta de PASAJERO, no de conductor.\n\n'
          'Qué hacer:\n'
          '• Abrí la app RAI Pasajero (o Play «RAI» unificada → pestaña Pasajero), o\n'
          '• Entrá aquí con un correo de conductor '
          '(p. ej. pablo148145 o ianalonso).$sufijo';
    }
    if (isClienteFlavor && rol == 'taxista') {
      return 'No puedes entrar en RAI Pasajero con esta cuenta.\n\n'
          'Motivo: es una cuenta de CONDUCTOR.\n\n'
          'Qué hacer: abrí RAI Conductor o elegí la pestaña Conductor.$sufijo';
    }
    return 'Esta cuenta no corresponde a esta aplicación.$sufijo';
  }

  /// Play unificada (`all`): mensaje según pantalla de entrada (pasajero vs conductor).
  static String mensajeMismatchEntrada({
    required String rolFirestore,
    required String entradaRol,
    String? email,
    String? telefono,
  }) {
    final actual = _canon(rolFirestore);
    final entrada = _canon(entradaRol);
    final mail = (email ?? '').trim();
    final quien = mail.isNotEmpty ? mail : 'Esta cuenta';

    if (entrada == 'cliente' && actual == 'taxista') {
      return 'No entró como pasajero.\n\n'
          'Motivo: $quien es cuenta de CONDUCTOR.\n\n'
          'Qué hacer: en inicio tocá la pestaña «Conductor» y volvé a entrar.';
    }
    if (entrada == 'taxista' && actual == 'cliente') {
      return 'No entró como conductor.\n\n'
          'Motivo: $quien es cuenta de PASAJERO (ventasopenask es pasajero).\n\n'
          'Qué hacer: en inicio tocá la pestaña «Pasajero» y volvé a entrar.';
    }

    return mensajeMismatch(
      rolFirestore: rolFirestore,
      email: email,
      telefono: telefono,
    );
  }

  static String tituloMismatch(String rolFirestore) {
    final rol = _canon(rolFirestore);
    if (isConductorFlavor && rol == 'cliente') {
      return 'No puedes entrar aquí';
    }
    if (isClienteFlavor && rol == 'taxista') {
      return 'No puedes entrar aquí';
    }
    return 'Cuenta no compatible';
  }

  /// Lanza [FirebaseAuthException] `role-mismatch` si el rol guardado ≠ app/login.
  static void assertRolEntradaPermitida({
    required String rolFirestore,
    required String entradaRol,
    String? email,
    String? telefono,
  }) {
    final actual = _canon(rolFirestore);
    final entrada = _canon(entradaRol);
    if (actual.isEmpty || esAdmin(actual)) return;
    if (!esRolOperativo(actual)) return;
    if (entrada.isEmpty) return;
    if (actual == entrada) return;

    final mensaje = isAllFlavors
        ? mensajeMismatchEntrada(
            rolFirestore: actual,
            entradaRol: entrada,
            email: email,
            telefono: telefono,
          )
        : mensajeMismatch(
            rolFirestore: actual,
            email: email,
            telefono: telefono,
          );

    guardarMotivoRechazo(mensaje);
    throw FirebaseAuthException(
      code: 'role-mismatch',
      message: mensaje,
    );
  }

  /// Cierra sesión Auth + Google tras rechazo.
  static Future<void> cerrarSesionTrasRechazo() async {
    try {
      await cerrarSesionAuthOnly();
    } catch (_) {}
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
