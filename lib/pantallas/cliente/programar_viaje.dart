// lib/pantallas/cliente/programar_viaje.dart
// ProgramarViaje — estilo RAI, tipo inDrive (autocomplete + mapa tiempo real)
// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_null_comparison

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// 🔰 IMPORT para ir al viaje en curso
import 'package:flygo_nuevo/pantallas/cliente/viaje_en_curso_cliente.dart';

// ✅ Confirmación de viaje programado (no confundir con “en curso”)

// ✅ IMPORT para la pantalla de espera de turismo
import 'package:flygo_nuevo/pantallas/cliente/programar_viaje_multi.dart';

// Tus servicios/componentes
import 'package:flygo_nuevo/utils/navegacion_salida_app.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/permisos_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/widgets/campo_lugar_autocomplete.dart';
import 'package:flygo_nuevo/widgets/cotizacion_precio_loading.dart';
import 'package:flygo_nuevo/widgets/programar_viaje_futuro_animation.dart';
import 'package:flygo_nuevo/widgets/parpadeo_ruta_programar.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/pay_config.dart';
import 'package:flygo_nuevo/pantallas/cliente/viaje_programado_pendiente.dart';

// ✅ IMPORTS PARA TURISMO
import 'package:flygo_nuevo/widgets/turismo_destinos_sheet_host.dart';
import 'package:flygo_nuevo/servicios/turismo_catalogo_rd.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';

// ✅ NUEVO SERVICIO UNIFICADO DE TARIFAS
import 'package:flygo_nuevo/servicios/tarifa_service_unificado.dart';
import 'package:flygo_nuevo/utils/trip_publish_windows.dart';

// ===== Flags / Reglas =====
const bool kUsePlacesAutocomplete = true;
const bool kUseDirectionsForDistance = true;
const int kMaxDiasProgramacion = 90;

// ===== Snackbars =====
const String kMsgLogin = 'Debes iniciar sesión para continuar.';
const String kMsgCalcFirst = 'Debes calcular el precio primero.';
const String kMsgMaxFuture =
    'Solo puedes programar hasta 90 días en el futuro.';
const String kMsgPickupPasado =
    'La hora de recogida no puede quedar en el pasado. Elige la hora actual o una próxima.';

class ProgramarViaje extends StatefulWidget {
  final bool modoAhora;
  final String? tipoServicio;
  final String? subtipoTurismo;
  final String? catalogoTurismoId;

  // 🔥 NUEVOS PARÁMETROS PARA DESTINO PRECARGADO
  final String? destinoPrecargado;
  final double? latDestinoPrecargado;
  final double? lonDestinoPrecargado;

  const ProgramarViaje({
    super.key,
    required this.modoAhora,
    this.tipoServicio,
    this.subtipoTurismo,
    this.catalogoTurismoId,
    this.destinoPrecargado,
    this.latDestinoPrecargado,
    this.lonDestinoPrecargado,
  });

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

  // El tipo de servicio viene del widget, no se cambia localmente
  String get tipoServicio => widget.tipoServicio ?? 'normal';

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

  /// Solo en programar: buscar punto de salida en RD (p. ej. sin GPS local).
  bool _origenBuscarDireccion = false;

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

  static const double _sheetMinFracProgramar = 0.30;
  int _mapProgrammaticCameraDepth = 0;
  Timer? _programarMapGestureEndDebounce;

  void _onProgramarMapCameraIdle() {
    if (_mapProgrammaticCameraDepth > 0) {
      _mapProgrammaticCameraDepth--;
      return;
    }
    _programarMapGestureEndDebounce?.cancel();
    if (mounted) _expandProgramarSheetTrasMapaInteract();
  }

  void _expandProgramarSheetTrasMapaInteract() {
    if (!_sheetCtrl.isAttached) return;
    final double target = (_vistaResumenCotizada && _mostrarResumenCotizacion)
        ? 0.72
        : (widget.modoAhora ? 0.86 : 0.88);
    try {
      _sheetCtrl.animateTo(
        target.clamp(_sheetMinFracProgramar, 0.88),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  void _onProgramarMapUserGesture() {
    if (_mapProgrammaticCameraDepth > 0) return;
    unawaited(_collapseProgramarSheetForMap());
  }

  Future<void> _collapseProgramarSheetForMap() async {
    if (!_sheetCtrl.isAttached) return;
    try {
      final double s = _sheetCtrl.size;
      if (s <= _sheetMinFracProgramar + 0.03) return;
      await _sheetCtrl.animateTo(
        _sheetMinFracProgramar,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  Future<void> _programarMapAnimate(
      Future<void> Function(GoogleMapController c) op) async {
    final GoogleMapController? c = _map;
    if (c == null) return;
    _mapProgrammaticCameraDepth++;
    try {
      await op(c);
    } catch (_) {
      if (_mapProgrammaticCameraDepth > 0) _mapProgrammaticCameraDepth--;
    }
  }

  // Flecha “nudge”
  late final AnimationController _nudgeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  late final Animation<Offset> _nudgeOffset = Tween<Offset>(
    begin: const Offset(0, .15),
    end: const Offset(0, -0.05),
  ).animate(CurvedAnimation(parent: _nudgeCtrl, curve: Curves.easeInOut));
  Timer? _nudgeTimer;

  // ✅ VARIABLES PARA TURISMO
  TurismoLugar? _destinoTurismoSeleccionado;
  String _tipoVehiculoTurismo = 'carro';
  int? _pasajerosTurismo;

  // ✅ VARIABLES PARA PEAJE
  final TextEditingController _peajeCtrl = TextEditingController();
  double _peaje = 0.0;

  // ✅ Timer para debounce del cálculo automático
  Timer? _calculoDebounce;

  /// Al invalidar (p. ej. X en destino), los cálculos async viejos no reaplican precio.
  int _cotizacionSeq = 0;

  /// Tras cotizar: panel corto con precio grande; el cliente puede abrir el formulario completo.
  bool _vistaResumenCotizada = false;

  // 🔥 CACHÉ para el contador de viajes
  int? _contadorViajesCache;
  DateTime? _contadorTimestamp;
  Map<String, dynamic>? _promoSnapshotCotizacion;

  // 🎨 Color del servicio (solo UI)
  Color get _colorServicio {
    switch (tipoServicio) {
      case 'motor':
        return Colors.orange;
      case 'turismo':
        return Colors.purple;
      default:
        return Colors.greenAccent;
    }
  }

  @override
  void initState() {
    super.initState();

    if (widget.modoAhora) {
      fechaHora = DateTime.now();
    } else {
      fechaHora = DateTime.now().add(const Duration(minutes: 20));
      if (kUsePlacesAutocomplete) {
        _origenBuscarDireccion = true;
      }
    }

    // Si viene con subtipoTurismo, lo asignamos
    if (widget.subtipoTurismo != null) {
      _tipoVehiculoTurismo = _normalizarTipoVehiculo(widget.subtipoTurismo!);
    }

    // 🔥 Si viene con destino precargado (desde catálogo turismo)
    if (widget.destinoPrecargado != null &&
        widget.latDestinoPrecargado != null &&
        widget.lonDestinoPrecargado != null) {
      // 🔥 Determinar el subtipo basado en el nombre del destino
      final String subtipo =
          _determinarSubtipoTurismo(widget.destinoPrecargado!);

      // Crear objeto TurismoLugar a partir de datos precargados
      _destinoTurismoSeleccionado = TurismoLugar(
        id: widget.catalogoTurismoId ?? 'destino_manual',
        nombre: widget.destinoPrecargado!,
        ciudad: _extraerCiudadDeDestino(widget.destinoPrecargado!),
        subtipo: subtipo,
        lat: widget.latDestinoPrecargado!,
        lon: widget.lonDestinoPrecargado!,
        descripcion: widget.destinoPrecargado!,
        imagen: null,
        popularidad: 0,
      );

      destinoTexto = widget.destinoPrecargado!;
      destino = widget.destinoPrecargado!;
      latDestino = widget.latDestinoPrecargado;
      lonDestino = widget.lonDestinoPrecargado;

      // Programar cálculo automático después de que el mapa esté listo
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _programarCalculoAutomatico();
      });
    }

    _initUbicacionParaMapa();

    WidgetsBinding.instance.addPostFrameCallback((_) => _expandSheet());
    _nudgeCtrl.repeat(reverse: true);
    _nudgeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _nudgeCtrl.stop();
    });

    // 🔥 Si es turismo y no hay destino seleccionado, abrir selector automáticamente
    if (tipoServicio == 'turismo' && _destinoTurismoSeleccionado == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mostrarSelectorDestinosTuristicos();
      });
    }
  }

  // 🔥 Función para normalizar tipo de vehículo
  String _normalizarTipoVehiculo(String tipo) {
    final t = tipo.toLowerCase();
    if (t.contains('carro')) return 'carro';
    if (t.contains('jeepeta')) return 'jeepeta';
    if (t.contains('minivan')) return 'minivan';
    if (t.contains('bus')) return 'bus';
    return 'carro';
  }

  // 🔥 Función para determinar el subtipo de turismo basado en el nombre del destino
  String _determinarSubtipoTurismo(String destino) {
    final destinoLower = destino.toLowerCase();

    if (destinoLower.contains('aeropuerto') ||
        destinoLower.contains('airport') ||
        destinoLower.contains('sdq') ||
        destinoLower.contains('puj') ||
        destinoLower.contains('sti')) {
      return 'AEROPUERTO';
    }
    if (destinoLower.contains('playa') || destinoLower.contains('beach')) {
      return 'PLAYA';
    }
    if (destinoLower.contains('resort')) {
      return 'RESORT';
    }
    if (destinoLower.contains('hotel')) {
      return 'HOTEL';
    }
    if (destinoLower.contains('tour') || destinoLower.contains('excursion')) {
      return 'TOUR';
    }
    if (destinoLower.contains('parque') || destinoLower.contains('park')) {
      return 'PARQUE';
    }
    if (destinoLower.contains('montaña') || destinoLower.contains('montana')) {
      return 'MONTANA';
    }
    if (destinoLower.contains('muelle') || destinoLower.contains('puerto')) {
      return 'MUELLE';
    }
    if (destinoLower.contains('cascada') || destinoLower.contains('salto')) {
      return 'CASCADA';
    }
    if (destinoLower.contains('lago') || destinoLower.contains('laguna')) {
      return 'LAGO';
    }
    if (destinoLower.contains('museo')) {
      return 'MUSEO';
    }
    if (destinoLower.contains('zona colonial')) {
      return 'ZONA_COLONIAL';
    }

    return 'CIUDAD';
  }

