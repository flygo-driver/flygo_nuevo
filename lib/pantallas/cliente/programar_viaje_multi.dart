// lib/pantallas/cliente/programar_viaje_multi.dart
// ✅ CORREGIDO - CÁLCULO AUTOMÁTICO FUNCIONANDO

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flygo_nuevo/servicios/cliente_verificacion_identidad_service.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/utils/crear_viaje_errores.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/tarifa_service_unificado.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/utils/trip_publish_windows.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/location_permission_service.dart';
import 'package:flygo_nuevo/servicios/rai_offline_cotizacion_service.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_cliente_service.dart';
import 'package:flygo_nuevo/servicios/pool_timbre_session_guard.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/rai_map_presentation.dart';
import 'package:flygo_nuevo/utils/hora_am_pm.dart';
import 'package:flygo_nuevo/utils/navegacion_salida_app.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_cliente_banner.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_cliente_map_alert.dart';
import 'package:flygo_nuevo/widgets/boton_volver_inicio_sin_confirmar.dart';
import 'package:flygo_nuevo/widgets/cliente_viaje_orientacion_banner.dart';
import 'package:flygo_nuevo/widgets/cotizacion_precio_loading.dart';
import 'package:flygo_nuevo/widgets/promo_mxk_cliente_panel.dart';
import 'package:flygo_nuevo/widgets/overflow_safe_labeled_dropdown.dart';
import 'package:flygo_nuevo/widgets/parpadeo_ruta_programar.dart';
import 'package:flygo_nuevo/servicios/cliente_metodo_pago_preferido_service.dart';
import 'package:flygo_nuevo/widgets/cliente_metodo_pago_solicitud_tiles.dart';
import 'package:flygo_nuevo/widgets/campo_lugar_autocomplete.dart';
import 'package:flygo_nuevo/widgets/programar_viaje_hoja_moderna.dart';
import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/servicios/negocio_aliado_promo_service.dart';
import 'package:flygo_nuevo/widgets/cliente_negocio_aliado_cotizacion_banner.dart';
import 'package:flygo_nuevo/utils/multiparada_ruta_helper.dart';

class _LugarSel {
  final String label;
  final double lat;
  final double lon;
  const _LugarSel({required this.label, required this.lat, required this.lon});
}

/// Solo UI: colores por tipo de punto en la ruta (claro / oscuro).
class _EstiloRutaCampo {
  final Color acento;
  final Color fondo;
  final Color borde;
  final IconData icono;
  const _EstiloRutaCampo({
    required this.acento,
    required this.fondo,
    required this.borde,
    required this.icono,
  });
}

/// Variante visual de los campos de ruta (mockup: origen con glow, paradas finas, destino morado sólido).
enum _RutaCampoVisual { origen, parada, destino }

/// Campo activo para elegir punto con el mapa de fondo (sin pantalla aparte).
enum _CampoRutaMapa { ninguno, origen, parada, destino }

class ProgramarViajeMulti extends StatefulWidget {
  const ProgramarViajeMulti({super.key});

  /// Multiparada: solo servicio normal en pool de vehículos.
  static String normalizarTipoServicioMulti(String raw) => 'normal';

  /// Siempre pool general (sin turismo ADM ni motor).
  static String canalAsignacionParaMulti(String tipoNorm) => 'pool';

  @override
  State<ProgramarViajeMulti> createState() => _ProgramarViajeMultiState();
}

class _ProgramarViajeMultiState extends State<ProgramarViajeMulti> {
  static const int _kMaxParadasIntermedias = 5;
  /// Etiqueta interna del origen GPS; no se muestra en el campo de texto (evita confusión al escribir).
  static const String _kLabelOrigenGpsActual = 'Mi ubicación actual';

  _LugarSel? _origen;
  _LugarSel? _destino;
  final List<_LugarSel?> _paradas = <_LugarSel?>[null];
  DateTime _fechaHora = DateTime.now().add(const Duration(minutes: 30));
  bool _esAhora = true;

  String _tipoVehiculo = 'Carro';
  bool _cargando = false;
  String _mensajeCarga = '';

  double _distKm = 0;
  double _precio = 0;
  double _peaje = 0;
  List<Map<String, dynamic>> _segmentos = [];
  DirectionsResult? _directionsRutaMulti;

  GoogleMapController? _map;
  final Set<Marker> _mapMarkers = <Marker>{};
  final Set<Polyline> _mapPolylines = <Polyline>{};
  LatLng? _mapCentro;

  // 🔥 CACHÉ para el contador de viajes
  int? _contadorViajesCache;
  DateTime? _contadorTimestamp;
  Map<String, dynamic>? _promoSnapshotCotizacion;
  Map<String, dynamic>? _cotizacionDesglose;
  bool _promoOmitidaPorLargaDistancia = false;
  NegocioAliadoPromoEval? _negocioPromoEval;

  // Timer para debounce del cálculo automático
  Timer? _calculoDebounce;

  final DraggableScrollableController _sheetCtrl =
      DraggableScrollableController();

  static const double _sheetMinFracMulti = 0.28;

  int _mapProgrammaticCameraDepth = 0;
  Timer? _multiMapGestureEndDebounce;
  bool _resolviendoDestinoMapa = false;
  int _destinoMapaSeq = 0;
  _CampoRutaMapa _campoMapaActivo = _CampoRutaMapa.ninguno;
  int? _paradaMapaActiva;

  /// Evita que un cálculo en curso bloquee el siguiente (varios tramos tardan más que el debounce).
  int _calculoSeq = 0;

  /// Resumen compacto tras cotizar.
  bool _vistaResumenCotizada = false;
  String _metodoPagoCategoria = 'efectivo';
  bool _metodoPagoElegidoPorCliente = false;

  Color get _colorServicio => Colors.greenAccent;

