import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_actions.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/utilidades/constante.dart';
import 'package:flygo_nuevo/widgets/cliente_viaje_orientacion_banner.dart';

/// Pantalla cliente: conductores que publicaron «Voy para» (tipo [oferta]).
class BolaConductoresEnRutaClientePage extends StatelessWidget {
  const BolaConductoresEnRutaClientePage({super.key});

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
                          onPressed: () =>
                              Navigator.of(context, rootNavigator: true)
                                  .pushNamed(rutaBolaPueblo),
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
