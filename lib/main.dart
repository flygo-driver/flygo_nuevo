import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart' as intl;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:flygo_nuevo/servicios/fcm_service.dart';
import 'package:flygo_nuevo/servicios/location_permission_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'firebase_bootstrap.dart';
import 'package:flygo_nuevo/keys.dart' show kAppDisplayName;
import 'package:flygo_nuevo/utilidades/constante.dart'
    show rutaBolaConductoresCliente, rutaBolaPueblo;

// 🔔 Servicios
import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/servicios/push_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/pool_deep_link.dart';
import 'package:flygo_nuevo/servicios/error_reporting.dart';
import 'package:flygo_nuevo/servicios/theme_mode_service.dart';
import 'package:flygo_nuevo/servicios/custom_theme_service.dart';
import 'package:flygo_nuevo/servicios/text_scale_service.dart';
import 'package:flygo_nuevo/servicios/comision_viaje_pct_service.dart';
import 'package:flygo_nuevo/servicios/analytics_rai.dart';
import 'package:flygo_nuevo/app_flavor.dart';

// 🔐 Auth / Gates
import 'package:flygo_nuevo/auth/seleccion_usuario.dart';
import 'package:flygo_nuevo/auth/login_admin.dart';
import 'package:flygo_nuevo/widgets/verify_email_gate.dart';
import 'package:flygo_nuevo/widgets/admin_gate.dart';
import 'package:flygo_nuevo/legal/legal_acceptance_service.dart';
import 'package:flygo_nuevo/legal/terms_policy_screen.dart';

// 🧭 Cliente
import 'package:flygo_nuevo/shell/cliente_shell.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje_multi.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/historial_viajes_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/metodos_pago.dart';
import 'package:flygo_nuevo/pantallas/cliente/espera_asignacion_turismo.dart';
import 'package:flygo_nuevo/pantallas/cliente/historial_pagos_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/pago_metodo.dart';
import 'package:flygo_nuevo/pantallas/cliente/bola_conductores_en_ruta_cliente.dart';

// 🔴 NUEVO - REGISTRO CLIENTE (DESDE AUTH)
import 'package:flygo_nuevo/auth/registro_cliente.dart';

// 🧭 Comunes
import 'package:flygo_nuevo/pantallas/comun/soporte.dart';
import 'package:flygo_nuevo/pantallas/comun/configuracion_perfil.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_a_pueblo.dart';

// 🧭 Taxista
import 'package:flygo_nuevo/pantallas/taxista/entry_taxista.dart';
import 'package:flygo_nuevo/shell/taxista_shell.dart';
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

// ================== SPLASH EN FLUTTER (tras el nativo) ==================
/// Splash unificado: barra lineal de borde a borde + logo. [subtitle] solo si hace falta copy explícito.
Widget _raiSplashScaffold({String? subtitle}) {
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
                  'assets/icon/logo_rai_vertical.png',
                  width: 150,
                  height: 150,
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      subtitle,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 15),
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

/// En escritorio (Windows/macOS) solo permitimos cuentas de administración.
class _DesktopNonAdminWall extends StatelessWidget {
  const _DesktopNonAdminWall();

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
              ElevatedButton.icon(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
      // En Windows evitamos FCM (MissingPluginException en métodos de firebase_messaging).
      if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) {
        FirebaseMessaging.onBackgroundMessage(
            fcmFirebaseMessagingBackgroundHandler);
      }
      await _conectarEmuladores();
      // Detección AUTOMÁTICA del flavor desde el applicationId del paquete
      // (com.flygo.rd2 → cliente, com.flygo.rd2.conductor → conductor).
      // Es a prueba de errores humanos: si el dev olvida --dart-define al
      // construir, el applicationId sigue siendo distinto y el flavor real
      // se detecta correctamente.
      await AppFlavor.init();
      await NotificationService.I.ensureInited();
      FcmService.registerForegroundHandlers();
      if (!kIsWeb && defaultTargetPlatform != TargetPlatform.windows) {
        unawaited(LocationPermissionService.checkAndRequestBasicPermission());
      }
      await ThemeModeService.init();
      // Color de fondo personalizable por el usuario (cliente). Si nunca lo
      // ha cambiado, mantiene el aspecto previo (gris claro / negro).
      await CustomThemeService.init();
      // Tamaño de texto personalizable (tipo inDrive). Si nunca lo cambia,
      // queda en 1.0 (tamaño normal de Flutter).
      await TextScaleService.init();

