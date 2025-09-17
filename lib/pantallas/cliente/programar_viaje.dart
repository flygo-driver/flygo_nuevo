import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// 👇 todos a package: para evitar rutas relativas frágiles
import 'package:flygo_nuevo/widgets/cliente_drawer.dart';
import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/permisos_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/widgets/campo_lugar_autocomplete.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart'; // DetalleLugar
import 'package:flygo_nuevo/servicios/directions_service.dart';

// ===== Flags / Reglas de negocio =====
const bool kUsePlacesAutocomplete = true;
const bool kUseDirectionsForDistance = true;
const int  kAhoraUmbralMin = 10;
// ⬇️ Ventana máxima de programación (producción)
const int  kMaxDiasProgramacion = 90;

class ProgramarViaje extends StatefulWidget {
  final bool modoAhora;
  const ProgramarViaje({super.key, required this.modoAhora});

  @override
  State<ProgramarViaje> createState() => _ProgramarViajeState();
}

class _ProgramarViajeState extends State<ProgramarViaje> {
  final _formKey = GlobalKey<FormState>();

  // ---- Form
  String origenManual = '';
  String destino = '';
  DateTime fechaHora = DateTime.now();
  String tipoVehiculo = 'Carro';
  String metodoPago = 'Efectivo';
  bool idaYVuelta = false;
  bool usarOrigenManual = false;

  // ---- Coords
  double? latCliente;
  double? lonCliente;
  double? latDestino;
  double? lonDestino;

  // ---- Textos
  String origenTexto = '';
  String destinoTexto = '';
  double distanciaKm = 0.0;

  // ---- UI
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
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
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
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      final here = LatLng(pos.latitude, pos.longitude);
      _origenMap = here;
      _updateOrigenMarker(here);

      setState(() => _cargandoUbicacion = false);

