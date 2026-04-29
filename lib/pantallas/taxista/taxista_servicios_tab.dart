import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/taxista/login_chofer_turismo.dart';
import 'package:flygo_nuevo/pantallas/taxista/pool_turismo_taxista.dart';
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_crear.dart';
import 'package:flygo_nuevo/pantallas/taxista/pools_taxista_lista.dart';
import 'package:flygo_nuevo/pantallas/taxista/viajes_turismo_asignados.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/utilidades/constante.dart';

/// Turismo, cupos y Bola (misma oferta que el antiguo menú lateral).
class TaxistaServiciosTab extends StatelessWidget {
  const TaxistaServiciosTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servicios'),
        centerTitle: true,
      ),
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
              subtitle: const Text('Regístrate y espera aprobación'),
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
                          'Turismo liberado por administración',
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
              'Viajes por cupos',
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
                'Mis viajes por cupos',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Ver ocupación, pagos y reservas'),
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
                'Crear viaje por cupos',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Consular o Tour, ida o ida/vuelta'),
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
                title: const Text(
                  'Bola ahorro',
                  style: TextStyle(fontWeight: FontWeight.w600),
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
                    title: const Text(
                      'Bola ahorro',
                      style: TextStyle(fontWeight: FontWeight.w600),
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
