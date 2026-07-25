import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:flygo_nuevo/design_system/rai_design_system.dart';
import 'package:flygo_nuevo/pantallas/taxista/corporativo_acceso_gate_page.dart';
import 'package:flygo_nuevo/pantallas/taxista/turismo_acceso_gate_page.dart';
import 'package:flygo_nuevo/pantallas/taxista/mis_rutas_corporativas_page.dart';
import 'package:flygo_nuevo/pantallas/taxista/pool_turismo_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_crear.dart';
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_lista.dart';
import 'package:flygo_nuevo/pantallas/taxista/viajes_turismo_asignados.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/servicios/solicitud_corporativo_repo.dart';
import 'package:flygo_nuevo/servicios/solicitud_turismo_repo.dart';
import 'package:flygo_nuevo/utilidades/constante.dart';
import 'package:flygo_nuevo/utils/pools_producto_copy.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';
import 'package:flygo_nuevo/widgets/rai_driver_ui.dart';

/// Servicios habilitados según perfil del conductor (sin lógica de negocio nueva).
class TaxistaServiciosTab extends StatelessWidget {
  const TaxistaServiciosTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return RaiDriverTabScaffold(
      title: 'Servicios',
      subtitle: 'Módulos activos para tu perfil',
      body: user == null
          ? const Center(child: Text('Inicia sesión'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, usrSnap) {
                final uData = usrSnap.data?.data();
                final poolModo =
                    ViajePoolTaxistaGate.poolModoConductorDesdeUsuario(uData);
                final esMotor =
                    poolModo == TaxistaPoolModoConductor.motor;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  children: [
                    if (!esMotor) ...[
                      AppSection(
                        title: 'Pool compartido',
                        accent: RaiDsColors.purple,
                        child: StreamBuilder<
                            DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('billeteras_taxista')
                              .doc(user.uid)
                              .snapshots(),
                          builder: (context, billSnap) {
                            final bloqueado = PagosTaxistaRepo
                                .bloqueoOperativoPorComisionEfectivo(
                              billSnap.data?.data(),
                            );
                            return AppServiceCard(
                              icon: PhosphorIconsFill.arrowsLeftRight,
                              title: etiquetaBolaAhorroUi,
                              subtitle: bloqueado
                                  ? 'Recarga pendiente (misma regla que el pool)'
                                  : 'Tablero intermunicipal compartido',
                              accent: RaiDsColors.purple,
                              status: bloqueado
                                  ? AppServiceStatus.bloqueado
                                  : AppServiceStatus.activo,
                              statusLabel:
                                  bloqueado ? 'Bloqueado' : 'Activo',
                              enabled: !bloqueado,
                              onTap: bloqueado
                                  ? null
                                  : () => Navigator.of(context,
                                          rootNavigator: true)
                                      .pushNamed(rutaBolaPueblo),
                            );
                          },
                        ),
                      ),
                      AppSection(
                        title: 'Salidas por cupos',
                        accent: RaiDsColors.teal,
                        child: Column(
                          children: [
                            AppServiceCard(
                              icon: PhosphorIconsFill.usersThree,
                              title: PoolsProductoCopy.salidasMis,
                              subtitle:
                                  'Tus giras publicadas · editar, cupos y reservas',
                              accent: RaiDsColors.teal,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const PoolsTaxistaLista(),
                                  ),
                                );
                              },
                            ),
                            AppServiceCard(
                              icon: PhosphorIconsFill.plusCircle,
                              title: PoolsProductoCopy.publicarTitulo,
                              subtitle: PoolsProductoCopy.tipos,
                              accent: RaiDsColors.teal,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const PoolsTaxistaCrear(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                    _TurismoServiciosSection(uid: user.uid),
                    _CorporativoServiciosSection(uid: user.uid),
                    const SizedBox(height: 8),
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            PhosphorIconsRegular.info,
                            color: RaiDsColors.textMuted,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Algunos servicios requieren aprobación de administración. '
                              'Cuando te aprueben, aparecerán aquí automáticamente.',
                              style: RaiDsTypography.caption(context).copyWith(
                                color: RaiDsColors.textSecondary(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _TurismoServiciosSection extends StatelessWidget {
  const _TurismoServiciosSection({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EstadoRegistroTurismo>(
      stream: SolicitudTurismoRepo.streamEstadoRegistro(uid),
      builder: (context, estadoSnap) {
        final reg = estadoSnap.data;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('choferes_turismo')
              .doc(uid)
              .snapshots(),
          builder: (context, choferSnap) {
            final data = choferSnap.data?.data();
            final estado =
                (data?['estado'] ?? '').toString().trim().toLowerCase();
            final aprobado = estado == 'aprobado' || estado == 'activo';
            final pendiente = reg?.fase == 'pendiente_adm';

            final children = <Widget>[];

            if (aprobado) {
              children.addAll([
                AppServiceCard(
                  icon: PhosphorIconsFill.airplaneTilt,
                  title: 'Pool turístico',
                  subtitle: 'Viajes liberados por ADM · activa disponibilidad',
                  accent: RaiDsColors.orange,
                  status: AppServiceStatus.activo,
                  statusLabel: 'Activo',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PoolTurismoTaxista(),
                      ),
                    );
                  },
                ),
                AppServiceCard(
                  icon: PhosphorIconsFill.mapPin,
                  title: 'Mis viajes turismo',
                  subtitle: 'Viajes que te han asignado',
                  accent: RaiDsColors.orange,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ViajesTurismoAsignadosTaxista(),
                      ),
                    );
                  },
                ),
              ]);
            } else if (pendiente) {
              children.add(
                AppServiceCard(
                  icon: PhosphorIconsFill.hourglass,
                  title: 'Turismo — en revisión',
                  subtitle: 'Administración revisará tu vehículo y documentos.',
                  accent: RaiDsColors.orange,
                  status: AppServiceStatus.pendiente,
                  statusLabel: 'Pendiente',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TurismoAccesoGatePage(),
                      ),
                    );
                  },
                ),
              );
            } else {
              children.add(
                AppServiceCard(
                  icon: PhosphorIconsFill.suitcase,
                  title: 'Turismo',
                  subtitle: 'Solicitá acceso para operar viajes turísticos',
                  accent: RaiDsColors.orange,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TurismoAccesoGatePage(),
                      ),
                    );
                  },
                ),
              );
            }

            if (children.isEmpty) return const SizedBox.shrink();

            return AppSection(
              title: 'Turismo',
              accent: RaiDsColors.orange,
              child: Column(children: children),
            );
          },
        );
      },
    );
  }
}

