import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_actions.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/servicios/cliente_viaje_activo_gate.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/utilidades/constante.dart';
import 'package:flygo_nuevo/widgets/cliente_viaje_orientacion_banner.dart';

/// Pantalla cliente: conductores que publicaron «Voy para» (tipo [oferta]).
class BolaConductoresEnRutaClientePage extends StatefulWidget {
  const BolaConductoresEnRutaClientePage({super.key});

  @override
  State<BolaConductoresEnRutaClientePage> createState() =>
      _BolaConductoresEnRutaClientePageState();
}

class _BolaConductoresEnRutaClientePageState
    extends State<BolaConductoresEnRutaClientePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirigirSiViajeActivo());
  }

  Future<void> _redirigirSiViajeActivo() async {
    if (!mounted) return;
    if (!ClienteViajeActivoGate.debeBloquearFlujosNuevoViaje) return;

    final bool retomar = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            icon: const Icon(Icons.local_taxi_rounded, color: Color(0xFF1B5E20)),
            title: const Text('Tenés un viaje en curso'),
            content: const Text(
              'Esta pantalla es para buscar un conductor nuevo. '
              'Retomá tu viaje activo para seguir el recorrido.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Volver'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Retomar viaje'),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    if (retomar) {
      NavigationService.retomarViajeActivoCliente();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final col = BolaPuebloColors.of(context);

    return Scaffold(
      backgroundColor: col.bgDeep,
      appBar: AppBar(
        backgroundColor: col.appBarScrim,
        elevation: 0,
        foregroundColor: col.onSurface,
        title: Text(
          'Conductores en ruta',
          style: BolaPuebloUi.screenTitleBola(context),
        ),
      ),
      body: user == null
          ? Center(
              child: Text(
                'Iniciá sesión',
                style: TextStyle(color: col.onMuted),
              ),
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, usrSnap) {
                final nombre =
                    (usrSnap.data?.data()?['nombre'] ?? 'Usuario').toString();
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: BolaPuebloRepo.streamTablero(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: BolaPuebloTheme.accent),
                      );
                    }
                    final err = snap.error;
                    if (err != null) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No se pudo cargar el tablero: $err',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: col.onMuted),
                          ),
                        ),
                      );
                    }

                    final docsAll = snap.data?.docs ?? const [];
                    final filtrados = docsAll.where((d) {
                      final m = d.data();
                      final estado = (m['estado'] ?? '').toString();
                      final tipo = (m['tipo'] ?? '').toString();
                      if (tipo != 'oferta' || estado != 'abierta') {
                        return false;
                      }
                      return BolaPuebloRepo.visibleEnTableroParaUsuario(
                        m,
                        user.uid,
                        bolaId: d.id,
                        rol: 'cliente',
                      );
                    }).toList();

                    return ListView(
                      padding: BolaPuebloUi.listScrollPadding(context, top: 8),
                      children: [
                        const ClienteViajeOrientacionBanner(
                          mensaje: ClienteViajeOrientacionCopy.bolaAhora,
                          icon: Icons.groups_rounded,
                          accentColor: BolaPuebloTheme.accent,
                        ),
                        const SizedBox(height: 12),
                        BolaPuebloUi.quickSteps(
                          context,
                          steps: const [
                            (icon: Icons.touch_app_rounded, label: 'Elegir'),
                            (icon: Icons.handshake_rounded, label: 'Acordar'),
                            (icon: Icons.directions_car_rounded, label: 'Viajar'),
                          ],
                        ),
                        const SizedBox(height: 14),
                        BolaPuebloUi.bigAction(
                          context: context,
                          label: 'Mapa y tablero completo',
                          icon: Icons.map_rounded,
                          onPressed: () async {
                            if (!await ClienteViajeActivoGate
                                .intentarFlujoNuevoViaje(context)) {
                              return;
                            }
                            if (!context.mounted) return;
                            Navigator.of(context, rootNavigator: true)
                                .pushNamed(rutaBolaPueblo);
                          },
                          background: BolaPuebloTheme.accentSecondary,
                        ),
                        const SizedBox(height: 18),
                        BolaPuebloUi.sectionTitle(
                            context, 'Disponibles ahora'),
                        const SizedBox(height: 14),
                        if (filtrados.isEmpty)
                          BolaPuebloUi.emptyBoard(
                            context,
                            icon: Icons.local_taxi_outlined,
                            message:
                                'No hay conductores ahora. Probá «Pedir bola» en el mapa.',
                          )
                        else
                          ...filtrados.map((d) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: BolaPuebloPublicacionCard(
                                docId: d.id,
                                data: d.data(),
                                user: user,
                                nombre: nombre,
                                rol: 'cliente',
                                onAbrirModoViaje: (bolaId) {
                                  unawaited(
                                    BolaPuebloDialogs.abrirModoViajeBolaPorId(
                                      context: context,
                                      bolaId: bolaId,
                                    ),
                                  );
                                },
                              ),
                            );
                          }),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}
