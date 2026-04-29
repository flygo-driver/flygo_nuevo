// lib/auth/auth_check.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Destinos existentes en tu app
import 'package:flygo_nuevo/shell/cliente_shell.dart';
import 'package:flygo_nuevo/pantallas/taxista/entry_taxista.dart';
import 'package:flygo_nuevo/widgets/admin_gate.dart';
import 'package:flygo_nuevo/widgets/rai_linear_loading_body.dart';

// Flujo selección / login
import 'package:flygo_nuevo/auth/seleccion_usuario.dart';
import 'package:flygo_nuevo/servicios/google_auth.dart';
import 'package:flygo_nuevo/legal/legal_acceptance_service.dart';
import 'package:flygo_nuevo/legal/terms_policy_screen.dart';

/// ================== FLAGS QA (modo flexible) ==================
/// En release, por default quedan false.
const bool kQaFlexibleAccess =
    bool.fromEnvironment('QA_FLEX', defaultValue: !kReleaseMode);
const bool kQaAllowAnonOnCollision =
    bool.fromEnvironment('QA_ALLOW_ANON', defaultValue: !kReleaseMode);
const bool kQaAllowAnonOnAuthError =
    bool.fromEnvironment('QA_ALLOW_ANON_ERR', defaultValue: !kReleaseMode);

/// Si quieres ser AÚN más estricto en producción:
/// - true: si Firestore falla, NO deja pasar.
/// - false: permite fallback a 'cliente' cuando Firestore falla (NO recomendado para público).
const bool kProductionStrict =
    bool.fromEnvironment('PROD_STRICT', defaultValue: true);

