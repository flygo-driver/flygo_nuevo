import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/auth/seleccion_usuario.dart';

// 👇 IMPORTA LOS SHELLS DESDE LA CARPETA REAL
import 'package:flygo_nuevo/shell/cliente_shell.dart';
import 'package:flygo_nuevo/shell/taxista_shell.dart';

class RoleGate extends StatelessWidget {
  const RoleGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return _splash("Verificando sesión...");
        }
        if (!authSnap.hasData) return const SeleccionUsuario();

        final user = authSnap.data!;
        return StreamBuilder<String?>(
          stream: RolesService.streamRol(user.uid),
          builder: (context, rolSnap) {
            if (rolSnap.connectionState == ConnectionState.waiting) {
              return _splash("Cargando rol...");
            }

            final rol = (rolSnap.data ?? '').toLowerCase().trim();
            if (rol.isEmpty) {
              RolesService.ensureUserDoc(user.uid);
              return const SeleccionUsuario();
            }

            if (rol == 'cliente') return const ClienteShell();
            if (rol == 'taxista') return const TaxistaShell();
            return const SeleccionUsuario();
          },
        );
      },
    );
  }

  Widget _splash(String texto) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.greenAccent),
            const SizedBox(height: 16),
            Text(texto, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
