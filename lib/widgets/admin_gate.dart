// lib/widgets/admin_gate.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// Importa el panel admin desde donde realmente está en tu proyecto.
import '../pantallas/admin/admin_centro_operaciones.dart';
import '../servicios/launch_config_bootstrap.dart';
import '../servicios/roles_service.dart';

class AdminGate extends StatelessWidget {
  const AdminGate({super.key, this.child});

  /// Si se indica, los admins ven [child] en lugar del centro de operaciones.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const _NoAuth();

    final refUsuario =
        FirebaseFirestore.instance.collection('usuarios').doc(uid);
    final refRol = FirebaseFirestore.instance.collection('roles').doc(uid);

    // 1er stream: usuarios/{uid}
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: refUsuario.snapshots(),
      builder: (context, snapUser) {
        if (snapUser.connectionState == ConnectionState.waiting) {
          return const _Cargando();
        }
        if (snapUser.hasError) {
          return _Error(msg: 'Error usuarios: ${snapUser.error}');
        }

        final rolUsuario = (snapUser.data?.data()?['rol'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

        if (RolesService.esRolAdmin(rolUsuario)) {
          return child ?? const _AdminCentroConBootstrap();
        }

        // 2do stream (fallback): roles/{uid}
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: refRol.snapshots(),
          builder: (context, snapRol) {
            if (snapRol.connectionState == ConnectionState.waiting) {
              return const _Cargando();
            }
            if (snapRol.hasError) {
              return _Error(msg: 'Error roles: ${snapRol.error}');
            }

            final rolDoc = (snapRol.data?.data()?['rol'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            if (RolesService.esRolAdmin(rolDoc)) {
              return child ?? const _AdminCentroConBootstrap();
            }

            // Ninguna fuente dijo admin
            return const _SinPermisos();
          },
        );
      },
    );
  }
}

class _AdminCentroConBootstrap extends StatefulWidget {
  const _AdminCentroConBootstrap();

  @override
  State<_AdminCentroConBootstrap> createState() =>
      _AdminCentroConBootstrapState();
}

class _AdminCentroConBootstrapState extends State<_AdminCentroConBootstrap> {
  @override
  void initState() {
    super.initState();
    unawaited(LaunchConfigBootstrap.ensureProduccionSoportable());
  }

  @override
  Widget build(BuildContext context) => const AdminCentroOperaciones();
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
