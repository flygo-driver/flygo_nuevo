import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_actions.dart';
import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_viaje_activo_page.dart';
import 'package:flygo_nuevo/servicios/bola_pueblo_repo.dart';
import 'package:flygo_nuevo/utilidades/constante.dart';

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
                    final safeBottom = MediaQuery.of(context).padding.bottom;
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
                      if (tipo != 'oferta' || estado != 'abierta') return false;
                      return true;
                    }).toList();

                    return ListView(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 28 + safeBottom),
                      children: [
                        BolaPuebloUi.actionPanel(
                          context,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              BolaPuebloUi.sectionLabel(
                                context,
                                'Cómo funciona hasta la comisión RAI',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '1) Elegís un conductor y su ruta (está en un punto y va hacia otro).\n'
                                '2) Negociás el monto en la tarjeta; al cerrar, vas al punto donde él espera (navegación).\n'
                                '3) Subís, él confirma abordo e inicia con tu código → viaje en curso.\n'
                                '4) Cuando ambos confirman llegada al destino, la bola queda finalizada y se registra el 10% RAI sobre el monto acordado (comisión del conductor, como en el tablero completo).',
                                style: BolaPuebloUi.panelBody(context),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: () =>
                              Navigator.of(context, rootNavigator: true)
                                  .pushNamed(rutaBolaPueblo),
                          icon: const Icon(Icons.map_rounded),
                          label: const Text('Abrir mapa y tablero completo'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: col.onSurface,
                            side: BorderSide(color: col.outlineSoft),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Conductores disponibles ahora',
                          style: TextStyle(
                            color: col.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Cada tarjeta muestra nombre, «estoy en» → «voy para» y referencia de precio.',
                          style: TextStyle(
                            color: col.onMuted,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (filtrados.isEmpty)
                          BolaPuebloUi.emptyBoard(
                            context,
                            icon: Icons.local_taxi_outlined,
                            message:
                                'Todavía no hay conductores con ruta publicada. '
                                'Volvé más tarde o pedí tu viaje con «Pedir bola» en el mapa.',
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
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) => BolaPuebloViajeActivoPage(
                                          bolaId: bolaId),
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
