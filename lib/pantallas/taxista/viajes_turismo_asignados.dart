// lib/pantallas/taxista/viajes_turismo_asignados.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../utils/estilos.dart';
import '../../utils/calculos/estados.dart';
// Si tienes un drawer del taxista, descomenta esta línea y ajusta el import:
// import '../../widgets/taxista_drawer.dart';

// 👉 Import para ir al viaje en curso del taxista
import 'package:flygo_nuevo/pantallas/taxista/viaje_en_curso_taxista.dart';

class ViajesTurismoAsignadosTaxista extends StatelessWidget {
  const ViajesTurismoAsignadosTaxista({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamMisViajes() {
    final User? user = FirebaseAuth.instance.currentUser;
    final String? uid = user?.uid;
    if (uid == null) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }

    return FirebaseFirestore.instance
        .collection('viajes')
        .where('uidTaxista', isEqualTo: uid)
        .where('tipoServicio', isEqualTo: 'turismo')
        // Mismo whereIn histórico (índices existentes). En ruta: usar «Viaje en curso» del menú.
        .where('estado',
            whereIn: <String>['pendiente_admin', EstadosViaje.aceptado])
        .orderBy('fechaHora')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EstilosRai.fondoOscuro,
      // drawer: const TaxistaDrawer(),
      appBar: AppBar(
        backgroundColor: EstilosRai.fondoOscuro,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Mis viajes turismo',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              'Solo viajes que te asignó administración. No aparecen en «Viajes disponibles».',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                  height: 1.3),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _streamMisViajes(),
              builder: (BuildContext context,
                  AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: EstilosRai.textoVerde),
                  );
                }

                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snap.error}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  );
                }

                final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                    snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No tienes viajes de turismo asignados.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int i) {
                    final QueryDocumentSnapshot<Map<String, dynamic>> doc =
                        docs[i];
                    final Map<String, dynamic> data = doc.data();

                    final String origen = (data['origen'] ?? '').toString();
                    final String destino = (data['destino'] ?? '').toString();
                    final String tipoVehiculo =
                        (data['tipoVehiculo'] ?? '').toString();
                    final double precio = (data['precio'] ?? 0).toDouble();
                    final double km = (data['distanciaKm'] ?? 0).toDouble();
                    final String estado = (data['estado'] ?? '').toString();

                    DateTime? fechaHora;
                    final dynamic fh = data['fechaHora'];
                    if (fh is Timestamp) fechaHora = fh.toDate();
                    if (fh is DateTime) fechaHora = fh;

                    String fechaStr = '—';
                    if (fechaHora != null) {
                      fechaStr =
                          '${fechaHora.day.toString().padLeft(2, '0')}/${fechaHora.month.toString().padLeft(2, '0')} '
                          '${fechaHora.hour.toString().padLeft(2, '0')}:${fechaHora.minute.toString().padLeft(2, '0')}';
                    }

                    return _ViajeTurismoChoferTile(
                      id: doc.id,
                      origen: origen,
                      destino: destino,
                      tipoVehiculo: tipoVehiculo,
                      precio: precio,
                      distanciaKm: km,
                      fechaStr: fechaStr,
                      estado: estado,
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

class _ViajeTurismoChoferTile extends StatelessWidget {
  final String id;
  final String origen;
  final String destino;
  final String tipoVehiculo;
  final double precio;
  final double distanciaKm;
  final String fechaStr;
  final String estado;

  const _ViajeTurismoChoferTile({
    required this.id,
    required this.origen,
    required this.destino,
    required this.tipoVehiculo,
    required this.precio,
    required this.distanciaKm,
    required this.fechaStr,
    required this.estado,
  });

  String _rd(double v) {
    final String s = v.toStringAsFixed(2);
    final List<String> parts = s.split('.');
    final RegExp re = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final String intPart =
        parts.first.replaceAllMapped(re, (Match m) => '${m[1]},');
    return 'RD\$ $intPart.${parts.last}';
  }

  String _km(double v) => '${v.toStringAsFixed(1)} km';

  void _abrirViajeEnCurso(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const ViajeEnCursoTaxista(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool terminal =
        EstadosViaje.esCompletado(estado) || EstadosViaje.esCancelado(estado);
    final String estadoEtiqueta = EstadosViaje.descripcion(estado);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$origen → $destino',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tipo: Turismo · $tipoVehiculo',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Fecha: $fechaStr',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              Chip(
                backgroundColor: Colors.green.withValues(alpha: 0.12),
                shape: const StadiumBorder(
                  side: BorderSide(
                    color: Colors.greenAccent,
                  ),
                ),
                label: Text(
                  _rd(precio),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Chip(
                backgroundColor: Colors.white10,
                label: Text(
                  _km(distanciaKm),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              Chip(
                backgroundColor: terminal
                    ? Colors.white10
                    : Colors.blue.withValues(alpha: 0.18),
                label: Text(
                  estadoEtiqueta.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: terminal ? Colors.white54 : Colors.blueAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!terminal)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _abrirViajeEnCurso(context),
                icon: const Icon(Icons.navigation_outlined),
                label: const Text(
                  'Abrir viaje (mapa, ETA, contacto)',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
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
