// Enruta al shell del cliente: espera turismo (sin chofer) vs viaje en curso.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/cliente/espera_asignacion_turismo.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

/// Decide qué pantalla mostrar cuando [ClienteShell] detecta `viajeActivoId`.
class ClientePantallaViajeActivo extends StatelessWidget {
  const ClientePantallaViajeActivo({super.key, this.viajeEnCursoKey});

  final Key? viajeEnCursoKey;

  static bool debeMostrarEsperaTurismo(Map<String, dynamic> data) {
    return AsignacionTurismoRepo.viajeTurismoEsperandoChofer(data);
  }

  @override
  Widget build(BuildContext context) {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return ViajeEnCursoCliente(
        key: viajeEnCursoKey,
        delegarEsperaTurismoAlRouter: true,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .snapshots(),
      builder: (
        BuildContext context,
        AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> userSnap,
      ) {
        final String viajeId =
            (userSnap.data?.data()?['viajeActivoId'] ?? '').toString().trim();
        if (viajeId.isEmpty) {
          return ViajeEnCursoCliente(
            key: viajeEnCursoKey,
            delegarEsperaTurismoAlRouter: true,
          );
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('viajes')
              .doc(viajeId)
              .snapshots(),
          builder: (
            BuildContext context,
            AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> viajeSnap,
          ) {
            if (!viajeSnap.hasData || !viajeSnap.data!.exists) {
              return ViajeEnCursoCliente(
                key: viajeEnCursoKey,
                delegarEsperaTurismoAlRouter: true,
              );
            }
            final Map<String, dynamic> data = viajeSnap.data!.data()!;
            if (ViajePoolTaxistaGate.esReservaProgramadaLejana(data)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ActiveTripService.liberarReservaProgramadaLejanaEnHome(
                  viajeId: viajeId,
                );
                ActiveTripService.notificarRebuildShell();
              });
              return const SizedBox.shrink();
            }
            final bool esperaTurismo = debeMostrarEsperaTurismo(data);
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: esperaTurismo
                  ? EsperaAsignacionTurismo(
                      key: ValueKey<String>('espera_turismo_$viajeId'),
                      viajeId: viajeId,
                      delegarTransicionEnCursoAlRouter: true,
                    )
                  : ViajeEnCursoCliente(
                      key: viajeEnCursoKey ??
                          ValueKey<String>('viaje_curso_$viajeId'),
                      delegarEsperaTurismoAlRouter: true,
                    ),
            );
          },
        );
      },
    );
  }
}
