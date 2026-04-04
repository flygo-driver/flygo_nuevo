import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart' as intl;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'firebase_bootstrap.dart';
import 'package:flygo_nuevo/keys.dart' show kAppDisplayName;

// 🔔 Servicios
import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/servicios/push_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/pool_deep_link.dart';
import 'package:flygo_nuevo/servicios/error_reporting.dart';
import 'package:flygo_nuevo/servicios/theme_mode_service.dart';

// 🔐 Auth / Gates
import 'package:flygo_nuevo/auth/seleccion_usuario.dart';
import 'package:flygo_nuevo/widgets/verify_email_gate.dart';
import 'package:flygo_nuevo/widgets/admin_gate.dart';
import 'package:flygo_nuevo/legal/legal_acceptance_service.dart';
import 'package:flygo_nuevo/legal/terms_policy_screen.dart';

// 🧭 Cliente
import 'package:flygo_nuevo/pantallas/cliente/cliente_home.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje_multi.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/historial_viajes_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/metodos_pago.dart';
import 'package:flygo_nuevo/pantallas/cliente/espera_asignacion_turismo.dart';
import 'package:flygo_nuevo/pantallas/cliente/historial_pagos_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/pago_metodo.dart';

// 🔴 NUEVO - REGISTRO CLIENTE (DESDE AUTH)
import 'package:flygo_nuevo/auth/registro_cliente.dart';

// 🧭 Comunes
import 'package:flygo_nuevo/pantallas/comun/soporte.dart';
import 'package:flygo_nuevo/pantallas/comun/configuracion_perfil.dart';

// 🧭 Taxista
import 'package:flygo_nuevo/pantallas/taxista/entry_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_disponible.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/historial_viajes_taxista.dart';

// 🔴 NUEVO - REGISTRO TAXISTA (DESDE AUTH)
import 'package:flygo_nuevo/auth/registro_taxista.dart';

// 🔴 NUEVOS IMPORTS PARA PAGOS
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/pantallas/taxista/bloqueado_por_pagos.dart';
import 'package:flygo_nuevo/pantallas/taxista/mis_pagos.dart';
import 'package:flygo_nuevo/pantallas/admin/verificar_pagos.dart';

// ================== FLAGS ==================
const bool kUseEmus =
    bool.fromEnvironment('USE_EMULATORS', defaultValue: false);

const String kHost = String.fromEnvironment('HOST', defaultValue: 'localhost');

// ================== EMULADORES ==================
Future<void> _conectarEmuladores() async {
  if (!kUseEmus) return;

  FirebaseFirestore.instance.useFirestoreEmulator(kHost, 8080);
  FirebaseStorage.instance.useStorageEmulator(kHost, 9199);
}

// ================== FCM BACKGROUND ==================
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseBootstrap.ensureInitialized();
}

// ================== SPLASH EN FLUTTER (tras el nativo) ==================
Widget _raiSplashScaffold({String subtitle = 'Cargando RAI...'}) {
  return Scaffold(
    backgroundColor: Colors.black,
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/icon/logo_rai_vertical.png',
            width: 150,
            height: 150,
          ),
          const SizedBox(height: 30),
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.greenAccent),
          ),
          const SizedBox(height: 20),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    ),
  );
}

void _installErrorHandlers() {
  ErrorWidget.builder = (details) => Material(
        color: Colors.black,
        child: Builder(
          builder: (context) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '⚠️ Ocurrió un error',
                      style: TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'No pudimos cargar esta pantalla. Intenta nuevamente.',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: () {
                        ErrorReporting.reportError(
                          details.exceptionAsString(),
                          context: 'ErrorWidget.builder',
                        );
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          '/auth_check',
                          (r) => false,
                        );
                      },
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    ErrorReporting.reportError(
      details.exceptionAsString(),
      context: 'FlutterError.onError',
    );
  };
}

// ================== BOOTSTRAP: primer frame rápido (quita splash nativo) ==================
class RaiBootstrap extends StatefulWidget {
  const RaiBootstrap({super.key});

  @override
  State<RaiBootstrap> createState() => _RaiBootstrapState();
}

class _RaiBootstrapState extends State<RaiBootstrap> {
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await FirebaseBootstrap.ensureInitialized();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await _conectarEmuladores();
      await NotificationService.I.ensureInited();
      await ThemeModeService.init();

