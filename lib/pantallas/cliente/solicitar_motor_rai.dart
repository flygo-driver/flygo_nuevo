// ✅ Pantalla Motor estilo Uber/RAI: mapa + bottom sheet + destino + calcular + confirmar
// ✅ NO rompe Firestore: usa ViajesRepo.crearViajePendiente igual que tu flujo
// ✅ tipoVehiculo fijo = "Motor" (normal)
// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flygo_nuevo/widgets/cliente_drawer.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';

import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/permisos_service.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/tarifa_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';

import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/widgets/campo_lugar_autocomplete.dart';
import 'package:flygo_nuevo/widgets/cotizacion_precio_loading.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart'; // DetalleLugar

// ===== Flags =====
const bool kUsePlacesAutocomplete = true;
const bool kUseDirectionsForDistance = true;

// ===== Mensajes =====
const String kMsgLogin = 'Debes iniciar sesión para continuar.';
const String kMsgCalcFirst = 'Debes calcular el precio primero.';

// ===== Motor fijo =====
const String kVehiculoMotor = 'Motor';
const int kAcceptLeadMinutes = 120;

class SolicitarMotorRai extends StatefulWidget {
  const SolicitarMotorRai({super.key});

  @override
  State<SolicitarMotorRai> createState() => _SolicitarMotorRaiState();
}

