import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../../keys.dart' as app_keys;
import '../../servicios/gps_service.dart';
import '../../servicios/lugares_service.dart'; // <- sin "hide kGooglePlacesApiKey"
import '../../servicios/distancia_service.dart';
import '../../servicios/directions_service.dart';
import '../../data/viaje_data.dart';
import '../cliente/viaje_en_curso_cliente.dart';
import '../../utils/estilos.dart';
import '../../widgets/campo_lugar_autocomplete.dart';

class NuevoViajeMapa extends StatefulWidget {
  const NuevoViajeMapa({super.key});

  @override
  State<NuevoViajeMapa> createState() => _NuevoViajeMapaState();
}

class _NuevoViajeMapaState extends State<NuevoViajeMapa> {
  GoogleMapController? _map;
  LatLng? _miCentro;
  LatLng? _origen;
  LatLng? _destino;

  // Etiquetas legibles para Firestore (Place name / address bonita)
  String? _origenLabel;
  String? _destinoLabel;

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  double? _distKm;
  int? _durSeg;
  double? _precio;

  double? _biasLat;
  double? _biasLon;

  Timer? _debounce;

  // === GPS en tiempo real ===
  StreamSubscription<Position>? _gpsSub;
  bool _seguirMiGPS = true; // si true, la cámara sigue al usuario

  int _nuevoViajeMapProgDepth = 0;
  bool _nuevoViajeChromeHidden = false;

  void _onNuevoViajeMapCameraIdle() {
    if (_nuevoViajeMapProgDepth > 0) _nuevoViajeMapProgDepth--;
  }

  void _onNuevoViajeMapUserGesture() {
    if (_nuevoViajeMapProgDepth > 0) return;
    setState(() => _nuevoViajeChromeHidden = true);
  }

  Future<void> _nuevoViajeMapAnimate(
      Future<void> Function(GoogleMapController c) op) async {
    final GoogleMapController? c = _map;
    if (c == null) return;
    _nuevoViajeMapProgDepth++;
    try {
      await op(c);
    } catch (_) {
      if (_nuevoViajeMapProgDepth > 0) _nuevoViajeMapProgDepth--;
    }
  }

  @override
  void initState() {
    super.initState();
    _cargarUbicacionInicial().then((_) => _suscribirGPS());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _gpsSub?.cancel();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _cargarUbicacionInicial() async {
    final pos = await GpsService.obtenerUbicacionActual(
      timeout: const Duration(seconds: 8),
      maxEdadUltima: const Duration(minutes: 3),
    );
    if (!mounted) return;

    const fallback = LatLng(18.4861, -69.9312); // Santo Domingo

    setState(() {
      _miCentro = pos != null ? LatLng(pos.latitude, pos.longitude) : fallback;
      _biasLat = _miCentro!.latitude;
      _biasLon = _miCentro!.longitude;
      // Opcional: inicializar origen en mi ubicación
      _origen ??= _miCentro;
      _origenLabel ??= 'Mi ubicación';
    });
  }

  void _suscribirGPS() {
    // Configuración del stream para seguimiento suave (prefer_const_declarations)
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 8, // metros
      timeLimit: Duration(seconds: 12),
    );

    _gpsSub =
        Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);

      _miCentro = here;

      // Si aún no hay origen seleccionado, usar mi posición
      _origen ??= here;

      // Seguir cámara si está habilitado
      if (_seguirMiGPS && _map != null) {
        unawaited(_nuevoViajeMapAnimate(
          (c) => c.animateCamera(CameraUpdate.newLatLng(here)),
        ));
      }

      // Actualiza sesgo para el autocompletar
      _biasLat = here.latitude;
      _biasLon = here.longitude;

