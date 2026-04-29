import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/comun/bola_pueblo_viaje_activo_page.dart';
import 'package:flygo_nuevo/pantallas/taxista/toggle_disponibilidad.dart';
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

/// En curso + disponibilidad (sin duplicar la barra inferior).
class TaxistaTrabajoHub extends StatelessWidget {
  const TaxistaTrabajoHub({super.key});

  static const Set<String> _estadosActivos = {
    'aceptado',
    'en_camino_pickup',
    'a_bordo',
    'en_curso',
  };

  static const bool _qaGraceOnAccountSwitch = bool.fromEnvironment(
    'QA_ACCOUNT_SWITCH_GRACE',
    defaultValue: true,
  );
  static const Duration _qaGraceWindow = Duration(minutes: 3);

  static DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  /// Espejo Bola → flujo en [bolas_pueblo]; el resto → pantalla estándar de viaje.
  static void openViajeActivoTaxista(
    BuildContext context, {
    Map<String, dynamic>? datosViaje,
  }) {
    if (datosViaje != null &&
        ViajePoolTaxistaGate.esViajeEspejoBolaParaFlujo(datosViaje)) {
      final bid = (datosViaje['bolaPuebloId'] ?? datosViaje['bolaId'] ?? '')
          .toString()
          .trim();
      if (bid.isNotEmpty) {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => BolaPuebloViajeActivoPage(bolaId: bid),
          ),
        );
        return;
      }
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const ViajeEnCursoTaxista(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi trabajo'),
        centerTitle: true,
      ),
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
                    final activo = vData?['activo'] == true;
                    final uidCliente =
                        (vData?['uidCliente'] ?? vData?['clienteId'] ?? '')
                            .toString()
                            .trim();
                    final visible = vData != null &&
                        uidTx == user.uid &&
                        activo &&
                        uidCliente.isNotEmpty &&
                        _estadosActivos.contains(estado);

                    if (!visible && viajeActivoId.isNotEmpty) {
                      final now = DateTime.now();
                      final lastLoginAt = _toDate(
                        uData['lastLogin'] ??
                            uData['updatedAt'] ??
                            uData['actualizadoEn'],
                      );
                      final inQaGrace = _qaGraceOnAccountSwitch &&
                          lastLoginAt != null &&
                          now.difference(lastLoginAt) <= _qaGraceWindow;
                      if (inQaGrace) {
                        return _HubCard(
                          icon: Icons.navigation_outlined,
                          title: 'Viaje en curso',
                          subtitle: 'Sincronizando estado del viaje...',
                          onTap: () => openViajeActivoTaxista(
                            context,
                            datosViaje: vData,
                          ),
                        );
                      }
                      Future<void>(() async {
                        try {
                          await FirebaseFirestore.instance
                              .collection('usuarios')
                              .doc(user.uid)
                              .set({
                            'viajeActivoId': '',
                            'updatedAt': FieldValue.serverTimestamp(),
                            'actualizadoEn': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                        } catch (_) {}
                      });
                    }

                    return _HubCard(
                      icon: Icons.navigation_outlined,
                      title: 'Viaje en curso',
                      subtitle: visible
                          ? 'Tienes un viaje activo'
                          : 'No tienes viaje en curso',
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
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
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
      ),
    );
  }
}
