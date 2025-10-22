// lib/widgets/mapa_tiempo_real.dart
// Mapa en tiempo real estilo WhatsApp/inDrive: sigue tu ubicación,
// botón para volver a seguirte, long-press para marcar destino (preview con polyline).

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapaTiempoReal extends StatefulWidget {
  const MapaTiempoReal({super.key});

  @override
  State<MapaTiempoReal> createState() => _MapaTiempoRealState();
}

class _MapaTiempoRealState extends State<MapaTiempoReal> {
  GoogleMapController? _map;
  StreamSubscription<Position>? _posSub;

  static const LatLng _fallback = LatLng(18.4861, -69.9312); // Santo Domingo
  final Set<Marker> _markers = <Marker>{};
  final Set<Polyline> _polylines = <Polyline>{};

  bool _myLocEnabled = false;
  bool _serviceOn = true;
  bool _following = true; // si es true, la cámara te sigue
  bool _movingCamera = false;

  // Antirebote de animaciones de cámara
  DateTime _lastAnim = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _animMinGap = const Duration(milliseconds: 550);

  LatLng? _lastLatLng;
  double _lastBearing = 0;

  LatLng? _destino; // si el usuario deja presionado

  @override
  void initState() {
    super.initState();
    _iniciarUbicacion();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _iniciarUbicacion() async {
    _serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!_serviceOn && mounted) {
      _snack('Activa la ubicación del dispositivo.');
    }

    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (!mounted) return;

    final denied = p == LocationPermission.denied || p == LocationPermission.deniedForever;
    setState(() => _myLocEnabled = !denied);
    if (denied) return;

    // Última posición conocida (para no empezar “frío”)
    final last = await Geolocator.getLastKnownPosition();
    if (mounted && last != null) {
      final here = LatLng(last.latitude, last.longitude);
      _putSelfMarker(here);
      _animateTo(here, zoom: 16, bearing: last.heading);
      _lastLatLng = here;
      if (last.heading.isFinite) _lastBearing = last.heading;
    }

    // Stream de ubicación en vivo
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      final here = LatLng(pos.latitude, pos.longitude);
      _putSelfMarker(here);

      if (_following) {
        _animateTo(
          here,
          zoom: 17,
          bearing: (pos.heading.isFinite && pos.speed > 0.5) ? pos.heading : _lastBearing,
        );
      }

      _lastLatLng = here;
      if (pos.heading.isFinite) _lastBearing = pos.heading;
    }, onError: (_) {
      if (mounted) _snack('No se pudo obtener la ubicación en vivo.');
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ====== Marcadores ======
  void _putSelfMarker(LatLng p) {
    _markers
      ..removeWhere((m) => m.markerId.value == 'yo')
      ..add(Marker(
        markerId: const MarkerId('yo'),
        position: p,
        infoWindow: const InfoWindow(title: 'Mi ubicación'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        // usa int (no double) para evitar el warning
        zIndexInt: 2,
      ));
    if (mounted) setState(() {});
  }

  void _putDestinoMarker(LatLng p) {
    _markers
      ..removeWhere((m) => m.markerId.value == 'destino')
      ..add(Marker(
        markerId: const MarkerId('destino'),
        position: p,
        infoWindow: const InfoWindow(title: 'Destino'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        zIndexInt: 1,
      ));
    if (mounted) setState(() {});
  }

  // ====== Cámara / animaciones ======
  Future<void> _animateTo(LatLng p, {double? zoom, double? tilt, double? bearing}) async {
    final c = _map;
    if (c == null) return;

    final now = DateTime.now();
    if (now.difference(_lastAnim) < _animMinGap && _movingCamera) return;

    _movingCamera = true;
    try {
      await c.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: p,
          zoom: zoom ?? 16,
          tilt: tilt ?? 0,
          bearing: (bearing ?? 0) % 360,
        ),
      ));
      _lastAnim = now;
    } catch (_) {
      try {
        c.moveCamera(CameraUpdate.newLatLngZoom(p, zoom ?? 16));
      } catch (_) {}
    } finally {
      _movingCamera = false;
    }
  }

  Future<void> _fitTo(LatLng a, LatLng b) async {
    final c = _map;
    if (c == null) return;
    final bounds = _boundsFrom(a, b);
    try {
      await c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    } catch (_) {
      // segundo intento (algunas veces falla si aún no pintó el mapa)
      await Future.delayed(const Duration(milliseconds: 120));
      try {
        await c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
      } catch (_) {}
    }
  }

  LatLngBounds _boundsFrom(LatLng a, LatLng b) {
    final southWest = LatLng(
      math.min(a.latitude, b.latitude),
      math.min(a.longitude, b.longitude),
    );
    final northEast = LatLng(
      math.max(a.latitude, b.latitude),
      math.max(a.longitude, b.longitude),
    );
    return LatLngBounds(southwest: southWest, northeast: northEast);
  }

  // ====== Interacciones ======
  void _onUserGesture() {
    if (_following) setState(() => _following = false);
  }

  Future<void> _onLongPress(LatLng p) async {
    _destino = p;
    _putDestinoMarker(p);
    final me = _lastLatLng ?? _fallback;

    _polylines
      ..clear()
      ..add(Polyline(
        polylineId: const PolylineId('preview'),
        points: [me, p],
        width: 5,
        color: const Color(0xFF49F18B),
        geodesic: true,
      ));
    setState(() {});
    await _fitTo(me, p);
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: const CameraPosition(target: _fallback, zoom: 12),
            onMapCreated: (ctrl) => _map = ctrl,
            myLocationEnabled: _myLocEnabled,
            myLocationButtonEnabled: false,
            compassEnabled: true,
            zoomControlsEnabled: false,
            rotateGesturesEnabled: true,
            markers: _markers,
            polylines: _polylines,
            onLongPress: _onLongPress,
            onCameraMoveStarted: _onUserGesture,
            onTap: (_) => _onUserGesture(),
            mapToolbarEnabled: false,
          ),
        ),

        // Banner si falta servicio/permisos
        if (!_serviceOn || !_myLocEnabled)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: _Banner(
              text: !_serviceOn
                  ? 'Activa la ubicación del dispositivo'
                  : 'Da permiso de ubicación a la app',
              icon: !_serviceOn ? Icons.location_off : Icons.privacy_tip_outlined,
            ),
          ),

        // Botones flotantes: seguirme / limpiar destino
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'follow_me',
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                onPressed: () async {
                  if (!_myLocEnabled) return;
                  setState(() => _following = true);
                  final pos = await Geolocator.getCurrentPosition(
                    desiredAccuracy: LocationAccuracy.bestForNavigation,
                  );
                  final here = LatLng(pos.latitude, pos.longitude);
                  _putSelfMarker(here);
                  await _animateTo(
                    here,
                    zoom: 17,
                    bearing: (pos.heading.isFinite && pos.speed > 0.5) ? pos.heading : _lastBearing,
                  );
                },
                child: Icon(_following ? Icons.navigation : Icons.my_location),
              ),
              const SizedBox(height: 10),
              if (_destino != null)
                FloatingActionButton(
                  heroTag: 'clear_dest',
                  mini: true,
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  onPressed: () {
                    _destino = null;
                    _polylines.clear();
                    _markers.removeWhere((m) => m.markerId.value == 'destino');
                    setState(() {});
                  },
                  child: const Icon(Icons.clear),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Banner({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1F23),
        borderRadius: BorderRadius.all(Radius.circular(10)),
        border: Border.fromBorderSide(BorderSide(color: Color(0x5949F18B))),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF49F18B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