      // Centrado suave (cuando el mapa ya exista, si no, no hace nada).
      await _map?.animateCamera(
        CameraUpdate.newCameraPosition(
          const CameraPosition(target: LatLng(0, 0), zoom: 1),
        ),
      );
      await _map?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: here, zoom: 15),
        ),
      );

      _didCenterOnce = true;

      // Seguimiento en tiempo real
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 8),
      ).listen((p) {
        final ll = LatLng(p.latitude, p.longitude);
        _origenMap = ll;
        _updateOrigenMarker(ll);
        if (_map != null && _didCenterOnce) {
          _map!.animateCamera(CameraUpdate.newLatLng(ll));
        }
        setState(() {});
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
      ),
    );

    final placemarks = await _safePlacemark(p.latitude, p.longitude);
    destinoTexto = placemarks.isNotEmpty
        ? _direccionBonitaRD(placemarks.first)
        : '(${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)})';
    destino = destinoTexto;
    _destinoDet = null;

    if (_origenMap != null) {
      _polylines
        ..clear()
        ..add(
          Polyline(
            polylineId: const PolylineId('ruta'),
            points: [_origenMap!, p],
            width: 4,
            color: const Color(0xFF49F18B),
            geodesic: true,
          ),
        );
    }

    setState(() {});
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
    final ciudad =
        ((p.locality ?? '').trim().isNotEmpty ? p.locality!.trim() : (p.subAdministrativeArea ?? '').trim()).trim();
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

    // Para programados, origen debe ser explícito
    if (!widget.modoAhora) {
      final tieneOrigenExplicito = (usarOrigenManual && (_origenDetManual != null || origenManual.isNotEmpty));
      if (!tieneOrigenExplicito) {
        _snack("❌ Para programar, indica un origen (campo 'Origen' o autocompletar).");
        return;
      }
    }

    if (destino.isEmpty && (latDestino == null || lonDestino == null) && _destinoDet == null) {
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
        // modo "Ahora": se permite ubicación actual
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
        origenLegible = placemarks.isNotEmpty ? _direccionBonitaRD(placemarks.first) : "Ubicación actual";
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

      // Distancia
      double dist = DistanciaService.calcularDistancia(origenLat, origenLon, dLat, dLon);

      if (kUseDirectionsForDistance) {
        final dir = await DirectionsService.drivingDistanceKm(
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

      final precioDouble = DistanciaService.calcularPrecio(dist, idaYVuelta: idaYVuelta);
      final int precioCents = (precioDouble * 100).round();
      final int comisionCents = ((precioCents * 20) + 50) ~/ 100;
      final int gananciaCents = precioCents - comisionCents;

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
            ),
          );

        _polylines
          ..clear()
          ..add(
            Polyline(
              polylineId: const PolylineId('ruta'),
              points: [LatLng(origenLat, origenLon), LatLng(dLat, dLon)],
              width: 4,
              color: const Color(0xFF49F18B),
              geodesic: true,
            ),
          );

        _map?.animateCamera(
          CameraUpdate.newLatLngBounds(
            _boundsFrom(LatLng(origenLat, origenLon), LatLng(dLat, dLon)),
            80,
          ),
        );
      });
    } catch (e) {
      _snack("❌ Error al calcular distancia: $e");
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  LatLngBounds _boundsFrom(LatLng a, LatLng b) {
    final southWest = LatLng(math.min(a.latitude, b.latitude), math.min(a.longitude, b.longitude));
    final northEast = LatLng(math.max(a.latitude, b.latitude), math.max(a.longitude, b.longitude));
    return LatLngBounds(southwest: southWest, northeast: northEast);
  }

  // ====== FECHA/HORA ======
  Future<void> _seleccionarFechaHora() async {
    final now = DateTime.now();
    final last = now.add(const Duration(days: kMaxDiasProgramacion));

    final fecha = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(minutes: 5)),
      firstDate: now,
      lastDate: last, // límite de 90 días
      builder: (context, child) {
        final base = ThemeData.dark();
        return Theme(
          data: base.copyWith(
  colorScheme: const ColorScheme.dark(primary: Colors.greenAccent),
  dialogTheme: const DialogThemeData(backgroundColor: Colors.black), // ✅
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
        final base = ThemeData.dark();
        return Theme(
          data: base.copyWith(
            colorScheme: const ColorScheme.dark(primary: Colors.greenAccent),
            timePickerTheme: const TimePickerThemeData(
              backgroundColor: Colors.black,
              dialHandColor: Colors.greenAccent,
            ),
          ),
          child: child!,
        );
      },
    );

    if (!mounted || hora == null) return;
    setState(() {
      fechaHora = DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute);
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
              trailing: label == metodoPago ? const Icon(Icons.check, color: Colors.greenAccent) : null,
              onTap: () => Navigator.pop(ctx, label),
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                height: 4,
                width: 48,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
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

  // ====== CONFIRMAR ======
  Future<void> _programarViaje(ScaffoldMessengerState messenger, NavigatorState nav) async {
    if (_cargando) return;
    if (!_formKey.currentState!.validate()) return;

    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      messenger.showSnackBar(const SnackBar(content: Text("Debes iniciar sesión para continuar.")));
      return;
    }

    if (!ubicacionObtenida || latCliente == null || latDestino == null) {
      messenger.showSnackBar(const SnackBar(content: Text("Debes calcular el precio primero.")));
      return;
    }

    // Validaciones de ventana temporal (producción)
    if (!widget.modoAhora) {
      final now = DateTime.now();
      final minFuturo = now.add(const Duration(minutes: kAhoraUmbralMin + 1));
      final maxFuturo = now.add(const Duration(days: kMaxDiasProgramacion));

      if (fechaHora.isBefore(minFuturo)) {
        messenger.showSnackBar(
          SnackBar(content: Text("Selecciona una hora al menos ${kAhoraUmbralMin + 1} minutos en el futuro.")),
        );
        return;
      }
      if (fechaHora.isAfter(maxFuturo)) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Solo puedes programar hasta 90 días en el futuro.")),
        );
        return;
      }
    }

    setState(() => _cargando = true);

    try {
      await u.getIdToken(true);
      await RolesService.ensureUserDoc(u.uid, defaultRol: Roles.cliente);
      final rol = await RolesService.getRol(u.uid);
      if ((rol ?? '').toLowerCase() != 'cliente') {
        messenger.showSnackBar(const SnackBar(content: Text("Esta cuenta no es de cliente.")));
        return;
      }

      final origenLegible =
          (origenTexto.isNotEmpty) ? origenTexto : (usarOrigenManual ? origenManual : "Ubicación actual");
      final destinoLegible = (destinoTexto.isNotEmpty) ? destinoTexto : destino;

      // Guardamos fecha en UTC para estabilidad backend
      final DateTime fechaParaGuardarUtc =
          widget.modoAhora ? DateTime.now().toUtc() : fechaHora.toUtc();

      final id = await ViajesRepo.crearViajePendiente(
        uidCliente: u.uid,
        origen: origenLegible,
        destino: destinoLegible,
        latOrigen: latCliente!,
        lonOrigen: lonCliente!,
        latDestino: latDestino!,
        lonDestino: lonDestino!,
        fechaHora: fechaParaGuardarUtc, // UTC
        precio: precioCalculado,
        metodoPago: metodoPago,
        tipoVehiculo: tipoVehiculo,
        idaYVuelta: idaYVuelta,
      );

      final accion = widget.modoAhora ? 'solicitado exitosamente' : 'programado exitosamente';
      messenger.showSnackBar(SnackBar(content: Text("✅ Viaje $accion — #${id.substring(0, 6)}")));

      if (mounted && Navigator.canPop(context)) {
        nav.pop(id);
      }
    } on FirebaseException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('❌ Firestore (${e.code}): ${e.message ?? e}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('❌ Error al guardar el viaje: $e')));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ====== UI ======
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
                width: active ? 2 : 1,
              ),
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
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ProgramarViaje(modoAhora: true)));
        }),
        const SizedBox(width: 10),
        tab('Programar viaje', !ahora, () {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ProgramarViaje(modoAhora: false)));
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('dd/MM/yyyy - HH:mm');
    final canConfirm = ubicacionObtenida && precioCalculado > 0;

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
        // 🎨 Logo en AppBar (diseño)
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
              child: const _Banner(text: 'Activa la ubicación en Ajustes del sistema.', icon: Icons.location_off),
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
            minChildSize: 0.26,
            maxChildSize: 0.88,
            initialChildSize: 0.36,
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
                        Center(
                          child: Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Tabs modo (enmarcados)
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

                        // ===== DESTINO con overlay clickeable sobre la LUPA =====
                        if (kUsePlacesAutocomplete)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                children: [
                                  CampoLugarAutocomplete(
                                    label: 'Destino',
                                    hint: '¿A dónde vas?',
                                    onPlaceSelected: (det) {
                                      _destinoDet = det;
                                      destino = det.displayLabel;
                                      destinoTexto = det.displayLabel;
                                      latDestino = det.lat;
                                      lonDestino = det.lon;
                                      _onLongPressMap(LatLng(det.lat, det.lon)); // pinta en mapa + línea
                                      setState(() {});
                                    },
                                    onTextChanged: (t) {
                                      destino = t;
                                      latDestino = null;
                                      lonDestino = null;
                                    },
                                  ),
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
                              const Expanded(child: Text('¿Ida y vuelta?', style: TextStyle(color: Colors.white))),
                              Switch.adaptive(value: idaYVuelta, onChanged: (v) => setState(() => idaYVuelta = v)),
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
                                items: const [
                                  'Carro',
                                  'Jeepeta',
                                  'Minibús',
                                  'Minivan',
                                  'Autobús/Guagua',
                                ].map((e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e, style: const TextStyle(color: Colors.white)),
                                    )).toList(),
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
                                  label: Text('Elegir método de pago',
                                      style: TextStyle(color: Colors.green.shade300, fontWeight: FontWeight.w700)),
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
                          Text("Programado para: ${formato.format(fechaHora)}",
                              style: const TextStyle(color: Colors.greenAccent)),
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

                        if (precioCalculado > 0)
                          _Caja(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Resumen', style: TextStyle(color: Colors.white70)),
                                const SizedBox(height: 6),
                                Text('Distancia estimada: ${FormatosMoneda.km(distanciaKm)}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text('Total estimado: ${FormatosMoneda.rd(precioCalculado)}',
                                    style: const TextStyle(
                                        color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 4),
                                Text('Ganancia taxista aprox.: ${FormatosMoneda.rd(gananciaTaxistaCalculada)}',
                                    style: const TextStyle(color: Colors.white70)),
                              ],
                            ),
                          ),

                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: canConfirm
                                ? () => _programarViaje(ScaffoldMessenger.of(context), Navigator.of(context))
                                : null,
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(widget.modoAhora ? 'Confirmar Viaje' : 'Confirmar Programación'),
                            style: _botonEstilo(),
                          ),
                        ),

                        if (latCliente != null && latDestino != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              "Desde: ${origenTexto.isNotEmpty ? origenTexto : (usarOrigenManual ? origenManual : 'Ubicación actual')}\n"
                              "Hasta: ${destinoTexto.isNotEmpty ? destinoTexto : destino}",
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ),
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
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.greenAccent, width: 2),
          ),
        ),
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
