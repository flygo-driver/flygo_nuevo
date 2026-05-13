import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_bootstrap.dart';
import 'keys.dart' show kAppDisplayName;
import 'package:flygo_nuevo/servicios/comision_viaje_pct_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runZonedGuarded(
    () => runApp(const DesktopBootstrapApp()),
    (error, stack) {
      debugPrint('Desktop bootstrap error: $error\n$stack');
    },
  );
}

class DesktopBootstrapApp extends StatefulWidget {
  const DesktopBootstrapApp({super.key});

  @override
  State<DesktopBootstrapApp> createState() => _DesktopBootstrapAppState();
}

class _DesktopBootstrapAppState extends State<DesktopBootstrapApp> {
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
      unawaited(ComisionViajePctService.refresh(force: true));
      ComisionViajePctService.startPeriodicRefresh();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        title: kAppDisplayName,
        debugShowCheckedModeBanner: false,
        home: _ErrorScreen(error: _error.toString()),
      );
    }

    if (!_ready) {
      return const MaterialApp(
        title: kAppDisplayName,
        debugShowCheckedModeBanner: false,
        home: _LoadingScreen(),
      );
    }

    return const DesktopAdminApp();
  }
}

class DesktopAdminApp extends StatelessWidget {
  const DesktopAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final darkTheme = ThemeData.dark(useMaterial3: false).copyWith(
      scaffoldBackgroundColor: Colors.black,
      colorScheme: ThemeData.dark().colorScheme.copyWith(
            primary: Colors.greenAccent,
            secondary: Colors.greenAccent,
          ),
    );

    return MaterialApp(
      title: kAppDisplayName,
      debugShowCheckedModeBanner: false,
      theme: darkTheme,
      routes: {
        '/auth_check': (_) => const DesktopAuthGate(),
      },
      home: const DesktopAuthGate(),
    );
  }
}

class DesktopAuthGate extends StatefulWidget {
  const DesktopAuthGate({super.key});

  @override
  State<DesktopAuthGate> createState() => _DesktopAuthGateState();
}

class _DesktopAuthGateState extends State<DesktopAuthGate> {
  bool _checking = true;
  bool _isAdmin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _checking = false;
            _isAdmin = false;
          });
        }
        return;
      }

      final isAdmin = await _isAdminByUid(user.uid);
      if (mounted) {
        setState(() {
          _checking = false;
          _isAdmin = isAdmin;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checking = false;
          _isAdmin = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<bool> _isAdminByUid(String uid) async {
    final db = FirebaseFirestore.instance;

    final usuario = await db.collection('usuarios').doc(uid).get();
    final rolUsuario = (usuario.data()?['rol'] ?? '').toString().trim().toLowerCase();
    if (rolUsuario == 'admin' || rolUsuario == 'administrador') return true;

    final rol = await db.collection('roles').doc(uid).get();
    final rolDoc = (rol.data()?['rol'] ?? '').toString().trim().toLowerCase();
    return rolDoc == 'admin' || rolDoc == 'administrador';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (_checking) return const _LoadingScreen();
    if (_error != null) return _ErrorScreen(error: _error!);
    if (user == null) {
      return _DesktopEmailAdminLogin(onLoggedIn: _checkSession);
    }
    if (_isAdmin) {
      return _DesktopAdminHome(onRefresh: _checkSession);
    }
    return _NonAdminScreen(onSignedOut: _checkSession);
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: CircularProgressIndicator(color: Colors.greenAccent),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No se pudo iniciar la app de escritorio.\n$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

class _NonAdminScreen extends StatelessWidget {
  const _NonAdminScreen({required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings_outlined, color: Colors.white54, size: 52),
              const SizedBox(height: 16),
              const Text(
                'Esta version de escritorio es solo para administracion.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tu cuenta no tiene rol admin. Cierra sesion e intenta con una cuenta de administracion.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  onSignedOut();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesion'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopEmailAdminLogin extends StatefulWidget {
  const _DesktopEmailAdminLogin({required this.onLoggedIn});

  final VoidCallback onLoggedIn;

  @override
  State<_DesktopEmailAdminLogin> createState() => _DesktopEmailAdminLoginState();
}

class _DesktopEmailAdminLoginState extends State<_DesktopEmailAdminLogin> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      widget.onLoggedIn();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'user-not-found' => 'No existe una cuenta con ese correo.',
        'wrong-password' => 'Contrasena incorrecta.',
        'invalid-email' => 'Correo invalido.',
        'too-many-requests' => 'Demasiados intentos, intenta luego.',
        _ => 'No se pudo iniciar sesion (${e.code}).',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            color: const Color(0xFF121212),
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Acceso Administracion',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Correo',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final text = (v ?? '').trim();
                        if (text.isEmpty || !text.contains('@')) return 'Correo invalido';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Contrasena',
                        border: OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (_) => _login(),
                      validator: (v) {
                        if ((v ?? '').length < 6) return 'Minimo 6 caracteres';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        child: Text(_loading ? 'Entrando...' : 'Entrar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopAdminHome extends StatefulWidget {
  const _DesktopAdminHome({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  State<_DesktopAdminHome> createState() => _DesktopAdminHomeState();
}

class _DesktopAdminHomeState extends State<_DesktopAdminHome> {
  bool _loading = true;
  int _usuarios = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = FirebaseFirestore.instance;
      final usuarios = await db.collection('usuarios').limit(1).get();
      if (!mounted) return;
      setState(() {
        _usuarios = usuarios.size;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Administracion Desktop'),
        actions: [
          IconButton(
            onPressed: _loadSummary,
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
          ),
          IconButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              widget.onRefresh();
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesion',
          ),
        ],
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator(color: Colors.greenAccent)
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Sesion admin activa en Windows',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error == null
                          ? 'Firestore conectado. Consulta de prueba OK (usuarios leidos: $_usuarios).'
                          : 'Firestore error: $_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
