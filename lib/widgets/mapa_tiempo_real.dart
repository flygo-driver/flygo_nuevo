// lib/widgets/mapa_tiempo_real.dart
// Mapa en tiempo real estilo WhatsApp/inDrive: sigue tu ubicación,
// botón para volver a seguirte, long-press para marcar destino (preview con polyline).

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapaTiempoReal extends StatefulWidget {
  final LatLng? origen;           // Ubicación del cliente/pickup
  final String? origenNombre;     // Nombre del origen
  final LatLng? destino;          // Ubicación del destino final
  final String? destinoNombre;    // Nombre del destino
  final bool mostrarOrigen;       // Si debe mostrar el marcador de origen
  final bool mostrarDestino;      // Si debe mostrar el marcador de destino
  final LatLng? ubicacionTaxista; // Ubicación del taxista (para que el cliente vea)
  final bool mostrarTaxista;      // Si mostrar el marcador del taxista
  final bool esCliente;           // Si es la vista del cliente
  final bool esTaxista;           // Si es la vista del taxista

  const MapaTiempoReal({
    super.key,
    this.origen,
    this.origenNombre,
    this.destino,
    this.destinoNombre,
    this.mostrarOrigen = true,
    this.mostrarDestino = true,
    this.ubicacionTaxista,
    this.mostrarTaxista = false,
    this.esCliente = false,
    this.esTaxista = true,
  });

  @override
  State<MapaTiempoReal> createState() => _MapaTiempoRealState();
}

class _MapaTiempoRealState extends State<MapaTiempoReal> {
  GoogleMapController? _map;
  StreamSubscription<Position>? _posSub;
  Timer? _markerRefreshDebounce;

  static const LatLng _fallback = LatLng(18.4861, -69.9312); // Santo Domingo
  final Set<Marker> _markers = <Marker>{};
  final Set<Polyline> _polylines = <Polyline>{};

  bool _myLocEnabled = false;
  bool _serviceOn = true;
  bool _following = true; // si es true, la cámara te sigue
  bool _mapReady = false;

  // Antirebote de animaciones de cámara (siempre respectar; antes solo si _movingCamera y permitía spam)
  DateTime _lastAnim = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _animMinGap = const Duration(milliseconds: 650);
  LatLng? _lastCameraFollowTarget;

  LatLng? _lastLatLng;
  double _lastBearing = 0;

  LatLng? _destinoSeleccionado; // si el usuario deja presionado

  @override
  void initState() {
    super.initState();
    _iniciarUbicacion();
  }

  @override
  void didUpdateWidget(MapaTiempoReal oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool origenChanged = oldWidget.origen != widget.origen;
    final bool destinoChanged = oldWidget.destino != widget.destino;
    final bool taxiChanged = oldWidget.ubicacionTaxista != widget.ubicacionTaxista;

    // Solo re-centrar cámara cuando cambian origen/destino (puntos fijos del viaje).
    // Si solo se mueve el taxista, actualizar marcadores sin animar la cámara (evita parpadeo).
    if (origenChanged || destinoChanged) {
      _actualizarMarcadores();
      _centrarEnPuntoImportante();
      return;
    }
    if (taxiChanged && widget.mostrarTaxista) {
      _actualizarMarcadores();
    }
  }

  @override
  void dispose() {
    _markerRefreshDebounce?.cancel();
    _posSub?.cancel();
    _map?.dispose();
    super.dispose();
  }

  void _scheduleMarkerRefresh() {
    _markerRefreshDebounce?.cancel();
    _markerRefreshDebounce = Timer(const Duration(milliseconds: 100), () {
      if (mounted) _actualizarMarcadores();
    });
  }

  static double _haversineM(LatLng a, LatLng b) {
    const double R = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
    final la1 = a.latitude * math.pi / 180.0;
    final la2 = b.latitude * math.pi / 180.0;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return R * (2 * math.atan2(math.sqrt(h), math.sqrt(1 - h)));
  }

