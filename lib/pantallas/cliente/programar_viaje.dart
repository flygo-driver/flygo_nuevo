// lib/pantallas/cliente/programar_viaje.dart
// ProgramarViaje — estilo RAI, tipo inDrive (autocomplete + mapa tiempo real)
// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, unnecessary_null_comparison

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// 🔰 IMPORT para ir al viaje en curso

// ✅ Confirmación de viaje programado (no confundir con “en curso”)

import 'package:flygo_nuevo/pantallas/cliente/programar_viaje_multi.dart'
    hide DestinoSeleccionado;

// Tus servicios/componentes
import 'package:flygo_nuevo/utils/navegacion_salida_app.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_cliente_banner.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_cliente_map_alert.dart';
import 'package:flygo_nuevo/servicios/custom_theme_service.dart';
import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/location_permission_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_cliente_service.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/rai_map_presentation.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/widgets/overflow_safe_labeled_dropdown.dart';
import 'package:flygo_nuevo/widgets/campo_lugar_autocomplete.dart';
import 'package:flygo_nuevo/widgets/cliente_viaje_orientacion_banner.dart';
import 'package:flygo_nuevo/widgets/cotizacion_precio_loading.dart';
import 'package:flygo_nuevo/widgets/cotizacion_desglose_panel.dart';
import 'package:flygo_nuevo/widgets/promo_mxk_cliente_panel.dart';
import 'package:flygo_nuevo/widgets/programar_viaje_futuro_animation.dart';
import 'package:flygo_nuevo/widgets/parpadeo_ruta_programar.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/rai_offline_cotizacion_service.dart';
import 'package:flygo_nuevo/servicios/roles_service.dart';
import 'package:flygo_nuevo/widgets/rai_cotizacion_offline_hint.dart';
import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/servicios/pool_timbre_session_guard.dart';
// ✅ IMPORTS PARA TURISMO
import 'package:flygo_nuevo/widgets/turismo_destinos_sheet_host.dart';
import 'package:flygo_nuevo/widgets/selector_destinos_turisticos.dart';
import 'package:flygo_nuevo/servicios/turismo_catalogo_rd.dart';

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

/// Sombras discretas para leer texto sobre mapa o fondos translúcidos (solo UI).
List<Shadow> _legibilityShadowsForChrome(Color toneRef) {
  final bool darkTone =
      ThemeData.estimateBrightnessForColor(toneRef) == Brightness.dark;
  if (darkTone) {
    return <Shadow>[
      Shadow(
        offset: const Offset(0, 1.2),
        blurRadius: 4.5,
        color: Colors.black.withValues(alpha: 0.78),
      ),
      Shadow(
        offset: Offset.zero,
        blurRadius: 14,
        color: Colors.black.withValues(alpha: 0.40),
      ),
    ];
  }
  return <Shadow>[
    Shadow(
      offset: const Offset(0, 1),
      blurRadius: 3.5,
      color: Colors.white.withValues(alpha: 0.88),
    ),
    Shadow(
      offset: Offset.zero,
      blurRadius: 12,
      color: Colors.white.withValues(alpha: 0.46),
    ),
  ];
}

