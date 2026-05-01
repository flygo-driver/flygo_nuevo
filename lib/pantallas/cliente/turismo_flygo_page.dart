// lib/pantallas/cliente/turismo_flygo_page.dart
// Pantalla Turismo RAI: mapa + panel tipo Uber/inDrive

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flygo_nuevo/pantallas/cliente/programar_viaje.dart';
import 'package:flygo_nuevo/widgets/auto_trip_router.dart';

class TurismoRaiPage extends StatefulWidget {
  const TurismoRaiPage({super.key});

  @override
  State<TurismoRaiPage> createState() => _TurismoRaiPageState();
}

class _TurismoRaiPageState extends State<TurismoRaiPage> {
  // ===== MAPA / GPS =====
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  StreamSubscription<Position>? _posSub;

  // SDQ por defecto
  LatLng _center = const LatLng(18.4861, -69.9312);
  bool _cargandoUbicacion = true;
  bool _permisoNegadoForever = false;

  int _turismoMapProgCameraDepth = 0;
  bool _turismoPanelHidden = false;
  Timer? _turismoMapGestureEndDebounce;

  void _onTurismoMapCameraIdle() {
    if (_turismoMapProgCameraDepth > 0) {
      _turismoMapProgCameraDepth--;
      return;
    }
    _turismoMapGestureEndDebounce?.cancel();
    if (mounted) setState(() => _turismoPanelHidden = false);
  }

  void _onTurismoMapUserGesture() {
    if (_turismoMapProgCameraDepth > 0) return;
    setState(() => _turismoPanelHidden = true);
  }

  Future<void> _turismoMapAnimate(
      Future<void> Function(GoogleMapController c) op) async {
    final GoogleMapController? c = _mapController;
    if (c == null) return;
    _turismoMapProgCameraDepth++;
    try {
      await op(c);
    } catch (_) {
      if (_turismoMapProgCameraDepth > 0) _turismoMapProgCameraDepth--;
    }
  }

  // ===== TURISMO: tipo seleccionado =====
  String _tipoSeleccionado = 'Aeropuerto ↔ Hotel';

  final List<String> _opciones = const [
    'Aeropuerto ↔ Hotel',
    'Hotel / Resort',
    'Playa / Tour',
    'Bar / Restaurante',
    'Eventos / Conciertos',
  ];