class _CorporativoServiciosSection extends StatelessWidget {
  const _CorporativoServiciosSection({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EstadoRegistroCorporativo>(
      stream: SolicitudCorporativoRepo.streamEstadoRegistro(uid),
      builder: (context, estadoSnap) {
        final reg = estadoSnap.data;
        final children = <Widget>[];

        if (reg?.fase == 'aprobado') {
          children.add(
            AppServiceCard(
              icon: PhosphorIconsFill.sealCheck,
              title: 'Pool corporativo activo',
              subtitle:
                  'Estás habilitado. RAI y la empresa te asignan rutas fijas; '
                  'abrí «Agenda corporativa» abajo o la pestaña Trabajo.',
              accent: RaiDsColors.blue,
              status: AppServiceStatus.activo,
              statusLabel: 'Activo',
              enabled: false,
              soloEstado: true,
            ),
          );
          children.add(
            StreamBuilder<Map<String, dynamic>?>(
              stream: CorporativoTaxistaService.streamOperacionChofer(uid),
              builder: (context, opSnap) {
                final rutasOp =
                    CorporativoTaxistaService.rutasDesdeOperacion(opSnap.data);
                return StreamBuilder<
                    List<DocumentSnapshot<Map<String, dynamic>>>>(
                  stream:
                      CorporativoTaxistaService.streamViajesAsignados(uid),
                  builder: (context, rutasSnap) {
                    final nDocs = rutasSnap.data?.length ?? 0;
                    final n = nDocs > 0 ? nDocs : rutasOp.length;
                    String? viajeListoId;
                    for (final r in rutasOp) {
                      if (r['listoParaAbrir'] != true) continue;
                      final id = (r['viajeHoyId'] ?? '').toString().trim();
                      if (id.isNotEmpty) {
                        viajeListoId = id;
                        break;
                      }
                    }
                    final listo = viajeListoId != null;
                    return AppServiceCard(
                      icon: PhosphorIconsFill.path,
                      title: 'Agenda corporativa',
                      subtitle: listo
                          ? 'Ruta lista · tocá aquí o en Trabajo → Mis rutas'
                          : (n > 0
                              ? 'Rutas fijas · horarios y Abrir ruta'
                              : 'Sin rutas asignadas aún'),
                      accent: RaiDsColors.blue,
                      status: n > 0 ? AppServiceStatus.activo : null,
                      statusLabel: n > 0 ? '$n' : null,
                      onTap: () {
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
          );
        } else if (reg?.fase == 'pendiente_adm') {
          children.add(
            AppServiceCard(
              icon: PhosphorIconsFill.hourglass,
              title: 'Corporativo — en revisión',
              subtitle: 'RAI revisará tu perfil de taxista.',
              accent: RaiDsColors.blue,
              status: AppServiceStatus.pendiente,
              statusLabel: 'Pendiente',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CorporativoAccesoGatePage(),
                  ),
                );
              },
            ),
          );
        } else {
          children.add(
            AppServiceCard(
              icon: PhosphorIconsFill.buildings,
              title: 'Corporativo',
              subtitle: 'Rutas fijas de empresas · solicitud y aprobación ADM',
              accent: RaiDsColors.blue,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CorporativoAccesoGatePage(),
                  ),
                );
              },
            ),
          );
        }

        return AppSection(
          title: 'Corporativo',
          accent: RaiDsColors.blue,
          child: Column(children: children),
        );
      },
    );
  }
}
