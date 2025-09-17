// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart' as intl;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:flygo_nuevo/firebase_options.dart';

// ✅ Autenticación (importa SOLO la clase que usas)
import 'package:flygo_nuevo/auth/auth_check.dart' show AuthCheck;
import 'package:flygo_nuevo/auth/login_cliente.dart';
import 'package:flygo_nuevo/auth/login_taxista.dart';
import 'package:flygo_nuevo/auth/registro_cliente.dart';
import 'package:flygo_nuevo/auth/registro_taxista.dart';

// ✅ Gates / Widgets
import 'package:flygo_nuevo/widgets/admin_gate.dart';

// ✅ Pantallas ya existentes
import 'package:flygo_nuevo/pantallas/taxista/entry_taxista.dart';
// Importa SOLO la clase (evita conflictos):
import 'package:flygo_nuevo/pantallas/cliente/cliente_home.dart' show ClienteHome;
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_disponible.dart';
import 'package:flygo_nuevo/pantallas/common/configuracion_perfil.dart';

// ✅ Nuevas pantallas/servicios (cliente)
import 'package:flygo_nuevo/pantallas/cliente/historial_viajes_cliente.dart';
import 'package:flygo_nuevo/pantallas/cliente/metodos_pago.dart';
import 'package:flygo_nuevo/pantallas/comun/soporte.dart';
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje_multi.dart';
import 'package:flygo_nuevo/pantallas/servicios_extras/consulares.dart';
import 'package:flygo_nuevo/pantallas/servicios_extras/tours.dart';

// ✅ Viajes por cupos (taxista)
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_lista.dart';
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_crear.dart';

// 🔔 Notificaciones / Navegación
import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/push_service.dart';

// 🌟 WelcomePage (pantalla de bienvenida)
import 'package:flygo_nuevo/pantallas/welcome_page.dart';
// 🔗 Legales internos
import 'package:flygo_nuevo/pantallas/comun/legales.dart';

// ⚠️ Importante: NO importes ni uses HomeFlyGo aquí (evitamos duplicados)

/// Flags de emuladores
const bool kUseEmus = bool.fromEnvironment('USE_EMULATORS', defaultValue: false);
const String kHost = String.fromEnvironment('HOST', defaultValue: 'localhost');

Future<void> _conectarEmuladores() async {
  if (!kUseEmus) return;
  FirebaseFirestore.instance.useFirestoreEmulator(kHost, 8080);
  FirebaseStorage.instance.useStorageEmulator(kHost, 9199);
}

/// --- 🔔 PUSH: handler de mensajes en background (FCM) ---
Future<void> _bg(RemoteMessage m) => firebaseMessagingBackgroundHandler(m);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _conectarEmuladores();
  await NotificationService.I.ensureInited();

  // 🔔 PUSH BG
  FirebaseMessaging.onBackgroundMessage(_bg);

  // 🌎 i18n
  Intl.defaultLocale = 'es';
  await intl.initializeDateFormatting('es');

  // Error UI helper
  ErrorWidget.builder = (details) {
    return Material(
      color: Colors.black,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent),
          ),
          child: SingleChildScrollView(
            child: Text(
              '⚠️ Error de UI:\n${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  };
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  // 🔔 Si hay sesión, asegura token
  final current = FirebaseAuth.instance.currentUser;
  if (current != null) {
    await PushService.ensureInitedAndSaved();
  }

  runApp(const FlyGoApp());
}

class FlyGoApp extends StatelessWidget {
  const FlyGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseDark = ThemeData.dark(useMaterial3: false);

    return MaterialApp(
      title: 'FlyGo RD',
      debugShowCheckedModeBanner: false,
      navigatorKey: NavigationService.navigatorKey,

      // 🌐 Localización
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

      // 🎨 Tema
      theme: baseDark.copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: baseDark.colorScheme.copyWith(
          primary: Colors.greenAccent,
          secondary: Colors.greenAccent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Colors.white10,
          contentTextStyle: TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          labelStyle: TextStyle(color: Colors.white),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.greenAccent),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.greenAccent, width: 2),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.greenAccent),
      ),

      // 🔰 Flujo real (sin duplicados): arranca por AuthCheck
      home: const AuthCheck(),

      // 🧭 Rutas
      routes: {
        // Welcome accesible por ruta (no como home)
        '/welcome': (_) => const WelcomePage(),

        // Auth
        '/login_cliente': (_) => const LoginCliente(),
        '/login_taxista': (_) => const LoginTaxista(),
        '/registro_cliente': (_) => const RegistroCliente(),
        '/registro_taxista': (_) => const RegistroTaxista(),
        '/auth_check': (_) => const AuthCheck(),

        // Cliente
        '/home_cliente': (_) => const ClienteHome(),
        '/programar_viaje': (_) => const ProgramarViaje(modoAhora: false),
        '/solicitar_viaje_ahora': (_) => const ProgramarViaje(modoAhora: true),
        '/viaje_en_curso_cliente': (_) => const ViajeEnCursoCliente(),

        // Taxista
        '/panel_taxista': (_) => const TaxistaEntry(),
        '/viaje_en_curso_taxista': (_) => const ViajeEnCursoTaxista(),
        '/viajes_disponibles': (_) => const ViajeDisponible(),

        // Admin
        '/admin': (_) => const AdminGate(),

        // Perfil
        '/configuracion_perfil': (_) => const ConfiguracionPerfil(),

        // Nuevos servicios (cliente)
        '/programar_viaje_multi': (_) => const ProgramarViajeMulti(),
        '/servicios_consulares': (_) => const ServiciosConsularesScreen(),
        '/tours_turisticos': (_) => const ToursTuristicosScreen(),

        // Viajes por cupos (taxista)
        '/pools_taxista_lista': (_) => const PoolsTaxistaLista(),
        '/pools_taxista_crear': (_) => const PoolsTaxistaCrear(),

        // Otros
        '/historial_viajes_cliente': (_) => const HistorialViajesCliente(),
        '/metodos_pago': (_) => const MetodosPago(),
        '/soporte': (_) => const Soporte(),

        // 🔗 Legales (nuevos)
        '/terminos': (_) => const TerminosCondicionesPage(),
        '/privacidad': (_) => const PoliticaPrivacidadPage(),
      },
    );
  }
}
