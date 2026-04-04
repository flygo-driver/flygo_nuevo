// lib/pantallas/taxista/detalle_viaje.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../utils/formatos_moneda.dart';
import '../../servicios/asignacion_turismo_repo.dart';
import '../../servicios/viajes_repo.dart';
import '../../servicios/ubicacion_taxista.dart';
import '../../servicios/roles_service.dart';
import '../../servicios/pagos_taxista_repo.dart';
import '../../utils/viaje_pool_taxista_gate.dart';
import 'viaje_en_curso_taxista.dart';

class DetalleViaje extends StatefulWidget {
  final String viajeId;
  const DetalleViaje({super.key, required this.viajeId});

  @override
  State<DetalleViaje> createState() => _DetalleViajeState();
}

class _DetalleViajeState extends State<DetalleViaje> {
  bool _procesando = false;

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

  Future<void> _ignorarViaje(String viajeId) async {
    setState(() => _procesando = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No autenticado');

      await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .update({
        'ignoradosPor': FieldValue.arrayUnion([user.uid]),
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Viaje ignorado. No volverá a aparecer.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  String _mensajeClaimFallido(String res) {
    switch (res) {
      case 'no-existe':
        return 'El viaje ya no existe.';
      case 'estado-no-pendiente':
        return 'El viaje ya no está pendiente.';
      case 'ya-asignado':
        return 'Ese viaje ya fue asignado.';
      case 'acceptAfter-futuro':
        return 'Aún no se libera.';
      case 'publish-futuro':
        return 'Aún no se publica.';
      case 'reservado-otro':
        return 'Reservado por otro taxista.';
      case 'taxista-ocupado':
        return 'Tienes un viaje activo.';
      default:
        if (res.startsWith('permiso:')) {
          return 'Permisos: ${res.split(':').last}';
        }
        return 'Error: $res';
    }
  }

  Future<void> _aceptarViaje(String viajeId) async {
    setState(() => _procesando = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No autenticado');

      if (!await RolesService.getDisponibilidad(user.uid)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Activa tu disponibilidad en el menú (Disponibilidad) para aceptar viajes.',
            ),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        return;
      }
      if (await PagosTaxistaRepo.tieneBloqueoSemanal(user.uid)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tienes pago semanal pendiente. Regulariza para aceptar viajes del pool.',
            ),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get();
      if (!doc.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El viaje ya no existe.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      final Map<String, dynamic> d = doc.data()!;
      final String tipoServicio = (d['tipoServicio'] ?? 'normal').toString();
      final String canalAsignacion =
          (d['canalAsignacion'] ?? 'pool').toString();

      if (tipoServicio == 'turismo' && canalAsignacion == 'admin') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Este viaje de turismo lo asigna el equipo administrativo; no puedes aceptarlo desde la app.',
            ),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        return;
      }

      if (tipoServicio == 'turismo' &&
          canalAsignacion == AsignacionTurismoRepo.canalTurismoPool) {
        await ViajesRepo.ensureTaxistaLibre(user.uid);
        await ViajesRepo.ensureSiguienteCoherente(user.uid);

        final ResultadoPrepClaimPoolTurismo prep =
            await AsignacionTurismoRepo.prepararClaimPoolTurismo(
          uidChofer: user.uid,
          viajeId: viajeId,
          rawViaje: Map<String, dynamic>.from(d),
        );
        if (!prep.ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                AsignacionTurismoRepo.mensajeNoAutorizadoPoolTurismo,
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
        final DatosClaimPoolTurismo datos = prep.datos!;

        final String res = await ViajesRepo.claimTripWithReason(
          viajeId: viajeId,
          uidTaxista: user.uid,
          nombreTaxista: datos.nombreChofer,
          telefono: datos.telefonoChofer,
          placa: datos.placa,
          tipoVehiculo: datos.subtipoTurismo,
        );

        if (!mounted) return;

        if (res == 'ok') {
          await ViajesRepo.sincronizarChoferTurismoTrasAceptarDesdePool(
            uidChofer: user.uid,
            viajeId: viajeId,
          );
          await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(user.uid)
              .set(
            {
              'siguienteViajeId': '',
              'updatedAt': FieldValue.serverTimestamp(),
              'actualizadoEn': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          await UbicacionTaxista.marcarNoDisponible();
          if (!mounted) return;
          Navigator.pop(context);
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ViajeEnCursoTaxista()),
          );
          return;
        }

        if (res == 'taxista-ocupado') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_mensajeClaimFallido(res)),
              backgroundColor: Colors.orangeAccent,
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ViajeEnCursoTaxista()),
          );
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensajeClaimFallido(res)),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      await ViajesRepo.ensureTaxistaLibre(user.uid);
      await ViajesRepo.ensureSiguienteCoherente(user.uid);

      final res = await ViajesRepo.claimTripWithReason(
        viajeId: viajeId,
        uidTaxista: user.uid,
        nombreTaxista: user.displayName ?? user.email ?? 'taxista',
        telefono: '',
        placa: '',
      );

      if (!mounted) return;

      if (res == 'ok') {
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(user.uid)
            .set({
          'siguienteViajeId': '',
          'updatedAt': FieldValue.serverTimestamp(),
          'actualizadoEn': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await UbicacionTaxista.marcarNoDisponible();

        if (!mounted) return;
        Navigator.pop(context);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ViajeEnCursoTaxista()),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensajeClaimFallido(res)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatoFecha = DateFormat('dd/MM/yyyy - HH:mm');
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
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
        body: const Center(
          child: Text(
            'Inicia sesión.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

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
      body: FutureBuilder<bool>(
        future: PagosTaxistaRepo.tieneBloqueoSemanal(uid),
        builder: (context, debtSnap) {
          final bloqueoDeuda = debtSnap.data ?? false;
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('usuarios')
                .doc(uid)
                .snapshots(),
            builder: (context, userSnap) {
              final userLoading = userSnap.connectionState ==
                      ConnectionState.waiting &&
                  !userSnap.hasData;
              final disponibleUsuario = RolesService.leerDisponibleDesdeUsuarioDoc(
                userSnap.data?.data(),
              );

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('viajes')
                    .doc(widget.viajeId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.greenAccent),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    );
                  }
                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const Center(
                      child: Text(
                        'El viaje no existe.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    );
                  }

                  final d = snapshot.data!.data()!;

                  final origen = (d['origen'] ?? '').toString();
                  final destino = (d['destino'] ?? '').toString();
                  final latOrigen = _asDouble(d['latCliente']);
                  final lonOrigen = _asDouble(d['lonCliente']);
                  final latDestino = _asDouble(d['latDestino']);
                  final lonDestino = _asDouble(d['lonDestino']);

                  final precio = _asDouble(d['precio']);
                  final ganancia = _asDouble(d['gananciaTaxista']) > 0
                      ? _asDouble(d['gananciaTaxista'])
                      : precio * 0.8;
                  final fecha = formatoFecha.format(_asDate(d['fechaHora']));
                  final metodoPago = (d['metodoPago'] ?? 'Efectivo').toString();
                  final tipoServicio =
                      (d['tipoServicio'] ?? 'normal').toString();
                  final tipoVehiculo = (d['tipoVehiculo'] ?? '').toString();
                  final marca = (d['marca'] ?? '').toString();
                  final modelo = (d['modelo'] ?? '').toString();
                  final color = (d['color'] ?? '').toString();
                  final placa = (d['placa'] ?? '').toString();
                  final idaYVuelta = (d['idaYVuelta'] ?? false) == true;

                  final uidTaxistaL = (d['uidTaxista'] ?? '').toString();
                  final sinTaxista = uidTaxistaL.isEmpty;
                  final turismoSoloAdmin =
                      ViajePoolTaxistaGate.esTurismoSoloAdminPendiente(d);
                  final puedeTomarPool =
                      ViajePoolTaxistaGate.viajeTomableEnPool(d, uid);
                  final puedeTomarTurismoPool =
                      ViajePoolTaxistaGate.esTurismoPoolTomable(d);
                  final puedeTomar =
                      puedeTomarPool || puedeTomarTurismoPool;

                  final bool accionesAceptarIgnorar =
                      puedeTomar && !turismoSoloAdmin;
                  final bool aceptarHabilitado = accionesAceptarIgnorar &&
                      !_procesando &&
                      disponibleUsuario &&
                      !bloqueoDeuda &&
                      !userLoading;

                  String etiquetaBotonAceptar() {
                    if (_procesando) return 'Procesando...';
                    if (userLoading) return 'Cargando perfil…';
                    if (bloqueoDeuda) return 'Pago semanal pendiente';
                    if (!disponibleUsuario) return 'No disponible';
                    return 'Aceptar viaje';
                  }

                  String? textoBloqueoAceptar() {
                    if (!accionesAceptarIgnorar || aceptarHabilitado) return null;
                    if (userLoading) {
                      return 'Cargando tu perfil…';
                    }
                    if (bloqueoDeuda) {
                      return 'Tienes pago semanal pendiente. Regulariza para aceptar viajes del pool.';
                    }
                    if (!disponibleUsuario) {
                      return 'Activa tu disponibilidad en el menú (Disponibilidad) para aceptar este viaje.';
                    }
                    return null;
                  }

                  final waypoints = d['waypoints'] as List<dynamic>?;

          final markers = <Marker>{};
          if (latOrigen != 0 && lonOrigen != 0) {
            markers.add(
              Marker(
                markerId: const MarkerId('origen'),
                position: LatLng(latOrigen, lonOrigen),
                infoWindow: InfoWindow(title: 'Origen: $origen'),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              ),
            );
          }
          
          if (waypoints != null && waypoints.isNotEmpty) {
            for (int i = 0; i < waypoints.length; i++) {
              final w = waypoints[i] as Map<String, dynamic>;
              final double lat = _asDouble(w['lat']);
              final double lon = _asDouble(w['lon']);
              final String label = w['label']?.toString() ?? 'Parada ${i + 1}';
              
              if (lat != 0 && lon != 0) {
                markers.add(
                  Marker(
                    markerId: MarkerId('parada_$i'),
                    position: LatLng(lat, lon),
                    infoWindow: InfoWindow(title: 'Parada ${i + 1}: $label'),
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                  ),
                );
              }
            }
          }
          
          if (latDestino != 0 && lonDestino != 0) {
            markers.add(
              Marker(
                markerId: const MarkerId('destino'),
                position: LatLng(latDestino, lonDestino),
                infoWindow: InfoWindow(title: 'Destino: $destino'),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              ),
            );
          }

          final centerLat = markers.isNotEmpty 
              ? markers.map((m) => m.position.latitude).reduce((a, b) => a + b) / markers.length
              : 18.4861;
          final centerLon = markers.isNotEmpty
              ? markers.map((m) => m.position.longitude).reduce((a, b) => a + b) / markers.length
              : -69.9312;
              
          final initialCamera = CameraPosition(target: LatLng(centerLat, centerLon), zoom: 12);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: GoogleMap(
                    initialCameraPosition: initialCamera,
                    markers: markers,
                    myLocationEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: false,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.circle, color: Colors.blueAccent, size: 12),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Origen: $origen',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    
                    if (waypoints != null && waypoints.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white24, height: 1),
                      const SizedBox(height: 8),
                      const Text(
                        '📍 Paradas intermedias:',
                        style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                      ),
                      ...waypoints.asMap().entries.map((entry) {
                        final int i = entry.key + 1;
                        final Map<String, dynamic> w = entry.value as Map<String, dynamic>;
                        final String label = w['label']?.toString() ?? 'Parada $i';
                        return Padding(
                          padding: const EdgeInsets.only(left: 16, top: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.flag_circle, color: Colors.orange, size: 14),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Parada $i: $label',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 8),
                    ],
                    
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.flag, color: Colors.greenAccent, size: 12),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Destino: $destino',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Center(
                child: Text(
                  FormatosMoneda.rd(precio),
                  style: const TextStyle(
                    fontSize: 40,
                    color: Colors.yellow,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Center(
                child: Text(
                  'Ganas: ${FormatosMoneda.rd(ganancia)}',
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip('📅 $fecha'),
                  _chip('💳 $metodoPago'),
                  if (tipoServicio != 'normal') _chip('🚗 $tipoServicio'),
                  if (tipoVehiculo.isNotEmpty) _chip('🚘 $tipoVehiculo'),
                  if (marca.isNotEmpty && modelo.isNotEmpty) _chip('$marca $modelo'),
                  if (color.isNotEmpty) _chip('🎨 $color'),
                  if (placa.isNotEmpty) _chip('🔖 $placa'),
                  if (idaYVuelta) _chip('🔄 Ida y vuelta'),
                ],
              ),
              const SizedBox(height: 24),

              if (!puedeTomar && !turismoSoloAdmin)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    sinTaxista
                        ? 'Este viaje no está disponible para aceptar en este momento.'
                        : 'Este viaje ya tiene chofer asignado o está cerrado.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                )
              else if (turismoSoloAdmin)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Text(
                    'Turismo (administración): un administrador asignará el chofer. '
                    'Cuando un viaje pase al pool turístico, podrás tomarlo desde «Pool turístico».',
                    style: TextStyle(color: Colors.white70, height: 1.35),
                  ),
                )
              else ...[
                if (textoBloqueoAceptar() != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      textoBloqueoAceptar()!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _procesando
                            ? null
                            : () => _ignorarViaje(widget.viajeId),
                        icon: _procesando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.not_interested,
                                color: Colors.redAccent),
                        label: Text(
                          _procesando ? 'Procesando...' : 'No me interesa',
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (aceptarHabilitado)
                            ? () => _aceptarViaje(widget.viajeId)
                            : null,
                        icon: _procesando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle, color: Colors.green),
                        label: Text(
                          etiquetaBotonAceptar(),
                          style: TextStyle(
                            color: aceptarHabilitado
                                ? Colors.green
                                : Colors.white54,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white24,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white70)),
    );
  }
}