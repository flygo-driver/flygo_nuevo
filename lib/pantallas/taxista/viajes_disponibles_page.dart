import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../servicios/viajes_repo_streams.dart';
import '../../servicios/distancia_service.dart';
import '../../servicios/viajes_repo.dart';
import '../../widgets/viaje_disponible_card.dart';

const int kAhoraUmbralMin = 10;

class ViajesDisponiblesPage extends StatelessWidget {
  const ViajesDisponiblesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Viajes disponibles', style: TextStyle(color: Colors.white)),
          bottom: const TabBar(
            indicatorColor: Colors.greenAccent,
            labelColor: Colors.greenAccent,
            unselectedLabelColor: Colors.white60,
            tabs: [Tab(text: 'AHORA'), Tab(text: 'PROGRAMADOS')],
          ),
        ),
        body: const TabBarView(
          children: [
            _ListaDisponibles(programados: false),
            _ListaDisponibles(programados: true),
          ],
        ),
      ),
    );
  }
}

class _ListaDisponibles extends StatelessWidget {
  final bool programados;
  const _ListaDisponibles({required this.programados});

  @override
  Widget build(BuildContext context) {
    final stream = programados
        ? ViajesRepoStreams.streamDisponiblesProgramados(umbralMin: kAhoraUmbralMin)
        : ViajesRepoStreams.streamDisponiblesAhora(umbralMin: kAhoraUmbralMin);

    final u = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Center(
            child: Text(
              programados ? 'Sin programados' : 'Sin viajes ahora',
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }

        final docs = snap.data!.docs;
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final doc = docs[i];
            final d = doc.data();

            final origen = (d['origen'] ?? '').toString();
            final destino = (d['destino'] ?? '').toString();
            final metodo = (d['metodoPago'] ?? 'Efectivo').toString();
            final veh = (d['tipoVehiculo'] ?? 'Carro').toString();

            double precio = 0;
            final pRaw = d['precio'];
            if (pRaw is num) precio = pRaw.toDouble();
            if (pRaw is String) precio = double.tryParse(pRaw) ?? 0;

            DateTime fecha = DateTime.now();
            final fh = d['fechaHora'];
            if (fh is Timestamp) fecha = fh.toDate();
            if (fh is String) {
              try { fecha = DateTime.parse(fh); } catch (_) {}
            }

            // Distancia si hay coords
            double? km;
            final la = _asDouble(d['latCliente']);
            final lo = _asDouble(d['lonCliente']);
            final l2a = _asDouble(d['latDestino']);
            final l2o = _asDouble(d['lonDestino']);
            if (la != null && lo != null && l2a != null && l2o != null) {
              km = DistanciaService.calcularDistancia(la, lo, l2a, l2o);
            }

            final gana = (precio > 0) ? (precio * 0.8) : null;

            return ViajeDisponibleCard(
              origen: origen,
              destino: destino,
              fechaHora: fecha,
              precio: precio,
              gananciaTaxista: gana,
              distanciaKm: km,
              metodoPago: metodo,
              tipoVehiculo: veh,
              programado: programados,
              onAceptar: (u == null)
                  ? null
                  : () async {
                      try {
                        await ViajesRepo.claimTrip(
                          viajeId: doc.id,
                          uidTaxista: u.uid,
                          nombreTaxista: u.displayName ?? 'Taxista',
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('✅ Viaje aceptado')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    },
            );
          },
        );
      },
    );
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