      Intl.defaultLocale = 'es';
      await intl.initializeDateFormatting('es');

      _installErrorHandlers();

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        PushService.ensureInitedAndSaved();
      }

      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e, st) {
      ErrorReporting.reportError(e, stack: st, context: 'RaiBootstrap._init');
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        title: kAppDisplayName,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'No se pudo iniciar la app',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$_error',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (!_ready) {
      return MaterialApp(
        title: kAppDisplayName,
        debugShowCheckedModeBanner: false,
        home: _raiSplashScaffold(subtitle: 'Iniciando...'),
      );
    }
    return const RaiApp();
  }
}

// ================== MAIN ==================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runZonedGuarded(
    () => runApp(const RaiBootstrap()),
    (error, stack) {
      ErrorReporting.reportError(
        error,
        stack: stack,
        context: 'runZonedGuarded',
      );
    },
  );
}

// ================== APP ==================
class RaiApp extends StatefulWidget {
  const RaiApp({super.key});

  @override
  State<RaiApp> createState() => _RaiAppState();
}

class _RaiAppState extends State<RaiApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushService.registerNotificationOpenHandlers();
      PushService.consumeInitialNotificationIfAny();
      PoolDeepLink.install();
    });
  }

  @override
  void dispose() {
    PoolDeepLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseDark = ThemeData.dark(useMaterial3: false);
    final baseLight = ThemeData.light(useMaterial3: false);

    final darkTheme = baseDark.copyWith(
      scaffoldBackgroundColor: Colors.black,
      colorScheme: baseDark.colorScheme.copyWith(
        primary: Colors.greenAccent,
        secondary: Colors.greenAccent,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    final lightTheme = baseLight.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF4F7FB),
      colorScheme: baseLight.colorScheme.copyWith(
        primary: const Color(0xFF16A34A),
        secondary: const Color(0xFF16A34A),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF111827),
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Color(0xFF111827),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeModeService.mode,
      builder: (context, mode, _) => MaterialApp(
        title: kAppDisplayName,
        debugShowCheckedModeBanner: false,
        navigatorKey: NavigationService.navigatorKey,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('es'),
          Locale('es', 'DO'),
          Locale('en'),
        ],
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: mode,
        routes: {
        '/login': (_) => const SeleccionUsuario(),
        '/auth_check': (_) => const AuthGatePublic(),

        // 🔴 NUEVO - REGISTRO (DESDE AUTH)
        '/registro_cliente': (_) => const RegistroCliente(),
        '/registro_taxista': (_) => const RegistroTaxista(),

        // Cliente
        '/solicitar_viaje_ahora': (_) => const ProgramarViaje(modoAhora: true),
        '/programar_viaje': (_) => const ProgramarViaje(modoAhora: false),
        '/programar_viaje_multi': (_) => const ProgramarViajeMulti(),
        '/viaje_en_curso_cliente': (_) => const ViajeEnCursoCliente(),
        '/historial_viajes_cliente': (_) => const HistorialViajesCliente(),
        '/metodos_pago': (_) => const MetodosPago(),
        '/espera_asignacion_turismo': (_) =>
            const EsperaAsignacionTurismo(viajeId: ''),
        '/historial_pagos': (_) => const HistorialPagosCliente(),
        '/pago_metodo': (_) => const PagoMetodo(),

        // comunes
        '/soporte': (_) => const Soporte(),
        '/configuracion_perfil': (_) => const ConfiguracionPerfil(),

        // taxista
        '/taxista_entry': (_) => const TaxistaEntry(),
        '/viaje_disponible': (_) => const ViajeDisponible(),
        '/viaje_en_curso_taxista': (_) => const ViajeEnCursoTaxista(),
        '/historial_viajes_taxista': (_) => const HistorialViajesTaxista(),

        // 🔴 NUEVAS RUTAS DE PAGOS
        '/mis_pagos': (_) => const MisPagos(),
        '/bloqueado_por_pagos': (_) => const BloqueadoPorPagos(),
        '/verificar_pagos': (_) => const VerificarPagos(),
        '/terminos_politica': (_) => const TermsPolicyScreen(),
        },
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (_) => const SeleccionUsuario(),
          );
        },
        home: const AuthGatePublic(),
      ),
    );
  }

}