      await AnalyticsRai.init();

      Intl.defaultLocale = 'es';
      await intl.initializeDateFormatting('es');

      unawaited(ComisionViajePctService.refresh(force: true));
      ComisionViajePctService.startPeriodicRefresh();

      unawaited(
        AnalyticsRai.logFunnel(
          'rai_bootstrap_ok',
          params: <String, Object>{'flavor': AppFlavor.current},
        ),
      );

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
        home: _raiSplashScaffold(),
      );
    }
    return const RaiApp();
  }
}

// ================== MAIN ==================
void _configureAndroidPhotoPicker() {
  final ImagePickerPlatform platform = ImagePickerPlatform.instance;
  if (platform is ImagePickerAndroid) {
    platform.useAndroidPhotoPicker = true;
  }
}

/// Barra de estado y **barra de navegación del sistema** (inicio / atrás / recientes)
/// siempre visibles en toda la app (no modo inmersivo), estilo apps tipo Uber.
void _configureGlobalSystemUi() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      _configureGlobalSystemUi();
      _configureAndroidPhotoPicker();
      runApp(const RaiBootstrap());
    },
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
      final bool isDesktop =
          defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.macOS;
      if (!isDesktop) {
        PoolDeepLink.install();
      }
    });
  }

  @override
  void dispose() {
    final bool isDesktop =
        defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS;
    if (!isDesktop) {
      PoolDeepLink.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Construye los ThemeData en función del color custom elegido por el usuario.
    // Si el color es `null` (nunca cambió), se usan los defaults históricos
    // (gris claro / negro), por lo que la app se ve igual que antes.
    ThemeData buildLight() {
      final baseLight = ThemeData.light(useMaterial3: false);
      final Color bg = CustomThemeService.resolveScaffoldBg(Brightness.light);
      // Texto óptimo (negro o blanco) calculado por contraste WCAG sobre `bg`.
      final Color onBg = CustomThemeService.textOn(bg);
      return baseLight.copyWith(
        scaffoldBackgroundColor: bg,
        colorScheme: baseLight.colorScheme.copyWith(
          primary: const Color(0xFF16A34A),
          secondary: const Color(0xFF16A34A),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: bg,
          foregroundColor: onBg,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: onBg,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    ThemeData buildDark() {
      final baseDark = ThemeData.dark(useMaterial3: false);
      final Color bg = CustomThemeService.resolveScaffoldBg(Brightness.dark);
      final Color onBg = CustomThemeService.textOn(bg);
      return baseDark.copyWith(
        scaffoldBackgroundColor: bg,
        colorScheme: baseDark.colorScheme.copyWith(
          primary: Colors.greenAccent,
          secondary: Colors.greenAccent,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: bg,
          foregroundColor: onBg,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: onBg,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    // Combinamos ambos notifiers para reconstruir el MaterialApp cuando cambie
    // el modo (light/dark/system) o el color custom elegido por el usuario.
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        ThemeModeService.mode,
        CustomThemeService.color,
        CustomThemeService.mapFloatingChrome,
        TextScaleService.factor,
      ]),
      builder: (context, _) {
        final ThemeMode mode = ThemeModeService.mode.value;
        final ThemeData lightTheme = buildLight();
        final ThemeData darkTheme = buildDark();
        return MaterialApp(
        title: kAppDisplayName,
        debugShowCheckedModeBanner: false,
        navigatorKey: NavigationService.navigatorKey,
        builder: (ctx, child) {
          final Brightness brightness;
          switch (mode) {
            case ThemeMode.dark:
              brightness = Brightness.dark;
              break;
            case ThemeMode.light:
              brightness = Brightness.light;
              break;
            case ThemeMode.system:
              brightness = MediaQuery.platformBrightnessOf(ctx);
              break;
          }
          final isDark = brightness == Brightness.dark;
          final overlay = SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor:
                isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF6F6F6),
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarContrastEnforced: true,
          );
          // Aplica el factor de escala global de texto (tipo inDrive).
          // Si el usuario nunca tocó nada, el factor es 1.0 y todo queda
          // exactamente igual que antes. El clamp evita overflow en cards
          // y botones existentes.
          final MediaQueryData mq = MediaQuery.of(ctx);
          final double userFactor = TextScaleService.factor.value;
          final scaledMq = mq.copyWith(
            textScaler: TextScaler.linear(userFactor).clamp(
              minScaleFactor: TextScaleService.minFactor,
              maxScaleFactor: TextScaleService.maxFactor,
            ),
          );
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlay,
            sized: false,
            child: MediaQuery(
              data: scaledMq,
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
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
          '/solicitar_viaje_ahora': (_) =>
              const ProgramarViaje(modoAhora: true),
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
          rutaBolaPueblo: (_) => const BolaPuebloAPuebloPage(),
          rutaBolaConductoresCliente: (_) =>
              const BolaConductoresEnRutaClientePage(),

          // taxista
          '/taxista_entry': (_) => const TaxistaEntry(),
          '/viaje_disponible': (_) => const TaxistaShell(),
          '/viaje_en_curso_taxista': (_) => const ViajeEnCursoTaxista(),
          '/historial_viajes_taxista': (_) => const HistorialViajesTaxista(),

          // 🔴 NUEVAS RUTAS DE PAGOS
          '/mis_pagos': (_) => const MisPagos(),
          '/bloqueado_por_pagos': (_) => const BloqueadoPorPagos(),
          '/verificar_pagos': (_) => const VerificarPagos(),
          '/terminos_politica': (_) => const TermsPolicyScreen(),
          '/admin': (_) => const AdminGate(),
        },
        onGenerateRoute: (settings) => null,
        onUnknownRoute: (settings) {
          return MaterialPageRoute<void>(
            builder: (_) => const AuthGatePublic(),
            settings: settings,
          );
        },
        home: const AuthGatePublic(),
      );
      },
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

    DocumentSnapshot<Map<String, dynamic>> uSnap = await uRef.get();
    if (uSnap.exists) {
      final data = uSnap.data() ?? <String, dynamic>{};
      final rol = (data['rol'] ?? '').toString().trim().toLowerCase();
      if (rol.isNotEmpty) return;
    }

    // Evita carrera con registro taxista: el gate puede leer antes del primer .set() en Firestore.
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 90));
      uSnap = await uRef.get();
      if (uSnap.exists) {
        final data = uSnap.data() ?? <String, dynamic>{};
        final rol = (data['rol'] ?? '').toString().trim().toLowerCase();
        if (rol.isNotEmpty) return;
      }
    }

    String rol = 'cliente';
    try {
      final rSnap = await rRef.get();
      final rolRoles =
          (rSnap.data()?['rol'] ?? '').toString().trim().toLowerCase();
      if (rolRoles == 'taxista' ||
          rolRoles == 'admin' ||
          rolRoles == 'cliente') {
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
        if (authSnap.connectionState == ConnectionState.waiting &&
            user == null) {
          return _raiSplashScaffold();
        }
        if (user == null) {
          final bool isDesktop =
              defaultTargetPlatform == TargetPlatform.windows ||
                  defaultTargetPlatform == TargetPlatform.macOS;
          return isDesktop ? const LoginAdmin() : const SeleccionUsuario();
        }

        PushService.ensureInitedAndSaved();

        final doc =
            FirebaseFirestore.instance.collection('usuarios').doc(user.uid);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: doc.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
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
                  return _buildGateForUsuarioData(
                      context, user, fresh.data() ?? {});
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
  // Sin rol en Firestore (carrera Google / upsert parcial) antes caía en splash infinito.
  var rol = (data['rol'] ?? '').toString().toLowerCase().trim();
  if (rol.isEmpty) {
    rol = 'cliente';
  }

  final bool isDesktop =
      defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS;

  return FutureBuilder<bool>(
    future: LegalAcceptanceService.hasAccepted(user.uid),
    builder: (context, legalSnap) {
      if (legalSnap.connectionState == ConnectionState.waiting) {
        return _raiSplashScaffold();
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

      final bool esAdmin = rol == 'admin' || rol == 'administrador';
      if (isDesktop && !esAdmin) {
        return const _DesktopNonAdminWall();
      }

      if (esAdmin) {
        return const AdminGate();
      }

      if (rol == 'taxista' || rol == 'driver') {
        return FutureBuilder<bool>(
          future: PagosTaxistaRepo.puedeTrabajar(user.uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _raiSplashScaffold();
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
          childWhenVerified: ClienteShell(),
        );
      }

      return _raiSplashScaffold();
    },
  );
}
