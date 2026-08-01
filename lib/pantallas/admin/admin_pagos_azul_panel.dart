import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'admin_ui_theme.dart';

/// Admin: pagos AZUL fallidos o pendientes + viajes tarjeta sin verificar tras cierre.
class AdminPagosAzulPanel extends StatelessWidget {
  const AdminPagosAzulPanel({super.key});

  static final DateFormat _fmtFecha =
      DateFormat('dd/MM/yyyy HH:mm', 'es');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Material(
            color: Colors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Modelo RAI: Efectivo → comisión del prepago del taxista (no liquidación semanal). '
                'Transferencia/tarjeta verificada → neto al chofer en «Comisiones semanales». '
                'Aquí ves cobros AZUL fallidos o viajes tarjeta finalizados sin verificar.',
                style: TextStyle(
                  color: AdminUi.onCard(context),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  labelColor: Theme.of(context).colorScheme.primary,
                  tabs: const [
                    Tab(text: 'AZUL fallidos'),
                    Tab(text: 'Tarjeta sin verificar'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _PagosAzulFallidosList(fmtFecha: _fmtFecha),
                      _ViajesTarjetaPendientesList(fmtFecha: _fmtFecha),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PagosAzulFallidosList extends StatelessWidget {
  const _PagosAzulFallidosList({required this.fmtFecha});

  final DateFormat fmtFecha;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pagos_azul')
          .where('estado', isEqualTo: 'failed')
          .limit(80)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return Center(
            child: Text(
              'Sin pagos AZUL fallidos recientes',
              style: TextStyle(color: AdminUi.secondary(context)),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final viajeId = (d['viajeId'] ?? '').toString();
            final montoCents = (d['montoCents'] is num)
                ? (d['montoCents'] as num).toInt()
                : 0;
            final err =
                (d['lastError'] ?? d['responseMessage'] ?? '').toString();
            return Card(
              color: AdminUi.card(context),
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(
                  'Viaje ${viajeId.isEmpty ? "—" : viajeId.substring(0, 8)}…',
                  style: TextStyle(
                    color: AdminUi.onCard(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  '${FormatosMoneda.rd(montoCents / 100)} · '
                  '${err.isNotEmpty ? err : "Pago rechazado o cancelado"}',
                  style: TextStyle(color: AdminUi.muted(context)),
                ),
                trailing: viajeId.isEmpty
                    ? null
                    : _ViajeTaxistaChip(viajeId: viajeId),
              ),
            );
          },
        );
      },
    );
  }
}

class _ViajesTarjetaPendientesList extends StatelessWidget {
  const _ViajesTarjetaPendientesList({required this.fmtFecha});

  final DateFormat fmtFecha;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('viajes')
          .where('completado', isEqualTo: true)
          .where('liquidado', isEqualTo: false)
          .limit(120)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Consulta limitada en Firestore. Revisá viajes con '
                'metodoPago Tarjeta y estadoPago pendiente.\n${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final pendientes = (snap.data?.docs ?? const [])
            .where((doc) {
              final m = doc.data();
              if (!MetodoPagoViaje.esTarjeta(m['metodoPago']?.toString())) {
                return false;
              }
              final ep =
                  (m['estadoPago'] ?? '').toString().trim().toLowerCase();
              return ep != 'verificado';
            })
            .toList();
        if (pendientes.isEmpty) {
          return Center(
            child: Text(
              'Sin viajes tarjeta finalizados pendientes de verificar',
              style: TextStyle(color: AdminUi.secondary(context)),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: pendientes.length,
          itemBuilder: (context, i) {
            final doc = pendientes[i];
            final m = doc.data();
            final nombre =
                (m['nombreTaxista'] ?? m['uidTaxista'] ?? '—').toString();
            final total = (m['precio'] is num)
                ? (m['precio'] as num).toDouble()
                : (m['gananciaTaxista'] is num
                    ? (m['gananciaTaxista'] as num).toDouble()
                    : 0.0);
            final fin = m['finalizadoEn'];
            String cuando = '—';
            if (fin is Timestamp) {
              cuando = fmtFecha.format(fin.toDate());
            }
            return Card(
              color: AdminUi.card(context),
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(
                  nombre,
                  style: TextStyle(
                    color: AdminUi.onCard(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  'Viaje ${doc.id.substring(0, 8)}… · '
                  '${FormatosMoneda.rd(total)} · $cuando · '
                  'NO entra en liquidación hasta verificar AZUL',
                  style: TextStyle(color: AdminUi.muted(context)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ViajeTaxistaChip extends StatelessWidget {
  const _ViajeTaxistaChip({required this.viajeId});

  final String viajeId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('viajes').doc(viajeId).get(),
      builder: (context, snap) {
        final nombre =
            (snap.data?.data()?['nombreTaxista'] ?? 'Conductor').toString();
        return Chip(
          label: Text(
            nombre,
            style: const TextStyle(fontSize: 11),
          ),
        );
      },
    );
  }
}