/// Sombras para la etiqueta del botón CONFIRMAR sobre mapa (contraste en ambos tonos).
List<Shadow> _ctaLabelShadows(Color labelColor) {
  final bool darkLabel =
      ThemeData.estimateBrightnessForColor(labelColor) == Brightness.dark;
  if (darkLabel) {
    return <Shadow>[
      Shadow(
        offset: const Offset(0, 1.2),
        blurRadius: 4,
        color: Colors.black.withValues(alpha: 0.48),
      ),
      Shadow(
        offset: Offset.zero,
        blurRadius: 12,
        color: Colors.black.withValues(alpha: 0.30),
      ),
    ];
  }
  return <Shadow>[
    Shadow(
      offset: const Offset(0, 1),
      blurRadius: 3,
      color: Colors.white.withValues(alpha: 0.92),
    ),
    Shadow(
      offset: Offset.zero,
      blurRadius: 10,
      color: Colors.black.withValues(alpha: 0.28),
    ),
  ];
}

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
  bool _precioEsEstimadoOffline = false;
  Map<String, dynamic>? _cotizacionDesglose;
  String _distanciaFuente = '';

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
  final Set<Circle> _circles = {};

  bool _locPermDeniedForever = false;
  bool _cargandoUbicacion = true;
  bool _mapMyLocationEnabled = false;

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
        ? 0.56
        : (widget.modoAhora ? 0.62 : 0.66);
    try {
      _sheetCtrl.animateTo(
        target.clamp(_sheetMinFracProgramar, 0.75),
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


  EdgeInsets _programarMapPadding(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final double h = mq.size.height;
    final double sheetFrac = _sheetCtrl.isAttached
        ? _sheetCtrl.size.clamp(_sheetMinFracProgramar, 0.75)
        : (_vistaResumenCotizada && _mostrarResumenCotizacion ? 0.52 : 0.34);
    return EdgeInsets.only(
      top: mq.padding.top + 64,
      bottom: h * sheetFrac + 12,
      left: 36,
      right: 36,
    );
  }

  Future<void> _fitProgramarBounds(LatLngBounds bounds, {double pad = 112}) async {
    await _programarMapAnimate((c) async {
      await RaiMapPresentation.fitBounds(
        c,
        bounds,
        padding: pad,
        maxZoom: RaiMapPresentation.maxZoomTrip,
      );
    });
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

  /// Acento del servicio legible sobre fondos claros (p. ej. apariencia blanca).
  Color _colorServicioLegibleEnFondoClaro() {
    switch (tipoServicio) {
      case 'motor':
        return const Color(0xFFEA580C);
      case 'turismo':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF059669);
    }
  }

  /// Precio grande del resumen de cotización: contraste WCAG sobre el tema elegido.
  Color _colorPrecioResumenCotizacion({
    required Color themedBg,
    required bool mapFloating,
    required Color accent,
  }) {
    if (mapFloating) return accent;
    if (ThemeData.estimateBrightnessForColor(themedBg) == Brightness.light) {
      return _colorServicioLegibleEnFondoClaro();
    }
    return accent;
  }

  Color _bordeTarjetaResumenCotizacion({
    required bool mapFloating,
    required bool fondoClaro,
    required Color accent,
    required Color bordeLegible,
  }) {
    if (mapFloating) return accent.withValues(alpha: 0.85);
    return fondoClaro ? bordeLegible : accent;
  }

  @override
  void initState() {
    super.initState();
    PoolTimbreSessionGuard.activarSesionPasajero();

    if (widget.modoAhora) {
      fechaHora = DateTime.now();
    } else {
      fechaHora = DateTime.now().add(const Duration(minutes: 20));
      if (kUsePlacesAutocomplete) {
        _origenBuscarDireccion = true;
      }
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
        _intentarCalculoTrasOrigenListo();
      });
    }

    _initUbicacionParaMapa();
    unawaited(RaiUbicacionClienteService.instance.ensureStarted());
    RaiUbicacionClienteService.instance.modo
        .addListener(_onModoUbicacionCliente);

    WidgetsBinding.instance.addPostFrameCallback((_) => _expandSheet());
    _nudgeCtrl.repeat(reverse: true);
    _nudgeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _nudgeCtrl.stop();
    });

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
    RaiUbicacionClienteService.instance.modo
        .removeListener(_onModoUbicacionCliente);
    _posSub?.cancel();
    _nudgeTimer?.cancel();
    _nudgeCtrl.dispose();
    _peajeCtrl.dispose();
    _calculoDebounce?.cancel();
    _programarMapGestureEndDebounce?.cancel();
    LocationPermissionService.stopGentleRetry();
    super.dispose();
  }

  /// Tras «Permitir» en el banner (una sola vez), retoma GPS y cotiza si ya hay ruta.
  void _onModoUbicacionCliente() {
    if (!mounted) return;
    if (RaiUbicacionClienteService.instance.modo.value !=
        RaiUbicacionClienteModo.listo) {
      return;
    }
    unawaited(_retomarTrasUbicacionLista());
  }

  Future<void> _retomarTrasUbicacionLista() async {
    LocationPermissionService.stopGentleRetry();
    if (_origenMap == null || !_mapMyLocationEnabled) {
      await _initUbicacionParaMapa();
    }
    if (!mounted) return;
    _intentarCalculoTrasOrigenListo();
  }

  bool _tieneOrigenParaCalculo() {
    if (widget.modoAhora) {
      if (_origenMap != null) return true;
      if (latCliente != null && lonCliente != null) return true;
      return false;
    }
    if (_origenBuscarDireccion) {
      // Con Places: solo cotizar cuando el usuario eligió un lugar (coords fijas).
      if (kUsePlacesAutocomplete) return _origenDetManual != null;
      return origenManual.trim().isNotEmpty;
    }
    return _origenMap != null;
  }

  void _intentarCalculoTrasOrigenListo() {
    if (!mounted || !_tieneDestinoParaCalculo() || !_tieneOrigenParaCalculo()) {
      return;
    }
    if (tipoServicio == 'turismo' && _destinoTurismoSeleccionado != null) {
      unawaited(_cotizarTurismoTrasElegirDestino(forzar: true));
      return;
    }
    _programarCalculoAutomatico();
  }

  Future<void> _expandSheet() async {
    final double target = tipoServicio == 'turismo'
        ? (widget.modoAhora ? 0.48 : 0.58)
        : (widget.modoAhora ? 0.62 : 0.66);
    final double clamped = target.clamp(_sheetMinFracProgramar, 0.75);
    try {
      await _sheetCtrl.animateTo(
        clamped,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  Future<void> _expandToMax() async {
    try {
      await _sheetCtrl.animateTo(
        0.76,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    } catch (_) {}
  }

  bool get _mostrarResumenCotizacion =>
      !_esTurismoProgramado &&
      _vistaResumenCotizada &&
      ubicacionObtenida &&
      precioCalculado > 0 &&
      !_cargando &&
      (tipoServicio != 'turismo' || _destinoTurismoSeleccionado != null);

  /// Turismo programado: tras cotizar desde catálogo no saltamos al resumen
  /// compacto (oculta fecha, vehículo e ida y vuelta).
  bool get _esTurismoProgramado =>
      widget.tipoServicio == 'turismo' && !widget.modoAhora;

  bool get _debeAutoMostrarResumenTrasCotizar => !_esTurismoProgramado;

  void _trasCotizarTurismoProgramado() {
    if (!_esTurismoProgramado || precioCalculado <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _expandToMax();
      _snack(
        'Destino listo. Elige fecha y hora, vehículo e ida y vuelta abajo.',
      );
    });
  }

  void _animarSheetParaResumenCotizado() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _sheetCtrl.animateTo(
          0.56,
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
    final basic = await LocationPermissionService.checkAndRequestBasicPermission(
      requestIfDenied: false,
    );
    if (!basic.serviceEnabled) {
      if (mounted) {
        setState(() => _cargandoUbicacion = false);
        LocationPermissionService.startGentleRetry(() {
          if (!mounted) return;
          unawaited(_initUbicacionParaMapa());
        });
      }
      return;
    }
    if (basic.deniedForever) {
      setState(() {
        _locPermDeniedForever = true;
        _cargandoUbicacion = false;
      });
      LocationPermissionService.startGentleRetry(() {
        if (!mounted) return;
        unawaited(_initUbicacionParaMapa());
      });
      return;
    }
    if (!basic.canUseLocation) {
      setState(() {
        _cargandoUbicacion = false;
        _mapMyLocationEnabled = false;
      });
      LocationPermissionService.startGentleRetry(() {
        if (!mounted) return;
        unawaited(_initUbicacionParaMapa());
      });
      return;
    }

    LocationPermissionService.stopGentleRetry();

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final here = LatLng(pos.latitude, pos.longitude);
      _origenMap = here;
      _updateOrigenMarker(here);

      setState(() {
        _cargandoUbicacion = false;
        _mapMyLocationEnabled = true;
      });

      await _programarMapAnimate(
        (c) => c.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: here, zoom: 15),
          ),
        ),
      );
      _didCenterOnce = true;

      await _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 15,
        ),
      ).listen((p) {
        final ll = LatLng(p.latitude, p.longitude);
        _origenMap = ll;
        _updateOrigenMarker(ll);
        if (_map != null && _didCenterOnce && !_tieneDestinoParaCalculo()) {
          unawaited(_programarMapAnimate(
            (c) => c.animateCamera(CameraUpdate.newLatLng(ll)),
          ));
        }
        _syncProgramarMapHalos();
        if (mounted) setState(() {});
        // Viaje ahora: si el destino se eligió antes que el GPS, recalcular al mover origen
        if (widget.modoAhora &&
            mounted &&
            _tieneDestinoParaCalculo() &&
            !ubicacionObtenida) {
          _intentarCalculoTrasOrigenListo();
        }
      });

      // Al quedar listo el GPS, si ya había origen+destino, calcular (viaje ahora o programar).
      if (mounted && _tieneDestinoParaCalculo()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_dibujarRutaSiHayDestino());
          _intentarCalculoTrasOrigenListo();
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

  void _syncProgramarMapHalos() {
    LatLng? dest;
    if (latDestino != null && lonDestino != null) {
      dest = LatLng(latDestino!, lonDestino!);
    }
    RaiMapPresentation.syncHalos(
      circles: _circles,
      origen: _origenMap,
      destino: dest,
    );
  }

  void _updateOrigenMarker(LatLng pos) {
    _markers.removeWhere((m) => m.markerId.value == 'origen');
    _markers.add(
      Marker(
        markerId: const MarkerId('origen'),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Origen · Salida'),
        zIndexInt: 5,
      ),
    );
    _syncProgramarMapHalos();
  }

  Future<void> _centrarEnMiUbicacion() async {
    if (_origenMap == null) {
      await RaiUbicacionClienteService.instance.ensureStarted();
      if (!RaiUbicacionClienteService.instance.ubicacionLista) {
        await RaiUbicacionClienteService.instance.activarUbicacionDesdeApp();
      }
      await _initUbicacionParaMapa();
      if (_origenMap == null) return;
    }
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
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Destino · Llegada'),
        zIndexInt: 6,
      ),
    );
    _syncProgramarMapHalos();

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
      _intentarCalculoTrasOrigenListo();
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
      return 1;
    }
  }

  // ====== CALCULAR PRECIO CON TARIFA POR TIPO DE SERVICIO ======
  Future<double> _calcularPrecioPorTipo(double distancia, bool idaVuelta,
      {double peaje = 0.0}) async {
    final servicio = TarifaServiceUnificado();
    await servicio.recargar();
    final user = FirebaseAuth.instance.currentUser;

    int contadorViajes = 1;
    if (user != null) {
      contadorViajes = await _obtenerContadorViajes(user.uid);
    }
    if (contadorViajes <= 0) contadorViajes = 1;
    _promoSnapshotCotizacion =
        await servicio.construirPromoSnapshot(contadorViajes);

    try {
      Future<({double precio, Map<String, dynamic>? desglose})> cotizar() {
        if (tipoServicio == 'normal') {
          return servicio.calcularPrecioConDesglose(
            tipoServicio: tipoServicio,
            tipoVehiculo: tipoVehiculo,
            distanciaKm: distancia,
            idaVuelta: idaVuelta,
            peaje: peaje,
            contadorViajes: contadorViajes,
          );
        }
        if (tipoServicio == 'motor') {
          return servicio.calcularPrecioConDesglose(
            tipoServicio: tipoServicio,
            distanciaKm: distancia,
            idaVuelta: idaVuelta,
            peaje: peaje,
            contadorViajes: contadorViajes,
          );
        }
        if (tipoServicio == 'turismo') {
          final String vehiculo = _tipoVehiculoTurismo;
          final String subtipo =
              _destinoTurismoSeleccionado?.subtipo ?? 'CIUDAD';
          return servicio.calcularPrecioConDesglose(
            tipoServicio: tipoServicio,
            tipoVehiculo: vehiculo,
            subtipoTurismo: subtipo,
            distanciaKm: distancia,
            idaVuelta: idaVuelta,
            peaje: peaje,
            contadorViajes: contadorViajes,
          );
        }
        return Future.value((precio: 0.0, desglose: null));
      }

      final result = await cotizar();
      _cotizacionDesglose = result.desglose;
      return result.precio;
    } catch (e) {
      if (mounted) _snack('Error calculando precio: $e');
      return 0.0;
    }
  }

  /// Si al confirmar «Ahora» el pickup se movió > [metros], recotiza con el GPS fresco.
  static const double _kMetrosRecotizarAlConfirmar = 120;

  Future<bool> _alinearPickupConfirmacionAhora({
    required double origenCotizadoLat,
    required double origenCotizadoLon,
    required double nuevoOrigenLat,
    required double nuevoOrigenLon,
  }) async {
    if (latDestino == null || lonDestino == null) return false;

    final double metros = Geolocator.distanceBetween(
      origenCotizadoLat,
      origenCotizadoLon,
      nuevoOrigenLat,
      nuevoOrigenLon,
    );

    latCliente = nuevoOrigenLat;
    lonCliente = nuevoOrigenLon;
    _origenMap = LatLng(nuevoOrigenLat, nuevoOrigenLon);

    if (metros <= _kMetrosRecotizarAlConfirmar) {
      return true;
    }

    final servicio = TarifaServiceUnificado();
    await servicio.recargar();
    final RaiDistanciaCotizacion? distRes =
        await RaiOfflineCotizacionService.resolverDistancia(
      originLat: nuevoOrigenLat,
      originLon: nuevoOrigenLon,
      destLat: latDestino!,
      destLon: lonDestino!,
      useDirections: kUseDirectionsForDistance,
      maxKmCotizable: servicio.distanciaMaximaCotizableKm,
    );
    if (distRes == null || distRes.km <= 0) return false;

    final double precioDouble =
        await _calcularPrecioPorTipo(distRes.km, idaYVuelta, peaje: _peaje);
    if (precioDouble <= 0) return false;

    final int precioCents = (precioDouble * 100).round();
    final int comisionCents =
        PlataformaEconomia.comisionViajeCentsDesdePrecioCents(precioCents);

    distanciaKm = distRes.km;
    precioCalculado = precioCents / 100.0;
    _precioEsEstimadoOffline = distRes.estimadoOffline;
    _distanciaFuente = distRes.fuente;
    comisionCalculada = comisionCents / 100.0;
    gananciaTaxistaCalculada = (precioCents - comisionCents) / 100.0;
    ubicacionObtenida = true;

    if (mounted) setState(() {});
    return true;
  }

  void _invalidarCotizacion() {
    _calculoDebounce?.cancel();
    _cotizacionSeq++;
    precioCalculado = 0;
    _precioEsEstimadoOffline = false;
    _cotizacionDesglose = null;
    _distanciaFuente = '';
    ubicacionObtenida = false;
    comisionCalculada = 0;
    gananciaTaxistaCalculada = 0;
    distanciaKm = 0;
    _cargando = false;
    _vistaResumenCotizada = false;
  }

  /// Invalida precio previo sin borrar destino (p. ej. nuevo lugar en autocomplete).
  void _invalidarPrecioCalculado() {
    _calculoDebounce?.cancel();
    _cotizacionSeq++;
    precioCalculado = 0;
    _precioEsEstimadoOffline = false;
    _cotizacionDesglose = null;
    _distanciaFuente = '';
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
    if (tipoServicio == 'turismo' && _destinoTurismoSeleccionado != null) {
      unawaited(_cotizarTurismoTrasElegirDestino(forzar: true));
      return;
    }
    if (_cargando && !automatico) return;
    if (_cargando && automatico) {
      _cotizacionSeq++;
    }

    if (!widget.modoAhora &&
        _origenBuscarDireccion &&
        origenManual.trim().isEmpty &&
        _origenDetManual == null) {
      return;
    }

    final bool tieneOrigen = _tieneOrigenParaCalculo();
    final bool tieneDestino = _tieneDestinoParaCalculo();

    if (!tieneOrigen || !tieneDestino) return;

    FocusScope.of(context).unfocus();
    _formKey.currentState?.save();

    destino = destino.trim();
    if (_origenBuscarDireccion) origenManual = origenManual.trim();

    setState(() => _cargando = true);
    final int runId = _cotizacionSeq;
    try {
      if (widget.modoAhora) {
        final ready = await LocationPermissionService.ensureLocationReady(
          context: context,
          requestIfDenied: false,
        );
        if (!ready.isUsable) {
          if (!automatico &&
              !RaiUbicacionClienteService.instance.bannerActivo) {
            _snack(LocationReadiness.kMsgEsperandoUbicacion);
          }
          _setCargaFalseSiCorre(runId);
          if (automatico && _tieneDestinoParaCalculo()) {
            unawaited(RaiUbicacionClienteService.instance.refrescar());
          }
          return;
        }
        if (ready.position != null) {
          final ll = LatLng(
            ready.position!.latitude,
            ready.position!.longitude,
          );
          _origenMap = ll;
          _updateOrigenMarker(ll);
          if (mounted) setState(() {});
        }
        unawaited(RaiUbicacionClienteService.instance.refrescar());
      }

      double origenLat = 0, origenLon = 0;
      String origenLegible = '';
      String destinoLegible = '';
      double dLat = 0, dLon = 0;

      // ORIGEN: búsqueda (solo programar) o mapa / GPS
      if (!widget.modoAhora && _origenBuscarDireccion) {
        if (kUsePlacesAutocomplete) {
          if (_origenDetManual == null) {
            _setCargaFalseSiCorre(runId);
            return;
          }
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
        if (!mounted) return;
        final ready = await LocationPermissionService.ensureLocationReady(
          context: context,
          requestIfDenied: false,
        );
        if (!ready.isUsable) {
          if (!automatico &&
              !RaiUbicacionClienteService.instance.bannerActivo) {
            _snack(LocationReadiness.kMsgEsperandoUbicacion);
          }
          _setCargaFalseSiCorre(runId);
          if (automatico && _tieneDestinoParaCalculo()) {
            unawaited(RaiUbicacionClienteService.instance.refrescar());
          }
          return;
        }
        final posicion = ready.position!;
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

      double dist = 0;
      DirectionsResult? dir;
      final servicio = TarifaServiceUnificado();
      await servicio.recargar();
      final maxKm = servicio.distanciaMaximaCotizableKm;
      final RaiDistanciaCotizacion? distRes =
          await RaiOfflineCotizacionService.resolverDistancia(
        originLat: origenLat,
        originLon: origenLon,
        destLat: dLat,
        destLon: dLon,
        useDirections: kUseDirectionsForDistance,
        maxKmCotizable: maxKm,
      );
      if (distRes == null || distRes.km <= 0) {
        if (!automatico) {
          _snack(
            '❌ No se pudo calcular distancia válida '
            '(máx. ${maxKm.toStringAsFixed(0)} km por carretera).',
          );
        }
        _setCargaFalseSiCorre(runId);
        return;
      }
      dist = distRes.km;
      dir = distRes.directions;
      final bool estimadoOffline = distRes.estimadoOffline;
      final String distanciaFuente = distRes.fuente;

      final List<LatLng> routeLatLng = dir?.path ?? const <LatLng>[];
      _peajeCtrl.text = _peaje.toStringAsFixed(0);

      final double precioDouble =
          await _calcularPrecioPorTipo(dist, idaYVuelta, peaje: _peaje);
      final int precioCents = (precioDouble * 100).round();
      final int comisionCents =
          PlataformaEconomia.comisionViajeCentsDesdePrecioCents(precioCents);
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
        _precioEsEstimadoOffline = estimadoOffline;
        _distanciaFuente = distanciaFuente;
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
                  BitmapDescriptor.hueGreen),
              infoWindow: const InfoWindow(title: 'Destino · Llegada'),
              zIndexInt: 6,
            ),
          );
        _syncProgramarMapHalos();

        _polylines.clear();
        if (routeLatLng.isNotEmpty) {
          RaiMapPresentation.applyRoutePolylines(
            _polylines,
            id: 'ruta',
            points: routeLatLng,
          );
        } else {
          RaiMapPresentation.applyRoutePolylines(
            _polylines,
            id: 'ruta',
            points: <LatLng>[
              LatLng(origenLat, origenLon),
              LatLng(dLat, dLon),
            ],
          );
        }

        _cargando = false;
        // Turismo programado: mantener formulario (fecha, vehículo, ida y vuelta).
        _vistaResumenCotizada = _debeAutoMostrarResumenTrasCotizar;
      });

      if (_debeAutoMostrarResumenTrasCotizar) {
        _animarSheetParaResumenCotizado();
      } else {
        _trasCotizarTurismoProgramado();
      }

      if (_map != null && runId == _cotizacionSeq) {
        if (routeLatLng.length >= 2) {
          await _fitProgramarBounds(_boundsFromList(routeLatLng));
        } else {
          await _fitProgramarBounds(
            _boundsFrom(LatLng(origenLat, origenLon), LatLng(dLat, dLon)),
            pad: 120,
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
        _polylines.clear();
        RaiMapPresentation.applyRoutePolylines(
          _polylines,
          id: 'ruta',
          points: pts.isNotEmpty
              ? pts
              : <LatLng>[LatLng(oLat, oLon), LatLng(dLat, dLon)],
        );
      });
      _syncProgramarMapHalos();

      if (_map != null) {
        if (pts.length >= 2) {
          await _fitProgramarBounds(_boundsFromList(pts));
        } else {
          await _fitProgramarBounds(
            _boundsFrom(LatLng(oLat, oLon), LatLng(dLat, dLon)),
            pad: 120,
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

  /// Un toque en el catálogo: destino + vehículo; cotiza en [_cotizarTurismoTrasElegirDestino].
  Future<void> _aplicarSeleccionTurismo(DestinoSeleccionado seleccion) async {
    String vehiculoValido = seleccion.tipoVehiculo;
    const vehiculosValidos = ['carro', 'jeepeta', 'minivan', 'bus'];
    if (!vehiculosValidos.contains(vehiculoValido)) {
      debugPrint(
        '⚠️ tipoVehiculo inválido "$vehiculoValido", usando carro',
      );
      vehiculoValido = 'carro';
    }

    if (seleccion.latOrigen != null && seleccion.lonOrigen != null) {
      latCliente = seleccion.latOrigen;
      lonCliente = seleccion.lonOrigen;
      _origenMap = LatLng(seleccion.latOrigen!, seleccion.lonOrigen!);
    } else if (latCliente == null && _origenMap != null) {
      latCliente = _origenMap!.latitude;
      lonCliente = _origenMap!.longitude;
    }

    if (!mounted) return;
    _calculoDebounce?.cancel();
    setState(() {
      _destinoTurismoSeleccionado = seleccion.lugar;
      _tipoVehiculoTurismo = vehiculoValido;
      _pasajerosTurismo = seleccion.pasajeros;

      latDestino = seleccion.lugar.lat;
      lonDestino = seleccion.lugar.lon;
      destinoTexto = seleccion.lugar.nombre;
      destino = seleccion.lugar.nombre;

      precioCalculado = 0;
      _precioEsEstimadoOffline = false;
      _cotizacionDesglose = null;
      _distanciaFuente = '';
      distanciaKm = 0;
      comisionCalculada = 0;
      gananciaTaxistaCalculada = 0;
      ubicacionObtenida = false;
      _vistaResumenCotizada = false;

      if (_origenMap != null) {
        _updateOrigenMarker(_origenMap!);
      }
      _markers
        ..removeWhere((m) => m.markerId.value == 'destino')
        ..add(
          Marker(
            markerId: const MarkerId('destino'),
            position: LatLng(seleccion.lugar.lat, seleccion.lugar.lon),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(title: seleccion.lugar.nombre),
            zIndexInt: 6,
          ),
        );
      _syncProgramarMapHalos();
    });

    await _cotizarTurismoTrasElegirDestino(forzar: true);
  }

  /// Origen para cotizar turismo (mapa, GPS o última posición conocida).
  Future<({double lat, double lon})?> _resolverOrigenParaCotizarTurismo() async {
    if (latCliente != null && lonCliente != null) {
      return (lat: latCliente!, lon: lonCliente!);
    }
    if (_origenMap != null) {
      return (lat: _origenMap!.latitude, lon: _origenMap!.longitude);
    }

    try {
      final Position? last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return (lat: last.latitude, lon: last.longitude);
      }
    } catch (_) {}

    try {
      final ({bool serviceEnabled, LocationPermission permission}) snap =
          await LocationPermissionService.checkServiceThenRequestIfNeeded();
      if (snap.serviceEnabled && GpsService.permissionUsable(snap.permission)) {
        final Position? pos = await GpsService.obtenerUbicacionActual(
          timeout: const Duration(seconds: 12),
          maxEdadUltima: const Duration(hours: 24),
        );
        if (pos != null) {
          return (lat: pos.latitude, lon: pos.longitude);
        }
      }
    } catch (_) {}

    try {
      final Position? last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return (lat: last.latitude, lon: last.longitude);
      }
    } catch (_) {}

    return null;
  }

  /// Cotiza turismo al elegir destino (buscador o catálogo) sin depender de que
  /// [_origenMap] ya estuviera listo antes del debounce genérico.
  Future<void> _cotizarTurismoTrasElegirDestino({bool forzar = false}) async {
    final TurismoLugar? dest = _destinoTurismoSeleccionado;
    if (dest == null || latDestino == null || lonDestino == null) return;
    if (_cargando && !forzar) return;
    _calculoDebounce?.cancel();
    if (_cargando && forzar) _cotizacionSeq++;

    final int runId = _cotizacionSeq;
    if (!mounted) return;
    setState(() => _cargando = true);

    try {
      await () async {
        final ({double lat, double lon})? origen =
            await _resolverOrigenParaCotizarTurismo();
        if (origen == null) {
          unawaited(RaiUbicacionClienteService.instance.refrescar());
          if (mounted) {
            _snack(
              widget.modoAhora
                  ? 'Permite tu ubicación en el banner superior para cotizar.'
                  : 'Activa el GPS y concede permiso de ubicación para cotizar.',
            );
          }
          return;
        }

        latCliente = origen.lat;
        lonCliente = origen.lon;
        _origenMap = LatLng(origen.lat, origen.lon);
        _updateOrigenMarker(_origenMap!);

        double dist = 0;
        bool estimadoOffline = false;
        String distanciaFuente = '';
        final servicioDist = TarifaServiceUnificado();
        await servicioDist.recargar();
        final RaiDistanciaCotizacion? distRes =
            await RaiOfflineCotizacionService.resolverDistancia(
          originLat: origen.lat,
          originLon: origen.lon,
          destLat: latDestino!,
          destLon: lonDestino!,
          useDirections: true,
          maxKmCotizable: servicioDist.distanciaMaximaCotizableKm,
        );
        if (distRes == null || distRes.km <= 0) {
          if (mounted) {
            _snack('No se pudo calcular la distancia al destino.');
          }
          return;
        }
        dist = distRes.km;
        estimadoOffline = distRes.estimadoOffline;
        distanciaFuente = distRes.fuente;

        final double precioDouble =
            await _calcularPrecioPorTipo(dist, idaYVuelta, peaje: _peaje);
        if (precioDouble <= 0) {
          if (mounted) {
            _snack('No se pudo calcular el precio para este destino.');
          }
          return;
        }
        final int precioCents = (precioDouble * 100).round();
        final int comisionCents =
            PlataformaEconomia.comisionViajeCentsDesdePrecioCents(precioCents);

        if (!mounted || runId != _cotizacionSeq) return;

        setState(() {
          distanciaKm = dist;
          precioCalculado = precioCents / 100.0;
          _precioEsEstimadoOffline = estimadoOffline;
          _distanciaFuente = distanciaFuente;
          comisionCalculada = comisionCents / 100.0;
          gananciaTaxistaCalculada = precioCalculado - comisionCalculada;
          ubicacionObtenida = true;
          _cargando = false;
          _vistaResumenCotizada =
              precioCalculado > 0 && _debeAutoMostrarResumenTrasCotizar;
        });

        await _dibujarRutaReal(
          oLat: origen.lat,
          oLon: origen.lon,
          dLat: latDestino!,
          dLon: lonDestino!,
          previewOnly: true,
        );

        if (precioCalculado > 0) {
          if (_debeAutoMostrarResumenTrasCotizar) {
            _animarSheetParaResumenCotizado();
          } else {
            _trasCotizarTurismoProgramado();
          }
        }
      }().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('cotizacion_turismo');
        },
      );
    } on TimeoutException {
      if (mounted) {
        _snack(
          'La cotización tardó demasiado. Revisa tu conexión o el GPS e intenta de nuevo.',
        );
      }
    } catch (e) {
      if (mounted) _snack('Error al cotizar: $e');
    } finally {
      _setCargaFalseSiCorre(runId);
    }
  }

  /// Destino turismo desde Places (mismo buscador que motor/normal).
  Future<void> _aplicarDestinoTurismoDesdeBusqueda(DetalleLugar det) async {
    final String ciudad = (det.address ?? '').split(',').first.trim();
    final TurismoLugar lugar = TurismoLugar(
      id: det.placeId.isNotEmpty ? 'google_${det.placeId}' : 'google_manual',
      nombre: det.name,
      ciudad: ciudad.isNotEmpty ? ciudad : 'República Dominicana',
      lat: det.lat,
      lon: det.lon,
      subtipo: 'busqueda',
      descripcion: det.displayLabel,
      imagen: null,
      popularidad: 0,
    );

    if (!mounted) return;
    setState(() {
      _destinoDet = null;
      _destinoTurismoSeleccionado = lugar;
      destino = det.displayLabel;
      destinoTexto = det.displayLabel;
      latDestino = det.lat;
      lonDestino = det.lon;
    });

    _markers
      ..removeWhere((m) => m.markerId.value == 'destino')
      ..add(
        Marker(
          markerId: const MarkerId('destino'),
          position: LatLng(det.lat, det.lon),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(title: det.name),
          zIndexInt: 6,
        ),
      );
    _syncProgramarMapHalos();

    await _cotizarTurismoTrasElegirDestino(forzar: true);
  }

  // ✅ MÉTODO PARA MOSTRAR SELECTOR DE DESTINOS TURÍSTICOS
  Future<void> _mostrarSelectorDestinosTuristicos() async {
    if (!mounted) return;
    await RaiUbicacionClienteService.instance.ensureStarted();
    try {
      final Position? last = await Geolocator.getLastKnownPosition();
      if (last != null && latCliente == null && _origenMap == null) {
        latCliente = last.latitude;
        lonCliente = last.longitude;
        _origenMap = LatLng(last.latitude, last.longitude);
      }
    } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext ctx) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Catálogo turístico'),
              centerTitle: true,
            ),
            body: TurismoDestinosSheetHost(
              showFloatingBack: false,
              esViajeProgramado: !widget.modoAhora,
              seedLat: latCliente ?? _origenMap?.latitude,
              seedLon: lonCliente ?? _origenMap?.longitude,
              tipoVehiculoInicial: _tipoVehiculoTurismo,
              onDestinoSeleccionado: (DestinoSeleccionado seleccion) async {
                Navigator.of(ctx).pop();
                await _aplicarSeleccionTurismo(seleccion);
              },
            ),
          );
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
    if (!mounted) return;
    final ({NavigatorState? tab, NavigatorState? raiz}) navCapturado =
        NavigationService.capturarNavigadoresFormulario(context);

    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      messenger.showSnackBar(const SnackBar(content: Text(kMsgLogin)));
      return;
    }
    if (RaiOfflineCotizacionService.estaOffline) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(RaiOfflineCotizacionService.mensajeNoConfirmar),
        ),
      );
      return;
    }
    PoolTimbreSessionGuard.activarSesionPasajero();
    NotificationService.I.suprimirTimbrePoolCliente();
    unawaited(NotificationService.I.stopTimbre());
    if (!ubicacionObtenida || latCliente == null || latDestino == null) {
      if (!ubicacionObtenida &&
          RaiUbicacionClienteService.instance.bannerActivo) {
        return;
      }
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

    if (await ActiveTripService.clienteTieneViajeEnSeguimiento(u.uid)) {
      messenger.showSnackBar(
        const SnackBar(content: Text(kMsgClienteYaTieneViajeActivo)),
      );
      return;
    }

    setState(() => _cargando = true);
    final ({NavigatorState? tab, NavigatorState? raiz}) nav = navCapturado;
    try {
      if (widget.modoAhora) {
        if (!mounted) return;
        final ready = await LocationPermissionService.ensureLocationReady(
          context: context,
          requestIfDenied: false,
        );
        if (!ready.isUsable) {
          if (!RaiUbicacionClienteService.instance.bannerActivo) {
            messenger.showSnackBar(
              SnackBar(content: Text(LocationReadiness.kMsgEsperandoUbicacion)),
            );
          }
          if (mounted) setState(() => _cargando = false);
          return;
        }
        if (ready.position != null) {
          final double cotLat = latCliente!;
          final double cotLon = lonCliente!;
          final double freshLat = ready.position!.latitude;
          final double freshLon = ready.position!.longitude;
          final double metrosMovidos = Geolocator.distanceBetween(
            cotLat,
            cotLon,
            freshLat,
            freshLon,
          );
          final bool alineado = await _alinearPickupConfirmacionAhora(
            origenCotizadoLat: cotLat,
            origenCotizadoLon: cotLon,
            nuevoOrigenLat: freshLat,
            nuevoOrigenLon: freshLon,
          );
          if (!alineado) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Tu ubicación cambió. Vuelve a calcular el precio antes de confirmar.',
                ),
              ),
            );
            if (mounted) setState(() => _cargando = false);
            return;
          }
          if (metrosMovidos > _kMetrosRecotizarAlConfirmar && mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Precio actualizado según tu ubicación: '
                  '${FormatosMoneda.rd(precioCalculado)}.',
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
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
      if (tipoServicio == 'turismo' &&
          _destinoTurismoSeleccionado != null &&
          _destinoTurismoSeleccionado!.subtipo.isNotEmpty) {
        extras['categoriaDestinoTurismo'] =
            _destinoTurismoSeleccionado!.subtipo;
      }
      if (_promoSnapshotCotizacion != null) {
        extras['promoSnapshot'] = _promoSnapshotCotizacion;
      }
      if (_cotizacionDesglose != null && _cotizacionDesglose!.isNotEmpty) {
        extras['cotizacionDesglose'] = _cotizacionDesglose;
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
        metodoPago: 'Efectivo',
        tipoVehiculo:
            tipoServicio == 'turismo' && _tipoVehiculoTurismo.isNotEmpty
                ? _mapTipoVehiculoTurismo(_tipoVehiculoTurismo)
                : tipoVehiculo,
        idaYVuelta: idaYVuelta,
        distanciaKm: distanciaKm > 0 ? distanciaKm : null,
        tipoServicio: tipoServicio,
        subtipoTurismo: tipoServicio == 'turismo'
            ? (_tipoVehiculoTurismo.isNotEmpty
                ? _tipoVehiculoTurismo
                : 'carro')
            : widget.subtipoTurismo,
        forzarEsAhora: viajeInmediato ? true : null,
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

      await NavigationService.navegarTrasCrearViajeCliente(
        viajeId: id,
        fechaHoraPickup: fechaProgramadaUtc,
        tipoServicio: tipoServicio,
        preNav: nav.tab,
        preNavRaiz: nav.raiz,
      );
    } on fs.FirebaseException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('❌ Firestore (${e.code}): ${e.message ?? e}')),
      );
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
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
    bool mapFloating = false,
  }) {
    // En modo flotante sobre el mapa, los rellenos del mockup quedan como
    // manchones que no destacan. Forzamos panel GRIS OSCURO casi negro
    // (#0F172A 0.92) con sombra negra para que parezca una card flotante
    // sólida sobre el mapa CLARO de Google Maps. Texto en blanco, borde
    // de acento brillante para resaltar contra el fondo oscuro y al mismo
    // tiempo contra el mapa claro.
    final Color floatingFill =
        const Color(0xFF0F172A).withValues(alpha: 0.92);
    // Si el accent que viene del call site es muy oscuro (modo claro),
    // lo "subimos" a un tono brillante para que se vea sobre el card oscuro.
    final Color floatingAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Color.alphaBlend(
                Colors.white.withValues(alpha: 0.55),
                accent,
              )
            : accent;
    final List<BoxShadow>? floatingShadow = mapFloating
        ? <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ]
        : null;

    if (!mockupRuta) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        decoration: BoxDecoration(
          color: mapFloating ? floatingFill : fill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: mapFloating
                ? floatingAccent.withValues(alpha: 0.85)
                : accent.withValues(alpha: 0.55),
            width: mapFloating ? 1.6 : 1.5,
          ),
          boxShadow: floatingShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icono,
                    color: mapFloating ? floatingAccent : accent, size: 22),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: TextStyle(
                    color: mapFloating ? Colors.white : tituloColor,
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

    final Color ayudaCol = mapFloating
        ? Colors.white.withValues(alpha: 0.78)
        : (ayudaColor ?? (isDark ? Colors.white60 : const Color(0xFF667085)));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: mapFloating
            ? floatingFill
            : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: mapFloating
              ? floatingAccent.withValues(alpha: 0.85)
              : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFD0D5DD)),
          width: mapFloating ? 1.6 : 1.0,
        ),
        boxShadow: floatingShadow,
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
                  color: (mapFloating ? floatingAccent : accent)
                      .withValues(alpha: mapFloating ? 0.22 : 0.16),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (mapFloating ? floatingAccent : accent)
                        .withValues(alpha: mapFloating ? 0.78 : 0.58),
                  ),
                ),
                child: Icon(icono,
                    color: mapFloating ? floatingAccent : accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        color: mapFloating ? Colors.white : tituloColor,
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
    bool mapFloating = false,
  }) {
    // En modo "Flotante sobre mapa" el morado oscuro de [destinoFill] queda
    // como una mancha opaca sobre el mapa de Google. Forzamos panel GRIS
    // OSCURO casi negro con texto blanco + borde de acento (púrpura claro)
    // + sombra negra para que la tarjeta destaque sobre el mapa siempre
    // claro de Google Maps, en cualquier modo de la app.
    final Color panelBg = mapFloating
        ? const Color(0xFF0F172A).withValues(alpha: 0.92)
        : destinoFill;
    final Color titleColor = mapFloating ? Colors.white : textPrimary;
    final Color bodyColor = mapFloating
        ? Colors.white.withValues(alpha: 0.82)
        : textSecondary;
    // Acento púrpura más brillante para resaltar contra la card oscura.
    final Color borderAccent = mapFloating
        ? const Color(0xFFD8B4FE)
        : destinoAccent;
    final Color borderCol = borderAccent.withValues(
      alpha: mapFloating ? 0.85 : 0.5,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderCol, width: mapFloating ? 1.6 : 1.0),
        boxShadow: mapFloating
            ? <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: borderAccent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Falta la llegada',
                  style: TextStyle(
                    color: titleColor,
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
              color: bodyColor,
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
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
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
                maxLines: 4,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
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
    final bool isDark = ThemeData.estimateBrightnessForColor(
            Theme.of(context).scaffoldBackgroundColor) ==
        Brightness.dark;
    final bool mapFloating = CustomThemeService.mapFloatingChrome.value;
    final Color themedBg = Theme.of(context).scaffoldBackgroundColor;
    final bool fondoClaro = !mapFloating &&
        ThemeData.estimateBrightnessForColor(themedBg) == Brightness.light;
    // En modo flotante: panel OSCURO sólido + texto blanco + borde de
    // acento brillante + sombra negra para destacar sobre el mapa claro
    // de Google. Funciona idéntico en modo claro y oscuro de la app.
    final Color textPrimary = mapFloating
        ? Colors.white
        : CustomThemeService.textOn(themedBg);
    final Color textSecondary = mapFloating
        ? Colors.white.withValues(alpha: 0.85)
        : CustomThemeService.textMutedOn(themedBg);
    final Color textMuted = mapFloating
        ? Colors.white.withValues(alpha: 0.70)
        : CustomThemeService.textSubtleOn(themedBg);
    final Color dividerSoft = mapFloating
        ? Colors.white.withValues(alpha: 0.22)
        : CustomThemeService.borderOn(themedBg);
    final Color c = _colorServicio;
    final Color cLegible = _colorServicioLegibleEnFondoClaro();
    // En flotante "subimos" el acento del servicio a un tono brillante para
    // que destaque sobre la card oscura. Si ya es brillante, lo dejamos.
    final Color cBright =
        ThemeData.estimateBrightnessForColor(c) == Brightness.dark
            ? Color.alphaBlend(Colors.white.withValues(alpha: 0.55), c)
            : c;
    final Color accent = mapFloating ? cBright : (fondoClaro ? cLegible : c);
    final Color precioColor = _colorPrecioResumenCotizacion(
      themedBg: themedBg,
      mapFloating: mapFloating,
      accent: accent,
    );
    final Color cardBorder = _bordeTarjetaResumenCotizacion(
      mapFloating: mapFloating,
      fondoClaro: fondoClaro,
      accent: accent,
      bordeLegible: cLegible,
    );
    final pRes = _paletasOrigenDestino(isDark, tipoServicio);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: mapFloating
                  ? const Color(0xFF0F172A).withValues(alpha: 0.93)
                  : (fondoClaro ? CustomThemeService.cardOn(themedBg) : null),
              gradient: mapFloating
                  ? null
                  : fondoClaro
                      ? LinearGradient(
                          colors: [
                            cLegible.withValues(alpha: 0.10),
                            cLegible.withValues(alpha: 0.03),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: [
                            c.withValues(alpha: isDark ? 0.22 : 0.12),
                            c.withValues(alpha: isDark ? 0.08 : 0.04),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: cardBorder,
                width: 2,
              ),
              boxShadow: mapFloating
                  ? <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.32),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : fondoClaro
                      ? <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: accent, size: 26),
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
                            color: accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                            border: mapFloating
                                ? Border.all(
                                    color:
                                        accent.withValues(alpha: 0.6))
                                : null,
                          ),
                          child: Text(
                            'Ida y vuelta',
                            style: TextStyle(
                                color: accent,
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
                    maxLines: 3,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: textMuted, fontSize: 12),
                  ),
                ],
                if (tipoServicio == 'turismo') ...[
                  const SizedBox(height: 6),
                  Text(
                    'Vehículo: ${_mapTipoVehiculoTurismo(_tipoVehiculoTurismo)}',
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: textMuted, fontSize: 12),
                  ),
                ],
                if (tipoServicio == 'normal') ...[
                  const SizedBox(height: 6),
                  Text(
                    'Vehículo: $tipoVehiculo',
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: textMuted, fontSize: 12),
                  ),
                ],
                PromoMxKClientePanel(
                  promoSnapshot: _promoSnapshotCotizacion,
                  promoOmitidaPorLargaDistancia:
                      _cotizacionDesglose?['promoOmitidaPorLargaDistancia'] == true,
                  textColor: textPrimary,
                  mutedColor: textMuted,
                ),
                const SizedBox(height: 4),
                Text(
                  'TOTAL A PAGAR',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fondoClaro ? textPrimary : textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: mapFloating
                        ? Colors.white.withValues(alpha: 0.08)
                        : precioColor.withValues(alpha: fondoClaro ? 0.10 : 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: precioColor.withValues(alpha: fondoClaro ? 0.42 : 0.55),
                      width: fondoClaro ? 2 : 1.5,
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      FormatosMoneda.rd(precioCalculado),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: precioColor,
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
                RaiCotizacionOfflineHint(visible: _precioEsEstimadoOffline),
                if (distanciaKm > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _cotizacionDesglose?['esLargaDistancia'] == true
                          ? 'Viaje interurbano · ${FormatosMoneda.km(distanciaKm)}'
                          : 'Viaje local · ${FormatosMoneda.km(distanciaKm)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                if (_distanciaFuente == 'directions')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Distancia por carretera (RD)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textMuted, fontSize: 11.5),
                    ),
                  ),
                if (_cotizacionDesglose != null)
                  CotizacionDesglosePanel(
                    desglose: _cotizacionDesglose!,
                    textColor: textPrimary,
                    mutedColor: textMuted,
                  ),
                if (!widget.modoAhora) ...[
                  const SizedBox(height: 10),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _seleccionarFechaHora,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.event_rounded,
                                size: 18, color: textSecondary),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                DateFormat('dd/MM/yyyy - HH:mm')
                                    .format(fechaHora),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: textSecondary,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.edit_calendar_outlined,
                                size: 16, color: accent),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (ubicacionObtenida &&
                            precioCalculado > 0 &&
                            !RaiOfflineCotizacionService.estaOffline)
                        ? () => _programarViaje(
                              ScaffoldMessenger.of(context),
                              Navigator.of(context),
                            )
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mapFloating
                          ? Color.alphaBlend(
                              Colors.black.withValues(alpha: 0.26), c)
                          : (fondoClaro ? cLegible : c),
                      foregroundColor:
                          mapFloating ? Colors.white : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: mapFloating
                            ? BorderSide(
                                color: Colors.white
                                    .withValues(alpha: 0.55),
                                width: 1.4,
                              )
                            : BorderSide.none,
                      ),
                      elevation: mapFloating ? 0 : 2,
                    ),
                    child: Text(
                      widget.modoAhora
                          ? 'Confirmar viaje'
                          : 'Confirmar programación',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _botonVolverInicioProgramar(foreground: accent),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (tipoServicio != 'turismo')
            Material(
            color: mapFloating
                ? const Color(0xFF0F172A).withValues(alpha: 0.92)
                : (fondoClaro
                    ? CustomThemeService.cardOn(themedBg)
                    : (isDark ? const Color(0xFF1A1A1A) : Colors.white)),
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
                    Icon(Icons.search_rounded, color: accent, size: 26),
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
      final bool isDark = ThemeData.estimateBrightnessForColor(
              Theme.of(context).scaffoldBackgroundColor) ==
          Brightness.dark;
      final bool mapFloating = CustomThemeService.mapFloatingChrome.value;
      // En modo flotante el fondo real es el mapa CLARO de Google → cards
      // oscuras + texto blanco para máxima legibilidad sin importar si la
      // app está en modo claro u oscuro.
      final Color textPrimary = mapFloating
          ? Colors.white
          : (isDark ? Colors.white : const Color(0xFF101828));
      final Color textSecondary = mapFloating
          ? Colors.white.withValues(alpha: 0.85)
          : (isDark ? Colors.white70 : const Color(0xFF475467));
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
      // Acento brillante en flotante para que destaque sobre la card oscura.
      final Color displayColor = mapFloating
          ? (widget.tipoServicio == 'turismo'
              ? const Color(0xFFD8B4FE)
              : widget.tipoServicio == 'motor'
                  ? const Color(0xFFFFB74D)
                  : const Color(0xFF49F18B))
          : color;
      final Widget iconoServicio = Container(
        padding: EdgeInsets.all(iconPad),
        decoration: BoxDecoration(
          color: displayColor.withValues(alpha: mapFloating ? 0.28 : 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(icono, color: displayColor, size: iconSize),
      );

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mapFloating
              ? const Color(0xFF0F172A).withValues(alpha: 0.92)
              : null,
          gradient: mapFloating
              ? null
              : LinearGradient(
                  colors: [color.withValues(alpha: 0.2), Colors.transparent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: mapFloating
                ? displayColor.withValues(alpha: 0.85)
                : color,
            width: mapFloating ? 1.6 : 1,
          ),
          boxShadow: mapFloating
              ? <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
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
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: textPrimary, fontWeight: FontWeight.bold),
                      ),
                    if (widget.tipoServicio == 'turismo' &&
                        _destinoTurismoSeleccionado != null)
                      Text(
                        'Destino: ${_destinoTurismoSeleccionado!.nombre}',
                        maxLines: 3,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: displayColor, fontSize: 12),
                      ),
                    if (widget.tipoServicio == 'turismo')
                      Text(
                        'Vehículo: ${_tipoVehiculoTurismo == 'carro' ? 'Carro' : _tipoVehiculoTurismo == 'jeepeta' ? 'Jeepeta' : _tipoVehiculoTurismo == 'minivan' ? 'Minivan' : 'Bus'}',
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
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

  Widget _buildTurismoVehiculoSelector({
    required bool mapFloating,
    required Color chromeToneRef,
    required bool strongChrome,
  }) {
    // En flotante el menú desplegable abre OSCURO sólido (#0F172A) con
    // texto BLANCO bold para que las 4 opciones se lean perfecto. El
    // label del botón cerrado también va blanco bold sobre la _Caja
    // oscura.
    final Color fillSurface = mapFloating
        ? const Color(0xFF0F172A)
        : CustomThemeService.cardOn(chromeToneRef);
    final Color labelColor = mapFloating
        ? Colors.white
        : CustomThemeService.textMutedOn(chromeToneRef);
    final Color ddColor = mapFloating
        ? Colors.white
        : CustomThemeService.textOn(chromeToneRef);
    final FontWeight ddWeight =
        mapFloating ? FontWeight.w800 : FontWeight.w600;
    return _Caja(
      mapFloating: mapFloating,
      strongChrome: strongChrome,
      child: OverflowSafeLabeledDropdown(
        leading: Icon(Icons.directions_car_filled_outlined, color: labelColor),
        label: 'Tipo de Vehículo',
        labelStyle: TextStyle(
          color: labelColor,
          fontWeight: mapFloating ? FontWeight.w700 : FontWeight.w500,
        ),
        dropdown: DropdownButton<String>(
          isExpanded: true,
          value: _tipoVehiculoTurismo,
          dropdownColor: fillSurface,
          underline: const SizedBox(),
          iconEnabledColor: ddColor,
          style: TextStyle(color: ddColor, fontSize: 16, fontWeight: ddWeight),
          items: [
            DropdownMenuItem(
                value: 'carro',
                child: Text('Carro',
                    style: TextStyle(color: ddColor, fontWeight: ddWeight))),
            DropdownMenuItem(
                value: 'jeepeta',
                child: Text('Jeepeta',
                    style: TextStyle(color: ddColor, fontWeight: ddWeight))),
            DropdownMenuItem(
                value: 'minivan',
                child: Text('Minivan',
                    style: TextStyle(color: ddColor, fontWeight: ddWeight))),
            DropdownMenuItem(
                value: 'bus',
                child: Text('Bus',
                    style: TextStyle(color: ddColor, fontWeight: ddWeight))),
          ],
          onChanged: (v) {
            setState(() {
              _tipoVehiculoTurismo = v ?? 'carro';
            });
            _intentarCalculoTrasOrigenListo();
          },
        ),
      ),
    );
  }

  void _salirAlInicioDesdeProgramar() {
    unawaited(NavigationService.irAlInicioCliente(context: context));
  }

  Widget _selectorFechaHoraProgramado({
    required Color textPrimary,
    required Color textSecondary,
    required bool isDark,
    required bool sheetStrongChrome,
    required Color accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Text(
          'Fecha y hora de recogida',
          style: TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _seleccionarFechaHora,
          icon: const Icon(Icons.calendar_today),
          label: const Text('Seleccionar fecha y hora'),
          style: _botonEstilo(context, sheetStrongChrome: sheetStrongChrome),
        ),
        const SizedBox(height: 6),
        Text(
          'Programado para: ${DateFormat('dd/MM/yyyy - HH:mm').format(fechaHora)}',
          style: TextStyle(
            color: sheetStrongChrome
                ? const Color(0xFF065F46)
                : (isDark ? Colors.greenAccent : const Color(0xFF0F9D58)),
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Podés cambiar la hora antes de confirmar la reserva.',
          style: TextStyle(color: textSecondary, fontSize: 12, height: 1.3),
        ),
      ],
    );
  }

  Widget _botonVolverInicioProgramar({
    Color? foreground,
    bool outlined = true,
  }) {
    final Widget btn = outlined
        ? OutlinedButton.icon(
            onPressed: _salirAlInicioDesdeProgramar,
            icon: const Icon(Icons.home_rounded, size: 20),
            label: const Text('Volver al inicio'),
            style: OutlinedButton.styleFrom(
              foregroundColor: foreground,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          )
        : TextButton.icon(
            onPressed: _salirAlInicioDesdeProgramar,
            icon: const Icon(Icons.home_rounded, size: 20),
            label: const Text('Volver al inicio'),
          );
    return SizedBox(width: double.infinity, child: btn);
  }

  /// Tras elegir destino del catálogo en turismo programado: guía al cliente
  /// hacia fecha, vehículo e ida y vuelta (antes quedaban ocultos en el resumen).
  Widget _bannerCompletarTurismoProgramado({
    required Color textPrimary,
    required Color textSecondary,
    required bool mapFloating,
  }) {
    if (!_esTurismoProgramado ||
        _destinoTurismoSeleccionado == null ||
        precioCalculado <= 0) {
      return const SizedBox.shrink();
    }

    final Color accent = mapFloating
        ? const Color(0xFFD8B4FE)
        : (Theme.of(context).brightness == Brightness.dark
            ? Colors.greenAccent
            : const Color(0xFF0F9D58));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: mapFloating ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_available_rounded, color: accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Completa tu reserva',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Destino: ${_destinoTurismoSeleccionado!.nombre}. '
            'Elige fecha y hora abajo, confirma el vehículo '
            '(${_mapTipoVehiculoTurismo(_tipoVehiculoTurismo)}) '
            'y activa ida y vuelta si la necesitas.',
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              height: 1.38,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: CustomThemeService.mapFloatingChrome,
      builder: (context, mapFloating, _) {
        final Color themedBg = Theme.of(context).scaffoldBackgroundColor;
        final bool isDark =
            ThemeData.estimateBrightnessForColor(themedBg) == Brightness.dark;
        // Fondo personalizable por el usuario (servicio CustomThemeService).
        // Tono de referencia OSCURO en flotante => textOn devuelve BLANCO,
        // borderOn devuelve claro, y _legibilityShadowsForChrome añade halo
        // NEGRO grueso para los textos sueltos sobre el mapa claro.
        const Color kChromeFloatingRef = Color(0xFF0F172A);
        final Color chromeToneRef =
            mapFloating ? kChromeFloatingRef : themedBg;
        final Color textPrimary = CustomThemeService.textOn(chromeToneRef);
        final Color textSecondary =
            CustomThemeService.textMutedOn(chromeToneRef);
        final Color textMuted = CustomThemeService.textSubtleOn(chromeToneRef);
        final Color switchCardBorder =
            CustomThemeService.borderOn(chromeToneRef);
        final Color switchAccent =
            isDark ? Colors.greenAccent : const Color(0xFF0F9D58);
        final double userBgAlpha = themedBg.a;
        final double sheetAlpha = userBgAlpha < 0.85 ? userBgAlpha : 0.85;
        final Color sheetBg = mapFloating
            ? Colors.transparent
            : themedBg.withValues(alpha: sheetAlpha);
        // Mapa a la vista (flotante o color translúcido): UI más marcada.
        final bool sheetStrongChrome = mapFloating || themedBg.a < 0.92;
        final List<Shadow>? chromeLegibilityShadows = sheetStrongChrome
            ? _legibilityShadowsForChrome(chromeToneRef)
            : null;

        final Color sheetHandle = mapFloating
            ? const Color(0xFF000000).withValues(alpha: 0.85)
            : sheetStrongChrome
                ? Colors.white.withValues(alpha: isDark ? 0.42 : 0.74)
                : (isDark ? Colors.white24 : const Color(0xFFD0D5DD));

        // Helpers para textos SUELTOS sobre el mapa (no dentro de cards
        // oscuras): negro intenso con halo BLANCO grueso. Así destacan
        // sobre el mapa claro de Google sin verse "borrosos" como sucedía
        // con texto blanco + halo negro.
        final Color freeTextColor =
            mapFloating ? const Color(0xFF000000) : textPrimary;
        final Color freeTextMutedColor =
            mapFloating ? const Color(0xFF1F2937) : textMuted;
        final List<Shadow>? freeTextHaloShadows = mapFloating
            ? <Shadow>[
                Shadow(
                  blurRadius: 8,
                  color: Colors.white.withValues(alpha: 0.95),
                  offset: const Offset(0, 0),
                ),
                Shadow(
                  blurRadius: 14,
                  color: Colors.white.withValues(alpha: 0.85),
                  offset: const Offset(0, 0),
                ),
                Shadow(
                  blurRadius: 2,
                  color: Colors.white,
                  offset: const Offset(0, 1),
                ),
              ]
            : null;
        final Color payLinkColor = mapFloating
            ? const Color(0xFF49F18B) // verde brillante: visible sobre oscuro
            : sheetStrongChrome
                ? const Color(0xFF065F46)
                : (isDark ? Colors.green.shade300 : const Color(0xFF0F9D58));
        final Color dividerSoft = mapFloating
            ? Colors.white.withValues(alpha: 0.28)
            : sheetStrongChrome
                ? Colors.white.withValues(alpha: isDark ? 0.32 : 0.42)
                : (isDark ? Colors.white24 : const Color(0xFFE4E7EC));
        final pRuta = _paletasOrigenDestino(isDark, tipoServicio);
        final bool uiRutaMockup = tipoServicio != 'turismo';

        return FlygoSalidaSegura(
      child: Scaffold(
        backgroundColor: mapFloating ? Colors.transparent : themedBg,
        appBar: RaiAppBar(
          title: tipoServicio == 'turismo' ? 'Turismo RAI' : 'Programar Viaje',
          backWhenCanPop: true,
        ),
        body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const RaiUbicacionClienteBanner(),
          Expanded(
            child: Stack(
        children: [
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: _cargandoUbicacion,
              child: GoogleMap(
                padding: _programarMapPadding(context),
                initialCameraPosition: const CameraPosition(
                  target: LatLng(18.4861, -69.9312),
                  zoom: 12,
                ),
                myLocationEnabled: _mapMyLocationEnabled && !_cargandoUbicacion,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: _markers,
                polylines: _polylines,
                circles: _circles,
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
              child: _Banner(
                  mapFloating: mapFloating,
                  text: 'Ubicando…', icon: Icons.location_searching),
            )
          else if (_locPermDeniedForever)
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: RaiUbicacionClienteMapAlert(
                mapFloating: mapFloating,
                permisoBloqueadoEnPantalla: true,
              ),
            )
          else if (_cargando &&
              (widget.modoAhora || tipoServicio == 'turismo') &&
              _tieneDestinoParaCalculo())
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: _Banner(
                mapFloating: mapFloating,
                text: 'Calculando precio de tu viaje…',
                icon: Icons.payments_outlined,
              ),
            )
          else if ((widget.modoAhora || tipoServicio == 'turismo') &&
              _tieneDestinoParaCalculo() &&
              !ubicacionObtenida &&
              !_cargandoUbicacion &&
              !_cargando)
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: RaiUbicacionClienteMapAlert(
                mapFloating: mapFloating,
                obteniendoGps:
                    RaiUbicacionClienteService.instance.modo.value ==
                            RaiUbicacionClienteModo.listo &&
                        _origenMap == null,
              ),
            ),
          Positioned(
            right: 16,
            bottom: 220,
            child: FloatingActionButton(
              heroTag: 'programar_viaje_centrar',
              mini: true,
              backgroundColor: mapFloating
                  ? const Color(0xFF0F172A).withValues(alpha: 0.93)
                  : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
              onPressed: _centrarEnMiUbicacion,
              child: Icon(Icons.my_location,
                  color: mapFloating
                      ? const Color(0xFF49F18B)
                      : (isDark ? Colors.white : const Color(0xFF0F9D58))),
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheetCtrl,
            minChildSize: _sheetMinFracProgramar,
            maxChildSize: 0.75,
            initialChildSize:
                tipoServicio == 'turismo' ? 0.38 : 0.32,
            snap: true,
            snapSizes: const [_sheetMinFracProgramar, 0.56, 0.75],
            builder: (context, controller) {
              final double safeBottom = MediaQuery.of(context).padding.bottom;
              const BorderRadius sheetTopRadius =
                  BorderRadius.vertical(top: Radius.circular(24));
              // En modo flotante:
              //   - sin sombras (no asoma nada por arriba)
              //   - sin blur (sigma 0 → no hay vidrio esmerilado)
              //   - sin borde superior
              //   - color del Container 100% transparente
              // → El sheet desaparece totalmente y SOLO se ven los textos,
              //   campos y botones flotando sobre el mapa real.
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: sheetTopRadius,
                  boxShadow: mapFloating
                      ? const <BoxShadow>[]
                      : <BoxShadow>[
                          BoxShadow(
                            color:
                                Colors.black.withValues(alpha: isDark ? 0.38 : 0.10),
                            blurRadius: 22,
                            offset: const Offset(0, -4),
                          ),
                          BoxShadow(
                            color: _colorServicio.withValues(alpha: 0.08),
                            blurRadius: 24,
                            spreadRadius: 1,
                          ),
                        ],
                ),
                child: ClipRRect(
                  borderRadius: sheetTopRadius,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: mapFloating ? 0.0 : 12,
                      sigmaY: mapFloating ? 0.0 : 12,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: sheetBg,
                        borderRadius: sheetTopRadius,
                        border: mapFloating
                            ? null
                            : Border(
                                top: BorderSide(
                                  color: sheetStrongChrome
                                      ? Colors.white.withValues(
                                          alpha: isDark ? 0.26 : 0.62)
                                      : Colors.white.withValues(
                                          alpha: isDark ? 0.06 : 0.55),
                                  width: sheetStrongChrome ? 1.15 : 0.8,
                                ),
                              ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                    if (_cargando)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: mapFloating
                            ? Container(
                                padding: const EdgeInsets.fromLTRB(
                                    14, 14, 14, 14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A)
                                      .withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white
                                        .withValues(alpha: 0.55),
                                    width: 1.6,
                                  ),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.30),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: Theme.of(context)
                                        .colorScheme
                                        .copyWith(onSurface: Colors.white),
                                  ),
                                  child: CotizacionPrecioLoadingStrip(
                                    accentColor: const Color(0xFF49F18B),
                                    isDark: true,
                                    message: (ubicacionObtenida &&
                                            precioCalculado > 0)
                                        ? 'Guardando viaje…'
                                        : 'Calculando precio…',
                                  ),
                                ),
                              )
                            : CotizacionPrecioLoadingStrip(
                                accentColor: _colorServicio,
                                isDark: isDark,
                                message:
                                    (ubicacionObtenida && precioCalculado > 0)
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
                          child: DefaultTextStyle.merge(
                            style: TextStyle(shadows: chromeLegibilityShadows),
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
                                              size: 18,
                                              color: mapFloating
                                                  ? const Color(0xFF000000)
                                                  : textMuted,
                                              shadows: freeTextHaloShadows),
                                          const SizedBox(width: 6),
                                          Text(
                                            tipoServicio == 'turismo'
                                                ? (_destinoTurismoSeleccionado !=
                                                        null
                                                    ? (_esTurismoProgramado
                                                        ? 'Destino listo · elige fecha y opciones abajo'
                                                        : 'Desliza para ver precio y confirmar')
                                                    : 'Busca un destino o abre el catálogo abajo')
                                                : (_mostrarResumenCotizacion
                                                    ? 'Toca “Cambiar ruta” abajo para el buscador y opciones'
                                                    : 'Desliza o toca para ver todo'),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                color: freeTextMutedColor,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                shadows: freeTextHaloShadows),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (!_mostrarResumenCotizacion)
                                ClienteViajeOrientacionBanner(
                                  mensaje: ClienteViajeOrientacionCopy.programarViaje(
                                    modoAhora: widget.modoAhora,
                                    tipoServicio: tipoServicio,
                                  ),
                                  icon: ClienteViajeOrientacionCopy.iconoProgramarViaje(
                                    tipoServicio,
                                    modoAhora: widget.modoAhora,
                                  ),
                                  accentColor: _colorServicio,
                                ),
                              if (!_mostrarResumenCotizacion)
                                const SizedBox(height: 10),
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
                                                    color: freeTextColor,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 18,
                                                    letterSpacing: -0.2,
                                                    shadows:
                                                        freeTextHaloShadows,
                                                  ),
                                                ),
                                                Text(
                                                  widget.modoAhora
                                                      ? 'Salida: tu ubicación (GPS) · llegada: escribila abajo'
                                                      : 'Completá salida y llegada',
                                                  style: TextStyle(
                                                    color: freeTextMutedColor,
                                                    fontSize: 12.5,
                                                    height: 1.35,
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    shadows:
                                                        freeTextHaloShadows,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Text(
                                              'Origen y destino',
                                              style: TextStyle(
                                                color: freeTextColor,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.4,
                                                shadows: freeTextHaloShadows,
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
                                                  color: mapFloating
                                                      ? const Color(0xFF000000)
                                                          .withValues(
                                                              alpha: 0.92)
                                                      : pRuta.origenBorde
                                                          .withValues(
                                                              alpha: 0.65),
                                                  width:
                                                      mapFloating ? 1.4 : 1.0,
                                                ),
                                                color: mapFloating
                                                    ? Colors.white.withValues(
                                                        alpha: 0.95)
                                                    : pRuta.origenAccent
                                                        .withValues(
                                                            alpha: 0.12),
                                                boxShadow: mapFloating
                                                    ? <BoxShadow>[
                                                        BoxShadow(
                                                          color: Colors.black
                                                              .withValues(
                                                                  alpha: 0.18),
                                                          blurRadius: 6,
                                                          offset: const Offset(
                                                              0, 2),
                                                        ),
                                                      ]
                                                    : null,
                                              ),
                                              child: Icon(
                                                Icons.gps_fixed_rounded,
                                                color: mapFloating
                                                    ? const Color(0xFFD97706)
                                                    : pRuta.origenAccent,
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
                                                      color: mapFloating
                                                          ? const Color(
                                                              0xFF000000)
                                                          : pRuta
                                                              .origenAccent,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      fontSize: 13,
                                                      shadows:
                                                          freeTextHaloShadows,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Tu ubicación en el mapa. Mové el pin si hace falta.',
                                                    style: TextStyle(
                                                      color:
                                                          freeTextMutedColor,
                                                      fontSize: 12,
                                                      height: 1.3,
                                                      fontWeight: mapFloating
                                                          ? FontWeight.w700
                                                          : FontWeight.w400,
                                                      shadows:
                                                          freeTextHaloShadows,
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
                                          mapFloating: mapFloating,
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
                                                          biasLat: latCliente ??
                                                              _origenMap
                                                                  ?.latitude,
                                                          biasLon: lonCliente ??
                                                              _origenMap
                                                                  ?.longitude,
                                                          asistenteDireccionHabilitado:
                                                              true,
                                                          showQuickSuggestions:
                                                              false,
                                                          showCategories: false,
                                                          fieldAccent: mapFloating
                                                              ? const Color(
                                                                  0xFFFCD34D)
                                                              : pRuta
                                                                  .origenAccent,
                                                          fieldFill: mapFloating
                                                              ? const Color(
                                                                      0xFF111827)
                                                                  .withValues(
                                                                      alpha:
                                                                          0.92)
                                                              : (isDark
                                                                  ? (uiRutaMockup
                                                                      ? const Color(
                                                                          0xFF1A1208)
                                                                      : const Color(
                                                                          0xFF1C1508))
                                                                  : Colors.white),
                                                          onPlaceSelected:
                                                              (det) async {
                                                            _origenDetManual =
                                                                det;
                                                            origenManual = det
                                                                .displayLabel;
                                                            origenTexto = det
                                                                .displayLabel;
                                                            latCliente =
                                                                det.lat;
                                                            lonCliente =
                                                                det.lon;
                                                            _origenMap = LatLng(
                                                                det.lat,
                                                                det.lon);
                                                            _updateOrigenMarker(
                                                                _origenMap!);
                                                            setState(() {});
                                                            await _dibujarRutaSiHayDestino();
                                                            _intentarCalculoTrasOrigenListo();
                                                          },
                                                          onTextChanged: (t) {
                                                            setState(() {
                                                              origenManual = t;
                                                              _origenDetManual =
                                                                  null;
                                                              origenTexto = '';
                                                              _invalidarCotizacion();
                                                            });
                                                            _intentarCalculoTrasOrigenListo();
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
                                    if (!_tieneDestinoParaCalculo() &&
                                        widget.tipoServicio != 'turismo') ...[
                                      _bannerAntesDeElegirDestino(
                                        destinoAccent: pRuta.destinoAccent,
                                        destinoFill: pRuta.destinoFill,
                                        textPrimary: textPrimary,
                                        textSecondary: textSecondary,
                                        mapFloating: mapFloating,
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
                                          mapFloating: mapFloating,
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
                                                    asistenteDireccionHabilitado:
                                                        true,
                                                    biasLat:
                                                        _origenMap?.latitude,
                                                    biasLon:
                                                        _origenMap?.longitude,
                                                    hint: uiRutaMockup
                                                        ? 'Dirección, barrio, hotel o lugar en RD…'
                                                        : '¿A dónde vas?',
                                                    fieldAccent: mapFloating
                                                        ? const Color(
                                                            0xFFD8B4FE)
                                                        : (uiRutaMockup &&
                                                                isDark
                                                            ? const Color(
                                                                0xFFD8B4FE)
                                                            : pRuta
                                                                .destinoAccent),
                                                    fieldFill: mapFloating
                                                        ? const Color(
                                                                0xFF111827)
                                                            .withValues(
                                                                alpha: 0.92)
                                                        : (isDark
                                                            ? (uiRutaMockup
                                                                ? const Color(
                                                                    0xFF1E0B36)
                                                                : const Color(
                                                                    0xFF1A0F2E))
                                                            : Colors.white),
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
                                                                      .hueGreen),
                                                          infoWindow:
                                                              const InfoWindow(
                                                                  title:
                                                                      'Destino · Llegada'),
                                                          zIndexInt: 6,
                                                        ),
                                                      );
                                                      _syncProgramarMapHalos();
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

                                                      _invalidarPrecioCalculado();
                                                      if (mounted) setState(() {});
                                                      _intentarCalculoTrasOrigenListo();
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
                                                      _intentarCalculoTrasOrigenListo();
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
                                          titulo: '¿A dónde quieres ir?',
                                          icono: Icons.explore,
                                          accent: pRuta.destinoAccent,
                                          fill: pRuta.destinoFill,
                                          tituloColor: textPrimary,
                                          mapFloating: mapFloating,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              CampoLugarAutocomplete(
                                                label: 'Buscar destino',
                                                asistenteDireccionHabilitado:
                                                    true,
                                                hint:
                                                    'Hotel, playa, aeropuerto o lugar en RD…',
                                                initialText:
                                                    _destinoTurismoSeleccionado
                                                            ?.nombre ??
                                                        (destinoTexto
                                                                .isNotEmpty
                                                            ? destinoTexto
                                                            : null),
                                                country: 'DO',
                                                biasLat: latCliente ??
                                                    _origenMap?.latitude,
                                                biasLon: lonCliente ??
                                                    _origenMap?.longitude,
                                                fieldAccent: mapFloating
                                                    ? const Color(0xFFD8B4FE)
                                                    : pRuta.destinoAccent,
                                                fieldFill: mapFloating
                                                    ? const Color(0xFF111827)
                                                        .withValues(alpha: 0.92)
                                                    : (isDark
                                                        ? const Color(
                                                            0xFF1A0F2E)
                                                        : Colors.white),
                                                onPlaceSelected: (det) async {
                                                  await _aplicarDestinoTurismoDesdeBusqueda(
                                                      det);
                                                },
                                                onTextChanged: (t) {
                                                  _markers.removeWhere((m) =>
                                                      m.markerId.value ==
                                                      'destino');
                                                  _polylines.clear();
                                                  setState(() {
                                                    destino = t;
                                                    _destinoDet = null;
                                                    _destinoTurismoSeleccionado =
                                                        null;
                                                    latDestino = null;
                                                    lonDestino = null;
                                                    if (t.trim().isEmpty) {
                                                      destinoTexto = '';
                                                    }
                                                    _invalidarCotizacion();
                                                  });
                                                },
                                              ),
                                              const SizedBox(height: 12),
                                              if (_destinoTurismoSeleccionado ==
                                                  null) ...[
                                                OutlinedButton.icon(
                                                  onPressed:
                                                      _mostrarSelectorDestinosTuristicos,
                                                  icon: Icon(
                                                    Icons.travel_explore_rounded,
                                                    color: pRuta.destinoAccent,
                                                  ),
                                                  label: const Text(
                                                    'Explorar catálogo turístico',
                                                  ),
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        pRuta.destinoAccent,
                                                    side: BorderSide(
                                                      color: pRuta.destinoAccent
                                                          .withValues(
                                                              alpha: 0.65),
                                                    ),
                                                    minimumSize: const Size(
                                                      double.infinity,
                                                      48,
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                    ),
                                                  ),
                                                ),
                                              ] else
                                                Container(
                                                  padding:
                                                      const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    // En flotante el padre
                                                    // (_seccionRutaCard) ya es
                                                    // oscuro: usamos blanco
                                                    // semitransparente para
                                                    // separarse sin tapar.
                                                    color: mapFloating
                                                        ? Colors.white
                                                            .withValues(
                                                                alpha: 0.10)
                                                        : (isDark
                                                            ? const Color(
                                                                0xFF0F172A)
                                                            : Colors.white),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    border: Border.all(
                                                      color: mapFloating
                                                          ? const Color(
                                                                  0xFFD8B4FE)
                                                              .withValues(
                                                                  alpha: 0.65)
                                                          : pRuta.destinoAccent
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
                                                              color: mapFloating
                                                                  ? const Color(
                                                                      0xFFD8B4FE)
                                                                  : pRuta
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
                                                            _intentarCalculoTrasOrigenListo();
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
                                    if (!widget.modoAhora &&
                                        tipoServicio == 'turismo' &&
                                        _destinoTurismoSeleccionado != null) ...[
                                      _bannerCompletarTurismoProgramado(
                                        textPrimary: textPrimary,
                                        textSecondary: textSecondary,
                                        mapFloating: mapFloating,
                                      ),
                                    ],
                                    if (!widget.modoAhora &&
                                        tipoServicio != 'turismo') ...[
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
                                        style: _botonEstilo(context,
                                            sheetStrongChrome: sheetStrongChrome),
                                      ),
                                      Text(
                                        'Programado para: ${DateFormat('dd/MM/yyyy - HH:mm').format(fechaHora)}',
                                        style: TextStyle(
                                          color: sheetStrongChrome
                                              ? const Color(0xFF065F46)
                                              : (isDark
                                                  ? Colors.greenAccent
                                                  : const Color(0xFF0F9D58)),
                                          fontWeight: FontWeight.w800,
                                          shadows: sheetStrongChrome
                                              ? <Shadow>[
                                                  Shadow(
                                                    offset: const Offset(0, 1),
                                                    blurRadius: 3.5,
                                                    color: Colors.white
                                                        .withValues(alpha: 0.95),
                                                  ),
                                                  Shadow(
                                                    offset: Offset.zero,
                                                    blurRadius: 14,
                                                    color: Colors.white
                                                        .withValues(alpha: 0.55),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    if (!widget.modoAhora &&
                                        tipoServicio == 'turismo' &&
                                        _destinoTurismoSeleccionado != null) ...[
                                      const ProgramarViajeFuturoAnimation(),
                                      _selectorFechaHoraProgramado(
                                        textPrimary: textPrimary,
                                        textSecondary: textSecondary,
                                        isDark: isDark,
                                        sheetStrongChrome: sheetStrongChrome,
                                        accent: pRuta.destinoAccent,
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
                                      mapFloating: mapFloating,
                                      strongChrome: sheetStrongChrome,
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
                                            activeThumbColor: Colors.white,
                                            activeTrackColor: switchAccent,
                                            // Thumb/track del estado OFF
                                            // calculados por contraste sobre
                                            // el fondo del cliente para que
                                            // el switch sea visible aunque
                                            // el fondo sea amarillo, blanco
                                            // o agua (donde el gris claro
                                            // del default desaparecía).
                                            inactiveThumbColor:
                                                CustomThemeService.textMutedOn(
                                                    chromeToneRef),
                                            inactiveTrackColor:
                                                CustomThemeService.borderOn(
                                                    chromeToneRef),
                                            onChanged: (v) {
                                              setState(() {
                                                idaYVuelta = v;
                                              });
                                              _intentarCalculoTrasOrigenListo();
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    if (tipoServicio != 'motor') ...[
                                      if (tipoServicio == 'normal')
                                        _Caja(
                                          mapFloating: mapFloating,
                                          strongChrome: sheetStrongChrome,
                                          child: OverflowSafeLabeledDropdown(
                                            leading: Icon(
                                              Icons
                                                  .directions_car_filled_outlined,
                                              color: textSecondary,
                                            ),
                                            label: 'Tipo de Vehículo',
                                            labelStyle: TextStyle(
                                              color: textSecondary,
                                              fontWeight: mapFloating
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                            dropdown: DropdownButton<String>(
                                              isExpanded: true,
                                              value: tipoVehiculo,
                                              dropdownColor: mapFloating
                                                  ? const Color(0xFF0F172A)
                                                  : CustomThemeService.cardOn(
                                                      chromeToneRef),
                                              underline: const SizedBox(),
                                              iconEnabledColor: textPrimary,
                                              style: TextStyle(
                                                color: textPrimary,
                                                fontSize: 16,
                                                fontWeight: mapFloating
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                              ),
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
                                                      child: Text(
                                                        e,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color: textPrimary,
                                                          fontWeight: mapFloating
                                                              ? FontWeight.w800
                                                              : FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: (v) {
                                                setState(() {
                                                  tipoVehiculo = v ?? 'Carro';
                                                });
                                                _intentarCalculoTrasOrigenListo();
                                              },
                                            ),
                                          ),
                                        ),
                                      if (tipoServicio == 'turismo')
                                        _buildTurismoVehiculoSelector(
                                          mapFloating: mapFloating,
                                          chromeToneRef: chromeToneRef,
                                          strongChrome: sheetStrongChrome,
                                        ),
                                      const SizedBox(height: 10),
                                    ],
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
                                            Builder(
                                              builder: (context) {
                                                final Color ctaFill =
                                                    sheetStrongChrome
                                                        ? Color.alphaBlend(
                                                            Colors.black
                                                                .withValues(
                                                                    alpha:
                                                                        0.26),
                                                            _colorServicio,
                                                          )
                                                        : _colorServicio;
                                                final Color ctaFg =
                                                    CustomThemeService.textOn(
                                                        ctaFill);
                                                return SizedBox(
                                                  width: double.infinity,
                                                  child: DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                      boxShadow:
                                                          sheetStrongChrome
                                                              ? <BoxShadow>[
                                                                  BoxShadow(
                                                                    color: Colors
                                                                        .black
                                                                        .withValues(
                                                                            alpha:
                                                                                0.58),
                                                                    blurRadius:
                                                                        30,
                                                                    spreadRadius:
                                                                        -1,
                                                                    offset:
                                                                        const Offset(
                                                                            0,
                                                                            12),
                                                                  ),
                                                                  BoxShadow(
                                                                    color: _colorServicio
                                                                        .withValues(
                                                                            alpha:
                                                                                0.50),
                                                                    blurRadius:
                                                                        24,
                                                                    spreadRadius:
                                                                        0.5,
                                                                    offset:
                                                                        const Offset(
                                                                            0,
                                                                            6),
                                                                  ),
                                                                ]
                                                              : const <BoxShadow>[],
                                                    ),
                                                    child: ElevatedButton(
                                                      onPressed: (ubicacionObtenida &&
                                                              precioCalculado >
                                                                  0 &&
                                                              !RaiOfflineCotizacionService
                                                                  .estaOffline)
                                                          ? () => _programarViaje(
                                                              ScaffoldMessenger
                                                                  .of(
                                                                      context),
                                                              Navigator.of(
                                                                  context))
                                                          : null,
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            ctaFill,
                                                        foregroundColor: ctaFg,
                                                        disabledBackgroundColor:
                                                            sheetStrongChrome
                                                                ? Colors.grey
                                                                    .withValues(
                                                                        alpha:
                                                                            0.42)
                                                                : null,
                                                        disabledForegroundColor:
                                                            sheetStrongChrome
                                                                ? Colors.white
                                                                    .withValues(
                                                                        alpha:
                                                                            0.65)
                                                                : null,
                                                        elevation:
                                                            sheetStrongChrome
                                                                ? 0
                                                                : 2,
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                    vertical:
                                                                        16),
                                                        shape:
                                                            RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      12),
                                                          side:
                                                              sheetStrongChrome
                                                                  ? BorderSide(
                                                                      color: Colors
                                                                          .white
                                                                          .withValues(alpha: 0.55),
                                                                      width: 1.4,
                                                                    )
                                                                  : BorderSide
                                                                      .none,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        widget.modoAhora
                                                            ? '✅ CONFIRMAR VIAJE'
                                                            : '✅ CONFIRMAR PROGRAMACIÓN',
                                                        style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          letterSpacing: 0.25,
                                                          shadows:
                                                              sheetStrongChrome
                                                                  ? _ctaLabelShadows(
                                                                      ctaFg)
                                                                  : null,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                            if (tipoServicio == 'turismo') ...[
                                              const SizedBox(height: 12),
                                              _botonVolverInicioProgramar(
                                                foreground: _colorServicio,
                                              ),
                                            ],
                                          ],
                                        ),
                                      )
                                    else if (_cargando)
                                      mapFloating
                                          ? Container(
                                              margin: const EdgeInsets
                                                  .symmetric(vertical: 8),
                                              padding: const EdgeInsets
                                                  .fromLTRB(18, 18, 18, 20),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF0F172A)
                                                    .withValues(alpha: 0.93),
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                                border: Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.55),
                                                  width: 1.6,
                                                ),
                                                boxShadow: <BoxShadow>[
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                            alpha: 0.32),
                                                    blurRadius: 18,
                                                    offset:
                                                        const Offset(0, 6),
                                                  ),
                                                ],
                                              ),
                                              child: Theme(
                                                data: Theme.of(context)
                                                    .copyWith(
                                                  colorScheme: Theme.of(
                                                          context)
                                                      .colorScheme
                                                      .copyWith(
                                                          onSurface:
                                                              Colors.white),
                                                ),
                                                child:
                                                    CotizacionPrecioLoadingStrip(
                                                  accentColor: const Color(
                                                      0xFF49F18B),
                                                  isDark: true,
                                                  message: (ubicacionObtenida &&
                                                          precioCalculado > 0)
                                                      ? 'Guardando viaje…'
                                                      : 'Calculando precio…',
                                                ),
                                              ),
                                            )
                                          : CotizacionPrecioLoadingPlaceholder(
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
                    ),
                  ],
                ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
            ),
          ),
        ],
      ),
    ),
    );
      },
    );
  }

  ButtonStyle _botonEstilo(BuildContext context,
      {required bool sheetStrongChrome}) {
    final bool isDark = ThemeData.estimateBrightnessForColor(
            Theme.of(context).scaffoldBackgroundColor) ==
        Brightness.dark;
    // Botón secundario "Seleccionar Fecha y Hora". En modo flotante el sheet
    // tiene cards oscuras sobre mapa claro: el botón se oscurece para igualar
    // el lenguaje visual y el borde es BLANCO semitransparente para destacar
    // tanto contra el botón oscuro como contra el mapa claro de fondo.
    final Color baseFill =
        isDark ? Colors.white : const Color(0xFF0F9D58);
    final Color fill = sheetStrongChrome
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.22), baseFill)
        : baseFill;
    final Color fg = sheetStrongChrome
        ? CustomThemeService.textOn(fill)
        : (isDark ? Colors.green : Colors.white);
    return ElevatedButton.styleFrom(
      backgroundColor: fill,
      foregroundColor: fg,
      minimumSize: const Size(double.infinity, 50),
      elevation: sheetStrongChrome ? 4 : 2,
      shadowColor: sheetStrongChrome
          ? Colors.black.withValues(alpha: 0.55)
          : null,
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: sheetStrongChrome
            ? BorderSide(
                color: Colors.white.withValues(alpha: 0.55),
                width: 1.4,
              )
            : BorderSide.none,
      ),
    );
  }
}