class AuthCheck extends StatefulWidget {
  const AuthCheck({super.key});
  @override
  State<AuthCheck> createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _navigated = false;
  bool _busy = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _run();
    });
  }

  void _go(Widget page) {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => page),
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

      // 0) No user => selección
      if (user == null) {
        _go(const SeleccionUsuario());
        return;
      }

      // 0.5) Politicas obligatorias luego del login (flujo tipo Uber/inDriver)
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

      // 1) Resolver rol de forma segura
      final rol = await _resolveRolSafe(user);

      if (!mounted) return;

      // 2) Redirigir (_sanitizeRol ya unifica administrador → admin)
      if (rol == 'admin') {
        _go(const AdminGate());
      } else if (rol == 'taxista') {
        _go(const TaxistaEntry());
      } else if (rol == 'cliente') {
        _go(const ClienteShell());
      } else {
        // rol raro => volver a selección
        _go(const SeleccionUsuario());
      }
    } on FirebaseAuthException catch (e) {
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
    // ✅ const porque solo depende de constantes
    const bool allowQaFallback = kQaFlexibleAccess && kQaAllowAnonOnAuthError;

    if (allowQaFallback) {
      try {
        final cred = await _auth.signInAnonymously();
        final u = cred.user;
        if (u != null) {
          await _tryEnsureUsuarioDoc(
            u.uid,
            preferRol: 'cliente',
            email: u.email,
            displayName: u.displayName,
            phone: u.phoneNumber,
          );
        }
        if (!mounted) return;
        _go(const ClienteShell());
        return;
      } catch (_) {
        // si falla el fallback, seguimos al error UI
      }
    }

    if (!mounted) return;
    setState(() {
      _errorMsg = msg;
      _busy = false;
    });
  }

  /// ✅ Resolver rol sin “inventarlo” en producción si Firestore falla.
  Future<String> _resolveRolSafe(User user) async {
    final uid = user.uid;

    // 1) Intentar /usuarios/{uid}
    try {
      final uRef = _db.collection('usuarios').doc(uid);
      final uSnap = await uRef.get();

      if (uSnap.exists) {
        final rol =
            (uSnap.data()?['rol'] ?? '').toString().trim().toLowerCase();
        if (rol.isNotEmpty) {
          _tryTouchUsuario(uid);
          return _sanitizeRol(rol);
        }
      }
    } on FirebaseException catch (e) {
      // Firestore falló (permisos/red/etc.)
      if (kProductionStrict && kReleaseMode) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: e.code,
          message: 'Firestore (/usuarios) bloqueó o falló: ${e.code}',
        );
      }
      return 'cliente';
    }

    // 2) Intentar /roles/{uid}
    String rolFinal = 'cliente';
    try {
      final rRef = _db.collection('roles').doc(uid);
      final rSnap = await rRef.get();

      if (rSnap.exists) {
        final rolRolesRaw =
            (rSnap.data()?['rol'] as String?)?.toLowerCase().trim();
        if ((rolRolesRaw ?? '').isNotEmpty) {
          rolFinal = rolRolesRaw ?? 'cliente';
        }
      }
    } on FirebaseException catch (e) {
      if (kProductionStrict && kReleaseMode) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: e.code,
          message: 'Firestore (/roles) bloqueó o falló: ${e.code}',
        );
      }
      rolFinal = 'cliente';
    }

    final pendingRaw = GoogleAuthService.consumePendingGoogleEntradaRol();
    if (pendingRaw != null && rolFinal != 'admin') {
      final p = _sanitizeRol(pendingRaw);
      if (p == 'taxista' || p == 'cliente') {
        rolFinal = p;
      }
    }

    rolFinal = _sanitizeRol(rolFinal);

    // 3) Best-effort: asegurar /usuarios (si reglas lo permiten)
    await _tryEnsureUsuarioDoc(
      uid,
      preferRol: rolFinal,
      email: user.email,
      displayName: user.displayName,
      phone: user.phoneNumber,
    );

    return rolFinal;
  }

  String _sanitizeRol(String rol) {
    final r = rol.trim().toLowerCase();
    if (r == 'administrador') return 'admin';
    if (r == 'admin' || r == 'taxista' || r == 'cliente') return r;
    return 'cliente';
  }

  /// Best-effort: tocar timestamps sin bloquear
  void _tryTouchUsuario(String uid) {
    final now = FieldValue.serverTimestamp();
    _db.collection('usuarios').doc(uid).set(
      {'lastLogin': now, 'updatedAt': now, 'actualizadoEn': now},
      SetOptions(merge: true),
    ).catchError((_) {});
  }

  /// Best-effort: crear/asegurar doc sin romper login
  Future<void> _tryEnsureUsuarioDoc(
    String uid, {
    required String preferRol,
    String? email,
    String? displayName,
    String? phone,
  }) async {
    final ref = _db.collection('usuarios').doc(uid);
    final now = FieldValue.serverTimestamp();

    try {
      final snap = await ref.get();

      if (!snap.exists) {
        await ref.set({
          'uid': uid,
          'email': email ?? '',
          'nombre': displayName ?? '',
          'telefono': phone ?? '',
          'rol': preferRol,
          'fechaRegistro': now,
          'actualizadoEn': now,
        });
        return;
      }

      final data = snap.data() ?? <String, dynamic>{};
      final hadRol = (data['rol'] ?? '').toString().trim().isNotEmpty;

      if (!hadRol) {
        await ref.set(
          {'rol': preferRol, 'updatedAt': now, 'actualizadoEn': now},
          SetOptions(merge: true),
        );
      } else {
        await ref.set(
          {'lastLogin': now, 'updatedAt': now, 'actualizadoEn': now},
          SetOptions(merge: true),
        );
      }
    } catch (_) {
      // Ignorar: reglas pueden bloquear set/get
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cargando
    if (_busy && _errorMsg == null) {
      return const RaiLinearLoadingBody(backgroundColor: Colors.black);
    }

    // Error UI (profesional para producción)
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
                  onPressed: () {
                    _go(const SeleccionUsuario());
                  },
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

    // fallback
    return const RaiLinearLoadingBody(backgroundColor: Colors.black);
  }
}