      setState(() {});
    });
  }

  void _onMapCreated(GoogleMapController c) {
    _map = c;
    if (_miCentro != null) {
      _nuevoViajeMapProgDepth++;
      try {
        c.moveCamera(CameraUpdate.newLatLngZoom(_miCentro!, 13));
      } catch (_) {
        if (_nuevoViajeMapProgDepth > 0) _nuevoViajeMapProgDepth--;
      }
    }
  }

  Future<void> _onSelectOrigen(DetalleLugar det) async {
    setState(() {
      _origen = LatLng(det.lat, det.lon);
      _origenLabel = det.displayLabel;
    });
    _updateMarkers();
    _fitBoundsIfNeeded();
    _refreshRutaConDebounce();
  }

  Future<void> _onSelectDestino(DetalleLugar det) async {
    setState(() {
      _destino = LatLng(det.lat, det.lon);
      _destinoLabel = det.displayLabel;
    });
    _updateMarkers();
    _fitBoundsIfNeeded();
    _refreshRutaConDebounce();
  }

  void _updateMarkers() {
    final m = <Marker>{};

    if (_origen != null) {
      m.add(
        Marker(
          markerId: const MarkerId('origen'),
          position: _origen!,
          infoWindow: InfoWindow(title: _origenLabel ?? 'Origen'),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          draggable: true,
          onDragEnd: (p) {
            _origen = p;
            _updateMarkers();
            _fitBoundsIfNeeded();
            _refreshRutaConDebounce();
          },
        ),
      );
    }

    if (_destino != null) {
      m.add(
        Marker(
          markerId: const MarkerId('destino'),
          position: _destino!,
          infoWindow: InfoWindow(title: _destinoLabel ?? 'Destino'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          draggable: true,
          onDragEnd: (p) {
            _destino = p;
            _updateMarkers();
            _fitBoundsIfNeeded();
            _refreshRutaConDebounce();
          },
        ),
      );
    }

    _markers
      ..clear()
      ..addAll(m);
    setState(() {});
  }

  void _fitBoundsIfNeeded() {
    if (_map == null) return;
    if (_origen == null && _destino == null) return;

    if (_origen != null && _destino != null) {
      final sw = LatLng(
        math.min(_origen!.latitude, _destino!.latitude),
        math.min(_origen!.longitude, _destino!.longitude),
      );
      final ne = LatLng(
        math.max(_origen!.latitude, _destino!.latitude),
        math.max(_origen!.longitude, _destino!.longitude),
      );
      final bounds = LatLngBounds(southwest: sw, northeast: ne);
      unawaited(_nuevoViajeMapAnimate(
        (c) => c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70)),
      ));
    } else {
      final p = _origen ?? _destino!;
      unawaited(_nuevoViajeMapAnimate(
        (c) => c.animateCamera(CameraUpdate.newLatLngZoom(p, 14)),
      ));
    }
  }

  void _refreshRutaConDebounce() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _calcularRutaYPrecio);
  }

  Future<void> _calcularRutaYPrecio() async {
    if (_origen == null || _destino == null) return;

    // 1) Intentar Directions (con tráfico)
    final dir = await DirectionsService.drivingDistanceKm(
      originLat: _origen!.latitude,
      originLon: _origen!.longitude,
      destLat: _destino!.latitude,
      destLon: _destino!.longitude,
      withTraffic: true,
      region: 'do',
    );

    double? km = dir?.km;
    int? sec = dir?.seconds;

    // 2) Fallback Haversine
    if (km == null || km <= 0) {
      km = DistanciaService.calcularDistancia(
        _origen!.latitude,
        _origen!.longitude,
        _destino!.latitude,
        _destino!.longitude,
      );
      sec = (km * 3600 / 28).round(); // ~28 km/h promedio urbano
    }

    // 3) Precio
    final precio = DistanciaService.calcularPrecio(km);

    // 4) Polyline
    final poly = await _fetchOverviewPolyline(
      _origen!.latitude,
      _origen!.longitude,
      _destino!.latitude,
      _destino!.longitude,
    );

    final polylines = <Polyline>{};
    if (poly != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: _decodePolyline(poly),
          width: 6,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _distKm = km;
      _durSeg = sec;
      _precio = precio;
      _polylines
        ..clear()
        ..addAll(polylines);
    });
  }

  Future<String?> _fetchOverviewPolyline(
    double oLat,
    double oLon,
    double dLat,
    double dLon,
  ) async {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$oLat,$oLon'
      '&destination=$dLat,$dLon'
      '&mode=driving'
      '&departure_time=now'
      '&traffic_model=best_guess'
      '&units=metric'
      '&region=do'
      '&key=${app_keys.kGooglePlacesApiKey}',
    );

    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final map = jsonDecode(body) as Map<String, dynamic>;
      final routes = (map['routes'] as List?) ?? const [];
      if (routes.isEmpty) return null;
      final route0 = routes.first as Map<String, dynamic>;
      final poly = (route0['overview_polyline'] as Map?)?['points']?.toString();
      return poly;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return poly;
  }

  String _fmtTiempo() {
    final s = _durSeg ?? 0;
    final m = (s / 60).round();
    if (m < 60) return '$m min';
    final h = m ~/ 60;
    final rm = m % 60;
    return '${h}h ${rm}m';
  }

  String _fmtKm(double? km) {
    if (km == null) return '— km';
    return '${km.toStringAsFixed(1)} km';
  }

  String _fmtRD(double? v) {
    if (v == null) return 'RD\$ 0.00';
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final re = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final intPart = parts.first.replaceAllMapped(re, (m) => '${m[1]},');
    return 'RD\$ $intPart.${parts.last}';
  }

  Future<void> _confirmarViaje() async {
    if (_origen == null || _destino == null || _precio == null) return;

    try {
      final id = await ViajeData.crearViajeCliente(
        origen: _origenLabel ?? 'Origen',
        destino: _destinoLabel ?? 'Destino',
        latCliente: _origen!.latitude,
        lonCliente: _origen!.longitude,
        latDestino: _destino!.latitude,
        lonDestino: _destino!.longitude,
        precio: _precio!,
        metodoPago: 'Efectivo', // Puedes cambiarlo desde una UI más adelante
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Viaje creado ✅ (ID: $id)')),
      );

      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const ViajeEnCursoCliente(),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear el viaje: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EstilosRai.fondoOscuro,
      appBar: AppBar(
        backgroundColor: EstilosRai.fondoOscuro,
        title: const Text('Nuevo Viaje', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Toggle para seguir la cámara al GPS
          IconButton(
            onPressed: () => setState(() => _seguirMiGPS = !_seguirMiGPS),
            icon: Icon(
              _seguirMiGPS ? Icons.gps_fixed : Icons.gps_not_fixed,
              color: Colors.white,
            ),
            tooltip: _seguirMiGPS ? 'Seguir mi GPS' : 'No seguir',
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: (_miCentro == null)
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
                    onMapCreated: _onMapCreated,
                    onCameraMove: (pos) {
                      _biasLat = pos.target.latitude;
                      _biasLon = pos.target.longitude;
                    },
                    onTap: (_) => _onNuevoViajeMapUserGesture(),
                    onCameraMoveStarted: _onNuevoViajeMapUserGesture,
                    onCameraIdle: _onNuevoViajeMapCameraIdle,
                    initialCameraPosition: CameraPosition(
                      target: _miCentro!,
                      zoom: 12.5,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    compassEnabled: true,
                    markers: _markers,
                    polylines: _polylines,
                    mapToolbarEnabled: false,
                    trafficEnabled: true,
                  ),
          ),
          if (_nuevoViajeChromeHidden)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 6,
              left: 12,
              right: 12,
              child: Material(
                color: Colors.black.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => setState(() => _nuevoViajeChromeHidden = false),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_location_alt_outlined,
                            color: Colors.white, size: 20),
                        SizedBox(width: 10),
                        Text(
                          'Mostrar origen y destino',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          AnimatedSlide(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            offset:
                _nuevoViajeChromeHidden ? const Offset(0, -1.08) : Offset.zero,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CampoLugarAutocomplete(
                      label: 'Origen',
                      hint: '¿Dónde te recogemos?',
                      country: 'DO',
                      biasLat: _biasLat,
                      biasLon: _biasLon,
                      onPlaceSelected: _onSelectOrigen,
                    ),
                    const SizedBox(height: 6),
                    CampoLugarAutocomplete(
                      label: 'Destino',
                      hint: '¿A dónde vas?',
                      country: 'DO',
                      biasLat: _biasLat,
                      biasLon: _biasLon,
                      onPlaceSelected: _onSelectDestino,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              offset:
                  _nuevoViajeChromeHidden ? const Offset(0, 1.08) : Offset.zero,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  border: const Border(top: BorderSide(color: Colors.white12)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${_fmtKm(_distKm)} • ${_fmtTiempo()}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          _fmtRD(_precio),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: (_origen != null &&
                                _destino != null &&
                                _precio != null)
                            ? _confirmarViaje
                            : null,
                        child: const Text(
                          'Confirmar viaje',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16),
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
