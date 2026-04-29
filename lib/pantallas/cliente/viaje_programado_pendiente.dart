import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';

class ViajeProgramadoPendiente extends StatefulWidget {
  final String viajeId;

  const ViajeProgramadoPendiente({
    super.key,
    required this.viajeId,
  });

  @override
  State<ViajeProgramadoPendiente> createState() =>
      _ViajeProgramadoPendienteState();
}

class _ViajeProgramadoPendienteState extends State<ViajeProgramadoPendiente> {
  bool _navegando = false;
  bool _cancelando = false;

  bool _taxistaAsignado(Map<String, dynamic> data) {
    final String uidTaxista = (data['uidTaxista'] ?? '').toString().trim();
    final String taxistaId = (data['taxistaId'] ?? '').toString().trim();
    return uidTaxista.isNotEmpty || taxistaId.isNotEmpty;
  }

  /// Turismo solo ADM no sigue el pool público: hasta asignación no pasamos al mapa por ventana.
  bool _esBusquedaPoolClienteNormal(Map<String, dynamic> data) {
    final String tipo = (data['tipoServicio'] ?? 'normal').toString();
    final String canal = (data['canalAsignacion'] ?? 'pool').toString();
    if (tipo == 'turismo' && canal == 'admin') return false;
    return true;
  }

  bool _poolYaVisibleParaConductores(Map<String, dynamic> data) {
    if (!_esBusquedaPoolClienteNormal(data)) return false;
    return ViajePoolTaxistaGate.ventanaPublicacionYAceptacionOk(data);
  }

  String? _etaAsignacion(Map<String, dynamic> data) {
    final latTx = (data['latTaxista'] is num)
        ? (data['latTaxista'] as num).toDouble()
        : ((data['driverLat'] is num)
            ? (data['driverLat'] as num).toDouble()
            : null);
    final lonTx = (data['lonTaxista'] is num)
        ? (data['lonTaxista'] as num).toDouble()
        : ((data['driverLon'] is num)
            ? (data['driverLon'] as num).toDouble()
            : null);
    final latCli =
        (data['latCliente'] is num) ? (data['latCliente'] as num).toDouble() : null;
    final lonCli =
        (data['lonCliente'] is num) ? (data['lonCliente'] as num).toDouble() : null;

    bool valid(double? lat, double? lon) =>
        lat != null &&
        lon != null &&
        lat.isFinite &&
        lon.isFinite &&
        lat.abs() <= 90 &&
        lon.abs() <= 180 &&
        !(lat == 0 && lon == 0);

    if (!valid(latTx, lonTx) || !valid(latCli, lonCli)) return null;

    final km = DistanciaService.calcularDistancia(latTx!, lonTx!, latCli!, lonCli!);
    if (!km.isFinite || km <= 0) return null;
    // Estimacion simple urbana.
    final minutos = (km / 28 * 60).clamp(1, 90).round();
    return 'Conductor asignado. ETA aproximado: $minutos min';
  }

  Future<void> _volverInicio() async {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil('/auth_check', (route) => false);
  }

  /// Misma condición que [ViajesRepo.cancelarPorCliente] (evita botón activo si Firestore rechazaría).
  bool _cancelablePorClienteSegunRepo(String estadoRaw) {
    final String n = EstadosViaje.normalizar(estadoRaw);
    if (n == EstadosViaje.completado || n == EstadosViaje.cancelado) {
      return false;
    }
    if (EstadosViaje.esEstadoSinCancelacionApp(estadoRaw)) return false;
    return n == EstadosViaje.pendiente ||
        n == EstadosViaje.pendientePago ||
        n == EstadosViaje.aceptado ||
        n == EstadosViaje.enCaminoPickup;
  }

  Future<void> _cancelarViajeProgramado() async {
    if (_cancelando) return;
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    setState(() => _cancelando = true);
    try {
      await ViajesRepo.cancelarPorCliente(
        viajeId: widget.viajeId,
        uidCliente: uid,
        motivo: 'Cancelado por cliente desde pendiente programado',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Viaje programado cancelado.')),
      );
      await _volverInicio();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar el viaje: $e')),
      );
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docRef =
        FirebaseFirestore.instance.collection('viajes').doc(widget.viajeId);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0F12),
        elevation: 0,
        title: const Text('Viaje programado'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            );
          }

          if (!snap.hasData || !snap.data!.exists) {
            return const Center(
              child: Text(
                'No se encontro el viaje programado.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          final data = snap.data!.data() ?? <String, dynamic>{};
          final String estado = (data['estado'] ?? '').toString();
          final bool asignado = _taxistaAsignado(data);
          final String? etaAsignado = _etaAsignacion(data);
          final bool estadoCancelable = _cancelablePorClienteSegunRepo(estado);

          final bool poolAbierto = _poolYaVisibleParaConductores(data);
          final bool irAlMapa = asignado || poolAbierto;

          if (irAlMapa && !_navegando) {
            _navegando = true;
            final bool avisarPool = poolAbierto && !asignado;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              if (avisarPool) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Tu viaje ya está disponible para conductores cercanos.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              await Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(
                  builder: (_) => const ViajeEnCursoCliente(),
                ),
                (route) => false,
              );
            });
          }

          return SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171A20),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x44000000),
                        blurRadius: 22,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.95, end: 1.05),
                        duration: const Duration(milliseconds: 1200),
                        curve: Curves.easeInOut,
                        builder: (_, scale, child) => Transform.scale(
                          scale: scale,
                          child: child,
                        ),
                        onEnd: () {
                          if (mounted) setState(() {});
                        },
                        child: const Icon(
                          Icons.schedule_rounded,
                          size: 58,
                          color: Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Viaje programado confirmado',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 21,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        poolAbierto
                            ? 'Redirigiendo al mapa: tu viaje ya está en la red de conductores.'
                            : 'Tu reserva está guardada. Cuando llegue la hora de publicación, los conductores podrán verla y te avisamos aquí.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(
                        color: Colors.greenAccent,
                        strokeWidth: 3,
                      ),
                      if (etaAsignado != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          etaAsignado,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        'Estado actual: ${estado.isEmpty ? 'pendiente' : estado}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        poolAbierto
                            ? 'Buscando conductor cercano en el mapa…'
                            : 'Te avisamos cuando tu viaje entre al pool y cuando un conductor lo acepte.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _volverInicio,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          icon: const Icon(Icons.home_outlined),
                          label: const Text('Volver al inicio'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (!estadoCancelable ||
                                  _cancelando ||
                                  asignado)
                              ? null
                              : _cancelarViajeProgramado,
                          icon: _cancelando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.cancel_outlined),
                          label: Text(
                            _cancelando
                                ? 'Cancelando...'
                                : 'Cancelar viaje programado',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB42318),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
