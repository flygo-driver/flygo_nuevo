// lib/auth/auth_check.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Destinos según rol (SOLO importamos, no definimos nada aquí)
import 'package:flygo_nuevo/pantallas/cliente/cliente_home.dart';
import 'package:flygo_nuevo/pantallas/taxista/entry_taxista.dart';

// Flujo de selección / login
import 'package:flygo_nuevo/auth/seleccion_usuario.dart';
import 'package:flygo_nuevo/auth/login_cliente.dart';

// Gate de verificación de correo (está en widgets)
import 'package:flygo_nuevo/widgets/verify_email_gate.dart';

class AuthCheck extends StatefulWidget {
  const AuthCheck({super.key});

  @override
  State<AuthCheck> createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _navigated = false; // evita dobles navegaciones

  @override
  void initState() {
    super.initState();
    // Espera al primer frame para tener un context estable
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verificarUsuario();
    });
  }

  void _go(Widget page) {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  Future<void> _verificarUsuario() async {
    try {
      final user = _auth.currentUser;

      // 1) Sin sesión ➜ selección de tipo de usuario
      if (user == null) {
        _go(const SeleccionUsuario());
        return;
      }

      // 2) Cargamos rol desde Firestore
      final doc = await _db.collection('usuarios').doc(user.uid).get();
      if (!mounted) return;

      final data = doc.data();
      final rol = (data?['rol'] ?? '').toString().toLowerCase().trim();

      // 3) Rutas según rol (gatea por verificación de correo)
      if (rol == 'cliente') {
        _go(const VerifyEmailGate(childWhenVerified: ClienteHome()));
        return;
      }

      if (rol == 'taxista') {
        _go(const VerifyEmailGate(childWhenVerified: TaxistaEntry()));
        return;
      }

      // 4) Rol desconocido ➜ vuelve a selección
      _go(const SeleccionUsuario());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al verificar usuario: $e')),
      );
      // fallback seguro
      _go(const LoginCliente());
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