  // Función auxiliar para extraer ciudad del destino
  String _extraerCiudadDeDestino(String destino) {
    if (destino.contains('Santo Domingo')) return 'Santo Domingo';
    if (destino.contains('Punta Cana')) return 'Punta Cana';
    if (destino.contains('Santiago')) return 'Santiago';
    if (destino.contains('La Romana')) return 'La Romana';
    if (destino.contains('Puerto Plata')) return 'Puerto Plata';
    if (destino.contains('Samana')) return 'Samaná';
    if (destino.contains('Jarabacoa')) return 'Jarabacoa';
    return 'República Dominicana';
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _nudgeTimer?.cancel();
    _nudgeCtrl.dispose();
    _peajeCtrl.dispose();
    _calculoDebounce?.cancel();
    _programarMapGestureEndDebounce?.cancel();
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

  bool get _mostrarResumenCotizacion =>
      _vistaResumenCotizada &&
      ubicacionObtenida &&
      precioCalculado > 0 &&
      !_cargando &&
      (tipoServicio != 'turismo' || _destinoTurismoSeleccionado != null);

  void _animarSheetParaResumenCotizado() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _sheetCtrl.animateTo(
          0.72,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
    });
  }

  void _abrirFormularioCompletoDesdeResumen() {
    setState(() => _vistaResumenCotizada = false);
    _expandToMax();
  }

  String _lineaOrigenResumen() {
    final o = origenTexto.trim();
    if (o.isNotEmpty) return o;
    if (!widget.modoAhora &&
        _origenBuscarDireccion &&
        origenManual.trim().isNotEmpty) {
      return origenManual.trim();
    }
    return 'Tu ubicación actual (GPS / mapa)';
  }

  String _lineaDestinoResumen() {
    final d = destinoTexto.trim();
    if (d.isNotEmpty) return d;
    if (_destinoTurismoSeleccionado != null) {
      return _destinoTurismoSeleccionado!.nombre;
    }
    final x = destino.trim();
    return x.isNotEmpty ? x : 'Destino';
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
        desiredAccuracy: LocationAccuracy.medium,
      );
      final here = LatLng(pos.latitude, pos.longitude);
      _origenMap = here;
      _updateOrigenMarker(here);

      setState(() => _cargandoUbicacion = false);

      await _programarMapAnimate(
        (c) => c.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: here, zoom: 15),
          ),
        ),
      );
      _didCenterOnce = true;

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 15,
        ),
      ).listen((p) {
        final ll = LatLng(p.latitude, p.longitude);
        _origenMap = ll;
        _updateOrigenMarker(ll);
        if (_map != null && _didCenterOnce) {
          unawaited(_programarMapAnimate(
            (c) => c.animateCamera(CameraUpdate.newLatLng(ll)),
          ));
        }
        if (mounted) setState(() {});
        // Viaje ahora: si el destino se eligió antes que el GPS, recalcular al mover origen
        if (widget.modoAhora &&
            mounted &&
            _tieneDestinoParaCalculo() &&
            !ubicacionObtenida) {
          _programarCalculoAutomatico();
        }
      });

      // Viaje ahora: al quedar listo el GPS, si ya había destino (Places / mapa / turismo), calcular
      if (mounted && widget.modoAhora && _tieneDestinoParaCalculo()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _dibujarRutaSiHayDestino();
          _programarCalculoAutomatico();
        });
      }
    } catch (_) {
      setState(() => _cargandoUbicacion = false);
    }
  }

  // 🔥 Nuevo método para dibujar ruta cuando hay destino
  Future<void> _dibujarRutaSiHayDestino() async {
    if (_origenMap != null && latDestino != null && lonDestino != null) {
      await _dibujarRutaReal(
        oLat: _origenMap!.latitude,
        oLon: _origenMap!.longitude,
        dLat: latDestino!,
        dLon: lonDestino!,
        previewOnly: true,
      );
    }
  }

  void _updateOrigenMarker(LatLng pos) {
    _markers.removeWhere((m) => m.markerId.value == 'origen');
    _markers.add(
      Marker(
        markerId: const MarkerId('origen'),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        infoWindow: const InfoWindow(title: 'Origen'),
        zIndexInt: 2,
      ),
    );
  }

  Future<void> _centrarEnMiUbicacion() async {
    if (_origenMap == null) return;
    _didCenterOnce = true;
    await _programarMapAnimate(
      (c) => c.animateCamera(CameraUpdate.newLatLng(_origenMap!)),
    );
  }

  void _onLongPressMap(LatLng p) async {
    unawaited(_collapseProgramarSheetForMap());
    latDestino = p.latitude;
    lonDestino = p.longitude;
    _destinoDet = null;
    if (mounted) {
      setState(_invalidarCotizacion);
    }

    _markers.removeWhere((m) => m.markerId.value == 'destino');
    _markers.add(
      Marker(
        markerId: const MarkerId('destino'),
        position: p,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: const InfoWindow(title: 'Destino'),
        zIndexInt: 1,
      ),
    );

    final placemarks = await _safePlacemark(p.latitude, p.longitude);
    destinoTexto = placemarks.isNotEmpty
        ? _direccionBonitaRD(placemarks.first)
        : '(${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)})';
    destino = destinoTexto;
    // Limpiar destino turístico si se selecciona uno manualmente
    if (tipoServicio == 'turismo') {
      setState(() {
        _destinoTurismoSeleccionado = null;
      });
    }

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

    if (_origenMap != null) {
      _programarCalculoAutomatico();
    }
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
        .replaceAll(RegExp(r'\bSto\.?\s*Dgo\.?\b', caseSensitive: false),
            'Santo Domingo')
        .replaceAll(RegExp(r'Higuey', caseSensitive: false), 'Higüey')
        .replaceAll(RegExp(r'San Pedro de Macoris', caseSensitive: false),
            'San Pedro de Macorís')
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

  // 🔥 NUEVO: Obtener contador de viajes del cliente CON CACHÉ
  Future<int> _obtenerContadorViajes(String uidCliente) async {
    if (_contadorViajesCache != null &&
        _contadorTimestamp != null &&
        DateTime.now().difference(_contadorTimestamp!) <
            const Duration(minutes: 5)) {
      return _contadorViajesCache!;
    }

    try {
      final snapshot = await fs.FirebaseFirestore.instance
          .collection('viajes')
          .where('uidCliente', isEqualTo: uidCliente)
          .where('completado', isEqualTo: true)
          .count()
          .get();

      // El MxK se calcula sobre el viaje que se está cotizando ahora,
      // no sobre los viajes ya completados.
      final int contador = (snapshot.count ?? 0) + 1;

      _contadorViajesCache = contador;
      _contadorTimestamp = DateTime.now();

      return contador;
    } catch (e) {
      debugPrint('Error obteniendo contador de viajes: $e');
      return 0;
    }
  }

  // ====== CALCULAR PRECIO CON TARIFA POR TIPO DE SERVICIO ======
  Future<double> _calcularPrecioPorTipo(double distancia, bool idaVuelta,
      {double peaje = 0.0}) async {
    final servicio = TarifaServiceUnificado();
    final user = FirebaseAuth.instance.currentUser;

    int contadorViajes = 1;
    if (user != null) {
      contadorViajes = await _obtenerContadorViajes(user.uid);
    }
    _promoSnapshotCotizacion =
        await servicio.construirPromoSnapshot(contadorViajes);

    try {
      if (tipoServicio == 'normal') {
        return await servicio.calcularPrecio(
          tipoServicio: tipoServicio,
          tipoVehiculo: tipoVehiculo,
          distanciaKm: distancia,
          idaVuelta: idaVuelta,
          peaje: peaje,
          contadorViajes: contadorViajes,
        );
      }

      if (tipoServicio == 'motor') {
        return await servicio.calcularPrecio(
          tipoServicio: tipoServicio,
          distanciaKm: distancia,
          idaVuelta: idaVuelta,
          peaje: peaje,
          contadorViajes: contadorViajes,
        );
      }

      if (tipoServicio == 'turismo') {
        // 🔥 CORREGIDO: Usar el tipo de vehículo correctamente
        final String vehiculo = _tipoVehiculoTurismo;
        final String subtipo = _destinoTurismoSeleccionado?.subtipo ?? 'CIUDAD';

        return await servicio.calcularPrecio(
          tipoServicio: tipoServicio,
          tipoVehiculo: vehiculo,
          subtipoTurismo: subtipo,
          distanciaKm: distancia,
          idaVuelta: idaVuelta,
          peaje: peaje,
          contadorViajes: contadorViajes,
        );
      }

      return 0.0;
    } catch (e) {
      if (mounted) _snack('Error calculando precio: $e');
      return 0.0;
    }
  }

  void _invalidarCotizacion() {
    _calculoDebounce?.cancel();
    _cotizacionSeq++;
    precioCalculado = 0;
    ubicacionObtenida = false;
    comisionCalculada = 0;
    gananciaTaxistaCalculada = 0;
    distanciaKm = 0;
    _cargando = false;
    _vistaResumenCotizada = false;
  }

  void _setCargaFalseSiCorre(int runId) {
    if (!mounted || runId != _cotizacionSeq) return;
    setState(() => _cargando = false);
  }

  /// Misma lógica que en [_obtenerUbicacionYCalcularPrecio] para saber si hay destino.
  bool _tieneDestinoParaCalculo() {
    if (_destinoTurismoSeleccionado != null) return true;
    if (latDestino != null && lonDestino != null) return true;
    if (kUsePlacesAutocomplete && _destinoDet != null) return true;
    return false;
  }

  void _programarCalculoAutomatico() {
    _calculoDebounce?.cancel();
    _calculoDebounce = Timer(const Duration(milliseconds: 800), () {
      _obtenerUbicacionYCalcularPrecio(automatico: true);
    });
  }

  Future<void> _obtenerUbicacionYCalcularPrecio(
      {bool automatico = false}) async {
    if (_cargando) return;

    if (!widget.modoAhora &&
        _origenBuscarDireccion &&
        origenManual.trim().isEmpty &&
        _origenDetManual == null) {
      return;
    }

    final bool tieneOrigen = widget.modoAhora
        ? _origenMap != null
        : (_origenBuscarDireccion
            ? (_origenDetManual != null || origenManual.trim().isNotEmpty)
            : _origenMap != null);
    final tieneDestino = latDestino != null ||
        _destinoDet != null ||
        _destinoTurismoSeleccionado != null;

    if (!tieneOrigen || !tieneDestino) return;

    FocusScope.of(context).unfocus();
    _formKey.currentState?.save();

    destino = destino.trim();
    if (_origenBuscarDireccion) origenManual = origenManual.trim();

    setState(() => _cargando = true);
    final int runId = _cotizacionSeq;
    try {
      double origenLat = 0, origenLon = 0;
      String origenLegible = '';
      String destinoLegible = '';
      double dLat = 0, dLon = 0;

      // ORIGEN: búsqueda (solo programar) o mapa / GPS
      if (!widget.modoAhora && _origenBuscarDireccion) {
        if (kUsePlacesAutocomplete && _origenDetManual != null) {
          origenLat = _origenDetManual!.lat;
          origenLon = _origenDetManual!.lon;
          origenLegible = _origenDetManual!.displayLabel;
        } else {
          final or = await _geocodeConFallback(origenManual);
          if (or == null) {
            if (!automatico) {
              _snack("❌ No se encontró esa dirección de origen.");
            }
            _setCargaFalseSiCorre(runId);
            return;
          }
          origenLat = or.lat;
          origenLon = or.lon;
          origenLegible = origenManual;
        }
      } else if (_origenMap != null) {
        origenLat = _origenMap!.latitude;
        origenLon = _origenMap!.longitude;
        final placemarks = await _safePlacemark(origenLat, origenLon);
        origenLegible = placemarks.isNotEmpty
            ? _direccionBonitaRD(placemarks.first)
            : "Ubicación actual";
      } else {
        final ok = await PermisosService.ensureUbicacion(context);
        if (!ok) {
          _setCargaFalseSiCorre(runId);
          return;
        }
        final posicion = await GpsService.obtenerUbicacionActual();
        if (posicion == null) {
          if (!automatico) _snack("❌ No se pudo obtener ubicación GPS.");
          _setCargaFalseSiCorre(runId);
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
      } else if (_destinoTurismoSeleccionado != null) {
        dLat = _destinoTurismoSeleccionado!.lat;
        dLon = _destinoTurismoSeleccionado!.lon;
        destinoLegible = _destinoTurismoSeleccionado!.nombre;
      } else {
        final de = await _geocodeConFallback(destino);
        if (de == null) {
          if (!automatico) _snack("❌ No se encontró esa dirección de destino.");
          _setCargaFalseSiCorre(runId);
          return;
        }
        dLat = de.lat;
        dLon = de.lon;
        final dPlacemarks = await _safePlacemark(dLat, dLon);
        destinoLegible = dPlacemarks.isNotEmpty
            ? _direccionBonitaRD(dPlacemarks.first)
            : destino;
      }

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
        if (!automatico) _snack("❌ No se pudo calcular una distancia válida.");
        _setCargaFalseSiCorre(runId);
        return;
      }

      final List<LatLng> routeLatLng = dir?.path ?? const <LatLng>[];
      _peajeCtrl.text = _peaje.toStringAsFixed(0);

      final double precioDouble =
          await _calcularPrecioPorTipo(dist, idaYVuelta, peaje: _peaje);
      final int precioCents = (precioDouble * 100).round();
      final int comisionCents = ((precioCents * 20) + 50) ~/ 100;
      final int gananciaCents = precioCents - comisionCents;

      if (!mounted || runId != _cotizacionSeq) return;

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
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueViolet),
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

        _cargando = false;
        // Siempre mostramos resumen al terminar una cotización para priorizar precio + confirmar.
        _vistaResumenCotizada = true;
      });

      _animarSheetParaResumenCotizado();

      if (_map != null && runId == _cotizacionSeq) {
        if (routeLatLng.length >= 2) {
          await _programarMapAnimate(
            (c) => c.animateCamera(
              CameraUpdate.newLatLngBounds(_boundsFromList(routeLatLng), 60),
            ),
          );
        } else {
          await _programarMapAnimate(
            (c) => c.animateCamera(
              CameraUpdate.newLatLngBounds(
                _boundsFrom(LatLng(origenLat, origenLon), LatLng(dLat, dLon)),
                80,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!automatico && runId == _cotizacionSeq) {
        _snack("❌ Error al calcular distancia: $e");
      }
      _setCargaFalseSiCorre(runId);
    }
  }

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
          await _programarMapAnimate(
            (c) => c.animateCamera(
              CameraUpdate.newLatLngBounds(_boundsFromList(pts), 60),
            ),
          );
        } else {
          await _programarMapAnimate(
            (c) => c.animateCamera(
              CameraUpdate.newLatLngBounds(
                _boundsFrom(LatLng(oLat, oLon), LatLng(dLat, dLon)),
                80,
              ),
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
        final cs = theme.colorScheme;
        return Theme(
          data: theme.copyWith(
            colorScheme: cs.copyWith(
              primary: cs.brightness == Brightness.dark
                  ? Colors.greenAccent
                  : const Color(0xFF0F9D58),
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
        final cs = theme.colorScheme;
        return Theme(
          data: theme.copyWith(
            colorScheme: cs.copyWith(
              primary: cs.brightness == Brightness.dark
                  ? Colors.greenAccent
                  : const Color(0xFF0F9D58),
            ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted || hora == null) return;

    setState(() {
      fechaHora = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        hora.hour,
        hora.minute,
      );
    });
  }

  // ====== MÉTODO DE PAGO ======
  Future<void> _elegirMetodoPago() async {
    if (_cargando) return;
    final elegido = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final t = Theme.of(ctx);
        final cs = t.colorScheme;
        final onSurface = cs.onSurface;
        final muted = onSurface.withValues(alpha: 0.65);
        final disabled = onSurface.withValues(alpha: 0.38);
        Widget item(String label, {bool enabled = true, String? subtitle}) {
          return ListTile(
            title: Text(
              label,
              style: TextStyle(
                color: enabled ? onSurface : disabled,
                fontWeight: enabled ? FontWeight.normal : FontWeight.w300,
              ),
            ),
            subtitle: subtitle != null
                ? Text(
                    subtitle,
                    style: TextStyle(color: muted, fontSize: 12),
                  )
                : null,
            trailing: label == metodoPago && enabled
                ? Icon(Icons.check,
                    color: cs.brightness == Brightness.dark
                        ? Colors.greenAccent
                        : const Color(0xFF0F9D58))
                : null,
            enabled: enabled,
            onTap: enabled ? () => Navigator.pop(ctx, label) : null,
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 8),
              Container(
                height: 4,
                width: 48,
                decoration: BoxDecoration(
                  color: onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Método de pago',
                style: TextStyle(color: muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              ...PayConfig.metodosReservaVisibles.map(
                (String label) => item(label),
              ),
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

  // ====== BLOQUEO ======
  Future<bool> _bloquearSiTaxista() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return true;
    try {
      final rol = (await RolesService.getRol(u.uid))?.toLowerCase();
      if (rol == Roles.taxista || rol == Roles.admin) {
        _snack('Esta cuenta es de $rol.');
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ✅ MÉTODO PARA MOSTRAR SELECTOR DE DESTINOS TURÍSTICOS
  void _mostrarSelectorDestinosTuristicos() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TurismoDestinosSheetHost(
        seedLat: latCliente ?? _origenMap?.latitude,
        seedLon: lonCliente ?? _origenMap?.longitude,
        tipoVehiculoInicial: _tipoVehiculoTurismo,
        onDestinoSeleccionado: (seleccion) async {
          // 🔥 VALIDAR TIPO DE VEHÍCULO - ASEGURAR QUE SEA VÁLIDO
          String vehiculoValido = seleccion.tipoVehiculo;
          const vehiculosValidos = ['carro', 'jeepeta', 'minivan', 'bus'];
          if (!vehiculosValidos.contains(vehiculoValido)) {
            debugPrint(
                '⚠️ Valor inválido recibido en tipoVehiculo: "$vehiculoValido", usando "carro"');
            vehiculoValido = 'carro';
          }

          Navigator.pop(context);

          if (latCliente == null && _origenMap != null) {
            latCliente = _origenMap!.latitude;
            lonCliente = _origenMap!.longitude;
          }

          setState(() {
            _destinoTurismoSeleccionado = seleccion.lugar;
            _tipoVehiculoTurismo = vehiculoValido;
            _pasajerosTurismo = seleccion.pasajeros;

            latDestino = seleccion.lugar.lat;
            lonDestino = seleccion.lugar.lon;
            destinoTexto = seleccion.lugar.nombre;
            destino = seleccion.lugar.nombre;

            distanciaKm = seleccion.distanciaKm;
            ubicacionObtenida = true;

            if (_map != null) {
              _markers.removeWhere((m) => m.markerId.value == 'destino');
              _markers.add(
                Marker(
                  markerId: const MarkerId('destino'),
                  position: LatLng(seleccion.lugar.lat, seleccion.lugar.lon),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueViolet),
                  infoWindow: InfoWindow(title: seleccion.lugar.nombre),
                ),
              );
            }
          });

          // 🔥 Dibujar ruta y calcular precio inmediatamente
          if (_origenMap != null && latDestino != null && lonDestino != null) {
            await _dibujarRutaReal(
              oLat: _origenMap!.latitude,
              oLon: _origenMap!.longitude,
              dLat: latDestino!,
              dLon: lonDestino!,
              previewOnly: true,
            );
          }
          _programarCalculoAutomatico();
        },
      ),
    );
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
      final maxFuturo = now.add(const Duration(days: kMaxDiasProgramacion));
      if (fechaHora.isAfter(maxFuturo)) {
        messenger.showSnackBar(const SnackBar(content: Text(kMsgMaxFuture)));
        return;
      }
      // Tolerancia por desfase reloj / redondeo del picker.
      if (fechaHora.isBefore(now.subtract(const Duration(seconds: 90)))) {
        messenger.showSnackBar(const SnackBar(content: Text(kMsgPickupPasado)));
        return;
      }
    }

    if (await _bloquearSiTaxista()) return;

    setState(() => _cargando = true);
    try {
      await u.getIdToken(true);

      final origenLegible = (origenTexto.isNotEmpty)
          ? origenTexto
          : (!widget.modoAhora &&
                  _origenBuscarDireccion &&
                  origenManual.trim().isNotEmpty)
              ? origenManual.trim()
              : "Ubicación actual";
      final destinoLegible = (destinoTexto.isNotEmpty) ? destinoTexto : destino;

      final DateTime nowUtc = DateTime.now().toUtc();
      final DateTime fechaProgramadaUtc =
          widget.modoAhora ? nowUtc : fechaHora.toUtc();

      /// Programar con recogida dentro de [poolLeadMinutesProgramado] min → como tab Ahora (mapa ya).
      /// Recogida más lejana → pantalla de espera hasta que abra el pool (luego salta a en curso sola).
      final bool viajeInmediato = TripPublishWindows.esProgramadoRecogidaCasiInmediata(
          fechaProgramadaUtc, nowUtc);

      DateTime publishAt;
      DateTime acceptAfter;

      if (viajeInmediato) {
        publishAt = nowUtc;
        acceptAfter = nowUtc;
      } else {
        publishAt = ViajesRepo.poolOpensAtForScheduledPickup(
          fechaProgramadaUtc,
          nowUtc,
        );
        acceptAfter = publishAt;
      }

      final Map<String, dynamic> extras = <String, dynamic>{};
      if (_peaje > 0) extras['peaje'] = _peaje;
      if (_pasajerosTurismo != null) {
        extras['pasajeros'] = _pasajerosTurismo;
      }
      if (_promoSnapshotCotizacion != null) {
        extras['promoSnapshot'] = _promoSnapshotCotizacion;
      }

      final id = await ViajesRepo.crearViajePendiente(
        uidCliente: u.uid,
        origen: origenLegible,
        destino: destinoLegible,
        latOrigen: latCliente!,
        lonOrigen: lonCliente!,
        latDestino: latDestino!,
        lonDestino: lonDestino!,
        fechaHora: fechaProgramadaUtc,
        precio: precioCalculado,
        metodoPago: metodoPago,
        tipoVehiculo:
            tipoServicio == 'turismo' && _tipoVehiculoTurismo.isNotEmpty
                ? _mapTipoVehiculoTurismo(_tipoVehiculoTurismo)
                : tipoVehiculo,
        idaYVuelta: idaYVuelta,
        distanciaKm: distanciaKm > 0 ? distanciaKm : null,
        tipoServicio: tipoServicio,
        subtipoTurismo: tipoServicio == 'turismo'
            ? _tipoVehiculoTurismo
            : widget.subtipoTurismo,
        catalogoTurismoId: tipoServicio == 'turismo'
            ? _destinoTurismoSeleccionado?.id
            : widget.catalogoTurismoId,
        canalAsignacion: tipoServicio == 'turismo' ? 'admin' : 'pool',
        extras: extras,
        publishAt: publishAt,
        acceptAfter: acceptAfter,
      );

      final accion = viajeInmediato
          ? 'solicitado exitosamente'
          : 'programado exitosamente';
      messenger.showSnackBar(
        SnackBar(content: Text("✅ Viaje $accion — #${id.substring(0, 6)}")),
      );

      if (viajeInmediato) {
        // Inmediato (tab «Ahora» o programado con recogida en ventana corta): mismo mapa que motor/ahora.
        await NavigationService.clearAndGo(const ViajeEnCursoCliente());
      } else {
        // Programado lejano: pantalla de espera hasta ventana de pool / conductor.
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ViajeProgramadoPendiente(viajeId: id),
          ),
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

  String _mapTipoVehiculoTurismo(String tipo) {
    switch (tipo) {
      case 'carro':
        return 'Carro Turismo';
      case 'jeepeta':
        return 'Jeepeta Turismo';
      case 'minivan':
        return 'Minivan Turismo';
      case 'bus':
        return 'Bus Turismo';
      default:
        return 'Carro Turismo';
    }
  }

  /// Acentos legibles en claro y oscuro: origen (amarillo) vs destino (púrpura).
  /// Con [tipoSvc] distinto de turismo usa la misma paleta que “Múltiples paradas”.
  ({
    Color origenAccent,
    Color origenFill,
    Color destinoAccent,
    Color destinoFill,
    Color origenBorde,
    Color destinoBorde,
  }) _paletasOrigenDestino(bool isDark, String tipoSvc) {
    if (tipoSvc == 'turismo') {
      final Color oa =
          isDark ? const Color(0xFFFCD34D) : const Color(0xFFD97706);
      final Color da =
          isDark ? const Color(0xFFE9D5FF) : const Color(0xFF7C3AED);
      return (
        origenAccent: oa,
        origenFill: isDark
            ? const Color(0xFF422006).withValues(alpha: 0.92)
            : const Color(0xFFFFFBEB),
        destinoAccent: da,
        destinoFill: isDark
            ? const Color(0xFF3B0764).withValues(alpha: 0.88)
            : const Color(0xFFFAF5FF),
        origenBorde: oa.withValues(alpha: 0.85),
        destinoBorde: da.withValues(alpha: 0.55),
      );
    }
    final Color oa = isDark ? const Color(0xFFFFE082) : const Color(0xFFD97706);
    final Color da = isDark ? const Color(0xFFE9D5FF) : const Color(0xFF7C3AED);
    return (
      origenAccent: oa,
      origenFill: isDark ? const Color(0xFF1A1208) : const Color(0xFFFFFBEB),
      destinoAccent: da,
      destinoFill: isDark ? const Color(0xFF1E0B36) : const Color(0xFFFAF5FF),
      origenBorde: isDark ? const Color(0xFFFF9800) : const Color(0xFFF59E0B),
      destinoBorde: isDark ? const Color(0xFFD8B4FE) : const Color(0xFFA855F7),
    );
  }

  Widget _prefixIconCajaRuta({
    required Color accent,
    required IconData icono,
    Color? colorIcono,
  }) {
    final Color ic = colorIcono ?? accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 2, 0),
      child: Center(
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.72)),
            color: accent.withValues(alpha: 0.14),
          ),
          child: Icon(icono, color: ic, size: 20),
        ),
      ),
    );
  }

  /// Fila tipo “Punto de partida” / destino de la pantalla múltiples paradas.
  Widget _tarjetaLineaPuntoMapa({
    required bool isDark,
    required Color accent,
    required Color fill,
    required Color borde,
    required IconData iconoCaja,
    required String titulo,
    required String subtitulo,
    required Color textMuted,
    bool resplandorOrigen = false,
    bool resplandorDestino = false,
  }) {
    final List<BoxShadow>? sombras = !isDark
        ? null
        : resplandorOrigen
            ? <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.36),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
                BoxShadow(
                  color: const Color(0xFFFFD54A).withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : resplandorDestino
                ? <BoxShadow>[
                    BoxShadow(
                      color: const Color(0xFFA78BFA).withValues(alpha: 0.48),
                      blurRadius: 20,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borde,
          width: resplandorOrigen || resplandorDestino ? 2 : 1.35,
        ),
        boxShadow: sombras,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _prefixIconCajaRuta(accent: accent, icono: iconoCaja),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        titulo,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: textMuted, size: 22),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  subtitulo,
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionRutaCard({
    required String titulo,
    required IconData icono,
    required Color accent,
    required Color fill,
    required Color tituloColor,
    required Widget child,
    bool mockupRuta = false,
    bool isDark = true,
    String? ayudaHeader,
    Color? ayudaColor,
    Color? lineaTimeline,
  }) {
    if (!mockupRuta) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icono, color: accent, size: 22),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: TextStyle(
                    color: tituloColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.65,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );
    }

    final Color ayudaCol =
        ayudaColor ?? (isDark ? Colors.white60 : const Color(0xFF667085));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFD0D5DD),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.58)),
                ),
                child: Icon(icono, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        color: tituloColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (ayudaHeader != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        ayudaHeader,
                        style: TextStyle(
                          color: ayudaCol,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (lineaTimeline != null)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: lineaTimeline, width: 2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: child,
              ),
            )
          else
            child,
        ],
      ),
    );
  }

  Widget _bannerAntesDeElegirDestino({
    required Color destinoAccent,
    required Color destinoFill,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: destinoFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: destinoAccent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: destinoAccent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Falta la llegada',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Escribí o elegí el destino en el buscador de abajo. El precio aparece cuando salida y llegada están listas.',
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaResumenViaje({
    required IconData icon,
    required String etiqueta,
    required String valor,
    required Color textPrimary,
    required Color textMuted,
    required Color accent,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                etiqueta,
                style: TextStyle(
                  color: textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                valor,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Panel compacto: origen, destino, precio grande, confirmar y acceso al buscador / formulario completo.
  Widget _tarjetaResumenCotizacion() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textPrimary = isDark ? Colors.white : const Color(0xFF101828);
    final Color textSecondary =
        isDark ? Colors.white70 : const Color(0xFF475467);
    final Color textMuted = isDark ? Colors.white60 : const Color(0xFF667085);
    final Color dividerSoft = isDark ? Colors.white24 : const Color(0xFFE4E7EC);
    final Color metodoPagoChipBg =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEFF1F5);
    final Color metodoPagoChipBorder =
        isDark ? Colors.white24 : const Color(0xFFD0D5DD);
    final Color c = _colorServicio;
    final pRes = _paletasOrigenDestino(isDark, tipoServicio);

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
                  c.withValues(alpha: isDark ? 0.22 : 0.12),
                  c.withValues(alpha: isDark ? 0.08 : 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c, width: 2),
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
                          color: textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _filaResumenViaje(
                  icon: Icons.trip_origin,
                  etiqueta: 'ORIGEN',
                  valor: _lineaOrigenResumen(),
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                  accent: pRes.origenAccent,
                ),
                const SizedBox(height: 14),
                _filaResumenViaje(
                  icon: Icons.search_rounded,
                  etiqueta: 'DESTINO',
                  valor: _lineaDestinoResumen(),
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                  accent: pRes.destinoAccent,
                ),
                const SizedBox(height: 16),
                Divider(color: dividerSoft, height: 1),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        FormatosMoneda.km(distanciaKm),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: textSecondary, fontWeight: FontWeight.w600),
                      ),
                      if (idaYVuelta)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Ida y vuelta',
                            style: TextStyle(
                                color: c,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_peaje > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Peaje incluido: ${FormatosMoneda.rd(_peaje)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textMuted, fontSize: 12),
                  ),
                ],
                if (tipoServicio == 'turismo') ...[
                  const SizedBox(height: 6),
                  Text(
                    'Vehículo: ${_mapTipoVehiculoTurismo(_tipoVehiculoTurismo)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textMuted, fontSize: 12),
                  ),
                ],
                if (tipoServicio == 'normal') ...[
                  const SizedBox(height: 6),
                  Text(
                    'Vehículo: $tipoVehiculo',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textMuted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  'TOTAL A PAGAR',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textMuted,
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
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                  ),
                ),
                if (!widget.modoAhora) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_rounded,
                            size: 18, color: textSecondary),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            DateFormat('dd/MM/yyyy - HH:mm').format(fechaHora),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: textSecondary,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.payments_outlined,
                          size: 18, color: textSecondary),
                      const SizedBox(width: 8),
                      Text('Pago:',
                          style: TextStyle(color: textMuted, fontSize: 13)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: metodoPagoChipBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: metodoPagoChipBorder),
                        ),
                        child: Text(
                          metodoPago,
                          style: TextStyle(
                              color: textPrimary, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _programarViaje(
                      ScaffoldMessenger.of(context),
                      Navigator.of(context),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                    child: Text(
                      widget.modoAhora
                          ? 'Confirmar viaje'
                          : 'Confirmar programación',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: _abrirFormularioCompletoDesdeResumen,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: dividerSoft),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: c, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cambiar ruta u opciones',
                            style: TextStyle(
                              color: textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tipoServicio == 'turismo'
                                ? 'Destino turístico, peaje, ida y vuelta, vehículo, pago y fecha'
                                : 'Abre el buscador, método de pago, fecha y el resto del formulario',
                            style: TextStyle(
                                color: textMuted, fontSize: 12, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_up_rounded,
                        color: textMuted, size: 28),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🎨 TARJETA DE SERVICIO
  Widget _selectorTipoServicio() {
    if (widget.tipoServicio != null) {
      final bool isDark = Theme.of(context).brightness == Brightness.dark;
      final Color textPrimary = isDark ? Colors.white : const Color(0xFF101828);
      final Color textSecondary =
          isDark ? Colors.white70 : const Color(0xFF475467);
      final Color color;
      final IconData icono;
      final String titulo;
      switch (widget.tipoServicio) {
        case 'motor':
          color = Colors.orange;
          icono = Icons.two_wheeler;
          titulo = '';
          break;
        case 'turismo':
          color = Colors.purple;
          icono = Icons.beach_access;
          titulo = 'Servicio Turismo';
          break;
        default:
          color = Colors.greenAccent;
          icono = Icons.directions_car;
          titulo = 'Servicio Normal';
      }
      final bool esMotorSvc = widget.tipoServicio == 'motor';
      final double iconPad = esMotorSvc ? 14 : 10;
      final double iconSize = esMotorSvc ? 36 : 24;
      final Widget iconoServicio = Container(
        padding: EdgeInsets.all(iconPad),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(icono, color: color, size: iconSize),
      );

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.2), Colors.transparent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisAlignment:
              esMotorSvc ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            esMotorSvc
                ? Semantics(
                    label: 'Servicio en motor',
                    excludeSemantics: true,
                    child: iconoServicio,
                  )
                : iconoServicio,
            if (widget.tipoServicio != 'motor') ...[
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (titulo.isNotEmpty)
                      Text(
                        titulo,
                        style: TextStyle(
                            color: textPrimary, fontWeight: FontWeight.bold),
                      ),
                    if (widget.tipoServicio == 'turismo' &&
                        _destinoTurismoSeleccionado != null)
                      Text(
                        'Destino: ${_destinoTurismoSeleccionado!.nombre}',
                        style: TextStyle(color: color, fontSize: 12),
                      ),
                    if (widget.tipoServicio == 'turismo')
                      Text(
                        'Vehículo: ${_tipoVehiculoTurismo == 'carro' ? 'Carro' : _tipoVehiculoTurismo == 'jeepeta' ? 'Jeepeta' : _tipoVehiculoTurismo == 'minivan' ? 'Minivan' : 'Bus'}',
                        style: TextStyle(color: textSecondary, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // 🔥 Selector de tipo de vehículo para turismo con valores únicos
  Widget _buildTurismoVehiculoSelector() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color labelColor = isDark ? Colors.white70 : const Color(0xFF475467);
    final Color ddColor = isDark ? Colors.white : const Color(0xFF101828);
    final Color ddBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    return _Caja(
      child: Row(
        children: [
          Icon(Icons.directions_car_filled_outlined, color: labelColor),
          const SizedBox(width: 10),
          Text('Tipo de Vehículo', style: TextStyle(color: labelColor)),
          const Spacer(),
          DropdownButton<String>(
            value: _tipoVehiculoTurismo,
            dropdownColor: ddBg,
            underline: const SizedBox(),
            style: TextStyle(color: ddColor, fontSize: 16),
            items: [
              DropdownMenuItem(
                  value: 'carro',
                  child: Text('Carro', style: TextStyle(color: ddColor))),
              DropdownMenuItem(
                  value: 'jeepeta',
                  child: Text('Jeepeta', style: TextStyle(color: ddColor))),
              DropdownMenuItem(
                  value: 'minivan',
                  child: Text('Minivan', style: TextStyle(color: ddColor))),
              DropdownMenuItem(
                  value: 'bus',
                  child: Text('Bus', style: TextStyle(color: ddColor))),
            ],
            onChanged: (v) {
              setState(() {
                _tipoVehiculoTurismo = v ?? 'carro';
              });
              _programarCalculoAutomatico();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textPrimary = isDark ? Colors.white : const Color(0xFF101828);
    final Color textSecondary =
        isDark ? Colors.white70 : const Color(0xFF475467);
    final Color textMuted = isDark ? Colors.white60 : const Color(0xFF667085);
    final Color switchCardBorder =
        isDark ? Colors.white24 : const Color(0xFFD0D5DD);
    final Color switchAccent =
        isDark ? Colors.greenAccent : const Color(0xFF0F9D58);
    final Color sheetBg = isDark ? Colors.black : const Color(0xFFF8FAFC);
    final Color sheetHandle = isDark ? Colors.white24 : const Color(0xFFD0D5DD);
    final Color payLinkColor =
        isDark ? Colors.green.shade300 : const Color(0xFF0F9D58);
    final Color metodoPagoChipBg =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEFF1F5);
    final Color metodoPagoChipBorder =
        isDark ? Colors.white24 : const Color(0xFFD0D5DD);
    final Color dividerSoft = isDark ? Colors.white24 : const Color(0xFFE4E7EC);
    final pRuta = _paletasOrigenDestino(isDark, tipoServicio);
    final bool uiRutaMockup = tipoServicio != 'turismo';

    return FlygoSalidaSegura(
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : const Color(0xFFE8EAED),
        appBar: RaiAppBar(
          title: 'Programar Viaje',
          backWhenCanPop: true,
          leading: SafeArea(
            bottom: false,
            child: IconButton(
              icon: Icon(
                Icons.arrow_back_rounded,
                color: isDark ? Colors.white : const Color(0xFF101828),
              ),
              tooltip: 'Volver',
              onPressed: () => intentarSalirAlGate(context),
            ),
          ),
        ),
        body: Stack(
        children: [
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
                onTap: (_) {
                  if (_mapProgrammaticCameraDepth > 0) return;
                  _onProgramarMapUserGesture();
                  _programarMapGestureEndDebounce?.cancel();
                  _programarMapGestureEndDebounce = Timer(
                    const Duration(milliseconds: 420),
                    () {
                      if (mounted) _expandProgramarSheetTrasMapaInteract();
                    },
                  );
                },
                onCameraMoveStarted: _onProgramarMapUserGesture,
                onCameraIdle: _onProgramarMapCameraIdle,
                compassEnabled: true,
                mapToolbarEnabled: false,
              ),
            ),
          ),
          if (_cargandoUbicacion)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: const _Banner(
                  text: 'Ubicando…', icon: Icons.location_searching),
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
          Positioned(
            right: 16,
            bottom: 220,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              onPressed: _centrarEnMiUbicacion,
              child: Icon(Icons.my_location,
                  color: isDark ? Colors.white : const Color(0xFF0F9D58)),
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheetCtrl,
            minChildSize: _sheetMinFracProgramar,
            maxChildSize: 0.88,
            initialChildSize: 0.36,
            snap: true,
            snapSizes: const [_sheetMinFracProgramar, 0.72, 0.88],
            builder: (context, controller) {
              final double safeBottom = MediaQuery.of(context).padding.bottom;
              return Container(
                decoration: BoxDecoration(
                  color: sheetBg,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(18)),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                      blurRadius: 16,
                    ),
                    BoxShadow(
                      color: _colorServicio.withValues(alpha: 0.1),
                      blurRadius: 20,
                      spreadRadius: 2,
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
                          accentColor: _colorServicio,
                          isDark: isDark,
                          message: (ubicacionObtenida && precioCalculado > 0)
                              ? 'Guardando viaje…'
                              : 'Calculando precio…',
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          _cargando ? 6 : 10,
                          16,
                          24 + safeBottom,
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
                                        color: sheetHandle,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    SlideTransition(
                                      position: _nudgeOffset,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.keyboard_double_arrow_up,
                                              size: 18, color: textMuted),
                                          const SizedBox(width: 6),
                                          Text(
                                            _mostrarResumenCotizacion
                                                ? 'Toca “Cambiar ruta” abajo para el buscador y opciones'
                                                : 'Desliza o toca para ver todo',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                color: textMuted,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_mostrarResumenCotizacion)
                                _tarjetaResumenCotizacion(),
                              if (!_mostrarResumenCotizacion)
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(height: 12),
                                    _selectorTipoServicio(),
                                    const SizedBox(height: 12),
                                    const SizedBox(height: 14),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 4, bottom: 2),
                                      child: uiRutaMockup
                                          ? Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Tu recorrido',
                                                  style: TextStyle(
                                                    color: textPrimary,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 18,
                                                    letterSpacing: -0.2,
                                                  ),
                                                ),
                                                Text(
                                                  widget.modoAhora
                                                      ? 'Salida: tu ubicación (GPS) · llegada: escribila abajo'
                                                      : 'Completá salida y llegada',
                                                  style: TextStyle(
                                                    color: textMuted,
                                                    fontSize: 12.5,
                                                    height: 1.35,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Text(
                                              'Origen y destino',
                                              style: TextStyle(
                                                color: textSecondary,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.4,
                                              ),
                                            ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (widget.modoAhora && uiRutaMockup)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: pRuta.origenBorde
                                                      .withValues(alpha: 0.65),
                                                ),
                                                color: pRuta.origenAccent
                                                    .withValues(alpha: 0.12),
                                              ),
                                              child: Icon(
                                                Icons.gps_fixed_rounded,
                                                color: pRuta.origenAccent,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Salida',
                                                    style: TextStyle(
                                                      color: pRuta.origenAccent,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Tu ubicación en el mapa. Mové el pin si hace falta.',
                                                    style: TextStyle(
                                                      color: textMuted,
                                                      fontSize: 12,
                                                      height: 1.3,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (!widget.modoAhora || !uiRutaMockup)
                                      ParpadeoRutaProgramar(
                                        pulseColor: pRuta.origenAccent,
                                        child: _seccionRutaCard(
                                          titulo: uiRutaMockup
                                              ? 'ORIGEN'
                                              : 'Origen',
                                          icono: uiRutaMockup
                                              ? Icons.search_rounded
                                              : Icons.my_location,
                                          accent: pRuta.origenAccent,
                                          fill: pRuta.origenFill,
                                          tituloColor: uiRutaMockup
                                              ? pRuta.origenAccent
                                              : textPrimary,
                                          mockupRuta: uiRutaMockup,
                                          isDark: isDark,
                                          ayudaHeader:
                                              uiRutaMockup ? 'Salida' : null,
                                          ayudaColor: textMuted,
                                          lineaTimeline: uiRutaMockup
                                              ? const Color(0xFFFFB74D)
                                              : null,
                                          child: widget.modoAhora
                                              ? Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    if (uiRutaMockup) ...[
                                                      _tarjetaLineaPuntoMapa(
                                                        isDark: isDark,
                                                        accent:
                                                            pRuta.origenAccent,
                                                        fill: pRuta.origenFill,
                                                        borde:
                                                            pRuta.origenBorde,
                                                        iconoCaja: Icons
                                                            .gps_fixed_rounded,
                                                        titulo:
                                                            'Punto de partida',
                                                        subtitulo:
                                                            'Toca para buscar en el mapa…',
                                                        textMuted: textMuted,
                                                        resplandorOrigen: true,
                                                      ),
                                                      const SizedBox(
                                                          height: 10),
                                                      Text(
                                                        'GPS en vivo. Mové el pin en el mapa o usá el botón de ubicación.',
                                                        style: TextStyle(
                                                          color: textSecondary,
                                                          fontSize: 12,
                                                          height: 1.3,
                                                        ),
                                                      ),
                                                    ] else ...[
                                                      Text(
                                                        'Salida desde tu ubicación',
                                                        style: TextStyle(
                                                          color: textPrimary,
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'GPS en vivo. Ajustá el punto en el mapa o con el botón de ubicación.',
                                                        style: TextStyle(
                                                          color: textSecondary,
                                                          fontSize: 12.5,
                                                          height: 1.3,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                          height: 12),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 14,
                                                          vertical: 12,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: isDark
                                                              ? pRuta
                                                                  .origenAccent
                                                                  .withValues(
                                                                      alpha:
                                                                          0.14)
                                                              : pRuta
                                                                  .origenFill,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(12),
                                                          border: Border.all(
                                                            color: pRuta
                                                                .origenAccent
                                                                .withValues(
                                                                    alpha:
                                                                        0.85),
                                                            width: 1.5,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .my_location_rounded,
                                                              color: pRuta
                                                                  .origenAccent,
                                                              size: 22,
                                                            ),
                                                            const SizedBox(
                                                                width: 10),
                                                            Expanded(
                                                              child: Text(
                                                                'El conductor te verá en el mapa al confirmar. Mové el pin si no coincide.',
                                                                style:
                                                                    TextStyle(
                                                                  color:
                                                                      textSecondary,
                                                                  fontSize:
                                                                      12.5,
                                                                  height: 1.35,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                )
                                              : kUsePlacesAutocomplete
                                                  ? Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        if (!uiRutaMockup) ...[
                                                          Text(
                                                            'Punto de salida en RD',
                                                            style: TextStyle(
                                                              color:
                                                                  textPrimary,
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 4),
                                                          Text(
                                                            'Buscá aunque no estés ahí todavía. Podés elegir un reciente sin escribir.',
                                                            style: TextStyle(
                                                              color:
                                                                  textSecondary,
                                                              fontSize: 12.5,
                                                              height: 1.3,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 12),
                                                        ],
                                                        CampoLugarAutocomplete(
                                                          label: uiRutaMockup
                                                              ? 'Buscar origen'
                                                              : 'Dirección de salida',
                                                          hint: uiRutaMockup
                                                              ? 'Dirección, barrio, hotel o lugar en RD…'
                                                              : 'Ej. SDQ, hotel, sector…',
                                                          showQuickSuggestions:
                                                              false,
                                                          showCategories: false,
                                                          fieldAccent: pRuta
                                                              .origenAccent,
                                                          fieldFill: isDark
                                                              ? (uiRutaMockup
                                                                  ? const Color(
                                                                      0xFF1A1208)
                                                                  : const Color(
                                                                      0xFF1C1508))
                                                              : Colors.white,
                                                          onPlaceSelected:
                                                              (det) async {
                                                            _origenDetManual =
                                                                det;
                                                            origenManual = det
                                                                .displayLabel;
                                                            origenTexto = det
                                                                .displayLabel;
                                                            _origenMap = LatLng(
                                                                det.lat,
                                                                det.lon);
                                                            _updateOrigenMarker(
                                                                _origenMap!);
                                                            setState(() {});
                                                            await _dibujarRutaSiHayDestino();
                                                            _programarCalculoAutomatico();
                                                          },
                                                          onTextChanged: (t) {
                                                            setState(() {
                                                              origenManual = t;
                                                              _origenDetManual =
                                                                  null;
                                                              origenTexto = '';
                                                              _invalidarCotizacion();
                                                            });
                                                            _programarCalculoAutomatico();
                                                          },
                                                        ),
                                                        const SizedBox(
                                                            height: 6),
                                                        Text(
                                                          'Ajustá el pin de salida en el mapa si hace falta.',
                                                          style: TextStyle(
                                                            color: textMuted,
                                                            fontSize: 11.5,
                                                            height: 1.25,
                                                          ),
                                                        ),
                                                        TextButton(
                                                          onPressed: () {
                                                            Navigator.of(
                                                                    context)
                                                                .push(
                                                              MaterialPageRoute<
                                                                  void>(
                                                                builder: (_) =>
                                                                    const ProgramarViajeMulti(),
                                                              ),
                                                            );
                                                          },
                                                          style: TextButton
                                                              .styleFrom(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                                    top: 4),
                                                            tapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                            alignment: Alignment
                                                                .centerLeft,
                                                          ),
                                                          child: Text(
                                                            'Múltiples paradas (lista)',
                                                            style: TextStyle(
                                                              color:
                                                                  payLinkColor,
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              decoration:
                                                                  TextDecoration
                                                                      .underline,
                                                              decorationColor:
                                                                  payLinkColor,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    )
                                                  : Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        if (uiRutaMockup) ...[
                                                          _tarjetaLineaPuntoMapa(
                                                            isDark: isDark,
                                                            accent: pRuta
                                                                .origenAccent,
                                                            fill: pRuta
                                                                .origenFill,
                                                            borde: pRuta
                                                                .origenBorde,
                                                            iconoCaja: Icons
                                                                .gps_fixed_rounded,
                                                            titulo:
                                                                'Punto de partida',
                                                            subtitulo:
                                                                'Toca para buscar en el mapa…',
                                                            textMuted:
                                                                textMuted,
                                                            resplandorOrigen:
                                                                true,
                                                          ),
                                                          const SizedBox(
                                                              height: 12),
                                                        ] else ...[
                                                          Text(
                                                            'Salida desde el mapa o GPS',
                                                            style: TextStyle(
                                                              color:
                                                                  textPrimary,
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 4),
                                                          Text(
                                                            'Mové el pin si hace falta.',
                                                            style: TextStyle(
                                                              color:
                                                                  textSecondary,
                                                              fontSize: 12.5,
                                                              height: 1.3,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 12),
                                                        ],
                                                        SizedBox(
                                                          width:
                                                              double.infinity,
                                                          child: OutlinedButton
                                                              .icon(
                                                            onPressed: () {
                                                              _origenBuscarDireccion =
                                                                  true;
                                                              _origenDetManual =
                                                                  null;
                                                              origenManual = '';
                                                              origenTexto = '';
                                                              _invalidarCotizacion();
                                                              if (mounted) {
                                                                setState(() {});
                                                              }
                                                            },
                                                            icon: Icon(
                                                              Icons
                                                                  .search_rounded,
                                                              size: 22,
                                                              color: uiRutaMockup
                                                                  ? (isDark
                                                                      ? const Color(
                                                                          0xFF2ECC71)
                                                                      : const Color(
                                                                          0xFF0F9D58))
                                                                  : pRuta
                                                                      .origenAccent,
                                                            ),
                                                            label: Text(
                                                              'Buscar dirección de salida',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                fontSize: 15,
                                                              ),
                                                            ),
                                                            style: uiRutaMockup
                                                                ? OutlinedButton
                                                                    .styleFrom(
                                                                    foregroundColor: isDark
                                                                        ? const Color(
                                                                            0xFF2ECC71)
                                                                        : const Color(
                                                                            0xFF0F9D58),
                                                                    backgroundColor:
                                                                        Colors
                                                                            .transparent,
                                                                    side:
                                                                        BorderSide(
                                                                      color: isDark
                                                                          ? const Color(
                                                                              0xFF2ECC71)
                                                                          : const Color(
                                                                              0xFF0F9D58),
                                                                      width:
                                                                          1.5,
                                                                    ),
                                                                    padding:
                                                                        const EdgeInsets
                                                                            .symmetric(
                                                                      vertical:
                                                                          14,
                                                                      horizontal:
                                                                          14,
                                                                    ),
                                                                  )
                                                                : OutlinedButton
                                                                    .styleFrom(
                                                                    foregroundColor:
                                                                        pRuta
                                                                            .origenAccent,
                                                                    backgroundColor: isDark
                                                                        ? pRuta.origenAccent.withValues(
                                                                            alpha:
                                                                                0.14)
                                                                        : pRuta
                                                                            .origenFill,
                                                                    side:
                                                                        BorderSide(
                                                                      color: pRuta
                                                                          .origenAccent
                                                                          .withValues(
                                                                              alpha: 0.85),
                                                                      width:
                                                                          1.5,
                                                                    ),
                                                                    padding:
                                                                        const EdgeInsets
                                                                            .symmetric(
                                                                      vertical:
                                                                          14,
                                                                      horizontal:
                                                                          14,
                                                                    ),
                                                                  ),
                                                          ),
                                                        ),
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  top: 8,
                                                                  left: 2),
                                                          child: Text(
                                                            'Útil si programás desde fuera o con poca señal.',
                                                            style: TextStyle(
                                                              color: textMuted,
                                                              fontSize: 11.5,
                                                              height: 1.25,
                                                            ),
                                                          ),
                                                        ),
                                                        TextButton(
                                                          onPressed: () {
                                                            Navigator.of(
                                                                    context)
                                                                .push(
                                                              MaterialPageRoute<
                                                                  void>(
                                                                builder: (_) =>
                                                                    const ProgramarViajeMulti(),
                                                              ),
                                                            );
                                                          },
                                                          style: TextButton
                                                              .styleFrom(
                                                            padding:
                                                                EdgeInsets.zero,
                                                            tapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                            alignment: Alignment
                                                                .centerLeft,
                                                          ),
                                                          child: Text(
                                                            'Múltiples paradas (lista)',
                                                            style: TextStyle(
                                                              color:
                                                                  payLinkColor,
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              decoration:
                                                                  TextDecoration
                                                                      .underline,
                                                              decorationColor:
                                                                  payLinkColor,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                        ),
                                      ),
                                    if (!_tieneDestinoParaCalculo()) ...[
                                      _bannerAntesDeElegirDestino(
                                        destinoAccent: pRuta.destinoAccent,
                                        destinoFill: pRuta.destinoFill,
                                        textPrimary: textPrimary,
                                        textSecondary: textSecondary,
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    if (widget.tipoServicio != 'turismo' &&
                                        kUsePlacesAutocomplete)
                                      ParpadeoRutaProgramar(
                                        pulseColor: uiRutaMockup && isDark
                                            ? const Color(0xFFC084FC)
                                            : pRuta.destinoAccent,
                                        child: _seccionRutaCard(
                                          titulo: uiRutaMockup
                                              ? 'DESTINO'
                                              : 'Destino',
                                          icono: Icons.search_rounded,
                                          accent: pRuta.destinoAccent,
                                          fill: pRuta.destinoFill,
                                          tituloColor: uiRutaMockup && isDark
                                              ? Colors.white
                                              : textPrimary,
                                          mockupRuta: uiRutaMockup,
                                          isDark: isDark,
                                          ayudaHeader:
                                              uiRutaMockup ? 'Llegada' : null,
                                          ayudaColor: textMuted,
                                          lineaTimeline: uiRutaMockup
                                              ? const Color(0xFFC084FC)
                                              : null,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Stack(
                                                children: [
                                                  CampoLugarAutocomplete(
                                                    label: 'Buscar destino',
                                                    hint: uiRutaMockup
                                                        ? 'Dirección, barrio, hotel o lugar en RD…'
                                                        : '¿A dónde vas?',
                                                    fieldAccent: uiRutaMockup &&
                                                            isDark
                                                        ? const Color(
                                                            0xFFD8B4FE)
                                                        : pRuta.destinoAccent,
                                                    fieldFill: isDark
                                                        ? (uiRutaMockup
                                                            ? const Color(
                                                                0xFF1E0B36)
                                                            : const Color(
                                                                0xFF1A0F2E))
                                                        : Colors.white,
                                                    onPlaceSelected:
                                                        (det) async {
                                                      _destinoDet = det;
                                                      destino =
                                                          det.displayLabel;
                                                      destinoTexto =
                                                          det.displayLabel;
                                                      latDestino = det.lat;
                                                      lonDestino = det.lon;

                                                      final destLL = LatLng(
                                                          det.lat, det.lon);
                                                      _markers.removeWhere(
                                                          (m) =>
                                                              m.markerId
                                                                  .value ==
                                                              'destino');
                                                      _markers.add(
                                                        Marker(
                                                          markerId:
                                                              const MarkerId(
                                                                  'destino'),
                                                          position: destLL,
                                                          icon: BitmapDescriptor
                                                              .defaultMarkerWithHue(
                                                                  BitmapDescriptor
                                                                      .hueViolet),
                                                          infoWindow:
                                                              const InfoWindow(
                                                                  title:
                                                                      'Destino'),
                                                          zIndexInt: 1,
                                                        ),
                                                      );
                                                      setState(() {});

                                                      if (_origenMap != null) {
                                                        await _dibujarRutaReal(
                                                          oLat: _origenMap!
                                                              .latitude,
                                                          oLon: _origenMap!
                                                              .longitude,
                                                          dLat: det.lat,
                                                          dLon: det.lon,
                                                          previewOnly: true,
                                                        );
                                                      }

                                                      _programarCalculoAutomatico();
                                                    },
                                                    onTextChanged: (t) {
                                                      _markers.removeWhere(
                                                          (m) =>
                                                              m.markerId
                                                                  .value ==
                                                              'destino');
                                                      _polylines.clear();
                                                      setState(() {
                                                        destino = t;
                                                        _destinoDet = null;
                                                        latDestino = null;
                                                        lonDestino = null;
                                                        destinoTexto = '';
                                                        _invalidarCotizacion();
                                                      });
                                                      _programarCalculoAutomatico();
                                                    },
                                                  ),
                                                ],
                                              ),
                                              if (destinoTexto.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 6),
                                                  child: Text(
                                                    'Destino seleccionado: $destinoTexto',
                                                    style: TextStyle(
                                                      color:
                                                          pRuta.destinoAccent,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (widget.tipoServicio == 'turismo') ...[
                                      ParpadeoRutaProgramar(
                                        pulseColor: pRuta.destinoAccent,
                                        child: _seccionRutaCard(
                                          titulo: 'Destino turístico',
                                          icono: Icons.explore,
                                          accent: pRuta.destinoAccent,
                                          fill: pRuta.destinoFill,
                                          tituloColor: textPrimary,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              if (_destinoTurismoSeleccionado ==
                                                  null)
                                                ElevatedButton.icon(
                                                  onPressed:
                                                      _mostrarSelectorDestinosTuristicos,
                                                  icon: const Icon(Icons.map),
                                                  label: const Text(
                                                      'Seleccionar destino turístico'),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        pRuta.destinoAccent,
                                                    foregroundColor:
                                                        Colors.white,
                                                    minimumSize: const Size(
                                                        double.infinity, 48),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                    ),
                                                  ),
                                                )
                                              else
                                                Container(
                                                  padding:
                                                      const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: isDark
                                                        ? const Color(
                                                            0xFF0F172A)
                                                        : Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    border: Border.all(
                                                      color: pRuta.destinoAccent
                                                          .withValues(
                                                              alpha: 0.55),
                                                    ),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Icon(
                                                              Icons
                                                                  .check_circle,
                                                              color: pRuta
                                                                  .destinoAccent,
                                                              size: 20),
                                                          const SizedBox(
                                                              width: 8),
                                                          Expanded(
                                                            child: Text(
                                                              _destinoTurismoSeleccionado!
                                                                  .nombre,
                                                              style: TextStyle(
                                                                color:
                                                                    textPrimary,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        _destinoTurismoSeleccionado!
                                                            .ciudad,
                                                        style: TextStyle(
                                                            color:
                                                                textSecondary),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        'Distancia: ${FormatosMoneda.km(distanciaKm)}',
                                                        style: TextStyle(
                                                            color: textMuted),
                                                      ),
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                vertical: 8),
                                                        child: TextFormField(
                                                          controller:
                                                              _peajeCtrl,
                                                          keyboardType:
                                                              TextInputType
                                                                  .number,
                                                          style: TextStyle(
                                                              color:
                                                                  textPrimary),
                                                          decoration:
                                                              InputDecoration(
                                                            labelText:
                                                                'Peaje (RD\$)',
                                                            hintText: 'Ej: 100',
                                                            labelStyle: TextStyle(
                                                                color:
                                                                    textSecondary),
                                                            hintStyle: TextStyle(
                                                                color:
                                                                    textMuted),
                                                            prefixIcon: Icon(
                                                                Icons.toll,
                                                                color:
                                                                    textMuted),
                                                            filled: true,
                                                            fillColor: isDark
                                                                ? const Color(
                                                                    0xFF1A1A1A)
                                                                : const Color(
                                                                    0xFFF8FAFC),
                                                            border:
                                                                OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          12),
                                                              borderSide:
                                                                  BorderSide(
                                                                      color:
                                                                          switchCardBorder),
                                                            ),
                                                            focusedBorder:
                                                                OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          12),
                                                              borderSide: BorderSide(
                                                                  color: pRuta
                                                                      .destinoAccent,
                                                                  width: 2),
                                                            ),
                                                          ),
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _peaje = double
                                                                      .tryParse(
                                                                          value) ??
                                                                  0.0;
                                                            });
                                                            _programarCalculoAutomatico();
                                                          },
                                                        ),
                                                      ),
                                                      TextButton.icon(
                                                        onPressed: () {
                                                          setState(() {
                                                            _destinoTurismoSeleccionado =
                                                                null;
                                                            _invalidarCotizacion();
                                                            latDestino = null;
                                                            lonDestino = null;
                                                            destinoTexto = '';
                                                            destino = '';
                                                            _peaje = 0.0;
                                                            _peajeCtrl.clear();
                                                          });
                                                        },
                                                        icon: const Icon(
                                                            Icons.refresh,
                                                            size: 16),
                                                        label: const Text(
                                                            'Cambiar destino'),
                                                        style: TextButton
                                                            .styleFrom(
                                                          foregroundColor: pRuta
                                                              .destinoAccent,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    if (!widget.modoAhora) ...[
                                      const SizedBox(height: 10),
                                      const ProgramarViajeFuturoAnimation(),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Fecha y hora del viaje',
                                        style: TextStyle(
                                          color: textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      ElevatedButton.icon(
                                        onPressed: _seleccionarFechaHora,
                                        icon: const Icon(Icons.calendar_today),
                                        label: const Text(
                                            'Seleccionar Fecha y Hora'),
                                        style: _botonEstilo(context),
                                      ),
                                      Text(
                                        'Programado para: ${DateFormat('dd/MM/yyyy - HH:mm').format(fechaHora)}',
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.greenAccent
                                              : const Color(0xFF0F9D58),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    const SizedBox(height: 14),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 4, bottom: 2),
                                      child: Text(
                                        'Opciones del viaje',
                                        style: TextStyle(
                                          color: textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _Caja(
                                      child: Row(
                                        children: [
                                          Icon(Icons.swap_horiz,
                                              color: textSecondary),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              '¿Ida y vuelta?',
                                              style: TextStyle(
                                                color: textPrimary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Switch.adaptive(
                                            value: idaYVuelta,
                                            activeColor: Colors.white,
                                            activeTrackColor: switchAccent,
                                            inactiveThumbColor: isDark
                                                ? Colors.white70
                                                : const Color(0xFF98A2B3),
                                            inactiveTrackColor: isDark
                                                ? Colors.white24
                                                : const Color(0xFFD0D5DD),
                                            onChanged: (v) {
                                              setState(() {
                                                idaYVuelta = v;
                                              });
                                              _programarCalculoAutomatico();
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    if (tipoServicio != 'motor') ...[
                                      if (tipoServicio == 'normal')
                                        _Caja(
                                          child: Row(
                                            children: [
                                              Icon(
                                                  Icons
                                                      .directions_car_filled_outlined,
                                                  color: textSecondary),
                                              const SizedBox(width: 10),
                                              Text('Tipo de Vehículo',
                                                  style: TextStyle(
                                                      color: textSecondary)),
                                              const Spacer(),
                                              DropdownButton<String>(
                                                value: tipoVehiculo,
                                                dropdownColor: isDark
                                                    ? const Color(0xFF1A1A1A)
                                                    : Colors.white,
                                                underline: const SizedBox(),
                                                style: TextStyle(
                                                    color: textPrimary,
                                                    fontSize: 16),
                                                items: [
                                                  'Carro',
                                                  'Jeepeta',
                                                  'Minibús',
                                                  'Minivan',
                                                  'AutobusGuagua'
                                                ]
                                                    .map(
                                                        (e) => DropdownMenuItem(
                                                              value: e,
                                                              child: Text(e,
                                                                  style: TextStyle(
                                                                      color:
                                                                          textPrimary)),
                                                            ))
                                                    .toList(),
                                                onChanged: (v) {
                                                  setState(() {
                                                    tipoVehiculo = v ?? 'Carro';
                                                  });
                                                  _programarCalculoAutomatico();
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (tipoServicio == 'turismo')
                                        _buildTurismoVehiculoSelector(),
                                      const SizedBox(height: 10),
                                    ],
                                    _Caja(
                                      child: Row(
                                        children: [
                                          Icon(Icons.credit_card_outlined,
                                              color: textSecondary),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: TextButton.icon(
                                              onPressed: _elegirMetodoPago,
                                              icon: Icon(
                                                  Icons
                                                      .account_balance_wallet_outlined,
                                                  color: payLinkColor),
                                              label: Text(
                                                'Elegir método de pago',
                                                style: TextStyle(
                                                    color: payLinkColor,
                                                    fontWeight:
                                                        FontWeight.w700),
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: metodoPagoChipBg,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: metodoPagoChipBorder),
                                            ),
                                            child: Text(metodoPago,
                                                style: TextStyle(
                                                    color: textSecondary,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (MetodoPagoViaje.esTransferencia(
                                        metodoPago))
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withValues(
                                                alpha: isDark ? 0.12 : 0.08),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                              color: isDark
                                                  ? Colors.blueAccent
                                                  : const Color(0xFF1570EF),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Transferencia al taxista',
                                                style: TextStyle(
                                                  color: textPrimary,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                'El pago por transferencia se realiza al taxista asignado.\n'
                                                'Cuando tengas el viaje asignado podras ver su cuenta bancaria\n'
                                                'y subir el comprobante para validacion de Administracion.',
                                                style: TextStyle(
                                                    color: textSecondary,
                                                    height: 1.35),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                'Efectivo y transferencia se pagan al taxista. La comision se liquida semanalmente.',
                                                style: TextStyle(
                                                  color: isDark
                                                      ? Colors.amberAccent
                                                      : const Color(0xFFB45309),
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    if (precioCalculado > 0)
                                      Container(
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 16),
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          color: _colorServicio.withValues(
                                              alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                              color: _colorServicio, width: 2),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              'DISTANCIA',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: _colorServicio,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              FormatosMoneda.km(distanciaKm),
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: textSecondary,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            SizedBox(
                                              width: double.infinity,
                                              child:
                                                  Divider(color: dividerSoft),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              'TOTAL',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: textSecondary,
                                                fontSize: 14,
                                              ),
                                            ),
                                            SizedBox(
                                              width: double.infinity,
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.center,
                                                child: Text(
                                                  FormatosMoneda.rd(
                                                      precioCalculado),
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: _colorServicio,
                                                    fontSize: 42,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (_peaje > 0)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 8),
                                                child: Text(
                                                  'Incluye peaje: ${FormatosMoneda.rd(_peaje)}',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                      color: textMuted,
                                                      fontSize: 12),
                                                ),
                                              ),
                                            const SizedBox(height: 20),
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton(
                                                onPressed: (ubicacionObtenida &&
                                                        precioCalculado > 0)
                                                    ? () => _programarViaje(
                                                        ScaffoldMessenger.of(
                                                            context),
                                                        Navigator.of(context))
                                                    : null,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      _colorServicio,
                                                  foregroundColor: Colors.black,
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 16),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                ),
                                                child: Text(
                                                  widget.modoAhora
                                                      ? '✅ CONFIRMAR VIAJE'
                                                      : '✅ CONFIRMAR PROGRAMACIÓN',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else if (_cargando)
                                      CotizacionPrecioLoadingPlaceholder(
                                        accentColor: _colorServicio,
                                        isDark: isDark,
                                        message: (ubicacionObtenida &&
                                                precioCalculado > 0)
                                            ? 'Guardando viaje…'
                                            : 'Calculando precio…',
                                      ),
                                  ],
                                ),
                              if (latCliente != null &&
                                  latDestino != null &&
                                  !_mostrarResumenCotizacion)
                                const SizedBox(height: 12),
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
      ),
    );
  }

  ButtonStyle _botonEstilo(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return ElevatedButton.styleFrom(
      backgroundColor: isDark ? Colors.white : const Color(0xFF0F9D58),
      foregroundColor: isDark ? Colors.green : Colors.white,
      minimumSize: const Size(double.infinity, 50),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

class _Caja extends StatelessWidget {
  final Widget child;
  const _Caja({required this.child});
  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : const Color(0xFFFFFFFF),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.fromBorderSide(
          BorderSide(color: isDark ? Colors.white24 : const Color(0xFFD0D5DD)),
        ),
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent =
        isDark ? const Color(0xFF49F18B) : const Color(0xFF0F9D58);
    final Color bg = isDark ? const Color(0xFF1C1F23) : const Color(0xFFE8F7EE);
    final Color textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border.fromBorderSide(
            BorderSide(color: accent.withValues(alpha: 0.45))),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
