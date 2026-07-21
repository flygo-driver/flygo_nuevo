import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/taxista/login_chofer_corporativo.dart';
import 'package:flygo_nuevo/pantallas/taxista/login_chofer_turismo.dart';
import 'package:flygo_nuevo/pantallas/taxista/mis_rutas_corporativas_page.dart';
import 'package:flygo_nuevo/pantallas/taxista/pool_turismo_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_crear.dart';
import 'package:flygo_nuevo/utils/pools_producto_copy.dart';
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_lista.dart';
import 'package:flygo_nuevo/pantallas/taxista/viajes_turismo_asignados.dart';
import 'package:flygo_nuevo/servicios/solicitud_corporativo_repo.dart';
import 'package:flygo_nuevo/servicios/solicitud_turismo_repo.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/utilidades/constante.dart';
import 'package:flygo_nuevo/widgets/shell_tab_nav.dart';

/// Turismo, cupos y Bola (misma oferta que el antiguo menú lateral).
class TaxistaServiciosTab extends StatelessWidget {
  const TaxistaServiciosTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    return RaiShellTabScaffold(
      title: 'Servicios',
      backTooltip: 'Recibir',
      onBack: ShellTabController.taxistaIrARecibir,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(
              'Turismo',
              style: TextStyle(
                color: cs.tertiary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(Icons.app_registration, color: cs.tertiary),
              title: const Text(
                'Ser chofer de turismo',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Registro, documentos y aprobación ADM'),
              trailing: Icon(Icons.chevron_right, color: cs.outline),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginChoferTurismo()),
                );
              },
            ),
          ),
          if (user != null)
            StreamBuilder<EstadoRegistroTurismo>(
              stream: SolicitudTurismoRepo.streamEstadoRegistro(user.uid),
              builder: (context, estadoSnap) {
                final EstadoRegistroTurismo? reg = estadoSnap.data;
                if (reg?.fase == 'pendiente_adm') {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    color: cs.tertiaryContainer.withValues(alpha: 0.35),
                    child: ListTile(
                      leading: Icon(Icons.hourglass_top, color: cs.tertiary),
                      title: const Text('Solicitud turismo en revisión'),
                      subtitle: const Text(
                        'Administración revisará tu vehículo y documentos.',
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          if (user != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('choferes_turismo')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data();
                final estado =
                    (data?['estado'] ?? '').toString().trim().toLowerCase();
                final esAprobado = estado == 'aprobado' || estado == 'activo';

                if (!esAprobado) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: Icon(Icons.lock_clock, color: cs.tertiary),
                      title: const Text('Pool turístico'),
                      subtitle: const Text(
                        'Disponible al aprobarte en turismo',
                      ),
                    ),
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Icon(Icons.pool, color: cs.tertiary),
                        title: const Text(
                          'Pool turístico',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Viajes liberados por ADM · activa disponibilidad',
                        ),
                        trailing: Icon(Icons.chevron_right, color: cs.outline),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PoolTurismoTaxista(),
                            ),
                          );
                        },
                      ),
                    ),
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Icon(Icons.tour, color: cs.tertiary),
                        title: const Text(
                          'Mis viajes turismo',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text('Viajes que te han asignado'),
                        trailing: Icon(Icons.chevron_right, color: cs.outline),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const ViajesTurismoAsignadosTaxista(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Text(
              'Corporativo',
              style: TextStyle(
                color: cs.secondary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(Icons.business_center_outlined, color: cs.secondary),
              title: const Text(
                'Ser chofer corporativo',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Rutas fijas de empresas · RAI te asigna manualmente',
              ),
              trailing: Icon(Icons.chevron_right, color: cs.outline),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginChoferCorporativo(),
                  ),
                );
              },
            ),
          ),
          if (user != null)
            StreamBuilder<EstadoRegistroCorporativo>(
              stream: SolicitudCorporativoRepo.streamEstadoRegistro(user.uid),
              builder: (context, estadoSnap) {
                final reg = estadoSnap.data;
                if (reg?.fase == 'pendiente_adm') {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    color: cs.secondaryContainer.withValues(alpha: 0.35),
                    child: ListTile(
                      leading: Icon(Icons.hourglass_top, color: cs.secondary),
                      title: const Text('Solicitud corporativo en revisión'),
                      subtitle: const Text(
                        'RAI revisará tu perfil de taxista.',
                      ),
                    ),
                  );
                }
                if (reg?.fase == 'aprobado') {
                  return Column(
                    children: [
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: cs.primaryContainer.withValues(alpha: 0.35),
                        child: const ListTile(
                          leading: Icon(Icons.verified_outlined),
                          title: Text('Pool corporativo activo'),
                          subtitle: Text(
                            'RAI te asignará rutas fijas de empresas.',
                          ),
                        ),
                      ),
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: StreamBuilder<Map<String, dynamic>?>(
                          stream:
                              CorporativoTaxistaService.streamOperacionChofer(
                            user.uid,
                          ),
                          builder: (context, opSnap) {
                            final rutasOp =
                                CorporativoTaxistaService.rutasDesdeOperacion(
                              opSnap.data,
                            );
                            return StreamBuilder<
                                List<DocumentSnapshot<Map<String, dynamic>>>>(
                              stream: CorporativoTaxistaService
                                  .streamViajesAsignados(user.uid),
                              builder: (context, rutasSnap) {
                                final nDocs = rutasSnap.data?.length ?? 0;
                                final n =
                                    nDocs > 0 ? nDocs : rutasOp.length;
                                String? viajeListoId;
                                for (final r in rutasOp) {
                                  if (r['listoParaAbrir'] != true) continue;
                                  final id =
                                      (r['viajeHoyId'] ?? '').toString().trim();
                                  if (id.isNotEmpty) {
                                    viajeListoId = id;
                                    break;
                                  }
                                }
                                final listo = viajeListoId != null;
                                return ListTile(
                                  leading: Badge(
                                    isLabelVisible: n > 0,
                                    label: Text('$n'),
                                    child: Icon(
                                      Icons.alt_route,
                                      color: cs.secondary,
                                    ),
                                  ),
                                  title: const Text(
                                    'Agenda corporativa',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    listo
                                        ? 'Ruta lista · abrila desde Mi trabajo'
                                        : (n > 0
                                            ? 'Rutas fijas · horarios y estado'
                                            : 'Sin rutas asignadas aún'),
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const MisRutasCorporativasPage(),
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Text(
              'Salidas por cupos',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(Icons.people_alt_outlined, color: cs.primary),
              title: const Text(
                PoolsProductoCopy.salidasMis,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Tus giras publicadas · editar, cupos y reservas',
              ),
              trailing: Icon(Icons.chevron_right, color: cs.outline),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PoolsTaxistaLista(),
                  ),
                );
              },
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(Icons.add_circle_outline, color: cs.primary),
              title: const Text(
                PoolsProductoCopy.publicarTitulo,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                PoolsProductoCopy.tipos,
              ),
              trailing: Icon(Icons.chevron_right, color: cs.outline),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PoolsTaxistaCrear(),
                  ),
                );
              },
            ),
          ),
          if (user == null)
            Card(
              child: ListTile(
                leading: Icon(Icons.swap_horiz_rounded, color: cs.outline),
                title: Text(
                  etiquetaBolaAhorroUi,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Inicia sesión'),
                enabled: false,
              ),
            )
          else
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('billeteras_taxista')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, billSnap) {
                final bloqueado =
                    PagosTaxistaRepo.bloqueoOperativoPorComisionEfectivo(
                  billSnap.data?.data(),
                );
                return Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.swap_horiz_rounded,
                      color: bloqueado ? cs.outline : cs.secondary,
                    ),
                    title: Text(
                      etiquetaBolaAhorroUi,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      bloqueado
                          ? 'Recarga pendiente (misma regla que el pool)'
                          : 'Tablero intermunicipal',
                    ),
                    trailing: Icon(Icons.chevron_right, color: cs.outline),
                    enabled: !bloqueado,
                    onTap: bloqueado
                        ? null
                        : () => Navigator.of(context, rootNavigator: true)
                            .pushNamed(rutaBolaPueblo),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
