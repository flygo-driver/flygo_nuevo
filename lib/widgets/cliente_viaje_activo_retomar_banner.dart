import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';

/// Banner persistente cuando el cliente pausó un viaje activo y está en el home.
class ClienteViajeActivoRetomarBanner extends StatelessWidget {
  const ClienteViajeActivoRetomarBanner({
    super.key,
    required this.uid,
  });

  final String uid;

  static String _etiquetaEstado(String estadoRaw) {
    final String st = EstadosViaje.normalizar(estadoRaw);
    if (EstadosViaje.esPendiente(st) || st == 'pendiente_admin') {
      return 'Buscando conductor';
    }
    if (EstadosViaje.esAceptado(st)) return 'Conductor asignado';
    if (EstadosViaje.esEnCaminoPickup(st)) return 'Conductor en camino';
    if (EstadosViaje.esAbordo(st)) return 'Abordo — listo para salir';
    if (EstadosViaje.esEnCurso(st)) return 'Viaje en ruta';
    return 'Viaje en curso';
  }

  @override
  Widget build(BuildContext context) {
    if (!ActiveTripService.debeForzarInicioClienteShell) {
      return const SizedBox.shrink();
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
        if (viajeId.isEmpty) return const SizedBox.shrink();

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
              return const SizedBox.shrink();
            }
            final Map<String, dynamic> d = viajeSnap.data!.data() ?? {};
            final String st =
                EstadosViaje.normalizar((d['estado'] ?? '').toString());
            if (EstadosViaje.esTerminal(st) || d['completado'] == true) {
              return const SizedBox.shrink();
            }

            final String estadoLabel = _etiquetaEstado(st);
            final String destino =
                (d['destino'] ?? d['destinoLabel'] ?? '').toString().trim();

            return Material(
              elevation: 0,
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[
                      Color(0xFF1B5E20),
                      Color(0xFF2E7D32),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFF1B5E20).withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: NavigationService.retomarViajeActivoCliente,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.local_taxi_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Viaje en curso',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.1,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                destino.isNotEmpty
                                    ? '$estadoLabel · $destino'
                                    : estadoLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: 12.5,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: NavigationService.retomarViajeActivoCliente,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1B5E20),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Retomar',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