  void _scrollAlResumenCotizado() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_expandMultiSheetTrasCotizar());
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(RaiUbicacionClienteService.instance.ensureStarted());
    RaiUbicacionClienteService.instance.modo
        .addListener(_onModoUbicacionCliente);
    unawaited(_precargarOrigenGpsSiListo());
    unawaited(_cargarMetodoPagoPreferido());
  }

  EdgeInsets _multiMapPadding(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final double h = mq.size.height;
    // Padding fijo según fase (no escuchar cada frame del sheet → evita
    // reconstruir GoogleMap al tocar/arrastrar el mapa).
    final double sheetFrac = _mostrarResumenMulti ? 0.56 : 0.38;
    return EdgeInsets.only(
      top: mq.padding.top + 8,
      bottom: h * sheetFrac + 12,
      left: 40,
      right: 40,
    );
  }

  Future<void> _expandMultiSheetTrasCotizar() async {
    if (!_sheetCtrl.isAttached) return;
    try {
      await _sheetCtrl.animateTo(
        0.56,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  void _onMultiMapCameraIdle() {
    if (_mapProgrammaticCameraDepth > 0) {
      _mapProgrammaticCameraDepth--;
      return;
    }
    _multiMapGestureEndDebounce?.cancel();
    if (mounted) _expandMultiSheetTrasMapaInteract();
  }

  void _expandMultiSheetTrasMapaInteract() {
    if (!_sheetCtrl.isAttached) return;
    final double target = _mostrarResumenMulti ? 0.56 : 0.42;
    try {
      _sheetCtrl.animateTo(
        target.clamp(_sheetMinFracMulti, 0.75),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  void _onMultiMapUserGesture() {
    if (_mapProgrammaticCameraDepth > 0) return;
    unawaited(_collapseMultiSheetForMap());
  }

  Future<void> _collapseMultiSheetForMap() async {
    if (!_sheetCtrl.isAttached) return;
    try {
      final double s = _sheetCtrl.size;
      if (s <= _sheetMinFracMulti + 0.03) return;
      await _sheetCtrl.animateTo(
        _sheetMinFracMulti,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  Future<void> _multiMapAnimate(
    Future<void> Function(GoogleMapController c) op,
  ) async {
    final GoogleMapController? c = _map;
    if (c == null) return;
    _mapProgrammaticCameraDepth++;
    try {
      await op(c).timeout(const Duration(seconds: 2));
    } catch (_) {
      if (_mapProgrammaticCameraDepth > 0) _mapProgrammaticCameraDepth--;
    }
  }

  bool _puedeElegirDestinoEnMapa() => true;

  void _activarCampoEnMapa(
    _CampoRutaMapa campo, {
    int? paradaIndex,
  }) {
    setState(() {
      _campoMapaActivo = campo;
      _paradaMapaActiva = paradaIndex;
    });
  }

  void _onCampoRutaEnfocado(
    _CampoRutaMapa campo, {
    int? paradaIndex,
  }) {
    _activarCampoEnMapa(campo, paradaIndex: paradaIndex);
    unawaited(_expandMultiSheetParaEscribir());
  }

  Future<void> _expandMultiSheetParaEscribir() async {
    if (!_sheetCtrl.isAttached) return;
    try {
      await _sheetCtrl.animateTo(
        0.75.clamp(_sheetMinFracMulti, 0.88),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }

  /// Sin campo activo: origen → paradas en uso → destino final.
  ({_CampoRutaMapa campo, int? paradaIndex}) _campoMapaParaTapLibre() {
    if (_origen == null) {
      return (campo: _CampoRutaMapa.origen, paradaIndex: null);
    }
    final bool usaParadasIntermedias = _paradas.length > 1 ||
        _paradas.whereType<_LugarSel>().isNotEmpty;
    if (usaParadasIntermedias) {
      for (int i = 0; i < _paradas.length; i++) {
        if (_paradas[i] == null) {
          return (campo: _CampoRutaMapa.parada, paradaIndex: i);
        }
      }
    }
    return (campo: _CampoRutaMapa.destino, paradaIndex: null);
  }

  void _invalidarCotizacionMulti({bool limpiarRutaMapa = true}) {
    _vistaResumenCotizada = false;
    _precio = 0;
    _distKm = 0;
    _peaje = 0;
    _segmentos = <Map<String, dynamic>>[];
    if (limpiarRutaMapa) {
      _directionsRutaMulti = null;
    }
    _cotizacionDesglose = null;
    _promoSnapshotCotizacion = null;
  }

  void _aplicarDetalleEnCampo(
    DetalleLugar det, {
    required _CampoRutaMapa campo,
    int? paradaIndex,
    required String fallbackLabel,
  }) {
    final _LugarSel lugar = _lugarNormalizado(
      _LugarSel(
        label: MultiparadaRutaHelper.normalizarLabel(
          det.displayLabel,
          fallbackLabel,
        ),
        lat: det.lat,
        lon: det.lon,
      ),
      fallbackLabel: fallbackLabel,
    );
    setState(() {
      switch (campo) {
        case _CampoRutaMapa.origen:
          _origen = lugar;
          break;
        case _CampoRutaMapa.destino:
          _destino = lugar;
          break;
        case _CampoRutaMapa.parada:
          if (paradaIndex != null && paradaIndex >= 0 &&
              paradaIndex < _paradas.length) {
            _paradas[paradaIndex] = lugar;
          }
          break;
        case _CampoRutaMapa.ninguno:
          break;
      }
      _campoMapaActivo = _CampoRutaMapa.ninguno;
      _paradaMapaActiva = null;
      _actualizarMapaMultiparada();
      if (campo != _CampoRutaMapa.destino) {
        _invalidarCotizacionMulti();
      }
    });
    if (campo == _CampoRutaMapa.destino && _paradasIntermediasCoherentes()) {
      _programarCalculoAutomatico();
    }
  }

  Widget _campoLugarIntegrado({
    required String label,
    required String hint,
    String? value,
    required bool esOrigen,
    required _CampoRutaMapa campoMapa,
    int? paradaIndex,
    required String fallbackLabel,
    _EstiloRutaCampo? estilo,
    _RutaCampoVisual visual = _RutaCampoVisual.parada,
    bool legacyRutaCampos = false,
    bool mockupLayoutCampo = false,
  }) {
    final bool activo = _campoMapaActivo == campoMapa &&
        (campoMapa != _CampoRutaMapa.parada ||
            _paradaMapaActiva == paradaIndex);

    return DecoratedBox(
      decoration: activo
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: estilo?.acento ?? _colorServicio,
                width: 2.2,
              ),
            )
          : const BoxDecoration(),
      child: Padding(
        padding: activo ? const EdgeInsets.all(2) : EdgeInsets.zero,
        child: CampoLugarAutocomplete(
          key: esOrigen
              ? ValueKey<String>(
                  'multi_orig_${_origen?.lat}_${_origen?.lon}_${_origen?.label}',
                )
              : campoMapa == _CampoRutaMapa.destino
                  ? ValueKey<String>(
                      'multi_dest_${_destino?.lat}_${_destino?.lon}_${_destino?.label}',
                    )
                  : ValueKey<String>(
                      'multi_parada_${paradaIndex ?? -1}_${value ?? ''}',
                    ),
          label: label,
          hint: hint,
          initialText: esOrigen ? _textoVisibleCampoOrigen(value) : value,
          mapaIntegradoEnPantalla: true,
          esCampoOrigen: esOrigen,
          asistenteDireccionHabilitado: true,
          biasLat: _origen?.lat ?? _mapCentro?.latitude,
          biasLon: _origen?.lon ?? _mapCentro?.longitude,
          fieldAccent: estilo?.acento,
          fieldFill: estilo?.fondo,
          onCampoEnfocado: () =>
              _onCampoRutaEnfocado(campoMapa, paradaIndex: paradaIndex),
          onPlaceSelected: (DetalleLugar det) {
            _aplicarDetalleEnCampo(
              det,
              campo: campoMapa,
              paradaIndex: paradaIndex,
              fallbackLabel: fallbackLabel,
            );
          },
        ),
      ),
    );
  }

  String? get _mensajeSeleccionMapaActiva {
    switch (_campoMapaActivo) {
      case _CampoRutaMapa.origen:
        return 'Tocá el mapa para marcar el punto de partida';
      case _CampoRutaMapa.destino:
        return 'Tocá el mapa para marcar el destino final';
      case _CampoRutaMapa.parada:
        final int i = (_paradaMapaActiva ?? 0) + 1;
        return 'Tocá el mapa para marcar la parada $i';
      case _CampoRutaMapa.ninguno:
        return null;
    }
  }

  /// Tocá o mantené pulsado el mapa → punto en el campo activo (o el siguiente vacío).
  Future<void> _aplicarPuntoDesdeMapa(LatLng p) async {
    if (!_puedeElegirDestinoEnMapa()) return;

    unawaited(_collapseMultiSheetForMap());

    _CampoRutaMapa campo = _campoMapaActivo;
    int? paradaIndex = _paradaMapaActiva;
    if (campo == _CampoRutaMapa.ninguno) {
      final ({_CampoRutaMapa campo, int? paradaIndex}) libre =
          _campoMapaParaTapLibre();
      campo = libre.campo;
      paradaIndex = libre.paradaIndex;
      if (mounted) {
        setState(() {
          _campoMapaActivo = campo;
          _paradaMapaActiva = paradaIndex;
        });
      }
    }

    String fallbackLabel;
    switch (campo) {
      case _CampoRutaMapa.origen:
        fallbackLabel = 'Origen';
        break;
      case _CampoRutaMapa.parada:
        fallbackLabel = 'Parada ${(paradaIndex ?? 0) + 1}';
        break;
      case _CampoRutaMapa.destino:
      case _CampoRutaMapa.ninguno:
        fallbackLabel = 'Destino final';
        campo = _CampoRutaMapa.destino;
        break;
    }

    if (campo == _CampoRutaMapa.parada &&
        (paradaIndex == null ||
            paradaIndex < 0 ||
            paradaIndex >= _paradas.length)) {
      return;
    }

    if (campo != _CampoRutaMapa.origen && _origen == null) return;

    final int seq = ++_destinoMapaSeq;

    if (mounted) {
      setState(() {
        _resolviendoDestinoMapa = true;
        if (campo == _CampoRutaMapa.destino) {
          _invalidarCotizacionMulti();
        }
        _actualizarMapaMultiparada();
      });
    }

    final det = await LugaresService.instance.detalleDesdeCoordenadas(
      p.latitude,
      p.longitude,
    );

    if (!mounted || seq != _destinoMapaSeq) return;

    final resolved = det ??
        DetalleLugar(
          placeId:
              'map_tap:${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}',
          name: 'Punto elegido en el mapa',
          address:
              '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
          lat: p.latitude,
          lon: p.longitude,
        );

    await LugaresService.instance.guardarReciente(
      DetalleLugar(
        placeId: resolved.placeId,
        name: resolved.name,
        address: resolved.address,
        lat: p.latitude,
        lon: p.longitude,
      ),
    );

    if (!mounted || seq != _destinoMapaSeq) return;

    _aplicarDetalleEnCampo(
      DetalleLugar(
        placeId: resolved.placeId,
        name: resolved.name,
        address: resolved.address,
        lat: p.latitude,
        lon: p.longitude,
      ),
      campo: campo,
      paradaIndex: paradaIndex,
      fallbackLabel: fallbackLabel,
    );

    if (!mounted || seq != _destinoMapaSeq) return;

    setState(() => _resolviendoDestinoMapa = false);
    _expandMultiSheetTrasMapaInteract();
  }

  void _onLongPressMapMulti(LatLng p) {
    unawaited(_aplicarPuntoDesdeMapa(p));
  }

  Future<void> _cargarMetodoPagoPreferido() async {
    final String cat =
        await ClienteMetodoPagoPreferidoService.cargarCategoria();
    // Si el cliente ya eligió mientras leíamos prefs, su toque manda.
    if (!mounted || _metodoPagoElegidoPorCliente) return;
    setState(() => _metodoPagoCategoria = cat);
  }

  void _onMetodoPagoCategoriaChanged(String cat) {
    setState(() {
      _metodoPagoElegidoPorCliente = true;
      _metodoPagoCategoria = cat;
    });
    unawaited(ClienteMetodoPagoPreferidoService.guardarCategoria(cat));
  }

  String get _metodoPagoEtiquetaDocumento =>
      ClienteMetodoPagoPreferidoService.etiquetaDocumentoDesdeCategoria(
        _metodoPagoCategoria,
      );

  void _onModoUbicacionCliente() {
    if (!mounted) return;
    if (RaiUbicacionClienteService.instance.modo.value !=
        RaiUbicacionClienteModo.listo) {
      return;
    }
    unawaited(_precargarOrigenGpsSiListo());
  }

  /// Origen desde GPS: cel / laptop / PC / tablet (producción).
  Future<void> _precargarOrigenGpsSiListo() async {
    if (_origen != null) return;
    final pos = await LocationPermissionService.posicionParaCotizarProduccion(
      pedirPermisoSiFalta: false,
    );
    if (pos == null) {
      unawaited(RaiUbicacionClienteService.instance.refrescar());
      return;
    }
    try {
      if (!mounted) return;
      setState(() {
        _origen = _LugarSel(
          label: _kLabelOrigenGpsActual,
          lat: pos.latitude,
          lon: pos.longitude,
        );
        _actualizarMapaMultiparada();
      });
      _programarCalculoAutomatico();
      unawaited(RaiUbicacionClienteService.instance.refrescar());
    } catch (_) {
      unawaited(RaiUbicacionClienteService.instance.refrescar());
    }
  }

  bool get _necesitaAlertaUbicacionMulti =>
      _origen == null && _destino != null;

  @override
  void dispose() {
    _sheetCtrl.dispose();
    RaiUbicacionClienteService.instance.modo
        .removeListener(_onModoUbicacionCliente);
    _calculoDebounce?.cancel();
    _multiMapGestureEndDebounce?.cancel();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

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

      // El MxK se evalúa para el próximo viaje a crear.
      final int contador = (snapshot.count ?? 0) + 1;
      _contadorViajesCache = contador;
      _contadorTimestamp = DateTime.now();

      return contador;
    } catch (e) {
      return 1;
    }
  }

  bool _precioCotizadoValidoParaValor(double precio) =>
      precio > 0 ||
      (_negocioPromoEval?.esViajeGratis == true && precio >= 0);

  Future<double> _aplicarPromoNegocioAliado(double precioNominal) async {
    _negocioPromoEval = null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || precioNominal <= 0) return precioNominal;
    try {
      final snap = await fs.FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .get();
      final eval = await NegocioAliadoPromoService.evaluarConUbicacion(
        usuario: snap.data(),
        precioNominalRd: precioNominal,
        origen: _origen?.label ?? '',
        destino: _destino?.label ?? '',
        latOrigen: _origen?.lat,
        lonOrigen: _origen?.lon,
        latDestino: _destino?.lat,
        lonDestino: _destino?.lon,
      );
      if (eval != null) {
        _negocioPromoEval = eval;
        return eval.precioClienteRd;
      }
    } catch (e) {
      debugPrint('Promo negocio aliado multi: $e');
    }
    return precioNominal;
  }

  void _actualizarMapaMultiparada() {
    final List<_LugarSel> puntos = <_LugarSel>[
      if (_origen != null) _origen!,
      ..._paradas.whereType<_LugarSel>(),
      if (_destino != null) _destino!,
    ];
    _mapMarkers.clear();
    _mapPolylines.clear();
    if (puntos.isEmpty) {
      _mapCentro = null;
      return;
    }

    for (int i = 0; i < puntos.length; i++) {
      final _LugarSel p = puntos[i];
      final bool esPrimero = i == 0;
      final bool esUltimo = i == puntos.length - 1;
      _mapMarkers.add(
        Marker(
          markerId: MarkerId('mp_$i'),
          position: LatLng(p.lat, p.lon),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            esPrimero
                ? BitmapDescriptor.hueOrange
                : (esUltimo
                    ? BitmapDescriptor.hueGreen
                    : BitmapDescriptor.hueAzure),
          ),
          infoWindow: InfoWindow(
            title: esPrimero
                ? 'Origen'
                : (esUltimo ? 'Destino' : 'Parada $i'),
            snippet: p.label,
          ),
        ),
      );
    }

    final List<LatLng>? path = _directionsRutaMulti?.path;
    if (path != null && path.length >= 2) {
      _mapPolylines.add(
        Polyline(
          polylineId: const PolylineId('ruta_multi'),
          points: path,
          width: 5,
          color: const Color(0xFF49F18B),
          geodesic: true,
        ),
      );
    } else if (puntos.length >= 2) {
      _mapPolylines.add(
        Polyline(
          polylineId: const PolylineId('ruta_multi'),
          points: puntos.map((p) => LatLng(p.lat, p.lon)).toList(),
          width: 4,
          color: const Color(0xFF49F18B),
          geodesic: true,
        ),
      );
    }

    _mapCentro = LatLng(puntos.first.lat, puntos.first.lon);
  }

  Future<void> _ajustarCamaraMapaMultiparada() async {
    if (_map == null) return;
    await _multiMapAnimate((GoogleMapController map) async {
      final List<_LugarSel> puntos = <_LugarSel>[
        if (_origen != null) _origen!,
        ..._paradas.whereType<_LugarSel>(),
        if (_destino != null) _destino!,
      ];
      if (puntos.isEmpty) return;
      if (puntos.length == 1) {
        await map.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(puntos.first.lat, puntos.first.lon),
            14,
          ),
        );
        return;
      }
      double minLat = puntos.first.lat;
      double maxLat = minLat;
      double minLon = puntos.first.lon;
      double maxLon = minLon;
      for (final _LugarSel p in puntos.skip(1)) {
        if (p.lat < minLat) minLat = p.lat;
        if (p.lat > maxLat) maxLat = p.lat;
        if (p.lon < minLon) minLon = p.lon;
        if (p.lon > maxLon) maxLon = p.lon;
      }
      await RaiMapPresentation.fitBounds(
        map,
        LatLngBounds(
          southwest: LatLng(minLat, minLon),
          northeast: LatLng(maxLat, maxLon),
        ),
        padding: 56,
      );
    });
  }

  Future<Map<String, double>> _calcularTramoReal(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
    String tramoNombre,
  ) async {
    if (mounted) {
      setState(() {
        _mensajeCarga = 'Calculando ruta: $tramoNombre...';
      });
    }

    try {
      var dir = await DirectionsService.drivingDistanceKm(
        originLat: lat1,
        originLon: lon1,
        destLat: lat2,
        destLon: lon2,
        withTraffic: true,
        region: 'do',
      );

      if (dir == null || dir.km <= 0) {
        dir = await DirectionsService.drivingDistanceKm(
          originLat: lat1,
          originLon: lon1,
          destLat: lat2,
          destLon: lon2,
          withTraffic: false,
          region: 'do',
        );
      }

      double km;
      if (dir != null && dir.km > 0) {
        km = dir.km;
      } else {
        km = DistanciaService.calcularDistancia(lat1, lon1, lat2, lon2);
        if (km > 0) {
          km = (km * 1.15).clamp(0.01, 500.0);
        } else {
          km = 0.05;
        }
      }

      if (km <= 0 || km > 4000) {
        if (mounted) {
          _snack('No se pudo calcular un tramo de la ruta.');
        }
        return <String, double>{'km': 0, 'peaje': 0};
      }

      final double peajeTramo = _estimarPeaje(km, lat1, lon1, lat2, lon2);

      return <String, double>{
        'km': km,
        'peaje': peajeTramo,
      };
    } catch (e) {
      double kmFb = DistanciaService.calcularDistancia(lat1, lon1, lat2, lon2);
      if (kmFb > 0) {
        kmFb = (kmFb * 1.15).clamp(0.05, 500.0);
      } else {
        kmFb = 0.05;
      }
      if (kmFb > 0 && kmFb <= 4000) {
        final double peajeTramo = _estimarPeaje(kmFb, lat1, lon1, lat2, lon2);
        return <String, double>{'km': kmFb, 'peaje': peajeTramo};
      }
      if (mounted) {
        _snack(
            'No se pudo calcular la ruta. Revisa conexión o la API de mapas.');
      }
      return <String, double>{'km': 0, 'peaje': 0};
    }
  }

  /// Peaje solo si la ruta es claramente interurbana (no inventar peaje en ciudad).
  /// Antes: radio 50 km a casetas → casi todo SD pagaba peaje falso.
  double _estimarPeaje(
      double km, double lat1, double lon1, double lat2, double lon2) {
    // Viaje urbano / multiparada corta: sin peaje automático (igual que viaje simple).
    if (km < 55) return 0;
    final double salto = DistanciaService.calcularDistancia(lat1, lon1, lat2, lon2);
    if (salto < 40) return 0;

    const Map<String, Map<String, double>> peajesRD = {
      'las americas': {'lat': 18.45, 'lon': -69.75, 'costo': 150},
      'duarte': {'lat': 19.0, 'lon': -70.5, 'costo': 200},
      'boca chica': {'lat': 18.45, 'lon': -69.63, 'costo': 100},
    };

    double totalPeaje = 0;
    for (final peaje in peajesRD.values) {
      // El corredor debe pasar cerca del peaje (origen O destino), no "estar en la ciudad".
      final double d1 = DistanciaService.calcularDistancia(
        lat1, lon1, peaje['lat']!, peaje['lon']!,
      );
      final double d2 = DistanciaService.calcularDistancia(
        lat2, lon2, peaje['lat']!, peaje['lon']!,
      );
      if (d1 < 12 || d2 < 12) {
        totalPeaje += peaje['costo']!;
      }
    }
    return totalPeaje;
  }

  /// Diámetro máximo entre todos los puntos de la ruta (km en línea recta).
  double _diametroRutaKm(List<_LugarSel> puntos) {
    if (puntos.length < 2) return 0;
    double maxD = 0;
    for (int i = 0; i < puntos.length; i++) {
      for (int j = i + 1; j < puntos.length; j++) {
        final double d = DistanciaService.calcularDistancia(
          puntos[i].lat,
          puntos[i].lon,
          puntos[j].lat,
          puntos[j].lon,
        );
        if (d > maxD) maxD = d;
      }
    }
    return maxD;
  }

  /// Suma haversine origen→paradas→destino (km).
  double _sumaHaversineRutaKm(List<_LugarSel> puntos) {
    if (puntos.length < 2) return 0;
    double sum = 0;
    for (int i = 0; i < puntos.length - 1; i++) {
      sum += DistanciaService.calcularDistancia(
        puntos[i].lat,
        puntos[i].lon,
        puntos[i + 1].lat,
        puntos[i + 1].lon,
      );
    }
    return sum;
  }

  /// Si Directions devolvió km absurdos para una ruta compacta en ciudad, usa
  /// estimación urbana coherente (haversine × factor calle).
  double _normalizarKmMultiparadaUrbana({
    required double totalKm,
    required List<_LugarSel> puntos,
    required List<Map<String, dynamic>> segmentos,
  }) {
    final double diametro = _diametroRutaKm(puntos);
    final double hv = _sumaHaversineRutaKm(puntos);
    final bool compacta = diametro > 0 && diametro <= 45;
    if (!compacta) return totalKm;

    final double techoUrbano = math.max(hv * 2.0, diametro * 2.8).clamp(5.0, 90.0);
    if (totalKm <= techoUrbano && totalKm > 0) return totalKm;

    final double kmUrbano = (hv * 1.28).clamp(1.0, techoUrbano);
    if (segmentos.isNotEmpty && hv > 0) {
      double acc = 0;
      for (int i = 0; i < segmentos.length; i++) {
        final _LugarSel a = puntos[i];
        final _LugarSel b = puntos[i + 1];
        final double h = DistanciaService.calcularDistancia(
          a.lat, a.lon, b.lat, b.lon,
        );
        final double share = (h / hv) * kmUrbano;
        segmentos[i] = <String, dynamic>{
          ...segmentos[i],
          'km': double.parse(share.toStringAsFixed(2)),
        };
        acc += share;
      }
      return double.parse(acc.toStringAsFixed(2));
    }
    return double.parse(kmUrbano.toStringAsFixed(2));
  }

  /// Sin huecos: no puede haber parada vacía entre dos paradas llenas.
  bool _paradasIntermediasCoherentes() {
    bool vistoVacio = false;
    for (final _LugarSel? p in _paradas) {
      if (p == null) {
        vistoVacio = true;
      } else if (vistoVacio) {
        return false;
      }
    }
    return true;
  }

  _LugarSel _lugarNormalizado(_LugarSel raw, {required String fallbackLabel}) {
    return _LugarSel(
      label: MultiparadaRutaHelper.normalizarLabel(raw.label, fallbackLabel),
      lat: MultiparadaRutaHelper.round6(raw.lat),
      lon: MultiparadaRutaHelper.round6(raw.lon),
    );
  }

  List<_LugarSel> _paradasIntermediasOrdenadas() =>
      _paradas.whereType<_LugarSel>().toList();

  void _compactarParadasVaciasAlFinal() {
    while (_paradas.length > 1 && _paradas.last == null) {
      _paradas.removeLast();
    }
    if (_paradas.isEmpty) {
      _paradas.add(null);
    }
  }

  String? _validarRutaMultiParaGuardar() {
    if (_origen == null || _destino == null) {
      return 'Completá origen y destino.';
    }
    if (!_paradasIntermediasCoherentes()) {
      return 'Completa las paradas en orden o quita las filas vacías.';
    }
    final List<({double lat, double lon, String label})> paradas =
        _paradasIntermediasOrdenadas()
            .map(
              (_LugarSel p) => (
                lat: p.lat,
                lon: p.lon,
                label: p.label,
              ),
            )
            .toList();
    return MultiparadaRutaHelper.validarSecuenciaRuta(
      latOrigen: _origen!.lat,
      lonOrigen: _origen!.lon,
      labelOrigen: _origen!.label,
      latDestino: _destino!.lat,
      lonDestino: _destino!.lon,
      labelDestino: _destino!.label,
      paradas: paradas,
    );
  }

  double _distanciaKmDesdeSegmentos(List<Map<String, dynamic>> segmentos) {
    if (segmentos.isEmpty) return _distKm;
    double sum = 0;
    for (final Map<String, dynamic> s in segmentos) {
      final dynamic km = s['km'];
      if (km is num && km > 0) sum += km.toDouble();
    }
    if (sum <= 0) return _distKm;
    return double.parse(sum.toStringAsFixed(2));
  }

  double _peajeDesdeSegmentos(List<Map<String, dynamic>> segmentos) {
    if (segmentos.isEmpty) return _peaje;
    double sum = 0;
    for (final Map<String, dynamic> s in segmentos) {
      final dynamic p = s['peaje'];
      if (p is num && p > 0) sum += p.toDouble();
    }
    return sum > 0 ? sum : _peaje;
  }

  /// Peaje RD una sola vez por ruta (misma regla que viaje simple; evita duplicar por tramo).
  void _normalizarPeajeMultiparada(
    List<Map<String, dynamic>> segmentos,
    double totalKm,
  ) {
    if (segmentos.isEmpty || _origen == null || _destino == null) return;
    final double peajeUnico = _estimarPeaje(
      totalKm,
      _origen!.lat,
      _origen!.lon,
      _destino!.lat,
      _destino!.lon,
    );
    for (int i = 0; i < segmentos.length; i++) {
      segmentos[i] = <String, dynamic>{
        ...segmentos[i],
        'peaje': i == 0 ? peajeUnico : 0.0,
      };
    }
  }

  // Cotización solo cuando hay origen, destino y paradas coherentes.
  void _programarCalculoAutomatico() {
    if (_origen == null || _destino == null) {
      return;
    }
    if (!_paradasIntermediasCoherentes()) {
      return;
    }

    _calculoDebounce?.cancel();
    _calculoSeq++;
    final int runId = _calculoSeq;
    _calculoDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _calcularConRutasReales(automatico: true, runId: runId);
      }
    });
  }

  void _finCargaMultiSiCorre(int runId) {
    if (!mounted || runId != _calculoSeq) return;
    setState(() {
      _cargando = false;
      _mensajeCarga = '';
    });
  }

  static const double _kMetrosRecotizarAlConfirmar = 120;

  bool get _origenEsGpsActual =>
      _origen?.label.trim() == _kLabelOrigenGpsActual;

  String? _textoVisibleCampoOrigen(String? label) {
    final String t = (label ?? '').trim();
    if (t.isEmpty || t == _kLabelOrigenGpsActual) return null;
    return label;
  }

  String _etiquetaOrigenResumen() {
    if (_origen == null) return '';
    if (_origenEsGpsActual) return 'Tu ubicación GPS';
    return _origen!.label;
  }

  Future<_LugarSel> _origenListoParaGuardar(_LugarSel raw) async {
    final _LugarSel base = _lugarNormalizado(raw, fallbackLabel: 'Origen');
    final bool esGps = base.label.trim() == _kLabelOrigenGpsActual;
    if (!esGps) {
      return base;
    }
    try {
      final DetalleLugar? det =
          await LugaresService.instance.detalleDesdeCoordenadas(
        base.lat,
        base.lon,
      );
      if (det != null) {
        return _lugarNormalizado(
          _LugarSel(
            label: MultiparadaRutaHelper.normalizarLabel(
              det.displayLabel,
              'Origen',
            ),
            lat: det.lat,
            lon: det.lon,
          ),
          fallbackLabel: 'Origen',
        );
      }
    } catch (_) {}
    return _lugarNormalizado(
      _LugarSel(
        label: 'Tu ubicación GPS',
        lat: base.lat,
        lon: base.lon,
      ),
      fallbackLabel: 'Origen',
    );
  }

  /// Origen, paradas, destino, waypoints y segmentos alineados para Firestore.
  Future<
      ({
        _LugarSel origen,
        _LugarSel destino,
        List<Map<String, dynamic>> waypoints,
        List<Map<String, dynamic>> rutaPuntos,
        List<Map<String, dynamic>> segmentos,
        double distKm,
        double peaje,
      })?> _prepararDatosRutaMultiparadaGuardar() async {
    _compactarParadasVaciasAlFinal();

    final _LugarSel origenGuardar = await _origenListoParaGuardar(_origen!);
    final _LugarSel destinoGuardar = _lugarNormalizado(
      _destino!,
      fallbackLabel: 'Destino final',
    );

    final List<_LugarSel> paradasOrdenadas = _paradasIntermediasOrdenadas();
    final List<Map<String, dynamic>> waypointsRaw = <Map<String, dynamic>>[];
    for (int i = 0; i < paradasOrdenadas.length; i++) {
      final _LugarSel p = _lugarNormalizado(
        paradasOrdenadas[i],
        fallbackLabel: 'Parada ${i + 1}',
      );
      waypointsRaw.add(<String, dynamic>{
        'lat': p.lat,
        'lon': p.lon,
        'label': p.label,
        'orden': i + 1,
      });
    }
    final List<Map<String, dynamic>> waypoints =
        MultiparadaRutaHelper.sanitizarWaypoints(waypointsRaw);
    if (waypoints.length != paradasOrdenadas.length) {
      return null;
    }

    final List<({String label, double lat, double lon})> puntosOrdenados =
        <({String label, double lat, double lon})>[
      (
        label: origenGuardar.label,
        lat: origenGuardar.lat,
        lon: origenGuardar.lon,
      ),
      ...waypoints.map(
        (Map<String, dynamic> w) => (
          label: (w['label'] ?? 'Parada').toString(),
          lat: (w['lat'] as num).toDouble(),
          lon: (w['lon'] as num).toDouble(),
        ),
      ),
      (
        label: destinoGuardar.label,
        lat: destinoGuardar.lat,
        lon: destinoGuardar.lon,
      ),
    ];

    final List<Map<String, dynamic>> rutaPuntos =
        MultiparadaRutaHelper.construirRutaPuntos(
      latOrigen: origenGuardar.lat,
      lonOrigen: origenGuardar.lon,
      labelOrigen: origenGuardar.label,
      latDestino: destinoGuardar.lat,
      lonDestino: destinoGuardar.lon,
      labelDestino: destinoGuardar.label,
      waypoints: waypoints,
    );

    final List<Map<String, dynamic>> segmentosGuardar =
        MultiparadaRutaHelper.alinearSegmentosConPuntos(
      segmentos: _segmentos,
      puntosOrdenados: puntosOrdenados,
    );

    final int tramosEsperados = _tramosEsperadosMulti();
    if (segmentosGuardar.length != tramosEsperados) {
      return null;
    }

    final double distKmGuardar = _distanciaKmDesdeSegmentos(segmentosGuardar);
    final double peajeGuardar = _peajeDesdeSegmentos(segmentosGuardar);
    if (distKmGuardar <= 0) {
      return null;
    }

    final String? errorCoords = MultiparadaRutaHelper.validarSecuenciaRuta(
      latOrigen: origenGuardar.lat,
      lonOrigen: origenGuardar.lon,
      labelOrigen: origenGuardar.label,
      latDestino: destinoGuardar.lat,
      lonDestino: destinoGuardar.lon,
      labelDestino: destinoGuardar.label,
      paradas: waypoints
          .map(
            (Map<String, dynamic> w) => (
              lat: (w['lat'] as num).toDouble(),
              lon: (w['lon'] as num).toDouble(),
              label: (w['label'] ?? 'Parada').toString(),
            ),
          )
          .toList(),
    );
    if (errorCoords != null) {
      return null;
    }

    return (
      origen: origenGuardar,
      destino: destinoGuardar,
      waypoints: waypoints,
      rutaPuntos: rutaPuntos,
      segmentos: segmentosGuardar,
      distKm: distKmGuardar,
      peaje: peajeGuardar,
    );
  }

  int _tramosEsperadosMulti() {
    if (_origen == null || _destino == null) return 0;
    return _paradas.whereType<_LugarSel>().length + 1;
  }

  /// Cotización desfasada respecto a origen / paradas / destino actuales.
  bool _cotizacionDesfasadaDePuntos() {
    if (_origen == null || _destino == null) return true;
    final int tramos = _tramosEsperadosMulti();
    if (_segmentos.length != tramos) return true;

    bool coordsCerca(double a, double b) => (a - b).abs() < 0.00005;

    final Map<String, dynamic> s0 = _segmentos.first;
    final double? lat0 = (s0['latOrigen'] as num?)?.toDouble();
    final double? lon0 = (s0['lonOrigen'] as num?)?.toDouble();
    if (lat0 == null ||
        lon0 == null ||
        !coordsCerca(lat0, _origen!.lat) ||
        !coordsCerca(lon0, _origen!.lon)) {
      return true;
    }

    final List<_LugarSel> paradas = _paradas.whereType<_LugarSel>().toList();
    for (int i = 0; i < paradas.length; i++) {
      final Map<String, dynamic> seg = _segmentos[i];
      final double? latD = (seg['latDestino'] as num?)?.toDouble();
      final double? lonD = (seg['lonDestino'] as num?)?.toDouble();
      if (latD == null ||
          lonD == null ||
          !coordsCerca(latD, paradas[i].lat) ||
          !coordsCerca(lonD, paradas[i].lon)) {
        return true;
      }
    }

    final Map<String, dynamic> sLast = _segmentos.last;
    final double? latF = (sLast['latDestino'] as num?)?.toDouble();
    final double? lonF = (sLast['lonDestino'] as num?)?.toDouble();
    if (latF == null ||
        lonF == null ||
        !coordsCerca(latF, _destino!.lat) ||
        !coordsCerca(lonF, _destino!.lon)) {
      return true;
    }
    return false;
  }

  /// Antes de guardar: precio/distancia/segmentos alineados con la ruta visible.
  Future<bool> _asegurarCotizacionCoherenteAntesDeGuardar({
    bool duranteConfirmacion = false,
  }) async {
    final int tramos = _tramosEsperadosMulti();
    if (tramos <= 0) return false;

    final bool cotizacionPendiente = _calculoDebounce?.isActive == true ||
        (_cargando && !duranteConfirmacion);
    if (!cotizacionPendiente &&
        _segmentos.length == tramos &&
        !_cotizacionDesfasadaDePuntos() &&
        _precioCotizadoValidoParaValor(_precio) &&
        _distKm > 0) {
      return true;
    }

    _calculoDebounce?.cancel();
    _calculoSeq++;
    final int runId = _calculoSeq;
    await _calcularConRutasReales(automatico: false, runId: runId);
    if (!mounted || runId != _calculoSeq) return false;
    return _segmentos.length == tramos &&
        !_cotizacionDesfasadaDePuntos() &&
        _precioCotizadoValidoParaValor(_precio) &&
        _distKm > 0;
  }

  /// RAI: solo confirmar con cotización cerrada y ruta alineada.
  bool get _puedeConfirmarViajeMulti {
    if (RaiOfflineCotizacionService.estaOffline) return false;
    if (_cargando || (_calculoDebounce?.isActive ?? false)) return false;
    if (_origen == null || _destino == null) return false;
    if (!_paradasIntermediasCoherentes()) return false;
    if (_validarRutaMultiParaGuardar() != null) return false;
    if (_precioCotizadoValidoParaValor(_precio) == false || _distKm <= 0 || _segmentos.isEmpty) return false;
    final int tramos = _tramosEsperadosMulti();
    if (tramos <= 0 || _segmentos.length != tramos) return false;
    if (_cotizacionDesfasadaDePuntos()) return false;
    return true;
  }

  VoidCallback? get _onConfirmarViajeMulti =>
      _puedeConfirmarViajeMulti ? _confirmar : null;

  /// Alinea pickup GPS al confirmar «Ahora»; recotiza ruta multiparada si se movió mucho.
  Future<bool> _alinearPickupConfirmacionAhoraMulti({
    required double origenCotizadoLat,
    required double origenCotizadoLon,
    required double nuevoOrigenLat,
    required double nuevoOrigenLon,
  }) async {
    if (_origen == null || _destino == null) return false;

    final double metros = Geolocator.distanceBetween(
      origenCotizadoLat,
      origenCotizadoLon,
      nuevoOrigenLat,
      nuevoOrigenLon,
    );

    _origen = _LugarSel(
      label: _origen!.label,
      lat: nuevoOrigenLat,
      lon: nuevoOrigenLon,
    );

    if (metros <= _kMetrosRecotizarAlConfirmar) {
      return _precioCotizadoValidoParaValor(_precio) && _distKm > 0;
    }

    _calculoSeq++;
    final int runId = _calculoSeq;
    await _calcularConRutasReales(automatico: true, runId: runId);
    if (!mounted || runId != _calculoSeq) return false;
    return _precioCotizadoValidoParaValor(_precio) && _distKm > 0;
  }

  Future<void> _calcularConRutasReales({
    bool automatico = false,
    required int runId,
  }) async {
    if (_origen == null || _destino == null) return;

    setState(() {
      _cargando = true;
      _mensajeCarga = 'Calculando ruta...';
      _vistaResumenCotizada = false;
    });

    try {
      final List<_LugarSel> waypoints =
          _paradas.whereType<_LugarSel>().toList();
      final List<_LugarSel> ordenParadas = <_LugarSel>[
        _origen!,
        ...waypoints,
        _destino!,
      ];
      final int nTramos = ordenParadas.length - 1;

      final List<Map<String, dynamic>> segmentos = <Map<String, dynamic>>[];
      double totalKm = 0;
      double totalPeaje = 0;
      DirectionsResult? directionsRutaMulti;

      Future<bool> armarDesdeDirectionsUnaSola() async {
        final List<({double lat, double lon})>? wpCoords = waypoints.isEmpty
            ? null
            : waypoints.map((w) => (lat: w.lat, lon: w.lon)).toList();

        var dir = await DirectionsService.drivingDistanceKm(
          originLat: _origen!.lat,
          originLon: _origen!.lon,
          destLat: _destino!.lat,
          destLon: _destino!.lon,
          waypoints: wpCoords,
          withTraffic: true,
          region: 'do',
        );

        if (dir == null || dir.km <= 0) {
          dir = await DirectionsService.drivingDistanceKm(
            originLat: _origen!.lat,
            originLon: _origen!.lon,
            destLat: _destino!.lat,
            destLon: _destino!.lon,
            waypoints: wpCoords,
            withTraffic: false,
            region: 'do',
          );
        }

        final List<double>? segsRaw = dir?.segmentDistances;
        if (dir == null || dir.km <= 0) {
          return false;
        }
        directionsRutaMulti = dir;

        List<double> segs = <double>[];
        if (segsRaw != null &&
            segsRaw.length == nTramos &&
            segsRaw.every((double s) => s > 0)) {
          segs = List<double>.from(segsRaw);
        } else {
          final List<double> rectas = <double>[];
          double sumRectas = 0;
          for (int i = 0; i < nTramos; i++) {
            final _LugarSel a = ordenParadas[i];
            final _LugarSel b = ordenParadas[i + 1];
            final double h = DistanciaService.calcularDistancia(
              a.lat,
              a.lon,
              b.lat,
              b.lon,
            );
            final double w = h > 0 ? h : 0.01;
            rectas.add(w);
            sumRectas += w;
          }
          if (sumRectas <= 0) {
            return false;
          }
          for (int i = 0; i < nTramos; i++) {
            segs.add(dir.km * (rectas[i] / sumRectas));
          }
        }

        segmentos.clear();
        totalKm = 0;
        totalPeaje = 0;
        for (int i = 0; i < nTramos; i++) {
          final _LugarSel desde = ordenParadas[i];
          final _LugarSel hasta = ordenParadas[i + 1];
          final double kmSeg = segs[i];
          if (kmSeg <= 0) {
            return false;
          }
          final double peajeSeg =
              _estimarPeaje(kmSeg, desde.lat, desde.lon, hasta.lat, hasta.lon);
          segmentos.add(<String, dynamic>{
            'tramo': i + 1,
            'origen': desde.label,
            'destino': hasta.label,
            'latOrigen': desde.lat,
            'lonOrigen': desde.lon,
            'latDestino': hasta.lat,
            'lonDestino': hasta.lon,
            'km': kmSeg,
            'peaje': peajeSeg,
          });
          totalKm += kmSeg;
          totalPeaje += peajeSeg;
        }
        return true;
      }

      final bool okRuta = await armarDesdeDirectionsUnaSola();

      if (!okRuta) {
        segmentos.clear();
        totalKm = 0;
        totalPeaje = 0;

        double prevLat = _origen!.lat;
        double prevLon = _origen!.lon;
        String prevLabel = _origen!.label;

        for (int i = 0; i < waypoints.length; i++) {
          final _LugarSel w = waypoints[i];
          final Map<String, double> resultado = await _calcularTramoReal(
            prevLat,
            prevLon,
            w.lat,
            w.lon,
            '$prevLabel → ${w.label}',
          );

          if (!mounted || runId != _calculoSeq) {
            _finCargaMultiSiCorre(runId);
            return;
          }

          if (resultado['km']! <= 0) {
            if (!automatico && runId == _calculoSeq) {
              _snack('Error en tramo ${i + 1}');
            }
            _finCargaMultiSiCorre(runId);
            return;
          }

          segmentos.add(<String, dynamic>{
            'tramo': i + 1,
            'origen': prevLabel,
            'destino': w.label,
            'latOrigen': prevLat,
            'lonOrigen': prevLon,
            'latDestino': w.lat,
            'lonDestino': w.lon,
            'km': resultado['km'],
            'peaje': resultado['peaje'],
          });

          totalKm += resultado['km']!;
          totalPeaje += resultado['peaje']!;
          prevLat = w.lat;
          prevLon = w.lon;
          prevLabel = w.label;
        }

        final Map<String, double> resultadoFinal = await _calcularTramoReal(
          prevLat,
          prevLon,
          _destino!.lat,
          _destino!.lon,
          '$prevLabel → ${_destino!.label}',
        );

        if (!mounted || runId != _calculoSeq) {
          _finCargaMultiSiCorre(runId);
          return;
        }

        if (resultadoFinal['km']! <= 0) {
          if (!automatico && runId == _calculoSeq) {
            _snack('Error en tramo final');
          }
          _finCargaMultiSiCorre(runId);
          return;
        }

        segmentos.add(<String, dynamic>{
          'tramo': waypoints.length + 1,
          'origen': prevLabel,
          'destino': _destino!.label,
          'latOrigen': prevLat,
          'lonOrigen': prevLon,
          'latDestino': _destino!.lat,
          'lonDestino': _destino!.lon,
          'km': resultadoFinal['km'],
          'peaje': resultadoFinal['peaje'],
        });

        totalKm += resultadoFinal['km']!;
        totalPeaje += resultadoFinal['peaje']!;
      }

      if (segmentos.isNotEmpty) {
        totalKm = segmentos.fold<double>(
          0,
          (double acc, Map<String, dynamic> s) =>
              acc + ((s['km'] as num?)?.toDouble() ?? 0),
        );
        totalKm = _normalizarKmMultiparadaUrbana(
          totalKm: totalKm,
          puntos: ordenParadas,
          segmentos: segmentos,
        );
        _normalizarPeajeMultiparada(segmentos, totalKm);
        totalPeaje = _peajeDesdeSegmentos(segmentos);
      }

      final TarifaServiceUnificado servicio = TarifaServiceUnificado();
      await servicio.recargar();

      final double maxKm = servicio.distanciaMaximaCotizableKm;
      if (totalKm <= 0 || DistanciaService.tramoEsImposible(totalKm, maxKm: maxKm)) {
        if (!automatico && runId == _calculoSeq) {
          _snack(
            'No se pudo cotizar esa ruta multiparada '
            '(máx. ${maxKm.toStringAsFixed(0)} km). Revisá las paradas.',
          );
        }
        _finCargaMultiSiCorre(runId);
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      int contadorViajes = 1;
      if (user != null) {
        contadorViajes = await _obtenerContadorViajes(user.uid);
      }
      if (contadorViajes <= 0) contadorViajes = 1;
      if (!mounted || runId != _calculoSeq) return;

      final promoSnapshot =
          await servicio.construirPromoSnapshot(contadorViajes);
      if (!mounted || runId != _calculoSeq) return;

      // Ciudad compacta (p. ej. varias paradas en SD): tarifa local continua,
      // sin bandas interurbanas ni peaje inventado.
      final bool urbanaLocal = _diametroRutaKm(ordenParadas) <= 45;
      if (urbanaLocal) {
        totalPeaje = 0;
        for (int i = 0; i < segmentos.length; i++) {
          segmentos[i] = <String, dynamic>{
            ...segmentos[i],
            'peaje': 0.0,
          };
        }
      }

      final double precioNominal = await servicio.calcularPrecio(
        tipoServicio: 'normal',
        tipoVehiculo: _tipoVehiculo,
        distanciaKm: totalKm,
        idaVuelta: false,
        peaje: totalPeaje,
        contadorViajes: contadorViajes,
        forzarTarifaUrbanaLocal: urbanaLocal,
        directionsCotizacion: directionsRutaMulti,
        latOrigenCotizacion: _origen!.lat,
        lonOrigenCotizacion: _origen!.lon,
      );
      final double precio = await _aplicarPromoNegocioAliado(precioNominal);

      if (!mounted || runId != _calculoSeq) {
        _finCargaMultiSiCorre(runId);
        return;
      }

      setState(() {
        _distKm = double.parse(totalKm.toStringAsFixed(2));
        _precio = precio;
        _peaje = totalPeaje;
        _segmentos = segmentos;
        _directionsRutaMulti = directionsRutaMulti;
        _promoSnapshotCotizacion = promoSnapshot;
        _cotizacionDesglose = servicio.ultimoDesgloseCotizacion;
        _promoOmitidaPorLargaDistancia =
            servicio.ultimoDesgloseCotizacion?['promoOmitidaPorLargaDistancia'] ==
                true;
        _cargando = false;
        _mensajeCarga = '';
        _vistaResumenCotizada = true;
        _actualizarMapaMultiparada();
      });
      _scrollAlResumenCotizado();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_ajustarCamaraMapaMultiparada());
      });
    } catch (e) {
      if (!automatico && runId == _calculoSeq) {
        _snack('Error calculando rutas: $e');
      }
      _finCargaMultiSiCorre(runId);
    }
  }

  Future<void> _confirmar() async {
    PoolTimbreSessionGuard.activarSesionPasajero();
    if (RaiOfflineCotizacionService.estaOffline) {
      _snack(RaiOfflineCotizacionService.mensajeNoConfirmar);
      return;
    }
    if (!_puedeConfirmarViajeMulti) {
      if (_calculoDebounce?.isActive == true || _cargando) {
        _snack('Espera a que termine el cálculo del precio.');
      } else if (!_precioCotizadoValidoParaValor(_precio) || _distKm <= 0) {
        _snack('Primero calcula el precio.');
      } else if (!_paradasIntermediasCoherentes()) {
        _snack('Completa las paradas en orden o quita las filas vacías.');
      } else {
        _snack('Actualiza la ruta: revisa origen, paradas y destino.');
      }
      return;
    }

    if (_segmentos.isEmpty) {
      _snack('Espera a que termine el cálculo de la ruta.');
      return;
    }

    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      _snack('Debes iniciar sesión.');
      return;
    }

    if (await ActiveTripService.clienteViajeActivoImpideNuevoPedido(
      u.uid,
      nuevoEsAhora: _esAhora,
    )) {
      _snack(kMsgClienteYaTieneViajeActivo);
      return;
    }

    if (_origen == null || _destino == null) {
      if (_origen == null &&
          RaiUbicacionClienteService.instance.bannerActivo) {
        return;
      }
      _snack('Selecciona origen y destino.');
      return;
    }

    if (!_esAhora) {
      final now = DateTime.now();
      final maxD = now.add(const Duration(days: 90));
      if (_fechaHora.isAfter(maxD)) {
        _snack('Solo puedes programar hasta 90 días adelante.');
        return;
      }
      if (_fechaHora.isBefore(now.subtract(const Duration(seconds: 90)))) {
        _snack('La hora de recogida no puede quedar en el pasado.');
        return;
      }
    }

    setState(() => _cargando = true);

    bool navegoFuera = false;
    final ({NavigatorState? tab, NavigatorState? raiz}) nav =
        NavigationService.capturarNavigadoresFormulario(context);

    try {
      if (_esAhora && _origenEsGpsActual) {
        final LocationReadiness ready =
            await LocationPermissionService.ensureLocationReady(
          context: context,
          requestIfDenied: false,
        );
        if (!ready.isUsable || ready.position == null) {
          if (!RaiUbicacionClienteService.instance.bannerActivo) {
            _snack(LocationReadiness.kMsgEsperandoUbicacion);
          }
          if (mounted) setState(() => _cargando = false);
          return;
        }
        final double cotLat = _origen!.lat;
        final double cotLon = _origen!.lon;
        final double freshLat = ready.position!.latitude;
        final double freshLon = ready.position!.longitude;
        final double metrosMovidos = Geolocator.distanceBetween(
          cotLat,
          cotLon,
          freshLat,
          freshLon,
        );
        final bool alineado = await _alinearPickupConfirmacionAhoraMulti(
          origenCotizadoLat: cotLat,
          origenCotizadoLon: cotLon,
          nuevoOrigenLat: freshLat,
          nuevoOrigenLon: freshLon,
        );
        if (!alineado) {
          _snack(
            'Tu ubicación cambió. Vuelve a calcular el precio antes de confirmar.',
          );
          if (mounted) setState(() => _cargando = false);
          return;
        }
        if (metrosMovidos > _kMetrosRecotizarAlConfirmar && mounted) {
          _snack(
            'Precio actualizado según tu ubicación: '
            '${FormatosMoneda.rd(_precio)}.',
          );
        }
        if (mounted) setState(() => _cargando = true);
      }

      final bool cotizacionOk =
          await _asegurarCotizacionCoherenteAntesDeGuardar(
        duranteConfirmacion: true,
      );
      if (!cotizacionOk) {
        _snack(
          'No se pudo alinear precio y ruta. Revisa origen, paradas y destino.',
        );
        if (mounted) setState(() => _cargando = false);
        return;
      }

      final String? errorRuta = _validarRutaMultiParaGuardar();
      if (errorRuta != null) {
        _snack(errorRuta);
        if (mounted) setState(() => _cargando = false);
        return;
      }

      final ({
        _LugarSel origen,
        _LugarSel destino,
        List<Map<String, dynamic>> waypoints,
        List<Map<String, dynamic>> rutaPuntos,
        List<Map<String, dynamic>> segmentos,
        double distKm,
        double peaje,
      })? plan = await _prepararDatosRutaMultiparadaGuardar();
      if (plan == null) {
        _snack(
          'No se pudo validar origen, paradas y destino. Revisá el mapa e inténtalo de nuevo.',
        );
        if (mounted) setState(() => _cargando = false);
        return;
      }

      final _LugarSel origenGuardar = plan.origen;
      final _LugarSel destinoGuardar = plan.destino;
      final List<Map<String, dynamic>> waypoints = plan.waypoints;
      final List<Map<String, dynamic>> rutaPuntos = plan.rutaPuntos;
      final List<Map<String, dynamic>> segmentosGuardar = plan.segmentos;
      final double distKmGuardar = plan.distKm;
      final double peajeGuardar = plan.peaje;

      if (!_precioCotizadoValidoParaValor(_precio)) {
        _snack('No se pudo validar precio y distancia de la ruta.');
        if (mounted) setState(() => _cargando = false);
        return;
      }

      const String tipoSrv = 'normal';
      const String canal = 'pool';

      final DateTime nowUtc = DateTime.now().toUtc();
      // Misma política que [ProgramarViaje] modoAhora: recogida = ahora (UTC), no +10 min.
      final DateTime fechaHoraViaje =
          _esAhora ? nowUtc : _fechaHora.toUtc();

      final bool viajeInmediato =
          TripPublishWindows.esProgramadoRecogidaCasiInmediata(
              fechaHoraViaje, nowUtc);
      // `_esAhora` refuerza navegación inmediata vía [forzarViajeInmediato] en el helper.

      DateTime? publishAtArg;
      DateTime? acceptAfterArg;
      if (viajeInmediato) {
        publishAtArg = nowUtc;
        acceptAfterArg = nowUtc;
      } else {
        publishAtArg =
            ViajesRepo.poolOpensAtForScheduledPickup(fechaHoraViaje, nowUtc);
        acceptAfterArg = publishAtArg;
      }

      final String id = await ViajesRepo.crearViajePendiente(
        uidCliente: u.uid,
        origen: origenGuardar.label,
        destino: destinoGuardar.label,
        latOrigen: origenGuardar.lat,
        lonOrigen: origenGuardar.lon,
        latDestino: destinoGuardar.lat,
        lonDestino: destinoGuardar.lon,
        fechaHora: fechaHoraViaje,
        precio: _precio,
        metodoPago: _metodoPagoEtiquetaDocumento,
        tipoVehiculo: _tipoVehiculo,
        idaYVuelta: false,
        categoria: 'multi',
        tipoServicio: tipoSrv,
        waypoints: waypoints,
        extras: {
          'paradas_count': waypoints.length,
          'tramos_total': segmentosGuardar.length,
          'segmentos': segmentosGuardar,
          'rutaPuntos': rutaPuntos,
          'peaje_total': peajeGuardar,
          'distancia_km': distKmGuardar,
          'esAhora': viajeInmediato,
          if (_cotizacionDesglose != null && _cotizacionDesglose!.isNotEmpty)
            'cotizacionDesglose': _cotizacionDesglose,
          if (_promoSnapshotCotizacion != null)
            'promoSnapshot': _promoSnapshotCotizacion,
          if (_cotizacionDesglose?['precioBloqueado'] == true)
            'precioBloqueado': true,
          if (_cotizacionDesglose?['recargoCondiciones'] != null)
            'cotizacionCondiciones': _cotizacionDesglose!['recargoCondiciones'],
          if (_cotizacionDesglose?['recargoCondiciones'] != null)
            'precioBloqueado': true,
        },
        distanciaKm: distKmGuardar,
        canalAsignacion: canal,
        publishAt: publishAtArg,
        acceptAfter: acceptAfterArg,
        forzarEsAhora: (viajeInmediato || _esAhora) ? true : null,
      );

      if (context.mounted) {
        _snack('✅ Viaje creado — #${id.substring(0, 6)}');
      }

      navegoFuera = true;
      final bool viajeOverlayInmediato = _esAhora || viajeInmediato;
      if (viajeOverlayInmediato) {
        await NavigationService.navegarTrasConfirmarViajeInmediatoCliente(
          viajeId: id,
          fechaHoraPickup: fechaHoraViaje,
          preNav: nav.tab,
          preNavRaiz: nav.raiz,
        );
      } else {
        await NavigationService.navegarTrasCrearViajeCliente(
          viajeId: id,
          fechaHoraPickup: fechaHoraViaje,
          tipoServicio: tipoSrv,
          preNav: nav.tab,
          preNavRaiz: nav.raiz,
          abrirEnCursoAlConfirmar: true,
        );
      }
    } on ClienteVerificacionIdentidadRequeridaException catch (e) {
      if (mounted) _snack(e.message);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) _snack(CrearViajeErrores.traducir(e));
    } on fs.FirebaseException catch (e) {
      if (mounted) {
        _snack(CrearViajeErrores.traducir(e));
      }
    } on StateError catch (e) {
      if (mounted) {
        _snack(e.message);
      }
    } catch (e) {
      if (mounted) {
        _snack(CrearViajeErrores.traducir(e));
      }
    } finally {
      if (mounted && !navegoFuera) {
        setState(() => _cargando = false);
      }
    }
  }

  Future<void> _seleccionarFechaHora() async {
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _fechaHora,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (!mounted || d == null) return;
    final TimeOfDay? t = await elegirHoraAmPm(
      context,
      initial: TimeOfDay.fromDateTime(_fechaHora),
    );
    if (!mounted || t == null) return;
    setState(() {
      _fechaHora = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Widget _buildDestinoSection({
    _EstiloRutaCampo? estiloDestino,
    bool legacyRutaCampos = false,
  }) {
    final bool mockupLayout = !legacyRutaCampos;

    return _campoLugarIntegrado(
      label: 'Destino',
      hint: 'Barrio, calle, hotel, aeropuerto…',
      value: _destino?.label,
      esOrigen: false,
      campoMapa: _CampoRutaMapa.destino,
      fallbackLabel: 'Destino final',
      estilo: estiloDestino,
      visual: _RutaCampoVisual.destino,
      legacyRutaCampos: legacyRutaCampos,
      mockupLayoutCampo: mockupLayout,
    );
  }

  bool get _mostrarResumenMulti =>
      _vistaResumenCotizada &&
      _precioCotizadoValidoParaValor(_precio) &&
      !_cargando;

  void _abrirFormularioCompletoMulti() {
    setState(() => _vistaResumenCotizada = false);
  }

  void _volverAlInicioSinConfirmar() {
    intentarSalirAlGate(context);
  }

  Widget _botonVolverSinConfirmar() {
    return BotonVolverInicioSinConfirmar(
      onPressed: _volverAlInicioSinConfirmar,
    );
  }

  Widget _tarjetaResumenMulti({
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color dividerSoft,
  }) {
    final Color c = _colorServicio;
    final String tipoLabel = 'Normal · $_tipoVehiculo';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                c.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.22
                        : 0.12),
                c.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.08
                        : 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
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
              const SizedBox(height: 12),
              Text(
                'Ruta',
                style: TextStyle(
                  color: textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _etiquetaOrigenResumen(),
                style:
                    TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
              ),
              ..._paradas.whereType<_LugarSel>().map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(Icons.arrow_downward, size: 16, color: c),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              p.label,
                              style: TextStyle(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.flag_rounded, size: 18, color: c),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _destino?.label ?? '',
                        style: TextStyle(
                            color: textPrimary, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(tipoLabel, style: TextStyle(color: textMuted, fontSize: 12)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: Divider(color: dividerSoft, height: 1),
              ),
              const SizedBox(height: 12),
              Text(
                FormatosMoneda.km(_distKm),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: textSecondary, fontWeight: FontWeight.w600),
              ),
              if (_peaje > 0) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  'Peaje incluido: ${FormatosMoneda.rd(_peaje)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textMuted, fontSize: 12),
                ),
              ],
              PromoMxKClientePanel(
                promoSnapshot: _promoSnapshotCotizacion,
                promoOmitidaPorLargaDistancia: _promoOmitidaPorLargaDistancia,
                textColor: textPrimary,
                mutedColor: textMuted,
              ),
              ClienteNegocioAliadoCotizacionBanner(eval: _negocioPromoEval),
              const SizedBox(height: 4),
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
                    FormatosMoneda.rd(_precio),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c,
                      fontSize: 50,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _onConfirmarViajeMulti,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Confirmar viaje',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              _botonVolverSinConfirmar(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1A1A1A)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: _abrirFormularioCompletoMulti,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: dividerSoft),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.edit_location_alt_rounded, color: c, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Cambiar paradas u opciones',
                          style: TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Vuelve al formulario completo: origen, paradas, tipo y pago',
                          style: TextStyle(
                              color: textMuted, fontSize: 12, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.unfold_more_rounded, color: textMuted, size: 28),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const bool rutaMockup = true;
    final Color textPrimary = isDark ? Colors.white : const Color(0xFF101828);
    final Color textSecondary =
        isDark ? Colors.white70 : const Color(0xFF475467);
    final Color textMuted = isDark ? Colors.white60 : const Color(0xFF667085);
    final Color payLinkColor =
        isDark ? Colors.green.shade300 : const Color(0xFF0F9D58);
    final Color dividerSoft = isDark ? Colors.white24 : const Color(0xFFE4E7EC);
    final Color ddBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;

    final _EstiloRutaCampo estiloOrigen = _EstiloRutaCampo(
      acento: isDark ? const Color(0xFFFFE082) : const Color(0xFFD97706),
      fondo: isDark ? const Color(0xFF1A1208) : const Color(0xFFFFFBEB),
      borde: isDark ? const Color(0xFFFF9800) : const Color(0xFFF59E0B),
      icono: Icons.trip_origin_rounded,
    );
    final _EstiloRutaCampo estiloParada = _EstiloRutaCampo(
      acento: isDark ? const Color(0xFFFFE082) : const Color(0xFFC2410C),
      fondo: isDark ? const Color(0xFF18120A) : const Color(0xFFFFF7ED),
      borde: isDark ? const Color(0xFFF59E0B) : const Color(0xFFFB923C),
      icono: Icons.add_location_alt_rounded,
    );
    final _EstiloRutaCampo estiloDestino = _EstiloRutaCampo(
      acento: isDark ? Colors.white : const Color(0xFF7C3AED),
      fondo: isDark ? const Color(0xFF3D0F5C) : const Color(0xFFFAF5FF),
      borde: isDark ? const Color(0xFFC084FC) : const Color(0xFFA855F7),
      icono: Icons.flag_rounded,
    );
    final Color lineaRecorrido =
        isDark ? const Color(0xFFFFB74D) : const Color(0xFFF59E0B);

    final Widget interiorRecorrido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _tituloSeccionRuta(
          estilo: estiloOrigen,
          titulo: 'ORIGEN',
          ayuda: 'Punto de salida',
          textoAyuda: textMuted,
        ),
        ParpadeoRutaProgramar(
          pulseColor: estiloOrigen.acento,
          child: _campoLugarIntegrado(
            label: 'Punto de partida',
            hint: 'Escribe origen o tocá el mapa…',
            value: _origen?.label,
            esOrigen: true,
            campoMapa: _CampoRutaMapa.origen,
            fallbackLabel: 'Origen',
            estilo: estiloOrigen,
            visual:
                rutaMockup ? _RutaCampoVisual.origen : _RutaCampoVisual.parada,
            legacyRutaCampos: false,
            mockupLayoutCampo: rutaMockup,
          ),
        ),
        if (rutaMockup)
          const SizedBox(height: 6)
        else
          _conectorRuta(estiloOrigen),
        _tituloSeccionRuta(
          estilo: estiloParada,
          titulo: 'PARADAS INTERMEDIAS',
          ayuda: 'Hasta $_kMaxParadasIntermedias paradas · opcional',
          textoAyuda: textMuted,
        ),
        ..._paradas.asMap().entries.map((MapEntry<int, _LugarSel?> e) {
          final int i = e.key;
          final _LugarSel? val = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _campoLugarIntegrado(
                    label: 'Parada ${i + 1}',
                    hint: 'Dirección de la parada ${i + 1}…',
                    value: val?.label,
                    esOrigen: false,
                    campoMapa: _CampoRutaMapa.parada,
                    paradaIndex: i,
                    fallbackLabel: 'Parada ${i + 1}',
                    estilo: estiloParada,
                    visual: _RutaCampoVisual.parada,
                    legacyRutaCampos: false,
                    mockupLayoutCampo: rutaMockup,
                  ),
                ),
                SizedBox(width: rutaMockup ? 6 : 4),
                if (rutaMockup)
                  Tooltip(
                    message: 'Quitar parada',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          setState(() {
                            if (_paradas.length > 1) {
                              _paradas.removeAt(i);
                            } else {
                              _paradas[i] = null;
                            }
                          });
                          _programarCalculoAutomatico();
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: estiloParada.acento,
                              width: 1.5,
                            ),
                            color: estiloParada.acento
                                .withValues(alpha: isDark ? 0.12 : 0.14),
                          ),
                          child: Icon(Icons.remove_rounded,
                              color: estiloParada.acento, size: 22),
                        ),
                      ),
                    ),
                  )
                else
                  IconButton(
                    tooltip: 'Quitar parada',
                    onPressed: () {
                      setState(() {
                        if (_paradas.length > 1) {
                          _paradas.removeAt(i);
                        } else {
                          _paradas[i] = null;
                        }
                      });
                      _programarCalculoAutomatico();
                    },
                    icon: Icon(Icons.remove_circle_outline_rounded,
                        color: estiloParada.acento),
                  ),
              ],
            ),
          );
        }),
        BotonAccionDestacadoHoja(
          onPressed: _paradas.length < _kMaxParadasIntermedias
              ? () {
                  final int nuevoIdx = _paradas.length;
                  setState(() => _paradas.add(null));
                  _onCampoRutaEnfocado(
                    _CampoRutaMapa.parada,
                    paradaIndex: nuevoIdx,
                  );
                }
              : null,
          icon: Icons.add_location_alt_rounded,
          label: 'Agregar parada',
          accent: estiloParada.borde,
        ),
        if (rutaMockup)
          const SizedBox(height: 8)
        else
          _conectorRuta(estiloParada),
        _tituloSeccionRuta(
          estilo: estiloDestino,
          titulo: 'DESTINO FINAL',
          ayuda: 'Destino final',
          textoAyuda: textMuted,
          colorTitulo: rutaMockup
              ? (isDark ? Colors.white : estiloDestino.acento)
              : null,
          colorIconoEnCaja: rutaMockup
              ? (isDark ? Colors.white : estiloDestino.acento)
              : null,
          bordeCajaIcono: rutaMockup
              ? (isDark ? const Color(0xFFC084FC) : estiloDestino.borde)
              : null,
          fondoCajaIcono: rutaMockup && isDark
              ? const Color(0xFF2D0A45).withValues(alpha: 0.9)
              : null,
        ),
        ParpadeoRutaProgramar(
          pulseColor: rutaMockup
              ? (isDark ? const Color(0xFFC084FC) : estiloDestino.borde)
              : estiloDestino.acento,
          child: _buildDestinoSection(
            estiloDestino: estiloDestino,
            legacyRutaCampos: false,
          ),
        ),
      ],
    );

    return FlygoSalidaSegura(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: isDark ? Colors.black : const Color(0xFFE8EAED),
        appBar: const RaiAppBar(
          title: 'Múltiples paradas',
          backWhenCanPop: true,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const RaiUbicacionClienteBanner(),
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: GoogleMap(
                      padding: _multiMapPadding(context),
                      initialCameraPosition: CameraPosition(
                        target: _mapCentro ??
                            const LatLng(18.4861, -69.9312),
                        zoom: _mapCentro != null ? 13 : 11,
                      ),
                      markers: _mapMarkers,
                      polylines: _mapPolylines,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      zoomGesturesEnabled: true,
                      scrollGesturesEnabled: true,
                      rotateGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      mapToolbarEnabled: false,
                      compassEnabled: true,
                      onMapCreated: (GoogleMapController c) {
                        _map = c;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          unawaited(_ajustarCamaraMapaMultiparada());
                        });
                      },
                      onLongPress: _onLongPressMapMulti,
                      onTap: (LatLng p) {
                        if (_mapProgrammaticCameraDepth > 0) return;
                        _onMultiMapUserGesture();
                        _multiMapGestureEndDebounce?.cancel();
                        if (_puedeElegirDestinoEnMapa()) {
                          unawaited(_aplicarPuntoDesdeMapa(p));
                        }
                        _multiMapGestureEndDebounce = Timer(
                          const Duration(milliseconds: 420),
                          () {
                            if (mounted) {
                              _expandMultiSheetTrasMapaInteract();
                            }
                          },
                        );
                      },
                      onCameraMoveStarted: _onMultiMapUserGesture,
                      onCameraIdle: _onMultiMapCameraIdle,
                    ),
                  ),
                  if (_necesitaAlertaUbicacionMulti)
                    Positioned(
                      top: 8,
                      left: 16,
                      right: 16,
                      child: const RaiUbicacionClienteMapAlert(),
                    )
                  else if (_resolviendoDestinoMapa)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 16,
                      right: 16,
                      child: Material(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(12),
                        elevation: 4,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                Icons.place_rounded,
                                color: Color(0xFF49F18B),
                                size: 22,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Obteniendo dirección del punto…',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (_mensajeSeleccionMapaActiva != null)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 16,
                      right: 16,
                      child: Material(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(12),
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          child: Row(
                            children: <Widget>[
                              const Icon(
                                Icons.touch_app_rounded,
                                color: Color(0xFFFF5A00),
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _mensajeSeleccionMapaActiva!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (_origen != null && _destino == null)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 16,
                      right: 16,
                      child: Material(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(12),
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          child: Row(
                            children: <Widget>[
                              const Icon(
                                Icons.touch_app_rounded,
                                color: Color(0xFFFF5A00),
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _paradas.length > 1 ||
                                          _paradas
                                              .whereType<_LugarSel>()
                                              .isNotEmpty
                                      ? 'Tocá el mapa para marcar la siguiente parada o el destino'
                                      : 'Tocá el mapa para marcar el destino final',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 14,
                    top: 8,
                    child: FloatingActionButton.small(
                      heroTag: 'multi_paradas_centrar',
                      backgroundColor: isDark
                          ? const Color(0xFF1E1E1E)
                          : Colors.white,
                      onPressed: () =>
                          unawaited(_ajustarCamaraMapaMultiparada()),
                      child: Icon(
                        Icons.my_location_rounded,
                        color: isDark
                            ? _colorServicio
                            : const Color(0xFF0F9D58),
                      ),
                    ),
                  ),
                  DraggableScrollableSheet(
                    controller: _sheetCtrl,
                    minChildSize: _sheetMinFracMulti,
                    maxChildSize: 0.88,
                    initialChildSize:
                        _mostrarResumenMulti ? 0.56 : 0.38,
                    snap: true,
                    snapSizes: const <double>[
                      _sheetMinFracMulti,
                      0.42,
                      0.56,
                      0.75,
                    ],
                    builder: (BuildContext ctx, ScrollController scrollController) {
                      final double safeBottom =
                          MediaQuery.paddingOf(ctx).bottom;
                      final double kbInset =
                          MediaQuery.viewInsetsOf(ctx).bottom;
                      final Color sheetBg =
                          isDark ? const Color(0xFF0F1115) : Colors.white;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          color: sheetBg,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: isDark ? 0.38 : 0.12),
                              blurRadius: 18,
                              offset: const Offset(0, -4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            const SizedBox(height: 10),
                            Center(
                              child: Container(
                                width: 44,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white30
                                      : const Color(0xFFD0D5DD),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView(
                                controller: scrollController,
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  16 + safeBottom + kbInset,
                                ),
                                children: <Widget>[
              if (_cargando)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CotizacionPrecioLoadingStrip(
                    accentColor: _colorServicio,
                    isDark: isDark,
                    message: _precio > 0 ? 'Procesando…' : 'Calculando precio…',
                  ),
                ),
              if (_mostrarResumenMulti)
                _tarjetaResumenMulti(
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  textMuted: textMuted,
                  dividerSoft: dividerSoft,
                ),
              if (!_mostrarResumenMulti) ...<Widget>[
                ClienteViajeOrientacionBanner(
                  mensaje: ClienteViajeOrientacionCopy.multiParadas(
                    tipoServicio: 'normal',
                    esAhora: _esAhora,
                  ),
                  icon: Icons.alt_route_rounded,
                  accentColor: _colorServicio,
                ),
                const SizedBox(height: 12),
                ProgramarViajeEncabezadoPersonaliza(
                  subtitulo: '',
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                  badges: <Widget>[
                    ProgramarViajeModoChip(
                      label: 'Múltiples paradas',
                      icon: Icons.alt_route_rounded,
                      accent: _colorServicio,
                      textColor: textPrimary,
                    ),
                    ProgramarViajeModoChip(
                      label: _esAhora ? 'Viaje ahora' : 'Programado',
                      icon: _esAhora
                          ? Icons.bolt_rounded
                          : Icons.calendar_month_rounded,
                      accent: _colorServicio,
                      textColor: textPrimary,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _card(
                  mockupSurface: rutaMockup,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ProgramarViajeEtiquetaVehiculo(
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                        mostrarAyuda: false,
                      ),
                      const SizedBox(height: 10),
                      OverflowSafeLabeledDropdown(
                        leading: Icon(Icons.directions_car,
                            color: textSecondary, size: 20),
                        label: 'Vehículo',
                        labelStyle: TextStyle(color: textSecondary),
                        gapAfterLeading: 10,
                        dropdown: DropdownButton<String>(
                          isExpanded: true,
                          value: _tipoVehiculo,
                          dropdownColor: ddBg,
                          underline: rutaMockup
                              ? Container(
                                  height: 1,
                                  margin: const EdgeInsets.only(top: 2),
                                  color: isDark
                                      ? Colors.white54
                                      : const Color(0xFF98A2B3),
                                )
                              : const SizedBox(),
                          style:
                              TextStyle(color: textPrimary, fontSize: 16),
                          items: [
                            'Carro',
                            'Jeepeta',
                            'Minibús',
                            'Minivan',
                            'AutobusGuagua'
                          ]
                              .map((e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(
                                      e,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: textPrimary),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _tipoVehiculo = v ?? 'Carro');
                            _programarCalculoAutomatico();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(
                  mockupSurface: rutaMockup,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '¿A dónde vas?',
                        style: TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        'Origen, paradas y destino',
                        style: TextStyle(
                            color: textMuted, fontSize: 12.5, height: 1.35),
                      ),
                      const SizedBox(height: 14),
                      if (rutaMockup)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: lineaRecorrido, width: 2),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: interiorRecorrido,
                          ),
                        )
                      else
                        interiorRecorrido,
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(
                  mockupSurface: rutaMockup,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Opciones del viaje',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                      if (!_esAhora) ...<Widget>[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _seleccionarFechaHora,
                          icon: Icon(Icons.calendar_today, color: payLinkColor),
                          label: Text(
                            fmtFechaHoraAmPm(_fechaHora, sep: '•'),
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: payLinkColor,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_precio > 0 && !_cargando && !_mostrarResumenMulti) ...<Widget>[
                  const SizedBox(height: 16),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _colorServicio.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _colorServicio, width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'DISTANCIA TOTAL',
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
                          FormatosMoneda.km(_distKm),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: Divider(color: dividerSoft),
                        ),
                        const SizedBox(height: 12),
                        PromoMxKClientePanel(
                          promoSnapshot: _promoSnapshotCotizacion,
                          promoOmitidaPorLargaDistancia:
                              _promoOmitidaPorLargaDistancia,
                          textColor: textPrimary,
                          mutedColor: textMuted,
                        ),
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
                              FormatosMoneda.rd(_precio),
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
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Incluye peaje: ${FormatosMoneda.rd(_peaje)}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: textMuted, fontSize: 12),
                            ),
                          ),
                        const SizedBox(height: 16),
                        ClienteMetodoPagoSolicitudTiles(
                          categoriaSeleccionada: _metodoPagoCategoria,
                          onCategoriaChanged: _onMetodoPagoCategoriaChanged,
                          fondoOscuro: true,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _onConfirmarViajeMulti,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _colorServicio,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              '✅ CONFIRMAR VIAJE',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _botonVolverSinConfirmar(),
                      ],
                    ),
                  ),
                ],
              ],
                if (_cargando)
                  CotizacionPrecioLoadingPlaceholder(
                    accentColor: _colorServicio,
                    isDark: isDark,
                    message: _precio > 0 ? 'Procesando…' : 'Calculando precio…',
                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  if (_cargando && _mensajeCarga.isNotEmpty)
                    Positioned.fill(
                      child: CotizacionPrecioLoadingDimmed(
                        accentColor: _colorServicio,
                        isDark: isDark,
                        message: _mensajeCarga,
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

  Widget _tituloSeccionRuta({
    required _EstiloRutaCampo estilo,
    required String titulo,
    required String ayuda,
    required Color textoAyuda,
    Color? colorTitulo,
    Color? colorIconoEnCaja,
    Color? fondoCajaIcono,
    Color? bordeCajaIcono,
  }) {
    final Color tituloCol = colorTitulo ?? estilo.acento;
    final Color iconCol = colorIconoEnCaja ?? estilo.acento;
    final Color fondoCaja =
        fondoCajaIcono ?? estilo.acento.withValues(alpha: 0.18);
    final Color bordeCaja =
        bordeCajaIcono ?? estilo.borde.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: fondoCaja,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: bordeCaja, width: 1.2),
            ),
            child: Icon(estilo.icono, size: 22, color: iconCol),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  titulo,
                  style: TextStyle(
                    color: tituloCol,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ayuda,
                  style:
                      TextStyle(color: textoAyuda, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _conectorRuta(_EstiloRutaCampo estilo) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 2, bottom: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: estilo.acento.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child, bool mockupSurface = true}) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (mockupSurface) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFD0D5DD),
          ),
        ),
        child: child,
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? Colors.white24 : const Color(0xFFD0D5DD)),
      ),
      child: child,
    );
  }

  Widget _btnLugar({
    required String label,
    String? value,
    required VoidCallback onTap,
    _EstiloRutaCampo? estilo,
    _RutaCampoVisual visual = _RutaCampoVisual.parada,
    bool legacyRutaCampos = false,
    bool mockupLayoutCampo = false,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color secondary = isDark ? Colors.white70 : const Color(0xFF475467);
    final Color muted = isDark ? Colors.white54 : const Color(0xFF667085);
    final Color primary = isDark ? Colors.white : const Color(0xFF101828);
    final Color fillDefault =
        isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF8FAFC);
    final Color borderDefault =
        isDark ? Colors.white24 : const Color(0xFFD0D5DD);

    Color fill = estilo?.fondo ?? fillDefault;
    Color border = estilo?.borde ?? borderDefault;
    Color labelColor = estilo?.acento ?? secondary;
    Color iconColor = estilo?.acento ?? secondary;
    Color chevronColor = muted;
    double borderW = estilo != null ? 1.6 : 1;
    List<BoxShadow>? shadows;

    if (estilo != null && legacyRutaCampos) {
      fill = estilo.fondo;
      border = estilo.borde;
      labelColor = estilo.acento;
      iconColor = estilo.acento;
      chevronColor = muted;
      borderW = 1.6;
      shadows = <BoxShadow>[
        BoxShadow(
          color: estilo.acento.withValues(alpha: isDark ? 0.12 : 0.08),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];
    } else if (estilo != null) {
      switch (visual) {
        case _RutaCampoVisual.origen:
          borderW = isDark ? 2 : 1.8;
          shadows = <BoxShadow>[
            BoxShadow(
              color: const Color(0xFFFF9800)
                  .withValues(alpha: isDark ? 0.38 : 0.22),
              blurRadius: 18,
              spreadRadius: 0,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: const Color(0xFFFFD54A)
                  .withValues(alpha: isDark ? 0.12 : 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ];
          break;
        case _RutaCampoVisual.parada:
          borderW = isDark ? 1.15 : 1.2;
          shadows = null;
          break;
        case _RutaCampoVisual.destino:
          if (isDark) {
            fill = const Color(0xFF4C1D95);
            border = const Color(0xFFD8B4FE);
            labelColor = Colors.white;
            iconColor = Colors.white;
            chevronColor = Colors.white.withValues(alpha: 0.85);
            borderW = 2;
            shadows = <BoxShadow>[
              BoxShadow(
                color: const Color(0xFFA78BFA).withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 0,
                offset: const Offset(0, 5),
              ),
            ];
          } else {
            borderW = 2;
            shadows = <BoxShadow>[
              BoxShadow(
                color: estilo.borde.withValues(alpha: 0.22),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ];
          }
          break;
      }
    }

    LinearGradient? gradienteMockupDestino;
    if (estilo != null &&
        !legacyRutaCampos &&
        visual == _RutaCampoVisual.destino &&
        isDark) {
      gradienteMockupDestino = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFF7C3AED),
          Color(0xFF5B21B6),
          Color(0xFF1E0B36),
        ],
        stops: <double>[0.0, 0.42, 1.0],
      );
    }

    final bool empty = value?.isEmpty ?? true;
    final Color line2Color =
        !legacyRutaCampos && visual == _RutaCampoVisual.destino && isDark
            ? (empty ? Colors.white70 : Colors.white)
            : (empty ? muted : primary);
    final FontWeight line2Weight = empty ? FontWeight.w500 : FontWeight.w600;

    final bool layoutTimeline =
        mockupLayoutCampo && estilo != null && !legacyRutaCampos;
    final double radioCampo = layoutTimeline ? 16 : 14;

    final TextStyle estiloTituloCampo = TextStyle(
      color: labelColor,
      fontWeight: FontWeight.w800,
      fontSize: layoutTimeline ? 14 : 13,
      letterSpacing: layoutTimeline ? 0.15 : 0.3,
    );
    final TextStyle estiloSubCampo = TextStyle(
      color: line2Color,
      fontSize: layoutTimeline ? 14.5 : 15,
      fontWeight: line2Weight,
      height: 1.25,
    );

    final Widget contenidoFila = layoutTimeline
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(estilo.icono, size: 22, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            label,
                            style: estiloTituloCampo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: chevronColor, size: 22),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      empty ? 'Toca para elegir dirección…' : value!,
                      style: estiloSubCampo,
                    ),
                  ],
                ),
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (estilo != null) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(estilo.icono, size: 22, color: iconColor),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label, style: estiloTituloCampo),
                    const SizedBox(height: 6),
                    Text(
                      empty ? 'Toca para elegir dirección…' : value!,
                      style: estiloSubCampo,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: chevronColor, size: 22),
            ],
          );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radioCampo),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: gradienteMockupDestino == null ? fill : null,
            gradient: gradienteMockupDestino,
            borderRadius: BorderRadius.circular(radioCampo),
            border: Border.all(color: border, width: borderW),
            boxShadow: shadows,
          ),
          child: contenidoFila,
        ),
      ),
    );
  }
}