  void _centrarEnPuntoImportante() {
    if (!_mapReady || _map == null) return;
    
    LatLng target;
    
    // Prioridad: 
    // 1. Si es taxista y debe mostrar origen (cliente) -> centrar en cliente
    // 2. Si debe mostrar destino -> centrar en destino
    // 3. Si no, centrar en ubicación actual
    if (widget.esTaxista && widget.mostrarOrigen && widget.origen != null) {
      target = widget.origen!;
      _following = false;
    } else if (widget.mostrarDestino && widget.destino != null) {
      target = widget.destino!;
      _following = false;
    } else if (_lastLatLng != null) {
      target = _lastLatLng!;
      _following = true;
    } else {
      target = _fallback;
    }
    
    _animateTo(target, zoom: 16);
  }

  void _actualizarMarcadores() {
    _markers.clear();

    // Marcador del taxista (para vista de cliente)
    if (widget.mostrarTaxista && widget.ubicacionTaxista != null) {
      _markers.add(Marker(
        markerId: const MarkerId('taxista'),
        position: widget.ubicacionTaxista!,
        infoWindow: const InfoWindow(title: 'Tu taxista'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        zIndexInt: 2,
      ));
    }

    // Marcador de origen (cliente)
    if (widget.mostrarOrigen && widget.origen != null) {
      _markers.add(Marker(
        markerId: const MarkerId('origen'),
        position: widget.origen!,
        infoWindow: InfoWindow(
          title: widget.esTaxista ? 'Recoger cliente' : 'Mi ubicación',
          snippet: widget.origenNombre ?? 'Punto de recogida',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          widget.esTaxista ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueBlue
        ),
        zIndexInt: 1,
      ));
    }

    // Marcador de destino
    if (widget.mostrarDestino && widget.destino != null) {
      _markers.add(Marker(
        markerId: const MarkerId('destino'),
        position: widget.destino!,
        infoWindow: InfoWindow(
          title: 'Destino',
          snippet: widget.destinoNombre ?? 'Lugar de destino',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        zIndexInt: 1,
      ));
    }

    // Marcador de ubicación actual del usuario
    if (_lastLatLng != null) {
      _markers.add(Marker(
        markerId: const MarkerId('yo'),
        position: _lastLatLng!,
        infoWindow: InfoWindow(
          title: widget.esTaxista ? 'Mi ubicación' : 'Mi ubicación',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          widget.esTaxista ? BitmapDescriptor.hueRed : BitmapDescriptor.hueAzure
        ),
        zIndexInt: 2,
      ));
    }

    // Si hay destino seleccionado manualmente
    if (_destinoSeleccionado != null) {
      _markers.add(Marker(
        markerId: const MarkerId('destino_manual'),
        position: _destinoSeleccionado!,
        infoWindow: const InfoWindow(title: 'Destino seleccionado'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        zIndexInt: 1,
      ));
    }

    if (mounted) setState(() {});
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

    // Última posición conocida (para no empezar "frío")
    final last = await Geolocator.getLastKnownPosition();
    if (mounted && last != null) {
      final here = LatLng(last.latitude, last.longitude);
      _lastLatLng = here;
      _actualizarMarcadores();
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
      _lastLatLng = here;
      _scheduleMarkerRefresh();

      if (_following && widget.esTaxista) {
        _animateTo(
          here,
          zoom: 17,
          bearing: (pos.heading.isFinite && pos.speed > 0.5) ? pos.heading : _lastBearing,
          followMode: true,
        );
      }

      if (pos.heading.isFinite) _lastBearing = pos.heading;
    }, onError: (_) {
      if (mounted) _snack('No se pudo obtener la ubicación en vivo.');
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ====== Cámara / animaciones ======
  Future<void> _animateTo(
    LatLng p, {
    double? zoom,
    double? tilt,
    double? bearing,
    bool followMode = false,
  }) async {
    final c = _map;
    if (c == null || !_mapReady) return;

    final now = DateTime.now();

    if (!followMode) {
      _lastCameraFollowTarget = null;
    }

    final sinceAnim = now.difference(_lastAnim);
    if (sinceAnim < _animMinGap) {
      if (!followMode) return;
      if (_lastCameraFollowTarget != null &&
          _haversineM(_lastCameraFollowTarget!, p) < 22.0) {
        return;
      }
    }

    try {
      await c.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: p,
          zoom: zoom ?? 16,
          tilt: tilt ?? 0,
          bearing: (bearing ?? 0) % 360,
        ),
      ));
      _lastAnim = DateTime.now();
      if (followMode) _lastCameraFollowTarget = p;
    } catch (_) {
      try {
        c.moveCamera(CameraUpdate.newLatLngZoom(p, zoom ?? 16));
        _lastAnim = DateTime.now();
        if (followMode) _lastCameraFollowTarget = p;
      } catch (_) {}
    }
  }

  Future<void> _fitTo(LatLng a, LatLng b) async {
    final c = _map;
    if (c == null || !_mapReady) return;
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
    _destinoSeleccionado = p;
    _actualizarMarcadores();
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

  // Métodos públicos para controlar la cámara desde fuera
  Future<void> centrarEnOrigen() async {
    if (widget.origen != null && _mapReady) {
      setState(() => _following = false);
      await _animateTo(widget.origen!, zoom: 17);
    }
  }

  Future<void> centrarEnDestino() async {
    final destino = _destinoSeleccionado ?? widget.destino;
    if (destino != null && _mapReady) {
      setState(() => _following = false);
      await _animateTo(destino, zoom: 17);
    }
  }

  Future<void> centrarEnMiUbicacion() async {
    if (_lastLatLng != null && _mapReady) {
      setState(() => _following = true);
      await _animateTo(_lastLatLng!, zoom: 17);
    }
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: const CameraPosition(target: _fallback, zoom: 12),
            onMapCreated: (ctrl) {
              _map = ctrl;
              _mapReady = true;
              // Centrar en el punto importante después de crear el mapa
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _centrarEnPuntoImportante();
              });
            },
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF1C1F23),
                borderRadius: BorderRadius.all(Radius.circular(10)),
                border: Border.fromBorderSide(BorderSide(color: Color(0x5949F18B))),
              ),
              child: Row(
                children: [
                  Icon(!_serviceOn ? Icons.location_off : Icons.privacy_tip_outlined, color: const Color(0xFF49F18B)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      !_serviceOn ? 'Activa la ubicación del dispositivo' : 'Da permiso de ubicación a la app',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
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
                onPressed: centrarEnMiUbicacion,
                child: Icon(_following ? Icons.navigation : Icons.my_location),
              ),
              const SizedBox(height: 10),
              // Botón centrar en origen (solo para taxista)
              if (widget.esTaxista && widget.origen != null && widget.mostrarOrigen)
                FloatingActionButton(
                  heroTag: 'center_origen',
                  mini: true,
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  onPressed: centrarEnOrigen,
                  child: const Icon(Icons.location_on),
                ),
              const SizedBox(height: 10),
              // Botón centrar en destino
              if ((widget.destino != null && widget.mostrarDestino) || _destinoSeleccionado != null)
                FloatingActionButton(
                  heroTag: 'center_destino',
                  mini: true,
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  onPressed: centrarEnDestino,
                  child: const Icon(Icons.flag),
                ),
              const SizedBox(height: 10),
              if (_destinoSeleccionado != null)
                FloatingActionButton(
                  heroTag: 'clear_dest',
                  mini: true,
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  onPressed: () {
                    setState(() {
                      _destinoSeleccionado = null;
                      _polylines.clear();
                      _actualizarMarcadores();
                    });
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