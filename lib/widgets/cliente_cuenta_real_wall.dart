import 'package:flutter/material.dart';

import 'package:flygo_nuevo/auth/login_cliente.dart';
import 'package:flygo_nuevo/servicios/cliente_cuenta_real_policy.dart';
import 'package:flygo_nuevo/servicios/logout.dart';

/// Bloquea shell cliente para sesiones anónimas (RAI: registro obligatorio).
class ClienteCuentaRealWall extends StatelessWidget {
  const ClienteCuentaRealWall({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Image.asset(
                'assets/icon/logo_rai_vertical.png',
                height: 120,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 28),
              const Text(
                'Registrate para continuar',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                ClienteCuentaRealPolicy.mensajeRegistroRequerido,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  height: 1.45,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () async {
                  await cerrarSesion(context);
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginCliente(),
                    ),
                    (r) => false,
                  );
                },
                icon: const Icon(Icons.phone_android),
                label: const Text('Continuar con teléfono o Google'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
