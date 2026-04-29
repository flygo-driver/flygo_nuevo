// lib/auth/role_gate.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/auth/seleccion_usuario.dart';

// Shells
import 'package:flygo_nuevo/shell/cliente_shell.dart';
import 'package:flygo_nuevo/shell/taxista_shell.dart';

// Admin
import 'package:flygo_nuevo/widgets/admin_gate.dart';

class RoleGate extends StatefulWidget {
  const RoleGate({super.key});
  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  bool _fixingMissingRol = false; // evita side-effects repetidos

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return _loadingSplash('Verificando sesión…');
        }
        if (authSnap.hasError) {
          return _errorPage('Error de autenticación:\n${authSnap.error}');
        }
        final user = authSnap.data;
        if (user == null) return const SeleccionUsuario();

        return StreamBuilder<String?>(
          stream: RolesService.streamRol(user.uid),
          builder: (context, rolSnap) {
            if (rolSnap.connectionState == ConnectionState.waiting) {
              return _loadingSplash('Cargando rol…');
            }
            if (rolSnap.hasError) {
              return _errorPage('Error al leer rol:\n${rolSnap.error}');
            }

            final rol = (rolSnap.data ?? '').toLowerCase().trim();
            const valid = {'admin', 'cliente', 'taxista'};

            // Si no hay rol válido, sincroniza una sola vez y muestra selección
            if (rol.isEmpty || !valid.contains(rol)) {
              if (!_fixingMissingRol) {
                _fixingMissingRol = true;
                Future.microtask(() async {
                  try {
                    await RolesService.syncRolConColeccionRoles(user.uid);
                    await RolesService.ensureUserDoc(user.uid);
                  } catch (e) {
                    debugPrint('RoleGate sync/ensure error: $e');
                  } finally {
                    if (mounted) _fixingMissingRol = false;
                  }
                });
              }
              return const SeleccionUsuario();
            }

            // Rutas por rol
            switch (rol) {
              case 'admin':
                return const AdminGate();
              case 'cliente':
                return const ClienteShell();
              case 'taxista':
                return const TaxistaShell();
            }

            // Fallback
            return const SeleccionUsuario();
          },
        );
      },
    );
  }

  // ===== UI helpers =====

  Widget _loadingSplash(String texto) {
    return const _SplashScaffold(
      child: _SplashContent(
        icon: CircularProgressIndicator(color: Colors.greenAccent),
        text: 'Cargando…',
      ),
    );
  }

  Widget _errorPage(String texto) {
    return _SplashScaffold(
      child: _SplashContent(
        icon:
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 28),
        text: texto,
      ),
    );
  }
}

/// Scaffold común negro para splash / error
class _SplashScaffold extends StatelessWidget {
  final Widget child;
  const _SplashScaffold({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: child),
    );
  }
}

/// Contenido reutilizable (icono + texto)
class _SplashContent extends StatelessWidget {
  final Widget icon;
  final String text;
  const _SplashContent({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(height: 16),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }
}
