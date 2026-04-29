// lib/pantallas/taxista/vista_previa_viaje.dart
// Vista previa del viaje para taxista (NO cambia tu lógica de aceptación).
// - Botones: "Aceptar viaje" (misma lógica vía callback) y "No me interesa" (solo cierra).
// - Mapa con marcadores Origen/Destino y ajuste automático de cámara.
// - Precio en grande (sin descuentos ni ahorro: solo lo que ve el taxista).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/cliente_perfil_conductor_chip.dart';

class VistaPreviaViaje extends StatefulWidget {
  final Viaje viaje;

  /// Callback que ejecuta EXACTAMENTE la misma lógica de aceptación
  /// que ya usas en la lista de viajes disponibles.
  final Future<void> Function() onAceptar;

  const VistaPreviaViaje({
    Key? key,
    required this.viaje,
    required this.onAceptar,
  }) : super(key: key);

  @override
  State<VistaPreviaViaje> createState() => _VistaPreviaViajeState();
}

class _VistaPreviaViajeState extends State<VistaPreviaViaje> {
  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();
  late final LatLng _origen;
  late final LatLng _destino;

  @override
  void initState() {
    super.initState();
    _origen = LatLng(widget.viaje.latCliente, widget.viaje.lonCliente);
    _destino = LatLng(widget.viaje.latDestino, widget.viaje.lonDestino);
  }

  Set<Marker> get _markers => {
        Marker(
          markerId: const MarkerId('origen'),
          position: _origen,
          infoWindow: const InfoWindow(title: 'Origen'),
        ),
        Marker(
          markerId: const MarkerId('destino'),
          position: _destino,
          infoWindow: const InfoWindow(title: 'Destino'),
        ),
      };

  Future<void> _fitBounds() async {
    final controller = await _mapController.future;

    final sw = LatLng(
      _min(_origen.latitude, _destino.latitude),
      _min(_origen.longitude, _destino.longitude),
    );
    final ne = LatLng(
      _max(_origen.latitude, _destino.latitude),
      _max(_origen.longitude, _destino.longitude),
    );

    // Si origen y destino son iguales, usa un zoom por defecto
    if (sw.latitude == ne.latitude && sw.longitude == ne.longitude) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
            CameraPosition(target: _origen, zoom: 15)),
      );
      return;
    }

    final bounds = LatLngBounds(southwest: sw, northeast: ne);
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  double _min(double a, double b) => (a < b) ? a : b;
  double _max(double a, double b) => (a > b) ? a : b;

  @override
  Widget build(BuildContext context) {
    final v = widget.viaje;

    // Sólo precio que ve el taxista (sin descuentos/ahorros del cliente)
    final double precioMostrar =
        (v.precioFinal > 0) ? v.precioFinal : (v.precio > 0 ? v.precio : 0);

    // Placeholder neutral (si luego agregas nombreCliente, úsalo aquí)
    const String nombreMostrar = 'Cliente';
    final String uidClientePrev =
        v.uidCliente.isNotEmpty ? v.uidCliente : v.clienteId;

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Detalle del viaje',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // ===== Mapa =====
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: _origen, zoom: 14),
              markers: _markers,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              compassEnabled: false,
              onMapCreated: (c) {
                if (!_mapController.isCompleted) {
                  _mapController.complete(c);
                }
                // Pequeño delay para asegurar que el mapa pintó antes de ajustar cámara
                Future.delayed(const Duration(milliseconds: 300), _fitBounds);
              },
            ),
          ),

          // ===== Panel inferior con info y botones =====
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            decoration: const BoxDecoration(
              color: Color(0xFF0D0D0D),
              boxShadow: [
                BoxShadow(
                  blurRadius: 8,
                  offset: Offset(0, -2),
                  color: Colors.black54,
                ),
              ],
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cliente
                Text(
                  'Cliente: $nombreMostrar',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.white70),
                ),
                if (uidClientePrev.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ClientePerfilConductorChip(
                    uidCliente: uidClientePrev,
                  ),
                ],
                const SizedBox(height: 10),

                // Origen
                Text('Origen',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: Colors.white54)),
                Text(
                  v.origen,
                  style:
                      theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),

                // Destino
                Text('Destino',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: Colors.white54)),
                Text(
                  v.destino,
                  style:
                      theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),

                // Precio grande
                Center(
                  child: Text(
                    FormatosMoneda.rd(precioMostrar),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: Colors.yellow,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Botones: "No me interesa" / "Aceptar viaje"
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop(false); // no aceptó
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          foregroundColor: Colors.white70,
                        ),
                        child: const Text('No me interesa'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            await widget
                                .onAceptar(); // MISMA lógica que en la lista
                            if (!context.mounted) {
                              return; // guardia correcta para BuildContext tras await
                            }
                            Navigator.of(context).pop(true);
                          } catch (_) {
                            // Errores ya se notifican en tu lógica original (snackbars, etc.)
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Aceptar viaje'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