class _SolicitarMotorRaiState extends State<SolicitarMotorRai>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Campos
  String destino = '';
  String metodoPago = 'Efectivo';
  bool idaYVuelta = false;

  // Coordenadas
  double? latCliente;
  double? lonCliente;
  double? latDestino;
  double? lonDestino;

  // Textos
  String origenTexto = '';
  String destinoTexto = '';

  // Autocomplete
  DetalleLugar? _destinoDet;

  // Estado
  bool _cargando = false;
  bool ubicacionObtenida = false;
  double distanciaKm = 0.0;

  // Precios
  double precioCalculado = 0.0;

  // Mapa
  GoogleMapController? _map;
  LatLng? _origenMap;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  bool _locPermDeniedForever = false;
  bool _cargandoUbicacion = true;

  /// Invalida cotizaciones async en curso (p. ej. borrar destino con la X).
  int _cotizacionSeq = 0;

  bool _vistaResumenCotizada = false;

  // Live GPS
  StreamSubscription<Position>? _posSub;
  bool _didCenterOnce = false;

  // Bottom sheet
  final DraggableScrollableController _sheetCtrl =
      DraggableScrollableController();

  // Nudge
  late final AnimationController _nudgeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<Offset> _nudgeOffset = Tween<Offset>(
    begin: const Offset(0, .15),
    end: const Offset(0, -0.05),
  ).animate(CurvedAnimation(parent: _nudgeCtrl, curve: Curves.easeInOut));
  Timer? _nudgeTimer;

  @override
  void initState() {
    super.initState();
    _initUbicacionParaMapa();

    WidgetsBinding.instance.addPostFrameCallback((_) => _expandSheet());
    _nudgeCtrl.repeat(reverse: true);
    _nudgeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _nudgeCtrl.stop();
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _nudgeTimer?.cancel();
    _nudgeCtrl.dispose();
    super.dispose();
  }

  Future<void> _expandSheet() async {
    try {
      await _sheetCtrl.animateTo(
        0.86,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  Future<void> _expandToMax() async {
    try {
      await _sheetCtrl.animateTo(
        0.88,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    } catch (_) {}
  }

  bool get _mostrarResumenMotor =>
      _vistaResumenCotizada &&
      ubicacionObtenida &&
      precioCalculado > 0 &&
      !_cargando;

  void _animarSheetResumenMotor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _sheetCtrl.animateTo(
          0.54,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
    });
  }

  void _abrirFormularioCompletoMotor() {
    setState(() => _vistaResumenCotizada = false);
    _expandToMax();
  }

  // ==========================
  // UBICACIÓN / MAPA
  // ==========================
  Future<void> _initUbicacionParaMapa() async {
    setState(() => _cargandoUbicacion = true);

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      setState(() {
        _locPermDeniedForever = true;
        _cargandoUbicacion = false;
      });
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final here = LatLng(pos.latitude, pos.longitude);
      _origenMap = here;
      _updateOrigenMarker(here);

      setState(() => _cargandoUbicacion = false);

      await _map?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: here, zoom: 15),
        ),
      );
      _didCenterOnce = true;

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 8,
        ),
      ).listen((p) {
        final ll = LatLng(p.latitude, p.longitude);
        _origenMap = ll;
        _updateOrigenMarker(ll);

        if (_map != null && _didCenterOnce) {
          _map!.animateCamera(CameraUpdate.newLatLng(ll));
        }
        if (mounted) setState(() {});
      });
    } catch (_) {
      setState(() => _cargandoUbicacion = false);
    }
  }

  void _updateOrigenMarker(LatLng pos) {
    _markers.removeWhere((m) => m.markerId.value == 'origen');
    _markers.add(
      Marker(
        markerId: const MarkerId('origen'),
        position: pos,
        infoWindow: const InfoWindow(title: 'Tu ubicación'),
        zIndexInt: 2,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _centrarEnMiUbicacion() async {
    if (_origenMap == null) return;
    _didCenterOnce = true;
    await _map?.animateCamera(CameraUpdate.newLatLng(_origenMap!));
  }

  void _invalidarCotizacionMotor() {
    _cotizacionSeq++;
    precioCalculado = 0;
    ubicacionObtenida = false;
    distanciaKm = 0;
    _cargando = false;
    _vistaResumenCotizada = false;
  }

  Future<void> _onLongPressMap(LatLng p) async {
    latDestino = p.latitude;
    lonDestino = p.longitude;
    _destinoDet = null;
    if (mounted) {
      setState(_invalidarCotizacionMotor);
    }

    _markers.removeWhere((m) => m.markerId.value == 'destino');
    _markers.add(
      Marker(
        markerId: const MarkerId('destino'),
        position: p,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Destino'),
        zIndexInt: 1,
      ),
    );

    final placemarks = await _safePlacemark(p.latitude, p.longitude);
    destinoTexto = placemarks.isNotEmpty
        ? _direccionBonitaRD(placemarks.first)
        : '(${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)})';
    destino = destinoTexto;

    if (_origenMap != null) {
      await _dibujarRutaReal(
        oLat: _origenMap!.latitude,
        oLon: _origenMap!.longitude,
        dLat: p.latitude,
        dLon: p.longitude,
        previewOnly: true,
      );
    } else {
      _polylines.clear();
    }

    if (mounted) setState(() {});
  }

  // ==========================
  // HELPERS GEOCODING
  // ==========================
  Future<List<Placemark>> _safePlacemark(double lat, double lon) async {
    try {
      return await placemarkFromCoordinates(lat, lon);
    } catch (_) {
      return const <Placemark>[];
    }
  }

  String _normalizarRD(String x) {
    var s = x.trim();
    if (s.isEmpty) return s;

    s = s
        .replaceAll(
          RegExp(r'\bSto\.?\s*Dgo\.?\b', caseSensitive: false),
          'Santo Domingo',
        )
        .replaceAll(RegExp(r'Higuey', caseSensitive: false), 'Higüey')
        .replaceAll(
          RegExp(r'San Pedro de Macoris', caseSensitive: false),
          'San Pedro de Macorís',
        )
        .replaceAll(
          RegExp(r'Santo Domingo D\.?N\.?', caseSensitive: false),
          'Santo Domingo',
        )
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    final tienePais = RegExp(
      r'(Rep(ú|u)blica Dominicana|RD|Dominican Republic)',
      caseSensitive: false,
    ).hasMatch(s);

    if (!tienePais) s = '$s, República Dominicana';
    return s;
  }

  Future<({double lat, double lon})?> _geocodeConFallback(String query) async {
    final intentos = <String>{
      query.trim(),
      _normalizarRD(query),
      '${query.trim()}, RD',
      '${query.trim()}, Dominican Republic',
    }.where((e) => e.isNotEmpty).toList();

    for (final q in intentos) {
      try {
        final results = await locationFromAddress(q);
        if (results.isNotEmpty) {
          final p = results.first;
          return (lat: p.latitude, lon: p.longitude);
        }
      } catch (_) {}
    }
    return null;
  }

  String _direccionBonitaRD(Placemark p) {
    final calle = [
      (p.thoroughfare ?? '').trim(),
      (p.subThoroughfare ?? '').trim(),
    ].where((s) => s.isNotEmpty).join(' ').trim();

    final sector = (p.subLocality ?? '').trim();
    final ciudad = ((p.locality ?? '').trim().isNotEmpty
            ? p.locality!.trim()
            : (p.subAdministrativeArea ?? '').trim())
        .trim();
    final prov = (p.administrativeArea ?? '').trim();
    final pais = (p.country ?? '').trim();

    final partes = <String>[
      if (calle.isNotEmpty) calle,
      if (sector.isNotEmpty) sector,
      if (ciudad.isNotEmpty) ciudad,
      if (prov.isNotEmpty) prov,
      if (pais.isNotEmpty) pais,
    ];
    return partes.join(', ');
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ==========================
  // RUTA PREVIEW
  // ==========================
  Future<void> _dibujarRutaReal({
    required double oLat,
    required double oLon,
    required double dLat,
    required double dLon,
    bool previewOnly = false,
  }) async {
    try {
      final dir = await DirectionsService.drivingDistanceKm(
        originLat: oLat,
        originLon: oLon,
        destLat: dLat,
        destLon: dLon,
        withTraffic: true,
        region: 'do',
      );
      if (dir == null) return;

      final List<LatLng> pts = dir.path ?? const <LatLng>[];
      setState(() {
        _polylines
          ..clear()
          ..add(
            Polyline(
              polylineId: const PolylineId('ruta'),
              points: pts.isNotEmpty
                  ? pts
                  : [LatLng(oLat, oLon), LatLng(dLat, dLon)],
              width: 5,
              color: const Color(0xFF49F18B),
              geodesic: true,
            ),
          );
      });

      if (_map != null) {
        if (pts.length >= 2) {
          await _map!.animateCamera(
            CameraUpdate.newLatLngBounds(_boundsFromList(pts), 60),
          );
        } else {
          await _map!.animateCamera(
            CameraUpdate.newLatLngBounds(
              _boundsFrom(LatLng(oLat, oLon), LatLng(dLat, dLon)),
              80,
            ),
          );
        }
      }

      if (previewOnly && dir.km > 0) {
        setState(() => distanciaKm = dir.km);
      }
    } catch (_) {}
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

  LatLngBounds _boundsFromList(List<LatLng> pts) {
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  // ==========================
  // CALCULAR PRECIO (MOTOR) - CORREGIDO
  // ==========================
  Future<void> _obtenerUbicacionYCalcularPrecio() async {
    if (_cargando) return;
    FocusScope.of(context).unfocus();
    _formKey.currentState?.save();

    destino = destino.trim();

    final tieneDestino = destino.isNotEmpty ||
        _destinoDet != null ||
        (latDestino != null && lonDestino != null);

    if (!tieneDestino) {
      _snack("❌ Indica un destino (buscador o mapa).");
      return;
    }

    setState(() => _cargando = true);
    final int runId = _cotizacionSeq;
    try {
      // ORIGEN: GPS
      final ok = await PermisosService.ensureUbicacion(context);
      if (!ok) return;

      final posicion = await GpsService.obtenerUbicacionActual();
      if (posicion == null) {
        _snack("❌ No se pudo obtener ubicación GPS.");
        return;
      }

      final origenLat = posicion.latitude;
      final origenLon = posicion.longitude;

      final placemarksO = await _safePlacemark(origenLat, origenLon);
      final origenLegible = placemarksO.isNotEmpty
          ? _direccionBonitaRD(placemarksO.first)
          : "Ubicación actual";

      _origenMap = LatLng(origenLat, origenLon);
      _updateOrigenMarker(_origenMap!);

      // DESTINO
      double dLat = 0, dLon = 0;
      String destinoLegible = '';

      if (_destinoDet != null) {
        dLat = _destinoDet!.lat;
        dLon = _destinoDet!.lon;
        destinoLegible = _destinoDet!.displayLabel;
      } else if (latDestino != null && lonDestino != null) {
        dLat = latDestino!;
        dLon = lonDestino!;
        final dPM = await _safePlacemark(dLat, dLon);
        destinoLegible = dPM.isNotEmpty
            ? _direccionBonitaRD(dPM.first)
            : (destinoTexto.isNotEmpty ? destinoTexto : 'Destino seleccionado');
      } else {
        final de = await _geocodeConFallback(destino);
        if (de == null) {
          _snack("❌ No se encontró esa dirección de destino.");
          return;
        }
        dLat = de.lat;
        dLon = de.lon;

        final dPM = await _safePlacemark(dLat, dLon);
        destinoLegible =
            dPM.isNotEmpty ? _direccionBonitaRD(dPM.first) : destino;
      }

      // Distancia base + Directions
      double dist =
          DistanciaService.calcularDistancia(origenLat, origenLon, dLat, dLon);

      DirectionsResult? dir;
      if (kUseDirectionsForDistance) {
        dir = await DirectionsService.drivingDistanceKm(
          originLat: origenLat,
          originLon: origenLon,
          destLat: dLat,
          destLon: dLon,
          withTraffic: true,
          region: 'do',
        );
        if (dir != null && dir.km > 0) dist = dir.km;
      }

      if (dist <= 0) {
        _snack("❌ No se pudo calcular una distancia válida.");
        return;
      }

      // ✅ 1. Calcular distancia FINAL (si es ida y vuelta)
      final double distanciaFinal = idaYVuelta ? dist * 2 : dist;

      // ✅ 2. Calcular precio con TarifaService (MOTOR) - SIN parámetro idaYVuelta
      final precioDouble = TarifaService.calcularPrecioPorTipo(
        distanciaKm: distanciaFinal,
        tipoVehiculo: kVehiculoMotor,
      );

      final List<LatLng> routeLatLng = dir?.path ?? const <LatLng>[];

      if (!mounted || runId != _cotizacionSeq) return;

      setState(() {
        latCliente = origenLat;
        lonCliente = origenLon;
        latDestino = dLat;
        lonDestino = dLon;

        origenTexto = origenLegible;
        destinoTexto = destinoLegible;

        distanciaKm = dist; // Guardamos la distancia original
        precioCalculado = precioDouble;
        ubicacionObtenida = true;

        _markers
          ..removeWhere((m) => m.markerId.value == 'destino')
          ..add(
            Marker(
              markerId: const MarkerId('destino'),
              position: LatLng(dLat, dLon),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen),
              infoWindow: const InfoWindow(title: 'Destino'),
              zIndexInt: 1,
            ),
          );

        _polylines.clear();
        if (routeLatLng.isNotEmpty) {
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('ruta'),
              points: routeLatLng,
              width: 5,
              color: const Color(0xFF49F18B),
              geodesic: true,
            ),
          );
        } else {
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('ruta'),
              points: [
                LatLng(origenLat, origenLon),
                LatLng(dLat, dLon),
              ],
              width: 4,
              color: const Color(0xFF49F18B),
              geodesic: true,
            ),
          );
        }
      });

      if (_map != null && runId == _cotizacionSeq) {
        if (routeLatLng.length >= 2) {
          await _map!.animateCamera(
            CameraUpdate.newLatLngBounds(_boundsFromList(routeLatLng), 60),
          );
        } else {
          await _map!.animateCamera(
            CameraUpdate.newLatLngBounds(
              _boundsFrom(
                LatLng(origenLat, origenLon),
                LatLng(dLat, dLon),
              ),
              80,
            ),
          );
        }
      }
    } catch (e) {
      if (runId == _cotizacionSeq) {
        _snack("❌ Error al calcular distancia: $e");
      }
    } finally {
      if (mounted && runId == _cotizacionSeq) {
        final mostrar = precioCalculado > 0 && ubicacionObtenida;
        setState(() {
          _cargando = false;
          if (mostrar) _vistaResumenCotizada = true;
        });
        if (mostrar) _animarSheetResumenMotor();
      }
    }
  }

  // ==========================
  // CONFIRMAR (guardar viaje)
  // ==========================
  Future<void> _confirmarMotor() async {
    if (_cargando) return;
    if (!_formKey.currentState!.validate()) return;

    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      _snack(kMsgLogin);
      return;
    }

    if (!ubicacionObtenida ||
        latCliente == null ||
        lonCliente == null ||
        latDestino == null ||
        lonDestino == null ||
        precioCalculado <= 0) {
      _snack(kMsgCalcFirst);
      return;
    }

    setState(() => _cargando = true);
    try {
      await u.getIdToken(true);

      final DateTime nowUtc = DateTime.now().toUtc();

      // ✅ extras SIN romper índices (mismo patrón)
      final extras = <String, dynamic>{
        'tipoServicio': 'NORMAL',
        'canalAsignacion': 'pool',
        'modoSolicitud': 'AHORA',
        'aceptableDesdeUtc': nowUtc
            .subtract(const Duration(minutes: kAcceptLeadMinutes))
            .toIso8601String(),
        'pantalla': 'SolicitarMotorRai',
      };

      final id = await ViajesRepo.crearViajePendiente(
        uidCliente: u.uid,
        origen: origenTexto.isNotEmpty ? origenTexto : 'Ubicación actual',
        destino: destinoTexto.isNotEmpty ? destinoTexto : destino,
        latOrigen: latCliente!,
        lonOrigen: lonCliente!,
        latDestino: latDestino!,
        lonDestino: lonDestino!,
        fechaHora: nowUtc,
        precio: precioCalculado,
        metodoPago: metodoPago,
        tipoVehiculo: kVehiculoMotor, // ✅ Motor fijo
        idaYVuelta: idaYVuelta,
        distanciaKm: distanciaKm > 0 ? distanciaKm : null,
        extras: extras,
      );

      _snack("✅ Motor solicitado — #${id.substring(0, 6)}");

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ViajeEnCursoCliente()),
        );
      }
    } on fs.FirebaseException catch (e) {
      _snack('❌ Firestore (${e.code}): ${e.message ?? e}');
    } catch (e) {
      _snack('❌ Error al guardar el viaje: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ==========================
  // UI
  // ==========================
  Widget _tarjetaResumenMotor() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    const Color c = Colors.orange;
    final onCard = scheme.onSurface;
    final subtle = scheme.onSurface.withValues(alpha: 0.62);
    final chipBg = isDark
        ? const Color(0xFF1E1E1E)
        : scheme.surfaceContainerHighest;
    final chipBorder =
        isDark ? Colors.white24 : scheme.outline.withValues(alpha: 0.28);
    final dividerColor =
        isDark ? Colors.white24 : scheme.outline.withValues(alpha: 0.22);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  c.withValues(alpha: isDark ? 0.2 : 0.12),
                  c.withValues(alpha: isDark ? 0.05 : 0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: c.withValues(alpha: isDark ? 0.85 : 0.5),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: c, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Listo para confirmar',
                        style: TextStyle(
                          color: onCard,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.trip_origin, size: 22, color: c),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ORIGEN',
                            style: TextStyle(
                              color: subtle,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            origenTexto.isNotEmpty ? origenTexto : 'Ubicación actual (GPS)',
                            style: TextStyle(
                              color: onCard,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.flag_rounded, size: 22, color: c),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DESTINO',
                            style: TextStyle(
                              color: subtle,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            destinoTexto.isNotEmpty ? destinoTexto : destino,
                            style: TextStyle(
                              color: onCard,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(color: dividerColor, height: 1),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    '${FormatosMoneda.km(distanciaKm)}${idaYVuelta ? ' · Ida y vuelta' : ''}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: subtle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'TOTAL A PAGAR',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: subtle,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      FormatosMoneda.rd(precioCalculado),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c,
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.payments_outlined, size: 18, color: subtle),
                      const SizedBox(width: 8),
                      Text(
                        'Pago:',
                        style: TextStyle(color: subtle, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: chipBorder),
                        ),
                        child: Text(
                          metodoPago,
                          style: TextStyle(
                            color: onCard,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (ubicacionObtenida && precioCalculado > 0) ? _confirmarMotor : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                    child: const Text(
                      'Confirmar viaje',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: _abrirFormularioCompletoMotor,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: chipBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: Colors.orange, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Editar viaje',
                            style: TextStyle(
                              color: onCard,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Destino, regreso y forma de pago',
                            style: TextStyle(
                              color: subtle,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: subtle,
                      size: 28,
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

  Future<void> _elegirMetodoPago() async {
    if (_cargando) return;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtle = scheme.onSurface.withValues(alpha: 0.65);
    final handle = scheme.onSurface.withValues(alpha: 0.28);

    final elegido = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        Widget item(String label) => ListTile(
              title: Text(
                label,
                style: TextStyle(color: scheme.onSurface),
              ),
              trailing: label == metodoPago
                  ? Icon(Icons.check, color: scheme.primary)
                  : null,
              onTap: () => Navigator.pop(ctx, label),
            );

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 8),
              Container(
                height: 4,
                width: 48,
                decoration: BoxDecoration(
                  color: handle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Método de pago',
                style: TextStyle(
                  color: subtle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              item('Efectivo'),
              item('Tarjeta'),
              item('Transferencia'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (elegido != null && elegido.trim().isNotEmpty) {
      setState(() => metodoPago = elegido);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final handleColor = scheme.onSurface.withValues(alpha: isDark ? 0.28 : 0.22);
    final hintStyle = TextStyle(
      color: scheme.onSurface.withValues(alpha: 0.55),
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

    return Scaffold(
      backgroundColor: scheme.surface,
      drawer: const ClienteDrawer(),
      appBar: const RaiAppBar(
        title: '',
        titleSemanticsLabel: 'Solicitar viaje en motor',
      ),
      body: Stack(
        children: [
          // ===== MAPA =====
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: _cargandoUbicacion,
              child: GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: LatLng(18.4861, -69.9312),
                  zoom: 12,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: _markers,
                polylines: _polylines,
                onMapCreated: (c) => _map = c,
                onLongPress: _onLongPressMap,
                compassEnabled: true,
                mapToolbarEnabled: false,
              ),
            ),
          ),

          // ===== BANNERS (ubicación) =====
          if (_cargandoUbicacion)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: const _Banner(
                text: 'Ubicando…',
                icon: Icons.location_searching,
              ),
            )
          else if (_locPermDeniedForever)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: const _Banner(
                text: 'Activa la ubicación en Ajustes del sistema.',
                icon: Icons.location_off,
              ),
            ),

          // ===== FAB CENTRAR =====
          Positioned(
            right: 16,
            bottom: 220,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: scheme.surfaceContainerHigh,
              foregroundColor: scheme.onSurface,
              elevation: 3,
              onPressed: _centrarEnMiUbicacion,
              child: const Icon(Icons.my_location_rounded),
            ),
          ),

          // ===== BOTTOM SHEET =====
          DraggableScrollableSheet(
            controller: _sheetCtrl,
            minChildSize: 0.26,
            maxChildSize: 0.88,
            initialChildSize: 0.36,
            snap: true,
            snapSizes: const [0.34, 0.86, 0.88],
            builder: (context, controller) {
              return Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(
                    top: BorderSide(
                      color: scheme.outline.withValues(alpha: 0.12),
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_cargando)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: CotizacionPrecioLoadingStrip(
                          accentColor: const Color(0xFFFF5A00),
                          isDark: isDark,
                          message: (ubicacionObtenida && precioCalculado > 0)
                              ? 'Enviando solicitud…'
                              : 'Calculando precio…',
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          _cargando ? 6 : 10,
                          16,
                          24,
                        ),
                        child: Form(
                          key: _formKey,
                          child: ListView(
                            controller: controller,
                            children: [
                        GestureDetector(
                          onTap: _expandToMax,
                          child: Column(
                            children: [
                              Container(
                                width: 44,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: handleColor,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(height: 6),
                              SlideTransition(
                                position: _nudgeOffset,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.keyboard_double_arrow_up_rounded,
                                      size: 18,
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.45),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _mostrarResumenMotor
                                            ? 'Toca abajo para editar'
                                            : 'Desliza para ver más',
                                        textAlign: TextAlign.center,
                                        style: hintStyle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (_mostrarResumenMotor) _tarjetaResumenMotor(),

                        if (!_mostrarResumenMotor)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                        _MotoUberHeader(isDark: isDark),
                        const SizedBox(height: 12),
                        _MotoSearchShell(
                          isDark: isDark,
                          child: kUsePlacesAutocomplete
                              ? CampoLugarAutocomplete(
                            label: '',
                            hint: '¿A dónde vamos?',
                            onPlaceSelected: (det) async {
                              _destinoDet = det;
                              destino = det.displayLabel;
                              destinoTexto = det.displayLabel;
                              latDestino = det.lat;
                              lonDestino = det.lon;

                              final p = LatLng(det.lat, det.lon);
                              _markers.removeWhere(
                                  (m) => m.markerId.value == 'destino');
                              _markers.add(
                                Marker(
                                  markerId: const MarkerId('destino'),
                                  position: p,
                                  icon: BitmapDescriptor.defaultMarkerWithHue(
                                      BitmapDescriptor.hueGreen),
                                  infoWindow: const InfoWindow(title: 'Destino'),
                                  zIndexInt: 1,
                                ),
                              );
                              setState(() {});

                              if (_origenMap != null) {
                                await _dibujarRutaReal(
                                  oLat: _origenMap!.latitude,
                                  oLon: _origenMap!.longitude,
                                  dLat: det.lat,
                                  dLon: det.lon,
                                  previewOnly: true,
                                );
                              }
                            },
                            onTextChanged: (t) {
                              _markers.removeWhere(
                                  (m) => m.markerId.value == 'destino');
                              _polylines.clear();
                              setState(() {
                                destino = t;
                                latDestino = null;
                                lonDestino = null;
                                destinoTexto = '';
                                _destinoDet = null;
                                _invalidarCotizacionMotor();
                              });
                            },
                          )
                        : TextFormField(
                            style: TextStyle(color: scheme.onSurface),
                            decoration: InputDecoration(
                              labelText: '¿A dónde vas?',
                              hintText: 'Ej: Punta Cana',
                              labelStyle: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.7),
                              ),
                              hintStyle: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.45),
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? Colors.grey[900]
                                  : const Color(0xFFF5F3FF),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: const Color(0xFF7C3AED),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: scheme.outline.withValues(alpha: 0.35),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFF7C3AED),
                                  width: 2,
                                ),
                              ),
                            ),
                            onTap: _expandToMax,
                            onSaved: (v) => destino = (v ?? ''),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Indica un destino'
                                : null,
                          ),
                        ),

                        const SizedBox(height: 12),
                        _MotoOptionsCard(
                          idaYVuelta: idaYVuelta,
                          onIdaYVuelta: (v) => setState(() => idaYVuelta = v),
                          metodoPago: metodoPago,
                          onElegirPago: _elegirMetodoPago,
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _obtenerUbicacionYCalcularPrecio,
                            style: _motoCtaStyle(context),
                            child: _cargando
                                ? SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color:
                                          isDark ? Colors.black : Colors.white,
                                    ),
                                  )
                                : const Text('Ver precio'),
                          ),
                        ),
                        const SizedBox(height: 8),

                        if (precioCalculado > 0)
                          _MotoEstimacionChip(
                            scheme: scheme,
                            isDark: isDark,
                            distanciaKm: distanciaKm,
                            idaYVuelta: idaYVuelta,
                            precio: precioCalculado,
                          ),
                        if (precioCalculado > 0) const SizedBox(height: 10),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                (ubicacionObtenida && precioCalculado > 0)
                                    ? _confirmarMotor
                                    : null,
                            style: _motoCtaStyle(context),
                            child: const Text('Confirmar viaje'),
                          ),
                        ),

                        const SizedBox(height: 10),
                        Center(
                          child: Text(
                            DateFormat('dd/MM/yyyy · HH:mm')
                                .format(DateTime.now()),
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.32),
                              fontSize: 11,
                            ),
                          ),
                        ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
            },
          ),
        ],
      ),
    );
  }

  /// CTA estilo app de movilidad (negro / blanco según tema).
  ButtonStyle _motoCtaStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color fg = isDark ? Colors.black : Colors.white;
    final Color bg = isDark ? Colors.white : const Color(0xFF000000);
    final Color disabledBg =
        isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.26);
    return ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      disabledBackgroundColor: disabledBg,
      disabledForegroundColor: fg.withValues(alpha: 0.4),
      minimumSize: const Size(double.infinity, 54),
      padding: const EdgeInsets.symmetric(vertical: 16),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
    );
  }
}

// ==========================
// Auxiliares UI
// ==========================
/// Cabecera compacta alineada al tema (menos contraste duro que bloque negro).
class _MotoUberHeader extends StatelessWidget {
  final bool isDark;

  const _MotoUberHeader({required this.isDark});

  static const _accent = Color(0xFFFF5A00);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = scheme.onSurface;
    final bg = isDark
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainerHighest;
    final border = scheme.outline.withValues(alpha: isDark ? 0.22 : 0.14);

    return Semantics(
      container: true,
      label: 'Pedir viaje en moto',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: isDark ? 0.22 : 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.two_wheeler_rounded,
                color: _accent,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Moto',
                    style: TextStyle(
                      color: on,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Te recogen donde estás. En el mapa: pulsación larga para marcar destino.',
                    style: TextStyle(
                      color: on.withValues(alpha: 0.52),
                      fontSize: 12,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MotoSearchShell extends StatelessWidget {
  final bool isDark;
  final Widget child;

  const _MotoSearchShell({
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = scheme.outline.withValues(alpha: isDark ? 0.22 : 0.14);
    final fill = isDark ? const Color(0xFF1A1A1A) : Colors.white;

    return Semantics(
      container: true,
      label: 'Buscar destino',
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: line),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _MotoOptionsCard extends StatelessWidget {
  final bool idaYVuelta;
  final ValueChanged<bool> onIdaYVuelta;
  final String metodoPago;
  final VoidCallback onElegirPago;

  const _MotoOptionsCard({
    required this.idaYVuelta,
    required this.onIdaYVuelta,
    required this.metodoPago,
    required this.onElegirPago,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = scheme.outline.withValues(alpha: isDark ? 0.2 : 0.12);
    final bg = isDark ? const Color(0xFF161616) : scheme.surface;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            title: Text(
              'Ida y vuelta',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: scheme.onSurface,
              ),
            ),
            value: idaYVuelta,
            onChanged: onIdaYVuelta,
            activeColor: const Color(0xFFFF5A00),
            activeTrackColor: const Color(0xFFFF5A00).withValues(alpha: 0.35),
          ),
          Divider(height: 1, thickness: 1, color: border),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Icon(
              Icons.payments_outlined,
              size: 22,
              color: scheme.onSurface.withValues(alpha: 0.45),
            ),
            title: Text(
              metodoPago,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            subtitle: Text(
              'Forma de pago',
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurface.withValues(alpha: 0.32),
            ),
            onTap: onElegirPago,
          ),
        ],
      ),
    );
  }
}

class _MotoEstimacionChip extends StatelessWidget {
  final ColorScheme scheme;
  final bool isDark;
  final double distanciaKm;
  final bool idaYVuelta;
  final double precio;

  const _MotoEstimacionChip({
    required this.scheme,
    required this.isDark,
    required this.distanciaKm,
    required this.idaYVuelta,
    required this.precio,
  });

  @override
  Widget build(BuildContext context) {
    final subtle = scheme.onSurface.withValues(alpha: 0.55);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF142018) : const Color(0xFFF3F6F4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF49F18B).withValues(alpha: isDark ? 0.3 : 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '${FormatosMoneda.km(distanciaKm)}${idaYVuelta ? ' · Ida y vuelta' : ''}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.75),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Estimación',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: subtle,
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                FormatosMoneda.rd(precio),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.greenAccent : const Color(0xFF047857),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Banner({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF49F18B);
    final bg = isDark ? const Color(0xFF1C1F23) : scheme.surfaceContainerHighest;
    final borderColor = accent.withValues(alpha: isDark ? 0.35 : 0.42);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border.all(color: borderColor),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}