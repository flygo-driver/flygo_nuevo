import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/comun/configuracion_perfil.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';

/// Perfil cliente incompleto: sugiere completar sin bloquear viajes activos.
class ClienteRegistroGate extends StatelessWidget {
  const ClienteRegistroGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return child;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .snapshots(),
      builder: (context, userSnap) {
        if (userSnap.connectionState == ConnectionState.waiting &&
            !userSnap.hasData) {
          return child;
        }

        final data = userSnap.data?.data() ?? <String, dynamic>{};
        final incompleto = data['registroClienteCompleto'] != true;
        final vid = (data['viajeActivoId'] ?? '').toString().trim();
        final tieneViaje = vid.isNotEmpty ||
            ActiveTripService.debeMantenerOverlayViajeEnShell;

        if (!incompleto || tieneViaje) return child;

        return _ClienteCompletarPerfilPrompt(child: child);
      },
    );
  }
}

class _ClienteCompletarPerfilPrompt extends StatelessWidget {
  const _ClienteCompletarPerfilPrompt({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Image.asset(
                'assets/icon/logo_rai_vertical.png',
                width: 120,
                height: 120,
              ),
              const SizedBox(height: 24),
              const Text(
                'Completa tu perfil',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Nombre y teléfono ayudan al conductor a contactarte. '
                'Puedes pedir viajes después; no hay bloqueo por deuda.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ConfiguracionPerfil(),
                    ),
                  );
                },
                icon: const Icon(Icons.edit),
                label: const Text('Completar ahora'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => child),
                  );
                },
                child: const Text('Continuar sin completar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
