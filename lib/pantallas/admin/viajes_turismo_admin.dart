// lib/pantallas/admin/viajes_turismo_admin.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../widgets/admin_drawer.dart';
import 'admin_ui_theme.dart';
import '../../utils/calculos/estados.dart';
import '../../servicios/asignacion_turismo_repo.dart';
import 'asignar_viaje_turismo.dart';

class ViajesTurismoAdmin extends StatelessWidget {
  const ViajesTurismoAdmin({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamViajes() {
    final db = FirebaseFirestore.instance;

    return db
        .collection('viajes')
        .where('tipoServicio', isEqualTo: 'turismo')
        .where('canalAsignacion', isEqualTo: 'admin')
        .where('estado', whereIn: [
          'pendiente_admin',
          EstadosViaje.pendiente,
          EstadosViaje.pendientePago,
        ])
        .orderBy('fechaHora')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.scaffold(context),
      drawer: const AdminDrawer(),
      appBar: AppBar(
        backgroundColor: AdminUi.scaffold(context),
        foregroundColor: AdminUi.appBarFg(context),
        iconTheme: IconThemeData(color: AdminUi.appBarFg(context)),
        title: Text(
          'Viajes Turismo — Asignación',
          style: TextStyle(color: AdminUi.onCard(context)),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminUi.infoFill(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AdminUi.infoBorder(context)),
              ),
              child: Text(
                'Canal turismo (admin): no aparecen en el pool normal de taxistas. '
                'Puedes asignar un chofer aprobado o «Liberar al pool turístico» para que solo choferes de turismo aprobados los vean y acepten.',
                style: TextStyle(color: AdminUi.secondary(context), fontSize: 12, height: 1.35),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _streamViajes(),
              builder: (BuildContext context, AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: AdminUi.progressAccent(context)),
                  );
                }

                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snap.error}',
                      style: TextStyle(color: AdminUi.secondary(context)),
                    ),
                  );
                }

                final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No hay viajes de turismo pendientes.',
                      style: TextStyle(color: AdminUi.secondary(context)),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final QueryDocumentSnapshot<Map<String, dynamic>> doc = docs[index];
                    final Map<String, dynamic> data = doc.data();

                    final String origen = (data['origen'] ?? '').toString();
                    final String destino = (data['destino'] ?? '').toString();
                    final String tipoVehiculo = (data['tipoVehiculo'] ?? '').toString();
                    final String subtipoTurismo =
                        (data['subtipoTurismo'] ?? '').toString();
                    final double precio = (data['precio'] ?? 0).toDouble();
                    final double km = (data['distanciaKm'] ?? 0).toDouble();
                    final String uidCliente = (data['uidCliente'] ?? '').toString();

                    double latCliente = 0;
                    double lonCliente = 0;
                    final dynamic lc = data['latCliente'];
                    final dynamic ln = data['lonCliente'];
                    if (lc is num) latCliente = lc.toDouble();
                    if (ln is num) lonCliente = ln.toDouble();

                    DateTime? fechaHora;
                    final dynamic fh = data['fechaHora'];
                    if (fh is Timestamp) fechaHora = fh.toDate();

                    final String fechaStr = fechaHora != null
                        ? '${fechaHora.day.toString().padLeft(2, '0')}/${fechaHora.month.toString().padLeft(2, '0')} '
                          '${fechaHora.hour.toString().padLeft(2, '0')}:${fechaHora.minute.toString().padLeft(2, '0')}'
                        : '—';

                    return _ViajeTurismoTile(
                      id: doc.id,
                      origen: origen,
                      destino: destino,
                      tipoVehiculo: tipoVehiculo,
                      subtipoTurismo: subtipoTurismo,
                      precio: precio,
                      distanciaKm: km,
                      fechaStr: fechaStr,
                      uidCliente: uidCliente,
                      latCliente: latCliente,
                      lonCliente: lonCliente,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ViajeTurismoTile extends StatelessWidget {
  final String id;
  final String origen;
  final String destino;
  final String tipoVehiculo;
  final String subtipoTurismo;
  final double precio;
  final double distanciaKm;
  final String fechaStr;
  final String uidCliente;
  final double latCliente;
  final double lonCliente;

  const _ViajeTurismoTile({
    required this.id,
    required this.origen,
    required this.destino,
    required this.tipoVehiculo,
    required this.subtipoTurismo,
    required this.precio,
    required this.distanciaKm,
    required this.fechaStr,
    required this.uidCliente,
    required this.latCliente,
    required this.lonCliente,
  });

  String _rd(double v) {
    final String s = v.toStringAsFixed(2);
    final List<String> parts = s.split('.');
    final RegExp re = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final String intPart = parts.first.replaceAllMapped(re, (Match m) => '${m[1]},');
    return 'RD\$ $intPart.${parts.last}';
  }

  String _km(double v) => '${v.toStringAsFixed(1)} km';

  Future<void> _asignarChofer(BuildContext context) async {
    if (!context.mounted) return;
    
    // 🔥 Navegar a la pantalla de asignación pasando el tipo de vehículo
    final bool? asignado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (BuildContext context) => AsignarViajeTurismo(
          viajeId: id,
          tipoVehiculo:
              subtipoTurismo.trim().isNotEmpty ? subtipoTurismo : tipoVehiculo,
          latOrigen: (latCliente != 0 || lonCliente != 0) ? latCliente : null,
          lonOrigen: (latCliente != 0 || lonCliente != 0) ? lonCliente : null,
        ),
      ),
    );

    if (asignado == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Chofer asignado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _liberarAlPoolTuristico(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: AdminUi.dialogSurface(ctx),
          title: Text(
            'Liberar al pool turístico',
            style: TextStyle(color: AdminUi.onCard(ctx)),
          ),
          content: Text(
            'El viaje saldrá de esta cola de administración y solo lo verán choferes de turismo aprobados en «Pool turístico».',
            style: TextStyle(color: AdminUi.secondary(ctx)),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar', style: TextStyle(color: AdminUi.onCard(ctx))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Liberar', style: TextStyle(color: Theme.of(ctx).colorScheme.primary)),
            ),
          ],
        );
      },
    );
    if (ok != true || !context.mounted) return;
    try {
      await FirebaseFirestore.instance.collection('viajes').doc(id).update(
        <String, dynamic>{
          'canalAsignacion': AsignacionTurismoRepo.canalTurismoPool,
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        },
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Viaje liberado al pool turístico'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo liberar: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String etiquetaTipo = subtipoTurismo.trim().isNotEmpty
        ? subtipoTurismo
        : (tipoVehiculo.isNotEmpty ? tipoVehiculo : '—');
    final green = AdminUi.accentGreen(context);
    final purple = Theme.of(context).brightness == Brightness.light
        ? Colors.deepPurple.shade700
        : Colors.purpleAccent;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminUi.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminUi.borderSubtle(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$origen → $destino',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AdminUi.onCard(context),
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Turismo · $etiquetaTipo',
            style: TextStyle(color: AdminUi.secondary(context), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Fecha: $fechaStr',
            style: TextStyle(color: AdminUi.muted(context), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            uidCliente.length >= 6
                ? 'Cliente: ${uidCliente.substring(0, 6)}…'
                : 'Cliente: ${uidCliente.isEmpty ? '—' : uidCliente}',
            style: TextStyle(color: AdminUi.muted(context), fontSize: 11),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Chip(
                backgroundColor: green.withValues(alpha: 0.15),
                shape: StadiumBorder(
                  side: BorderSide(color: green.withValues(alpha: 0.8)),
                ),
                label: Text(
                  _rd(precio),
                  style: TextStyle(
                    color: green,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                label: Text(
                  _km(distanciaKm),
                  style: TextStyle(color: AdminUi.secondary(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _asignarChofer(context),
              icon: Icon(Icons.person_search, color: Theme.of(context).colorScheme.onPrimary),
              label: Text(
                'Asignar chofer',
                style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _liberarAlPoolTuristico(context),
              icon: Icon(Icons.groups_2, color: purple),
              label: Text(
                'Liberar al pool turístico',
                style: TextStyle(color: purple),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: purple),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}