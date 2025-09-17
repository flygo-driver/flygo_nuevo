// lib/pantallas/taxista/detalle_viaje.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../utils/calculos/estados.dart';
import '../../utils/formatos_moneda.dart';
import '../../widgets/acciones_viaje_taxista.dart';

class DetalleViaje extends StatelessWidget {
  final String viajeId;
  const DetalleViaje({super.key, required this.viajeId});

  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  DateTime _asDate(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<String> _rolActual() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 'cliente';
    final u = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .get();
    return (u.data()?['rol'] ?? 'cliente').toString();
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy - HH:mm');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Detalle del viaje',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('viajes')
            .doc(viajeId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
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
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(
              child: Text(
                'El viaje no existe.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          final d = snap.data!.data()!;
          final origen = (d['origen'] ?? '').toString();
          final destino = (d['destino'] ?? '').toString();

          final estadoRaw = (d['estado'] ?? '').toString();
          final aceptado = (d['aceptado'] ?? false) == true;
          final completado = (d['completado'] ?? false) == true;

          final estadoBase = EstadosViaje.normalizar(
            estadoRaw.isNotEmpty
                ? estadoRaw
                : (completado
                      ? EstadosViaje.completado
                      : (aceptado
                            ? EstadosViaje.aceptado
                            : EstadosViaje.pendiente)),
          );

          final precio = _asDouble(d['precio']);
          final fecha = formatoFecha.format(_asDate(d['fechaHora']));
          final nombreTaxista = (d['nombreTaxista'] ?? '').toString();
          final uidTaxista = (d['uidTaxista'] ?? '').toString();
          final clienteId = (d['clienteId'] ?? '').toString();

          return FutureBuilder<String>(
            future: _rolActual(),
            builder: (context, rolSnap) {
              final rol = rolSnap.data ?? 'cliente';
              final soyTaxista = rol == 'taxista';

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    '🧭 $origen → $destino',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '🕓 Fecha: $fecha',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '💰 Total: ${FormatosMoneda.rd(precio)}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        '📍 Estado: ',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          EstadosViaje.descripcion(estadoBase),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (nombreTaxista.isNotEmpty || uidTaxista.isNotEmpty) ...[
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 8),
                    const Text(
                      'Conductor asignado',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      nombreTaxista.isNotEmpty ? nombreTaxista : uidTaxista,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                  ],

                  const Divider(color: Colors.white12),
                  const SizedBox(height: 12),

                  if (soyTaxista) ...[
                    const Text(
                      'Acciones del conductor',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AccionesViajeTaxista(
                      viajeId: viajeId,
                      estadoActual: estadoBase,
                    ),
                  ],

                  const SizedBox(height: 20),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 6),
                  Text(
                    'ID del viaje: $viajeId',
                    style: const TextStyle(color: Colors.white24, fontSize: 12),
                  ),
                  Text(
                    'Cliente: $clienteId',
                    style: const TextStyle(color: Colors.white24, fontSize: 12),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
