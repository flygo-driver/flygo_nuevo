// lib/pantallas/cliente/viajes_tabs_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../../widgets/viaje_card.dart';
import '../../servicios/distancia_service.dart';

const int kAhoraUmbralMin = 10;

// Estados activos del cliente (excluye completado/cancelado)
const List<String> _kEstadosActivos = <String>[
  'pendiente',
  'pendiente_pago',
  'pendientePago',
  'aceptado',
  'a_bordo',
  'en_curso',
];

class ViajesTabsPage extends StatelessWidget {
  const ViajesTabsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('Inicia sesión', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Viajes', style: TextStyle(color: Colors.white)),
          bottom: const TabBar(
            indicatorColor: Colors.greenAccent,
            labelColor: Colors.greenAccent,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(text: 'AHORA'),
              Tab(text: 'PROGRAMADOS'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ListaViajes(uid: u.uid, programados: false),
            _ListaViajes(uid: u.uid, programados: true),
          ],
        ),
      ),
    );
  }
}

class _ListaViajes extends StatelessWidget {
  final String uid;
  final bool programados;
  const _ListaViajes({required this.uid, required this.programados});

  // Query base: trae los viajes del cliente (uidCliente o legacy clienteId)
  fs.Query<Map<String, dynamic>> _qCliente(String uid) {
    final col = fs.FirebaseFirestore.instance.collection('viajes');
    // Igualdad pura → sin orderBy para evitar necesidad de índice compuesto;
    // ordenamos/filtramos en memoria.
    return col.where(
      fs.Filter.or(
        fs.Filter('uidCliente', isEqualTo: uid),
        fs.Filter('clienteId', isEqualTo: uid),
      ),
    );
  }

  bool _esAhora(DateTime fecha) => !fecha
      .isAfter(DateTime.now().add(const Duration(minutes: kAhoraUmbralMin)));

  @override
  Widget build(BuildContext context) {
    final stream = _qCliente(uid).snapshots();

    return StreamBuilder<fs.QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Text(
              'Error: ${snap.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Center(
            child: Text(
              programados
                  ? 'No hay viajes programados'
                  : 'No hay viajes ahora mismo',
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }

        // Filtrar por estados activos y dividir por tiempo (ahora/programados)
        final docs = snap.data!.docs.where((d) {
          final data = d.data();
          final estado = (data['estado'] ?? '').toString();
          if (!_kEstadosActivos.contains(estado)) return false;

          final fecha = _readDate(data['fechaHora']) ?? DateTime.now();
          final vaEnAhora = _esAhora(fecha);
          return programados ? !vaEnAhora : vaEnAhora;
        }).toList();

        if (docs.isEmpty) {
          return Center(
            child: Text(
              programados
                  ? 'No hay viajes programados'
                  : 'No hay viajes ahora mismo',
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }

        // Orden: AHORA (desc por fecha) / PROGRAMADOS (asc por fecha)
        docs.sort((a, b) {
          final fa = _readDate(a.data()['fechaHora']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final fb = _readDate(b.data()['fechaHora']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return programados ? fa.compareTo(fb) : fb.compareTo(fa);
        });

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data();

            final String origen = (d['origen'] ?? '').toString();
            final String destino = (d['destino'] ?? '').toString();
            final String metodo = (d['metodoPago'] ?? 'Efectivo').toString();
            final String veh = (d['tipoVehiculo'] ?? 'Carro').toString();

            final double precio = _readDouble(d['precio']) ?? 0.0;
            final DateTime fecha = _readDate(d['fechaHora']) ?? DateTime.now();

            final double? km = _readDouble(d['distanciaKm']) ??
                _calcKmFromCoords(
                  la: d['latCliente'] ?? d['latOrigen'],
                  lo: d['lonCliente'] ?? d['lonOrigen'],
                  l2a: d['latDestino'],
                  l2o: d['lonDestino'],
                );

            final double gana =
                _readDouble(d['gananciaTaxista']) ?? (precio * 0.8);

            return ViajeCard(
              origen: origen,
              destino: destino,
              fechaHora: fecha,
              precio: precio,
              gananciaTaxista: gana,
              distanciaKm: km,
              metodoPago: metodo,
              tipoVehiculo: veh,
              programado: programados,
              onTap: () {}, // si tienes detalle del viaje, navega aquí
              showAceptar: false, // vista de cliente → no mostrar botón Aceptar
              onAceptar: null,
            );
          },
        );
      },
    );
  }

  // ===== Helpers lectura segura =====
  static double? _readDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static DateTime? _readDate(dynamic v) {
    if (v == null) return null;
    if (v is fs.Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {}
    }
    return null;
  }

  static double? _calcKmFromCoords({
    required dynamic la,
    required dynamic lo,
    required dynamic l2a,
    required dynamic l2o,
  }) {
    final a = _readDouble(la);
    final b = _readDouble(lo);
    final c = _readDouble(l2a);
    final d = _readDouble(l2o);
    if (a == null || b == null || c == null || d == null) return null;
    return DistanciaService.calcularDistancia(a, b, c, d);
  }
}
