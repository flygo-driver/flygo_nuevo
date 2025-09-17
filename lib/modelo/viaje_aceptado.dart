// lib/pantallas/taxista/viaje_aceptado.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/calculos/estados.dart';

class ViajeAceptado extends StatefulWidget {
  final String viajeId;
  const ViajeAceptado({super.key, required this.viajeId});

  @override
  State<ViajeAceptado> createState() => _ViajeAceptadoState();
}

class _ViajeAceptadoState extends State<ViajeAceptado> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _coordsValid(double lat, double lon) {
    if (lat == 0 && lon == 0) return false;
    return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }

  // --- Navegación ---
  Future<void> _abrirGoogleMapsDestino(double lat, double lon) async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving',
    );
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _abrirGoogleMapsDireccion(String direccion) async {
    final q = Uri.encodeComponent(direccion);
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  // --- Acciones ---
  Future<void> _marcarClienteAbordo() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No hay usuario logueado')));
      return;
    }

    final ref = _db.collection('viajes').doc(widget.viajeId);
    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw Exception('El viaje no existe');
        final d = snap.data() as Map<String, dynamic>;

        // seguridad básica
        if ((d['uidTaxista'] ?? '') != uid) {
          throw Exception('No autorizado');
        }

        final estado = (d['estado'] ?? '').toString();
        if (!EstadosViaje.esAceptado(estado)) {
          throw Exception('El estado actual no permite marcar a bordo');
        }

        tx.update(ref, {
          'estado': EstadosViaje.aBordo, // 'a_bordo'
          'pickupConfirmadoEn': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(content: Text('✅ Cliente a bordo')),
      );
    } on FirebaseException catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Firestore: ${e.code} - ${e.message}')),
      );
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final docRef = _db.collection('viajes').doc(widget.viajeId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Viaje aceptado'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
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
                'El viaje no existe',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          final d = snap.data!.data()!;
          final origen = (d['origen'] ?? '').toString();
          final destino = (d['destino'] ?? '').toString();
          final precio = (d['precio'] ?? 0).toString();
          final estado = EstadosViaje.normalizar(
            (d['estado'] ?? '').toString(),
          );

          final latPickup = (d['latCliente'] is num)
              ? (d['latCliente'] as num).toDouble()
              : 0.0;
          final lonPickup = (d['lonCliente'] is num)
              ? (d['lonCliente'] as num).toDouble()
              : 0.0;
          final tieneCoords = _coordsValid(latPickup, lonPickup);

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
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
                  '💰 Total: $precio',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '📍 Estado: ${EstadosViaje.descripcion(estado)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 24),

                // Navegación al pickup
                ElevatedButton.icon(
                  onPressed: () {
                    if (tieneCoords) {
                      _abrirGoogleMapsDestino(latPickup, lonPickup);
                    } else {
                      _abrirGoogleMapsDireccion(origen);
                    }
                  },
                  icon: const Icon(Icons.map),
                  label: const Text('Navegar al pickup'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    minimumSize: const Size(double.infinity, 52),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Cliente a bordo
                ElevatedButton.icon(
                  onPressed: EstadosViaje.esAceptado(estado)
                      ? _marcarClienteAbordo
                      : null,
                  icon: const Icon(Icons.emoji_people),
                  label: const Text('Cliente a bordo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.green,
                    minimumSize: const Size(double.infinity, 52),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (!EstadosViaje.esAceptado(estado))
                  const Text(
                    'Este viaje ya no está en estado ACEPTADO.',
                    style: TextStyle(color: Colors.white38),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
