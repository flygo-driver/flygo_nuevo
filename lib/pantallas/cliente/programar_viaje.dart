// lib/pantallas/cliente/programar_viaje.dart
// ProgramarViaje — estilo FlyGo, tipo inDrive (autocomplete + mapa tiempo real)
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

// 🔰 IMPORT para ir al viaje en curso (opcional si usas ClienteTripRouter)
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';

// Tus servicios/componentes
import 'package:flygo_nuevo/widgets/cliente_drawer.dart';
import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/permisos_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/widgets/campo_lugar_autocomplete.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart'; // DetalleLugar
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';

// ===== Flags / Reglas =====
const bool kUsePlacesAutocomplete = true;
const bool kUseDirectionsForDistance = true;
const int kAhoraUmbralMin = 10; // minutos
const int kMaxDiasProgramacion = 90; // días

// Ventana para liberar programados (debe coincidir con lo que espera tu app)
const int kAcceptLeadMinutes = 120; // 2 horas antes

// ===== Snackbars =====
const String kMsgLogin = 'Debes iniciar sesión para continuar.';
const String kMsgCalcFirst = 'Debes calcular el precio primero.';
const String kMsgMaxFuture = 'Solo puedes programar hasta 90 días en el futuro.';
const String kMsgMinFuture =
    'Selecciona una hora al menos ${kAhoraUmbralMin + 1} minutos en el futuro.';

class ProgramarViaje extends StatefulWidget {
  final bool modoAhora; // true = Solicitar ahora, false = Programar
  const ProgramarViaje({super.key, required this.modoAhora});

  @override
  State<ProgramarViaje> createState() => _ProgramarViajeState();
}

