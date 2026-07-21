import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/taxista/mis_rutas_corporativas_page.dart';
import 'package:flygo_nuevo/pantallas/taxista/toggle_disponibilidad.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';
import 'package:flygo_nuevo/widgets/shell_tab_nav.dart';

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

    if (viajeId.isEmpty ||
        viajeData == null ||
        CorporativoTaxistaService.esViajeCorporativoAsignado(viajeData, uid) ||
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final listasListas = <Map<String, dynamic>>[];
    try {
      final op = await FirebaseFirestore.instance
          .collection('chofer_operacion')
          .doc(uid)
          .get();
      final rutas =
          CorporativoTaxistaService.rutasDesdeOperacion(op.data());
      for (final r in rutas) {
        if (r['completadoHoy'] == true) continue;
        if (r['listoParaAbrir'] != true) continue;
        final id = (r['viajeHoyId'] ?? '').toString().trim();
        if (id.isNotEmpty) listasListas.add(r);
      }
    } catch (_) {}
    if (!context.mounted) return;

    String? viajeListoId;
    if (listasListas.length == 1) {
      viajeListoId = (listasListas.first['viajeHoyId'] ?? '').toString().trim();
    } else if (listasListas.length > 1) {
      viajeListoId = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: const Color(0xFF111827),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Elegí la empresa / ruta',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tenés más de una ruta lista para trabajar',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  ...listasListas.map((r) {
                    final emp =
                        (r['empresaNombre'] ?? 'Empresa').toString().trim();
                    final pl =
                        (r['plantillaNombre'] ?? 'Ruta').toString().trim();
                    final hora = (r['hora'] ?? '').toString().trim();
                    final vid = (r['viajeHoyId'] ?? '').toString().trim();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, vid),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 12,
                          ),
                          alignment: Alignment.centerLeft,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              emp,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              hora.isNotEmpty ? '$pl · $hora' : pl,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      );
    }

    if (!context.mounted) return;

    if (viajeListoId != null && viajeListoId.isNotEmpty) {
      final bloquea = await CorporativoTaxistaService
          .taxistaTieneViajeNoCorporativoBloqueante(
        uid,
        exceptViajeId: viajeListoId,
      );
      if (!context.mounted) return;
      if (bloquea) {
        await CorporativoTaxistaService.encolarViajeCorporativoInformativo(
          uidTaxista: uid,
          viajeId: viajeListoId,
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Terminá tu viaje actual. La ruta corporativa quedó en cola.',
            ),
          ),
        );
        return;
      }
      await NavigationService.abrirViajeCorporativoTaxista(
        uidTaxista: uid,
        viajeId: viajeListoId,
        snackContext: context,
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MisRutasCorporativasPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return RaiShellTabScaffold(
      title: 'Mi trabajo',
      backTooltip: 'Recibir',
      onBack: ShellTabController.taxistaIrARecibir,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
                  return _HubCard(
                    icon: Icons.navigation_outlined,
                    title: 'Viaje en curso',
                    subtitle: 'No tienes un viaje activo',
                    onTap: () => openViajeActivoTaxista(context),
                  );
                }

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('viajes')
                      .doc(viajeActivoId)
                      .snapshots(),
                  builder: (context, vSnap) {
                    final csV = Theme.of(context).colorScheme;
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

                    // Corporativo no usa «Viaje en curso» — solo «Rutas corporativas».
                    if (esCorp || vData == null) {
                      return _HubCard(
                        icon: Icons.navigation_outlined,
                        title: 'Viaje en curso',
                        subtitle: 'No tienes un viaje activo',
                        onTap: () => openViajeActivoTaxista(context),
                      );
                    }

                    final visible = uidTx == user.uid &&
                        uidCliente.isNotEmpty &&
                        _estadosActivos.contains(estado);

                    return _HubCard(
                      icon: Icons.navigation_outlined,
                      title: 'Viaje en curso',
                      subtitle: visible
                          ? 'Tienes un viaje activo'
                          : 'Viaje vinculado · abrí para continuar',
                      trailing: visible
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: csV.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: csV.primary),
                              ),
                              child: Text(
                                'Activo',
                                style: TextStyle(
                                  color: csV.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
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
            _HubCard(
              icon: Icons.navigation_outlined,
              title: 'Viaje en curso',
              subtitle: 'Inicia sesión',
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
                    return _HubCard(
                      icon: Icons.alt_route,
                      title: 'Rutas corporativas',
                      subtitle: listoOp && empresasListas.isNotEmpty
                          ? 'Lista: $empresasListas'
                          : listoOp
                              ? 'Lista · tocá para abrir el viaje del día'
                              : (n == 1
                                  ? '1 ruta · agenda y horarios'
                                  : '$n rutas · agenda y horarios'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$n',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      onTap: () async {
                        await _abrirRutaCorporativaLista(context);
                      },
                      onLongPress: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MisRutasCorporativasPage(),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          _HubCard(
            icon: Icons.toggle_on_outlined,
            title: 'Disponibilidad',
            subtitle: 'Recibir viajes: ON / OFF',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
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

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Text(subtitle),
        trailing: trailing ?? Icon(Icons.chevron_right, color: cs.outline),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}