class _Caja extends StatelessWidget {
  final Widget child;
  final bool mapFloating;
  final bool strongChrome;

  const _Caja({
    required this.child,
    this.mapFloating = false,
    this.strongChrome = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color themedBg = Theme.of(context).scaffoldBackgroundColor;
    // En modo flotante el sheet no tiene fondo: pintamos un panel
    // GRIS MUY OSCURO (#0F172A 0.92) detrás de cada caja, con borde
    // BLANCO semitransparente (0.55) y sombra negra. El mapa de
    // Google Maps siempre es claro, así que cards oscuras = contraste
    // garantizado sin importar si la app está en claro u oscuro.
    final Color cardBg = mapFloating
        ? const Color(0xFF0F172A).withValues(alpha: 0.92)
        : CustomThemeService.cardOn(themedBg);
    final Color cardBorder = mapFloating
        ? Colors.white.withValues(alpha: 0.55)
        : strongChrome
            ? Color.alphaBlend(
                Colors.black.withValues(
                  alpha: ThemeData.estimateBrightnessForColor(themedBg) ==
                          Brightness.dark
                      ? 0.38
                      : 0.16,
                ),
                CustomThemeService.borderOn(themedBg),
              )
            : CustomThemeService.borderOn(themedBg);
    final double borderW =
        mapFloating ? 1.6 : (strongChrome ? 1.45 : 1.0);
    final List<BoxShadow>? floatingShadow = mapFloating
        ? <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ]
        : null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.fromBorderSide(
          BorderSide(color: cardBorder, width: borderW),
        ),
        boxShadow: floatingShadow,
      ),
      child: child,
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool mapFloating;

  const _Banner({
    required this.text,
    required this.icon,
    this.mapFloating = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color themedBg = Theme.of(context).scaffoldBackgroundColor;
    final Color cardBg = mapFloating
        ? const Color(0xFF0F172A).withValues(alpha: 0.92)
        : CustomThemeService.cardOn(themedBg);
    final Color textColor = mapFloating
        ? Colors.white
        : CustomThemeService.textOn(cardBg);
    final bool isDark = ThemeData.estimateBrightnessForColor(
            Theme.of(context).scaffoldBackgroundColor) ==
        Brightness.dark;
    final Color accent =
        isDark ? const Color(0xFF49F18B) : const Color(0xFF0F9D58);
    // En flotante usamos verde brillante para que el borde resalte sobre
    // la card oscura y al mismo tiempo sobre el mapa claro de Google.
    final Color borderAccent = mapFloating
        ? const Color(0xFF49F18B)
        : accent;
    final List<BoxShadow>? floatingShadow = mapFloating
        ? <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ]
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border.fromBorderSide(BorderSide(
            color: borderAccent.withValues(alpha: mapFloating ? 0.85 : 0.55),
            width: mapFloating ? 1.6 : 1.0)),
        boxShadow: floatingShadow,
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