class _ProgramarViajeState extends State<ProgramarViaje>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // ---- Form
  String origenManual = '';
  String destino = '';
  DateTime fechaHora = DateTime.now();
  String tipoVehiculo = 'Carro';
  String metodoPago = 'Efectivo';
  bool idaYVuelta = false;
  bool usarOrigenManual = false; // Para programar fuera del país

  // ---- Coords
  double? latCliente;
  double? lonCliente;
  double? latDestino;
  double? lonDestino;

  // ---- Textos
  String origenTexto = '';
  String destinoTexto = '';

  double distanciaKm = 0.0;

  // ---- UI (precios)
  double precioCalculado = 0.0;
  double comisionCalculada = 0.0;
  double gananciaTaxistaCalculada = 0.0;

  bool ubicacionObtenida = false;
  bool _cargando = false;

  // Autocomplete
  DetalleLugar? _origenDetManual;
  DetalleLugar? _destinoDet;

  // ===== Mapa
  GoogleMapController? _map;
  LatLng? _origenMap;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  bool _locPermDeniedForever = false;
  bool _cargandoUbicacion = true;

  // Live GPS
  StreamSubscription<Position>? _posSub;
  bool _didCenterOnce = false;

  // ===== Panel deslizante
  final DraggableScrollableController _sheetCtrl =
      DraggableScrollableController();

  // Flecha “nudge”
  late final AnimationController _nudgeCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final Animation<Offset> _nudgeOffset = Tween<Offset>(
    begin: const Offset(0, .15),
    end: const Offset(0, -0.05),
  ).animate(CurvedAnimation(parent: _nudgeCtrl, curve: Curves.easeInOut));
  Timer? _nudgeTimer;

  @override
  void initState() {
    super.initState();

    if (widget.modoAhora) {
      usarOrigenManual = false;
      fechaHora = DateTime.now();
    } else {
      fechaHora = DateTime.now().add(const Duration(minutes: 20));
    }

    _initUbicacionParaMapa();

    // Auto-subir el panel y nudge
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
    final target = (widget.modoAhora ? 0.86 : 0.88).clamp(0.26, 0.88);
    try {
      await _sheetCtrl.animateTo(
        target,
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

  // ====== UBICACIÓN/MAPA ======
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
        infoWindow: const InfoWindow(title: 'Origen'),
        zIndexInt: 2,
      ),
    );
  }

  Future<void> _centrarEnMiUbicacion() async {
    if (_origenMap == null) return;
    _didCenterOnce = true;
    await _map?.animateCamera(CameraUpdate.newLatLng(_origenMap!));
  }

  void _onLongPressMap(LatLng p) async {
    latDestino = p.latitude;
    lonDestino = p.longitude;

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
    _destinoDet = null;

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

  // ====== HELPERS GEOCODING ======
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
        .replaceAll(RegExp(r'\bSto\.?\s*Dgo\.?\b', caseSensitive: false), 'Santo Domingo')
        .replaceAll(RegExp(r'Higuey', caseSensitive: false), 'Higüey')
        .replaceAll(RegExp(r'San Pedro de Macoris', caseSensitive: false), 'San Pedro de Macorís')
        .replaceAll(RegExp(r'Santo Domingo D\.?N\.?', caseSensitive: false), 'Santo Domingo')
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

  // ====== CALCULAR PRECIO ======
  Future<void> _obtenerUbicacionYCalcularPrecio() async {
    if (_cargando) return;
    FocusScope.of(context).unfocus();
    _formKey.currentState?.save();

    destino = destino.trim();
    if (usarOrigenManual) origenManual = origenManual.trim();

    if (!widget.modoAhora) {
      final tieneOrigenExplicito =
          (usarOrigenManual && (_origenDetManual != null || origenManual.isNotEmpty));
      if (!tieneOrigenExplicito) {
        _snack("❌ Para programar, indica un origen (campo 'Origen' o autocompletar).");
        return;
      }
    }
    if (destino.isEmpty &&
        latDestino == null &&
        lonDestino == null &&
        _destinoDet == null) {
      _snack("❌ Indica un destino (buscador o toque prolongado en el mapa).");
      return;
    }

    setState(() => _cargando = true);
    try {
      double origenLat = 0, origenLon = 0;
      String origenLegible = '';
      String destinoLegible = '';
      double dLat = 0, dLon = 0;

      // ORIGEN
      if (usarOrigenManual && !widget.modoAhora) {
        if (kUsePlacesAutocomplete && _origenDetManual != null) {
          origenLat = _origenDetManual!.lat;
          origenLon = _origenDetManual!.lon;
          origenLegible = _origenDetManual!.displayLabel;
        } else {
          final or = await _geocodeConFallback(origenManual);
          if (or == null) {
            _snack("❌ No se encontró esa dirección de origen.");
            setState(() => _cargando = false);
            return;
          }
          origenLat = or.lat;
          origenLon = or.lon;
          origenLegible = origenManual;
        }
      } else {
        final ok = await PermisosService.ensureUbicacion(context);
        if (!ok) {
          setState(() => _cargando = false);
          return;
        }
        final posicion = await GpsService.obtenerUbicacionActual();
        if (posicion == null) {
          _snack("❌ No se pudo obtener ubicación GPS.");
          setState(() => _cargando = false);
          return;
        }
        origenLat = posicion.latitude;
        origenLon = posicion.longitude;
        final placemarks = await _safePlacemark(origenLat, origenLon);
        origenLegible = placemarks.isNotEmpty
            ? _direccionBonitaRD(placemarks.first)
            : "Ubicación actual";
      }

      // DESTINO
      if (latDestino != null && lonDestino != null) {
        dLat = latDestino!;
        dLon = lonDestino!;
        final dPM = await _safePlacemark(dLat, dLon);
        destinoLegible = dPM.isNotEmpty
            ? _direccionBonitaRD(dPM.first)
            : (destinoTexto.isNotEmpty ? destinoTexto : 'Destino seleccionado');
      } else if (kUsePlacesAutocomplete && _destinoDet != null) {
        dLat = _destinoDet!.lat;
        dLon = _destinoDet!.lon;
        destinoLegible = _destinoDet!.displayLabel;
      } else {
        final de = await _geocodeConFallback(destino);
        if (de == null) {
          _snack("❌ No se encontró esa dirección de destino.");
          setState(() => _cargando = false);
          return;
        }
        dLat = de.lat;
        dLon = de.lon;
        final dPlacemarks = await _safePlacemark(dLat, dLon);
        destinoLegible = dPlacemarks.isNotEmpty ? _direccionBonitaRD(dPlacemarks.first) : destino;
      }

      // Distancia / ruta
      double dist = DistanciaService.calcularDistancia(origenLat, origenLon, dLat, dLon);
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
        setState(() => _cargando = false);
        return;
      }

      // Precio (con comisiones)
      final precioDouble = DistanciaService.calcularPrecio(dist, idaYVuelta: idaYVuelta);
      final int precioCents = (precioDouble * 100).round();
      final int comisionCents = ((precioCents * 20) + 50) ~/ 100;
      final int gananciaCents = precioCents - comisionCents;

      // Polyline
      final List<LatLng> routeLatLng = dir?.path ?? const <LatLng>[];

      setState(() {
        latCliente = origenLat;
        lonCliente = origenLon;
        latDestino = dLat;
        lonDestino = dLon;

        _origenMap = LatLng(origenLat, origenLon);
        origenTexto = origenLegible;
        destinoTexto = destinoLegible;

        distanciaKm = dist;
        precioCalculado = precioCents / 100.0;
        comisionCalculada = comisionCents / 100.0;
        gananciaTaxistaCalculada = gananciaCents / 100.0;
        ubicacionObtenida = true;

        _updateOrigenMarker(LatLng(origenLat, origenLon));
        _markers
          ..removeWhere((m) => m.markerId.value == 'destino')
          ..add(
            Marker(
              markerId: const MarkerId('destino'),
              position: LatLng(dLat, dLon),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
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
              points: [LatLng(origenLat, origenLon), LatLng(dLat, dLon)],
              width: 4,
              color: const Color(0xFF49F18B),
              geodesic: true,
            ),
          );
        }
      });

      if (_map != null) {
        if (routeLatLng.length >= 2) {
          await _map!.animateCamera(
            CameraUpdate.newLatLngBounds(_boundsFromList(routeLatLng), 60),
          );
        } else {
          await _map!.animateCamera(
            CameraUpdate.newLatLngBounds(
              _boundsFrom(LatLng(origenLat, origenLon), LatLng(dLat, dLon)),
              80,
            ),
          );
        }
      }
    } catch (e) {
      _snack("❌ Error al calcular distancia: $e");
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // Dibujo de ruta al seleccionar destino (preview sin precios)
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
              points: pts.isNotEmpty ? pts : [LatLng(oLat, oLon), LatLng(dLat, dLon)],
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

  // ====== FECHA/HORA ======
  Future<void> _seleccionarFechaHora() async {
    final now = DateTime.now();
    final last = now.add(const Duration(days: kMaxDiasProgramacion));

    final fecha = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(minutes: 5)),
      firstDate: now,
      lastDate: last,
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.greenAccent,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted || fecha == null) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        final theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.greenAccent,
              surface: Colors.black,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted || hora == null) return;

    setState(() {
      fechaHora = DateTime(
        fecha.year, fecha.month, fecha.day, hora.hour, hora.minute,
      );
    });
  }

  Future<void> _elegirMetodoPago() async {
    if (_cargando) return;
    final elegido = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        Widget item(String label) => ListTile(
              title: Text(label, style: const TextStyle(color: Colors.white)),
              trailing: label == metodoPago
                  ? const Icon(Icons.check, color: Colors.greenAccent)
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
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Método de pago', style: TextStyle(color: Colors.white70)),
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

  // ====== BLOQUEO SOLO SI EL ROL EXPLÍCITO ES TAXISTA/ADMIN ======
  Future<bool> _bloquearSiTaxista() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return true; // sin login → bloquea
    try {
      final rol = (await RolesService.getRol(u.uid))?.toLowerCase();
      if (rol == Roles.taxista || rol == Roles.admin) {
        _snack('Esta cuenta es de $rol.');
        return true;
      }
    } catch (_) {
      // si falla, no bloqueamos: tratamos como cliente
    }
    return false;
  }

  // ====== CONFIRMAR ======
  Future<void> _programarViaje(
    ScaffoldMessengerState messenger,
    NavigatorState nav,
  ) async {
    if (_cargando) return;
    if (!_formKey.currentState!.validate()) return;

    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      messenger.showSnackBar(const SnackBar(content: Text(kMsgLogin)));
      return;
    }
    if (!ubicacionObtenida || latCliente == null || latDestino == null) {
      messenger.showSnackBar(const SnackBar(content: Text(kMsgCalcFirst)));
      return;
    }
    if (!widget.modoAhora) {
      final now = DateTime.now();
      final minFuturo = now.add(const Duration(minutes: kAhoraUmbralMin + 1));
      final maxFuturo = now.add(const Duration(days: kMaxDiasProgramacion));
      if (fechaHora.isBefore(minFuturo)) {
        messenger.showSnackBar(const SnackBar(content: Text(kMsgMinFuture)));
        return;
      }
      if (fechaHora.isAfter(maxFuturo)) {
        messenger.showSnackBar(const SnackBar(content: Text(kMsgMaxFuture)));
        return;
      }
    }

    // Bloqueo real: sólo si el rol explícito es taxista/admin
    if (await _bloquearSiTaxista()) return;

    setState(() => _cargando = true);
    try {
      await u.getIdToken(true);

      final origenLegible =
          (origenTexto.isNotEmpty) ? origenTexto : (usarOrigenManual ? origenManual : "Ubicación actual");
      final destinoLegible = (destinoTexto.isNotEmpty) ? destinoTexto : destino;

      // Fechas en UTC
      final DateTime nowUtc = DateTime.now().toUtc();
      final DateTime fechaProgramadaUtc = widget.modoAhora ? nowUtc : fechaHora.toUtc();

      // 1) Crear viaje pendiente en 'viajes'
      final id = await ViajesRepo.crearViajePendiente(
        uidCliente: u.uid,
        origen: origenLegible,
        destino: destinoLegible,
        latOrigen: latCliente!,
        lonOrigen: lonCliente!,
        latDestino: latDestino!,
        lonDestino: lonDestino!,
        fechaHora: fechaProgramadaUtc, // UTC
        precio: precioCalculado,
        metodoPago: metodoPago,
        tipoVehiculo: tipoVehiculo,
        idaYVuelta: idaYVuelta,
        distanciaKm: distanciaKm > 0 ? distanciaKm : null,
      );

      final accion = widget.modoAhora ? 'solicitado exitosamente' : 'programado exitosamente';
      messenger.showSnackBar(
        SnackBar(content: Text("✅ Viaje $accion — #${id.substring(0, 6)}")),
      );

      // 2) Ir directo a "Viaje en curso" del cliente (o deja que tu Router lo haga)
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ViajeEnCursoCliente()),
        );
      }
    } on fs.FirebaseException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('❌ Firestore (${e.code}): ${e.message ?? e}')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('❌ Error al guardar el viaje: $e')),
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ===== UI =====
  Widget _tabsModo() {
    final ahora = widget.modoAhora;
    Widget tab(String text, bool active, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: active ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF1E1E1E) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: active ? const Color(0xFF49F18B) : Colors.white24,
                  width: active ? 2 : 1),
            ),
            alignment: Alignment.center,
            child: Text(
              text,
              style: TextStyle(
                color: active ? Colors.greenAccent : Colors.white70,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab('Solicitar ahora', ahora, () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ProgramarViaje(modoAhora: true)),
          );
        }),
        const SizedBox(width: 10),
        tab('Programar viaje', !ahora, () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ProgramarViaje(modoAhora: false)),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const ClienteDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            tooltip: 'Menú',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Image.asset(
          'assets/icon/logo_flygo.png',
          height: 28,
          filterQuality: FilterQuality.high,
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // ===== Mapa =====
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: _cargandoUbicacion,
              child: GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: LatLng(18.4861, -69.9312), // SDQ fallback
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

          // Banners
          if (_cargandoUbicacion)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: const _Banner(text: 'Ubicando…', icon: Icons.location_searching),
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

          // FAB centrar
          Positioned(
            right: 16,
            bottom: 220,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: const Color(0xFF1E1E1E),
              onPressed: _centrarEnMiUbicacion,
              child: const Icon(Icons.my_location, color: Colors.white),
            ),
          ),

          // ===== Bottom sheet =====
          DraggableScrollableSheet(
            controller: _sheetCtrl,
            minChildSize: 0.26,
            maxChildSize: 0.88,
            initialChildSize: 0.36,
            snap: true,
            snapSizes: const [0.34, 0.86, 0.88],
            builder: (context, controller) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                  boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 16)],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      controller: controller,
                      children: [
                        // Handle + flechita animada
                        GestureDetector(
                          onTap: _expandToMax,
                          child: Column(
                            children: [
                              Container(
                                width: 44,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(height: 6),
                              SlideTransition(
                                position: _nudgeOffset,
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.keyboard_double_arrow_up, size: 18, color: Colors.white54),
                                    SizedBox(width: 6),
                                    Text(
                                      'Desliza o toca para ver todo',
                                      style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Tabs modo
                        _tabsModo(),
                        const SizedBox(height: 12),

                        // ORIGEN manual (solo programado)
                        if (!widget.modoAhora)
                          SwitchListTile(
                            title: const Text("Estoy fuera del país", style: TextStyle(color: Colors.white)),
                            subtitle: const Text(
                              "Para programar, fija un origen exacto.",
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            activeColor: Colors.greenAccent,
                            value: usarOrigenManual,
                            onChanged: (val) => setState(() => usarOrigenManual = val),
                          ),

                        if (usarOrigenManual && !widget.modoAhora) ...[
                          if (kUsePlacesAutocomplete)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CampoLugarAutocomplete(
                                  label: 'Origen',
                                  hint: 'Escribe tu punto de partida',
                                  onPlaceSelected: (det) {
                                    _origenDetManual = det;
                                    origenManual = det.displayLabel;
                                    origenTexto = det.displayLabel;
                                    setState(() {});
                                  },
                                  onTextChanged: (t) => origenManual = t,
                                ),
                                if (origenTexto.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text('Origen seleccionado: $origenTexto',
                                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                  ),
                              ],
                            )
                          else
                            _campoTexto(
                              "Origen",
                              (val) => origenManual = val,
                              validator: (val) =>
                                  (usarOrigenManual && (val == null || val.trim().isEmpty)) ? 'Indica un origen' : null,
                            ),
                          const SizedBox(height: 8),
                        ],

                        // ===== DESTINO
                        if (kUsePlacesAutocomplete)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                children: [
                                  CampoLugarAutocomplete(
                                    label: 'Destino',
                                    hint: '¿A dónde vas?',
                                    onPlaceSelected: (det) async {
                                      _destinoDet = det;
                                      destino = det.displayLabel;
                                      destinoTexto = det.displayLabel;
                                      latDestino = det.lat;
                                      lonDestino = det.lon;

                                      final p = LatLng(det.lat, det.lon);
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
                                      destino = t;
                                      latDestino = null;
                                      lonDestino = null;
                                    },
                                  ),

                                  // Tap en lupa → calcular directo
                                  Positioned.fill(
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: _obtenerUbicacionYCalcularPrecio,
                                          child: const SizedBox(width: 48, height: 50),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (destinoTexto.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text('Destino seleccionado: $destinoTexto',
                                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                ),
                              const SizedBox(height: 8),
                            ],
                          )
                        else
                          _campoTexto(
                            "Destino",
                            (val) => destino = val,
                            validator: (val) => (val == null || val.trim().isEmpty) ? 'Indica un destino' : null,
                          ),

                        // Ida y vuelta
                        _Caja(
                          child: Row(
                            children: [
                              const Icon(Icons.swap_horiz, color: Colors.white70),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text('¿Ida y vuelta?', style: TextStyle(color: Colors.white)),
                              ),
                              Switch.adaptive(
                                value: idaYVuelta,
                                onChanged: (v) => setState(() => idaYVuelta = v),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Tipo de vehículo
                        _Caja(
                          child: Row(
                            children: [
                              const Icon(Icons.directions_car_filled_outlined, color: Colors.white70),
                              const SizedBox(width: 10),
                              const Text('Tipo de Vehículo', style: TextStyle(color: Colors.white70)),
                              const Spacer(),
                              DropdownButton<String>(
                                value: tipoVehiculo,
                                dropdownColor: const Color(0xFF1A1A1A),
                                underline: const SizedBox(),
                                items: const ['Carro', 'Jeepeta', 'Minibús', 'Minivan', 'Autobús/Guagua']
                                    .map((e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(e, style: const TextStyle(color: Colors.white)),
                                        ))
                                    .toList(),
                                onChanged: (v) => setState(() => tipoVehiculo = v ?? 'Carro'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Método de pago
                        _Caja(
                          child: Row(
                            children: [
                              const Icon(Icons.credit_card_outlined, color: Colors.white70),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextButton.icon(
                                  onPressed: _elegirMetodoPago,
                                  icon: const Icon(Icons.account_balance_wallet_outlined),
                                  label: Text(
                                    'Elegir método de pago',
                                    style: TextStyle(color: Colors.green.shade300, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E1E),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Text(metodoPago,
                                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Fecha/hora (solo programado)
                        if (!widget.modoAhora) ...[
                          const Text("Fecha y hora del viaje", style: TextStyle(color: Colors.white)),
                          ElevatedButton.icon(
                            onPressed: _seleccionarFechaHora,
                            icon: const Icon(Icons.calendar_today),
                            label: const Text("Seleccionar Fecha y Hora"),
                            style: _botonEstilo(),
                          ),
                          Text(
                            "Programado para: ${DateFormat('dd/MM/yyyy - HH:mm').format(fechaHora)}",
                            style: const TextStyle(color: Colors.greenAccent),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Botón Calcular
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _obtenerUbicacionYCalcularPrecio,
                            icon: const Icon(Icons.place),
                            label: _cargando ? const Text("Calculando...") : const Text('Calcular Precio'),
                            style: _botonEstilo(),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Resumen
                        if (precioCalculado > 0)
                          _Caja(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Resumen', style: TextStyle(color: Colors.white70)),
                                const SizedBox(height: 6),
                                Text(
                                  'Distancia estimada: ${FormatosMoneda.km(distanciaKm)}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Total estimado: ${FormatosMoneda.rd(precioCalculado)}',
                                  style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),

                        // Confirmar
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: (ubicacionObtenida && precioCalculado > 0)
                                ? () => _programarViaje(ScaffoldMessenger.of(context), Navigator.of(context))
                                : null,
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(widget.modoAhora ? 'Confirmar Viaje' : 'Confirmar Programación'),
                            style: _botonEstilo(),
                          ),
                        ),

                        if (latCliente != null && latDestino != null) const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ===== Helpers UI (text fields / botones) =====
  Widget _campoTexto(
    String label,
    Function(String) onSaved, {
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: label == 'Origen' ? 'Ej: Santo Domingo, RD' : 'Ej: Punta Cana, RD',
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: Colors.grey[900],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.greenAccent),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Colors.greenAccent, width: 2),
          ),
        ),
        onTap: _expandToMax,
        onSaved: (val) => onSaved(val ?? ''),
        validator: validator,
      ),
    );
  }

  ButtonStyle _botonEstilo() {
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: Colors.green,
      minimumSize: const Size(double.infinity, 50),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

// ===== Auxiliares UI =====
class _Caja extends StatelessWidget {
  final Widget child;
  const _Caja({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.all(Radius.circular(12)),
        border: Border.fromBorderSide(BorderSide(color: Colors.white24)),
      ),
      child: child,
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