// ================== AUTH GATE PUBLIC ==================
class AuthGatePublic extends StatelessWidget {
  const AuthGatePublic({super.key});

  @override
  Widget build(BuildContext context) {
    return const _AuthGate();
  }
}

// ================== AUTH GATE REAL ==================
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  static Future<void> ensureUsuarioDoc(User user) async {
    final db = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();
    final uRef = db.collection('usuarios').doc(user.uid);
    final rRef = db.collection('roles').doc(user.uid);

    final uSnap = await uRef.get();
    if (uSnap.exists) {
      final data = uSnap.data() ?? <String, dynamic>{};
      final rol = (data['rol'] ?? '').toString().trim().toLowerCase();
      if (rol.isNotEmpty) return;
    }

    String rol = 'cliente';
    try {
      final rSnap = await rRef.get();
      final rolRoles = (rSnap.data()?['rol'] ?? '').toString().trim().toLowerCase();
      if (rolRoles == 'taxista' || rolRoles == 'admin' || rolRoles == 'cliente') {
        rol = rolRoles;
      }
    } catch (_) {}

    await uRef.set({
      'uid': user.uid,
      'email': (user.email ?? '').toString(),
      'nombre': (user.displayName ?? '').toString(),
      'telefono': (user.phoneNumber ?? '').toString(),
      'fotoUrl': (user.photoURL ?? '').toString(),
      'rol': rol,
      'updatedAt': now,
      'actualizadoEn': now,
      'lastLogin': now,
      'fechaRegistro': now,
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data ?? FirebaseAuth.instance.currentUser;
        if (authSnap.connectionState == ConnectionState.waiting && user == null) {
          return _raiSplashScaffold();
        }
        if (user == null) {
          return const SeleccionUsuario();
        }

        PushService.ensureInitedAndSaved();

        final doc =
            FirebaseFirestore.instance.collection('usuarios').doc(user.uid);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: doc.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return _raiSplashScaffold();
            }

            if (!snap.hasData || !snap.data!.exists) {
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: () async {
                  await ensureUsuarioDoc(user);
                  return doc.get();
                }(),
                builder: (context, ensured) {
                  if (ensured.connectionState != ConnectionState.done) {
                    return _raiSplashScaffold();
                  }
                  if (ensured.hasError) {
                    return Scaffold(
                      backgroundColor: Colors.black,
                      body: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No pudimos preparar tu perfil.\n${ensured.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    );
                  }
                  final fresh = ensured.data;
                  if (fresh == null || !fresh.exists) {
                    return const SeleccionUsuario();
                  }
                  return _buildGateForUsuarioData(context, user, fresh.data() ?? {});
                },
              );
            }

            final data = snap.data!.data() ?? {};
            return _buildGateForUsuarioData(context, user, data);
          },
        );
      },
    );
  }
}

Widget _buildGateForUsuarioData(
  BuildContext context,
  User user,
  Map<String, dynamic> data,
) {
  final rol = (data['rol'] ?? '').toString().toLowerCase().trim();

  return FutureBuilder<bool>(
    future: LegalAcceptanceService.hasAccepted(user.uid),
    builder: (context, legalSnap) {
      if (legalSnap.connectionState == ConnectionState.waiting) {
        return _raiSplashScaffold(subtitle: 'Cargando perfil...');
      }

      final hasAccepted = legalSnap.data ?? false;
      if (!hasAccepted) {
        return TermsPolicyScreen(
          requireAcceptance: true,
          onAccepted: () {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/auth_check', (r) => false);
          },
        );
      }

      if (rol == 'admin' || rol == 'administrador') {
        return const AdminGate();
      }

      if (rol == 'taxista' || rol == 'driver') {
        return FutureBuilder<bool>(
          future: PagosTaxistaRepo.puedeTrabajar(user.uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _raiSplashScaffold(subtitle: 'Verificando pagos...');
            }

            final puedeTrabajar = snapshot.data ?? true;

            if (!puedeTrabajar) {
              return const BloqueadoPorPagos();
            }

            return const VerifyEmailGate(
              childWhenVerified: TaxistaEntry(),
            );
          },
        );
      }

      if (rol == 'cliente' || rol == 'user') {
        return const VerifyEmailGate(
          childWhenVerified: ClienteHome(),
        );
      }

      return _raiSplashScaffold(subtitle: 'Sincronizando cuenta...');
    },
  );
}
