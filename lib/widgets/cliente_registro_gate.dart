import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/cliente/completar_perfil_cliente.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/cliente_perfil_onboarding.dart';

/// Tras teléfono/Google: obliga perfil mínimo (nombre + teléfono) antes del shell.
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
        // Sin doc / cargando: no flash de “completar perfil” (p. ej. tras cancelar).
        if (userSnap.connectionState == ConnectionState.waiting &&
            !userSnap.hasData) {
          return child;
        }
        if (!userSnap.hasData || userSnap.data?.exists != true) {
          return child;
        }

        final data = userSnap.data!.data() ?? <String, dynamic>{};
        final incompleto = ClientePerfilOnboarding.debeCompletarPerfil(data);
        final vid = (data['viajeActivoId'] ?? '').toString().trim();
        final tieneViaje = vid.isNotEmpty ||
            ActiveTripService.debeMantenerOverlayViajeEnShell;

        // Viaje activo: no bloquear (perfil después).
        if (!incompleto || tieneViaje) {
          return child;
        }

        // QA debug: permitir shell sin perfil si hace falta probar.
        if (kDebugMode && !kReleaseMode) {
          return _ClientePerfilOpcionalOverlay(child: child);
        }

        return const CompletarPerfilCliente();
      },
    );
  }
}

/// Solo debug: aviso suave sin bloquear.
class _ClientePerfilOpcionalOverlay extends StatelessWidget {
  const _ClientePerfilOpcionalOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Material(
            color: Colors.orange.shade900.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              dense: true,
              title: const Text(
                'Perfil incompleto (debug)',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              trailing: TextButton(
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const CompletarPerfilCliente(),
                    ),
                  );
                },
                child: const Text('Completar'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
