import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/navegacion/taxista_operacion_nav.dart';
import 'package:flygo_nuevo/pantallas/taxista/mis_rutas_corporativas_page.dart';
import 'package:flygo_nuevo/pantallas/taxista/toggle_disponibilidad.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';
import 'package:flygo_nuevo/widgets/rai_driver_ui.dart';

/// En curso + disponibilidad (sin duplicar la barra inferior).
class TaxistaTrabajoHub extends StatelessWidget {
  const TaxistaTrabajoHub({super.key});

  static const Set<String> _estadosActivos = {
    'aceptado',
    'en_camino_pickup',
    'a_bordo',
    'en_curso',
    'en_origen_esperando_codigo',
    'pendiente_codigo',
    'esperando_codigo_encargado',
  };

  /// Negociación Bola → tablero; taxi/pool → Viaje en curso. Corporativo → Mis rutas.
  static Future<void> openViajeActivoTaxista(
    BuildContext context, {
    Map<String, dynamic>? datosViaje,
  }) async {
    if (datosViaje != null &&
        ViajePoolTaxistaGate.debeUsarFlujoBolaPuebloEnLugarDeViajeEnCurso(
            datosViaje)) {
      unawaited(NavigationService.clearAndGoBolaTablero());
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await ViajesRepo.limpiarViajeActivoSiNoOperativo(uid);

    String viajeId = '';
    Map<String, dynamic>? viajeData = datosViaje;
    try {
      final uSnap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      viajeId = (uSnap.data()?['viajeActivoId'] ?? '').toString().trim();
      if (viajeId.isNotEmpty && viajeData == null) {
        final vSnap = await FirebaseFirestore.instance
            .collection('viajes')
            .doc(viajeId)
            .get();
        viajeData = vSnap.data();
      }
    } catch (_) {}

    if (!context.mounted) return;

    if (viajeData != null &&
        CorporativoTaxistaService.esViajeCorporativoAsignado(viajeData, uid)) {
      ActiveTripService.cancelarMantenimientoOverlayViaje();
      ActiveTripService.cancelarBloqueoShellTaxista();
      ActiveTripService.notificarRebuildShell();
      if (TaxistaOperacionNav.viajeOperativoBloqueanteCorp(viajeData, uid)) {
        await Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const MisRutasCorporativasPage(),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No tienes un viaje en curso. Las rutas corporativas están en '
              '«Rutas corporativas».',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    if (viajeId.isEmpty ||
        viajeData == null ||
        !ViajesRepo.viajeVisibleEnCursoTaxista(viajeData, uid)) {
      ActiveTripService.cancelarMantenimientoOverlayViaje();
      ActiveTripService.cancelarBloqueoShellTaxista();
      ActiveTripService.notificarRebuildShell();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No tienes un viaje en curso. Las rutas corporativas están en '
            '«Rutas corporativas».',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    await NavigationService.clearAndGoViajeEnCursoTaxista();
  }

  static Future<void> _abrirRutaCorporativaLista(BuildContext context) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const MisRutasCorporativasPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return RaiDriverTabScaffold(
      title: 'Mi trabajo',
      subtitle: 'Viaje activo, rutas y disponibilidad',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (user != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, uSnap) {
                final uData = uSnap.data?.data() ?? const <String, dynamic>{};
                final viajeActivoId =
                    (uData['viajeActivoId'] ?? '').toString().trim();

                if (viajeActivoId.isEmpty) {
                  return RaiDriverHubCard(
                    icon: Icons.navigation_rounded,
                    title: 'Viaje en curso',
                    subtitle: 'No tienes un viaje activo',
                    accent: RaiDriverColors.neon,
                    onTap: () => openViajeActivoTaxista(context),
                  );
                }

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('viajes')
                      .doc(viajeActivoId)
                      .snapshots(),
                  builder: (context, vSnap) {
                    final vData = vSnap.data?.data();
                    final uidTx =
                        (vData?['uidTaxista'] ?? vData?['taxistaId'] ?? '')
                            .toString();
                    final estado = EstadosViaje.normalizar(
                        (vData?['estado'] ?? '').toString());
                    final uidCliente =
                        (vData?['uidCliente'] ?? vData?['clienteId'] ?? '')
                            .toString()
                            .trim();
                    final esCorp = vData != null &&
                        CorporativoTaxistaService.esViajeCorporativoAsignado(
                          vData,
                          user.uid,
                        );

                    // Corporativo no usa «Viaje en curso» del pool.
                    if (esCorp) {
                      final bool corpActiva =
                          TaxistaOperacionNav.viajeOperativoBloqueanteCorp(
                        vData,
                        user.uid,
                      );
                      return RaiDriverHubCard(
                        icon: Icons.business_rounded,
                        title: corpActiva
                            ? 'Ruta corporativa activa'
                            : 'Viaje en curso',
                        subtitle: corpActiva
                            ? 'Continuá en «Rutas corporativas»'
                            : 'No tienes un viaje activo',
                        accent: RaiDriverColors.neon,
                        onTap: () => openViajeActivoTaxista(
                          context,
                          datosViaje: vData,
                        ),
                      );
                    }
                    if (vData == null) {
                      return RaiDriverHubCard(
                        icon: Icons.navigation_rounded,
                        title: 'Viaje en curso',
                        subtitle: 'No tienes un viaje activo',
                        accent: RaiDriverColors.neon,
                        onTap: () => openViajeActivoTaxista(context),
                      );
                    }

                    final visible = uidTx == user.uid &&
                        uidCliente.isNotEmpty &&
                        _estadosActivos.contains(estado);

                    return RaiDriverHubCard(
                      icon: Icons.navigation_rounded,
                      title: 'Viaje en curso',
                      subtitle: visible
                          ? 'Tienes un viaje activo'
                          : 'Viaje vinculado · abrí para continuar',
                      accent: RaiDriverColors.neon,
                      badge: visible
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: RaiDriverColors.neon
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Activo',
                                style: TextStyle(
                                  color: RaiDriverColors.neon,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : null,
                      onTap: () => openViajeActivoTaxista(
                        context,
                        datosViaje: vData,
                      ),
                    );
                  },
                );
              },
            )
          else
            RaiDriverHubCard(
              icon: Icons.navigation_rounded,
              title: 'Viaje en curso',
              subtitle: 'Inicia sesión',
              accent: RaiDriverColors.neon,
              onTap: () {},
            ),
          if (user != null)
            StreamBuilder<Map<String, dynamic>?>(
              stream:
                  CorporativoTaxistaService.streamOperacionChofer(user.uid),
              builder: (context, opSnap) {
                final rutasOp =
                    CorporativoTaxistaService.rutasDesdeOperacion(opSnap.data);
                return StreamBuilder<
                    List<DocumentSnapshot<Map<String, dynamic>>>>(
                  stream:
                      CorporativoTaxistaService.streamViajesAsignados(user.uid),
                  builder: (context, snap) {
                    final nDocs = snap.data?.length ?? 0;
                    final n = nDocs > 0 ? nDocs : rutasOp.length;
                    if (n <= 0) return const SizedBox.shrink();
                    final listoOp = rutasOp.any(
                      (r) =>
                          r['listoParaAbrir'] == true &&
                          (r['viajeHoyId'] ?? '').toString().trim().isNotEmpty,
                    );
                    final empresasListas = rutasOp
                        .where(
                          (r) =>
                              r['listoParaAbrir'] == true &&
                              (r['viajeHoyId'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty,
                        )
                        .map(
                          (r) => (r['empresaNombre'] ?? 'Empresa')
                              .toString()
                              .trim(),
                        )
                        .where((e) => e.isNotEmpty)
                        .toSet()
                        .join(' · ');
                    return RaiDriverHubCard(
                      icon: Icons.alt_route_rounded,
                      title: 'Rutas corporativas',
                      subtitle: listoOp && empresasListas.isNotEmpty
                          ? 'Lista: $empresasListas'
                          : listoOp
                              ? 'Lista · tocá para abrir el viaje del día'
                              : (n == 1
                                  ? '1 ruta · agenda y horarios'
                                  : '$n rutas · agenda y horarios'),
                      accent: RaiDriverColors.blue,
                      badge: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: RaiDriverColors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$n',
                          style: const TextStyle(
                            color: RaiDriverColors.blue,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      onTap: () async {
                        await _abrirRutaCorporativaLista(context);
                      },
                      onLongPress: () {
                        Navigator.of(context, rootNavigator: true).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const MisRutasCorporativasPage(),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          RaiDriverHubCard(
            icon: Icons.toggle_on_rounded,
            title: 'Disponibilidad',
            subtitle: 'Recibir viajes: ON / OFF',
            accent: RaiDriverColors.teal,
            onTap: () {
              Navigator.of(context, rootNavigator: true).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const ToggleDisponibilidad(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
