import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Destinos existentes en tu app
import 'package:flygo_nuevo/pantallas/cliente/cliente_home.dart';
import 'package:flygo_nuevo/pantallas/taxista/entry_taxista.dart';

// Flujo selección / login
import 'package:flygo_nuevo/auth/seleccion_usuario.dart';
import 'package:flygo_nuevo/auth/login_cliente.dart';

/// ================== FLAGS QA (modo flexible) ==================
const bool kQaFlexibleAccess =
    bool.fromEnvironment('QA_FLEX', defaultValue: !kReleaseMode);
const bool kQaAllowAnonOnCollision =
    bool.fromEnvironment('QA_ALLOW_ANON', defaultValue: !kReleaseMode);
const bool kQaAllowAnonOnAuthError =
    bool.fromEnvironment('QA_ALLOW_ANON_ERR', defaultValue: !kReleaseMode);

class AuthCheck extends StatefulWidget {
  const AuthCheck({super.key});
  @override
  State<AuthCheck> createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarYRedirigir());
  }

  void _go(Widget page) {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => page));
  }

  void _goAdminNamedOrFallback() {
    if (_navigated || !mounted) return;
    try {
      Navigator.of(context).pushReplacementNamed('/admin');
      _navigated = true;
    } catch (_) {
      _go(const ClienteHome());
    }
  }

  Future<void> _cargarYRedirigir() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        _go(const SeleccionUsuario());
        return;
      }

      final rol = await _resolveAndEnsureRol(user);
      if (!mounted) return;

      if (rol == 'admin') {
        _goAdminNamedOrFallback();
      } else if (rol == 'taxista') {
        _go(const TaxistaEntry());
      } else {
        _go(const ClienteHome()); // 👈 SIEMPRE HOME DEL CLIENTE
      }
    } catch (e) {
      if (kQaFlexibleAccess && kQaAllowAnonOnAuthError) {
        try {
          final cred = await _auth.signInAnonymously();
          final u = cred.user!;
          await _ensureUsuarioDoc(
            u.uid,
            preferRol: 'cliente',
            email: u.email,
            displayName: u.displayName,
            phone: u.phoneNumber,
          );
          if (!mounted) return;
          _go(const ClienteHome());
          return;
        } catch (_) {}
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al verificar usuario: $e')),
      );
      _go(const LoginCliente());
    }
  }

  Future<String> _resolveAndEnsureRol(User user) async {
    final uid = user.uid;

    final uRef = _db.collection('usuarios').doc(uid);
    final uSnap = await uRef.get();
    String rolActual = '';
    if (uSnap.exists) {
      rolActual = (uSnap.data()?['rol'] ?? '').toString().trim().toLowerCase();
      if (rolActual.isNotEmpty) {
        await uRef.set(
          {
            'lastLogin': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return rolActual;
      }
    }

    String? rolRoles;
    final rRef = _db.collection('roles').doc(uid);
    final rSnap = await rRef.get();
    if (rSnap.exists) {
      rolRoles = (rSnap.data()?['rol'] as String?)?.toLowerCase().trim();
    }

    final rolFinal = (rolRoles?.isNotEmpty ?? false) ? rolRoles! : 'cliente';

    await _ensureUsuarioDoc(
      uid,
      preferRol: rolFinal,
      email: user.email,
      displayName: user.displayName,
      phone: user.phoneNumber,
    );

    return rolFinal;
  }

  Future<void> _ensureUsuarioDoc(
    String uid, {
    required String preferRol,
    String? email,
    String? displayName,
    String? phone,
  }) async {
    final ref = _db.collection('usuarios').doc(uid);
    final snap = await ref.get();
    final now = FieldValue.serverTimestamp();

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
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
    );
  }
}
