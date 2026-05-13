import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';
import 'keys.dart' show kAppDisplayName;

const String _region = 'us-central1';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const DesktopHttpApp());
}

class DesktopHttpApp extends StatefulWidget {
  const DesktopHttpApp({super.key});

  @override
  State<DesktopHttpApp> createState() => _DesktopHttpAppState();
}

class _DesktopHttpAppState extends State<DesktopHttpApp> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppDisplayName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: false),
      home: !_ready
          ? const _Loading()
          : (_error != null ? _ErrorView(_error!) : const _DesktopHttpGate()),
    );
  }
}

class _DesktopHttpGate extends StatefulWidget {
  const _DesktopHttpGate();

  @override
  State<_DesktopHttpGate> createState() => _DesktopHttpGateState();
}

class _DesktopHttpGateState extends State<_DesktopHttpGate> {
  bool _checking = true;
  bool _navigatedToAdmin = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    debugPrint('[desktop-http] _check() init');
    setState(() {
      _checking = true;
    });
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[desktop-http] _check() no logged user');
      setState(() => _checking = false);
      return;
    }
    try {
      debugPrint('[desktop-http] calling desktopAdminSessionInfo for uid=${user.uid}');
      final s = await _callCallableHttp('desktopAdminSessionInfo', const {});
      final role = (s['role'] ?? '').toString().toLowerCase().trim();
      final ok = s['ok'] == true;
      final isAdmin = role == 'admin' || role == 'administrador';
      debugPrint('[desktop-http] session response ok=$ok role=$role body=$s');
      if (!ok || !isAdmin) {
        throw Exception('Sesion valida pero sin rol admin. role=$role');
      }
      if (!mounted) return;
      setState(() => _checking = false);
      if (!_navigatedToAdmin) {
        _navigatedToAdmin = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => AdminHomePage(session: s),
          ),
        );
      }
    } catch (e) {
      debugPrint('[desktop-http] _check() failed: $e');
      if (!mounted) return;
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() => _checking = false);
      await _showErrorDialog(
        context,
        'No se pudo entrar a Administracion',
        e.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const _Loading();
    if (FirebaseAuth.instance.currentUser == null) {
      return _LoginEmail(onLoggedIn: _check);
    }
    return const _Loading();
  }
}

class _LoginEmail extends StatefulWidget {
  const _LoginEmail({required this.onLoggedIn});
  final Future<void> Function() onLoggedIn;

  @override
  State<_LoginEmail> createState() => _LoginEmailState();
}

class _LoginEmailState extends State<_LoginEmail> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      debugPrint('[desktop-http] login email=${_email.text.trim()}');
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text,
      );
      debugPrint('[desktop-http] auth success uid=${FirebaseAuth.instance.currentUser?.uid}');
      await widget.onLoggedIn();
    } on FirebaseAuthException catch (e) {
      debugPrint('[desktop-http] auth error code=${e.code} message=${e.message}');
      if (!mounted) return;
      await _showErrorDialog(
        context,
        'Error de autenticacion',
        'code=${e.code}\nmessage=${e.message ?? 'sin mensaje'}',
      );
    } catch (e) {
      debugPrint('[desktop-http] login flow error: $e');
      if (!mounted) return;
      await _showErrorDialog(
        context,
        'Error en login',
        e.toString(),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Admin en PC/Laptop', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Correo', border: OutlineInputBorder()),
                      validator: (v) => (v == null || !v.contains('@')) ? 'Correo invalido' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pass,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Contrasena', border: OutlineInputBorder()),
                      validator: (v) => (v == null || v.length < 6) ? 'Minimo 6 caracteres' : null,
                      onFieldSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 12),
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

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key, required this.session});
  final Map<String, dynamic> session;

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  Map<String, dynamic> _session = const <String, dynamic>{};
  Timer? _timer;
  bool _refreshing = false;
  DateTime? _lastRefreshAt;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _lastRefreshAt = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshSession();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshSession() async {
    if (_refreshing) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    setState(() => _refreshing = true);
    try {
      final next = await _callCallableHttp('desktopAdminSessionInfo', const {});
      if (!mounted) return;
      setState(() {
        _session = next;
        _lastRefreshAt = DateTime.now();
      });
    } catch (e) {
      debugPrint('[desktop-http] refresh failed: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resumen =
        (_session['resumen'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final last = _lastRefreshAt;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel Admin Desktop (HTTP)'),
        actions: [
          IconButton(
            tooltip: 'Refrescar ahora',
            onPressed: _refreshing ? null : _refreshSession,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(
                  builder: (_) => const _DesktopHttpGate(),
                ),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sesion admin validada por Cloud Functions', style: TextStyle(fontSize: 17)),
              const SizedBox(height: 10),
              Text('Pagos pendientes: ${resumen['pagosPendientes'] ?? 0}'),
              Text('Pagados (muestra): ${resumen['pagosPagadosMuestra'] ?? 0}'),
              Text('Bloqueos activos (muestra): ${resumen['bloqueosActivosMuestra'] ?? 0}'),
              Text('Comisiones por vencer (muestra): ${resumen['comisionPorVencerMuestra'] ?? 0}'),
              const SizedBox(height: 8),
              Text(
                last == null
                    ? 'Refresco automatico cada 15s'
                    : 'Ultimo refresh: ${last.toLocal().toString().substring(0, 19)}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              const Text('Este modo NO usa cloud_firestore en Windows.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              SizedBox(
                width: 280,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => DesktopAdminModulePage(session: _session),
                      ),
                    );
                  },
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Text('Abrir módulo admin desktop'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

Future<void> _showErrorDialog(
  BuildContext context,
  String title,
  String message,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SelectableText(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<Map<String, dynamic>> _callCallableHttp(
  String name,
  Map<String, dynamic> payload,
) async {
  final user = FirebaseAuth.instance.currentUser;
  final token = await user?.getIdToken(true);
  if (token == null || token.isEmpty) {
    throw Exception('Token invalido de sesion');
  }

  final projectId = Firebase.app().options.projectId;
  final url = Uri.parse('https://$_region-$projectId.cloudfunctions.net/$name');
  final response = await http.post(
    url,
    headers: <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode(<String, dynamic>{'data': payload}),
  );

  if (response.statusCode != 200) {
    throw Exception('CF HTTP ${response.statusCode}: ${response.body}');
  }

  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  final inner = (decoded['result'] ?? decoded['data'] ?? decoded) as Map;
  return inner.cast<String, dynamic>();
}

class DesktopAdminModulePage extends StatelessWidget {
  const DesktopAdminModulePage({super.key, required this.session});

  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final resumen =
        (session['resumen'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración Desktop'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estado de administración',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text('Pagos pendientes: ${resumen['pagosPendientes'] ?? 0}'),
                    Text('Pagados (muestra): ${resumen['pagosPagadosMuestra'] ?? 0}'),
                    const SizedBox(height: 10),
                    const Text(
                      'Panel en modo estable para Windows: solo Auth + HTTP Cloud Functions.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}
