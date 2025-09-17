import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// Importa SOLO aquí el admin_home para evitar ciclos.
import '../pantallas/admin/admin_home.dart';

class AdminGate extends StatelessWidget {
  const AdminGate({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const _NoAuth();
    }

    final docRef =
        FirebaseFirestore.instance.collection('usuarios').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Cargando();
        }
        if (snap.hasError) {
          return _Error(msg: 'Error: ${snap.error}');
        }
        final data = snap.data?.data();
        final rol = (data?['rol'] ?? '').toString();

        if (rol == 'admin') {
          // ✅ Si es admin, entra directo al panel
          return const AdminHome();
        }
        return const _SinPermisos();
      },
    );
  }
}

class _NoAuth extends StatelessWidget {
  const _NoAuth();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'Inicia sesión para continuar',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();

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

class _Error extends StatelessWidget {
  final String msg;
  const _Error({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(msg, style: const TextStyle(color: Colors.redAccent)),
      ),
    );
  }
}

class _SinPermisos extends StatelessWidget {
  const _SinPermisos();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'No tienes permisos de administrador',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