  @override
  void initState() {
    super.initState();
    _initUbicacion();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _turismoMapGestureEndDebounce?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ================== UBICACIÓN / MAPA ==================
  Future<void> _initUbicacion() async {
    setState(() {
      _cargandoUbicacion = true;
      _permisoNegadoForever = false;
    });

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (!mounted) return;

    if (perm == LocationPermission.deniedForever) {
      setState(() {
        _permisoNegadoForever = true;
        _cargandoUbicacion = false;
      });
      return;
    }

    if (perm == LocationPermission.denied) {
      // Sin permiso, pero no forever
      setState(() {
        _cargandoUbicacion = false;
        _permisoNegadoForever = false;
      });
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      if (!mounted) return;

      final here = LatLng(pos.latitude, pos.longitude);

      setState(() {
        _center = here;
        _markers
          ..clear()
          ..add(
            Marker(
              markerId: const MarkerId('yo'),
              position: here,
              infoWindow: const InfoWindow(title: 'Estás aquí'),
            ),
          );
        _cargandoUbicacion = false;
      });

      if (_mapController != null) {
        await _turismoMapAnimate(
          (c) => c.animateCamera(CameraUpdate.newLatLngZoom(here, 14)),
        );
      }

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 10,
        ),
      ).listen((p) {
        if (!mounted) return;
        final ll = LatLng(p.latitude, p.longitude);
        setState(() {
          _center = ll;
          _markers
            ..removeWhere((m) => m.markerId.value == 'yo')
            ..add(
              Marker(
                markerId: const MarkerId('yo'),
                position: ll,
                infoWindow: const InfoWindow(title: 'Estás aquí'),
              ),
            );
        });
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargandoUbicacion = false;
      });
    }
  }

  Future<void> _centrarEnMiUbicacion() async {
    if (_mapController == null) return;
    await _turismoMapAnimate(
      (c) => c.animateCamera(CameraUpdate.newLatLngZoom(_center, 14)),
    );
  }

  // ================== NAVEGACIÓN A PROGRAMAR_VIAJE ==================
  void _irSolicitarAhora() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ClienteTripRouter(
          child: ProgramarViaje(modoAhora: true),
        ),
      ),
    );
  }

  void _irProgramarViaje() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ClienteTripRouter(
          child: ProgramarViaje(modoAhora: false),
        ),
      ),
    );
  }

  // ================== UI ==================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
              return;
            }
            await Navigator.of(context, rootNavigator: true).maybePop();
          },
        ),
        centerTitle: true,
        title: const Text(
          'Turismo RAI',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Stack(
        children: [
          // ===== MAPA DE FONDO =====
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _center,
                zoom: 12,
              ),
              onMapCreated: (c) => _mapController = c,
              onTap: (_) {
                if (_turismoMapProgCameraDepth > 0) return;
                _onTurismoMapUserGesture();
                _turismoMapGestureEndDebounce?.cancel();
                _turismoMapGestureEndDebounce = Timer(
                  const Duration(milliseconds: 420),
                  () {
                    if (mounted) setState(() => _turismoPanelHidden = false);
                  },
                );
              },
              onCameraMoveStarted: _onTurismoMapUserGesture,
              onCameraIdle: _onTurismoMapCameraIdle,
              markers: _markers,
              myLocationEnabled: !_permisoNegadoForever,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: true,
              mapToolbarEnabled: false,
            ),
          ),

          // Banner de estado de ubicación
          if (_cargandoUbicacion)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: const _BannerTurismo(
                icon: Icons.location_searching,
                text: 'Ubicando tu posición para turismo…',
              ),
            )
          else if (_permisoNegadoForever)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: const _BannerTurismo(
                icon: Icons.location_off,
                text: 'Activa la ubicación en Ajustes del sistema.',
              ),
            ),

          // FAB para centrar en mi ubicación
          Positioned(
            right: 16,
            bottom: 210,
            child: FloatingActionButton(
              heroTag: 'fab_turismo_center',
              mini: true,
              backgroundColor: const Color(0xFF1E1E1E),
              onPressed: _centrarEnMiUbicacion,
              child: const Icon(Icons.my_location, color: Colors.white),
            ),
          ),

          if (_turismoPanelHidden)
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: SafeArea(
                child: Center(
                  child: Material(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      onTap: () => setState(() => _turismoPanelHidden = false),
                      borderRadius: BorderRadius.circular(24),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.keyboard_arrow_up_rounded,
                                color: Colors.white, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Opciones turismo',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ===== PANEL TURISMO (tipo RAI / Driver) =====
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              offset: _turismoPanelHidden ? const Offset(0, 1.12) : Offset.zero,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 18,
                      offset: Offset(0, -4),
                    ),
                  ],
                  border: Border.all(
                      color: const Color(0xFF49F18B).withValues(alpha: 0.4)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    const Text(
                      'Turismo RAI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Traslados de aeropuerto, hoteles, playas, eventos y más.',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Chips de tipo de turismo
                    const Text(
                      '¿Qué tipo de servicio turístico necesitas?',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _opciones.map((op) {
                        final activo = op == _tipoSeleccionado;
                        return ChoiceChip(
                          label: Text(
                            op,
                            style: TextStyle(
                              color: activo ? Colors.black : Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          selected: activo,
                          selectedColor: const Color(0xFF49F18B),
                          backgroundColor: const Color(0xFF111827),
                          onSelected: (_) {
                            setState(() => _tipoSeleccionado = op);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Botón principal: Solicitar ahora
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _irSolicitarAhora,
                        icon: const Icon(Icons.local_taxi),
                        label: const Text('Solicitar ahora (Turismo)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF49F18B),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Botón secundario: Programar viaje
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _irProgramarViaje,
                        icon: const Icon(Icons.schedule_outlined),
                        label: const Text('Programar viaje turístico'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFF49F18B)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Banner superior de estado de ubicación =====
class _BannerTurismo extends StatelessWidget {
  final String text;
  final IconData icon;

  const _BannerTurismo({
    required this.text,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1F23),
        borderRadius: BorderRadius.all(Radius.circular(10)),
        border: Border.fromBorderSide(
          BorderSide(color: Color(0x5949F18B)),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF49F18B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Alias por compatibilidad con rutas o imports antiguos; preferir [TurismoRaiPage].
typedef TurismoFlyGoPage = TurismoRaiPage;
