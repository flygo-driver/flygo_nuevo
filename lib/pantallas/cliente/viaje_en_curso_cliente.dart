// lib/pantallas/cliente/viaje_en_curso_cliente.dart
// ignore_for_file: avoid_print -- [VIAJE_ACTIVO] / [FINALIZAR]

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/widgets/viaje_overlay_error_shield.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/telefono_viaje.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/cliente_viaje_data_merge.dart';
import 'package:flygo_nuevo/utils/cliente_viaje_estado_efectivo.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/utils/multiparada_ruta_helper.dart';
import 'package:flygo_nuevo/utils/viaje_navegacion_resolver.dart';
import 'package:flygo_nuevo/widgets/multiparada_navegacion_tarjetas.dart';
import 'package:flygo_nuevo/servicios/finance_config_service.dart';
import 'package:flygo_nuevo/utils/pago_tarjeta_cliente_gate.dart';
import 'package:flygo_nuevo/widgets/rai_pago_tarjeta_panel.dart';
import 'package:flygo_nuevo/widgets/viaje_metodo_pago_selector.dart';
import 'package:flygo_nuevo/widgets/tarjeta_pago_estado_viaje.dart';
import 'package:flygo_nuevo/utils/release_build_flags.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/cliente_metodo_pago_viaje_ui.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/navegacion_externa_launcher.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/servicios/rai_local_read_cache.dart';
import 'package:flygo_nuevo/servicios/error_auth_es.dart';
import 'package:flygo_nuevo/utils/chat_viaje_nav.dart';
import 'package:flygo_nuevo/widgets/viaje_chat_mapa_overlay.dart';
import 'package:flygo_nuevo/navegacion/post_viaje_cliente_nav.dart';
import 'package:flygo_nuevo/widgets/cliente_post_viaje_reopen_guard.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/drivers_location_nearby_repo.dart';
import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/widgets/cliente_espera_taxista_panel.dart';
import 'package:flygo_nuevo/widgets/cliente_viaje_conductor_asignado_panel.dart';
import 'package:flygo_nuevo/widgets/cliente_viaje_espera_cronometro.dart';
import 'package:flygo_nuevo/widgets/cliente_viaje_live_conductores.dart';
import 'package:flygo_nuevo/widgets/mapa_tiempo_real.dart';
import 'package:flygo_nuevo/utils/rai_live_marker_animator.dart';
import 'package:flygo_nuevo/widgets/rai_live_driver_map_animator.dart';
import 'package:flygo_nuevo/widgets/rai_map_vehicle_icons.dart';
import 'package:flygo_nuevo/utils/rai_map_presentation.dart';
import 'package:flygo_nuevo/widgets/navegacion_waze_maps_sheet.dart';
import 'package:flygo_nuevo/servicios/pool_timbre_session_guard.dart';
import 'package:flygo_nuevo/servicios/notification_service.dart';
import 'package:flygo_nuevo/servicios/viaje_comunicacion_repo.dart';
import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/widgets/cliente_pantalla_viaje_activo.dart';
import 'package:flygo_nuevo/widgets/viaje_chat_mensajes_en_vivo.dart';
import 'package:flygo_nuevo/utils/transferencia_recaudo_ui.dart';
import 'package:flygo_nuevo/utils/viaje_codigo_verificacion_helper.dart';
import 'package:flygo_nuevo/widgets/viaje_flujo_orientacion.dart';
import 'package:flygo_nuevo/widgets/rai_viaje_en_curso_ui.dart';

part 'viaje_en_curso_cliente_pin_sync.dart';
part 'viaje_en_curso_cliente_pin_widgets.dart';

// ===== Helpers =====
LatLng _latLng(double lat, double lon) => LatLng(lat, lon);

bool _isValidCoord(double lat, double lon) =>
    lat.isFinite &&
    lon.isFinite &&
    !(lat == 0 && lon == 0) &&
    lat >= -90 &&
    lat <= 90 &&
    lon >= -180 &&
    lon <= 180;

GeoPoint? _geoPointSeguro(Object? raw) {
  if (raw is GeoPoint) return raw;
  if (raw is Map) {
    final lat = raw['latitude'] ?? raw['lat'];
    final lon = raw['longitude'] ?? raw['lng'] ?? raw['lon'];
    if (lat is num && lon is num) {
      return GeoPoint(lat.toDouble(), lon.toDouble());
    }
  }
  return null;
}

String _safeFecha(DateTime? dt) {
  try {
    return dt == null ? '—' : DateFormat('dd/MM/yyyy - HH:mm').format(dt);
  } catch (_) {
    return '—';
  }
}

String _safeMoney(num? n) {
  try {
    return FormatosMoneda.rd((n ?? 0).toDouble());
  } catch (_) {
    return FormatosMoneda.rd(0);
  }
}

/// Barra lineal (evita doble círculo con el diálogo de bloqueo; más actual que el spinner).
Widget _cargaLinealOscura({String? mensaje}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 4,
              color: Colors.greenAccent,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          if (mensaje != null && mensaje.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ],
      ),
    ),
  );
}

bool _esPermisoDenegadoFirestore(Object? e) {
  if (e is FirebaseException) {
    return e.code == 'permission-denied';
  }
  final String s = e.toString().toLowerCase();
  return s.contains('permission-denied') || s.contains('permission_denied');
}

String _s(Object? x) => x?.toString() ?? '';

double _taxistaHueByEstado(String estado) {
  final String e = EstadosViaje.normalizar(estado);
  if (e == EstadosViaje.aceptado || e == EstadosViaje.enCaminoPickup) {
    return BitmapDescriptor.hueRed;
  }
  if (e == EstadosViaje.aBordo || e == EstadosViaje.enCurso) {
    return BitmapDescriptor.hueOrange;
  }
  return BitmapDescriptor.hueYellow;
}

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const double R = 6371.0;
  final double dLat = (lat2 - lat1) * math.pi / 180.0;
  final double dLon = (lon2 - lon1) * math.pi / 180.0;
  final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}

/// Firma del documento de viaje para el mapa / UI: ignora campos de alta frecuencia irrelevantes (timestamps, etc.).
String _viajeDocMapUiSig(DocumentSnapshot<Map<String, dynamic>> ds) {
  if (!ds.exists) return '';
  final Map<String, dynamic> d = ds.data() ?? {};
  // ~11 m: marcador del taxista se mueve, pero no reconstruye todo el árbol en cada ping.
  String r4(Object? n) {
    if (n is num && n.isFinite) return n.toStringAsFixed(4);
    return 'x';
  }

  final String est = EstadosViaje.normalizar((d['estado'] ?? '').toString());
  final Object? dLat = d['driverLat'] ?? d['latTaxista'];
  final Object? dLon = d['driverLon'] ?? d['lonTaxista'];
  final String tid = (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString();
  final bool codigoOk = d['codigoVerificado'] == true;
  final bool completado = d['completado'] == true;
  final int wp = (d['waypoints'] is List) ? (d['waypoints'] as List).length : 0;
  final String codPin =
      (d['codigoVerificacion'] ?? d['codigo_verificacion'] ?? '').toString();
  final bool clienteAbordo = d['clienteAbordo'] == true;
  final dynamic exAb = d['extras'];
  final bool clienteAbordoExtras = exAb is Map && exAb['clienteAbordo'] == true;

  return '${ds.id}|$est|${r4(dLat)}|${r4(dLon)}|${r4(d['latCliente'])}|${r4(d['lonCliente'])}|'
      '${r4(d['latDestino'])}|${r4(d['lonDestino'])}|$tid|$codigoOk|$completado|'
      '${d['metodoPago']}|${d['precio']}|$wp|$codPin|${d['multiparadaLegCompletadas']}|${d['multiparadaCompleta']}|'
      '$clienteAbordo|$clienteAbordoExtras|'
      '${d['nombreTaxista']}|${d['telefonoTaxista']}|${d['telefono']}';
}

class ViajeEnCursoCliente extends StatefulWidget {
  /// Cuando es hijo de [ClientePantallaViajeActivo], la espera turismo la resuelve el router.
  final bool delegarEsperaTurismoAlRouter;

  const ViajeEnCursoCliente({
    super.key,
    this.delegarEsperaTurismoAlRouter = false,
  });

  @override
  State<ViajeEnCursoCliente> createState() => _ViajeEnCursoClienteState();
}

class _ViajeEnCursoClienteState extends State<ViajeEnCursoCliente>
    with
        TickerProviderStateMixin,
        WidgetsBindingObserver,
        _ViajeEnCursoClientePinSync,
        _ViajeEnCursoClientePinWidgets {
  /// Pruebas en silla: solo debug/profile con define; nunca en Play Store.
  bool get _simCasa => ReleaseBuildFlags.simCasaEnabled;

  /// Forzar “conductor cerca del pickup” sin GPS real (solo [_simCasa]).
  bool _debugConductorCercaPickup = false;

  GoogleMapController? _map;
  bool _myLoc = false;

  final Map<PolylineId, Polyline> _polylines = {};
  Timer? _routeDebounce;

  String _lastRouteKey = '';
  String _lastBoundsKey = '';

  /// Último snapshot del viaje para no mostrar pantalla negra si el stream reconecta.
  DocumentSnapshot<Map<String, dynamic>>? _lastViajeUiCache;


  /// Evita avisar dos veces al cliente que el conductor canceló (una por marca de tiempo).
  DateTime? _cancelacionTaxistaAvisada;

  /// Para evitar abrir la pantalla de Factura más de una vez por viaje.
  String _postViajeFlujoIniciadoParaViajeId = '';

  /// Multiparada: destinos ya visitados (solo UI cliente; prefs por viaje).
  int _multiLegCompletadas = 0;
  final Set<int> _clienteMultiNavLegIndices = <int>{};
  bool _clienteOrigenMultiNavAbierto = false;
  String? _clienteMultiNavViajeId;
  String? _multiNavLoadedForViajeId;

  /// Publica la posición del cliente en el documento del viaje (Firestore en vivo).
  StreamSubscription<Position>? _clienteViajePosSub;
  String? _clienteViajePosViajeId;

  /// Evita solapar varias corridas de [_ensureClienteUbicacionEnViaje] (mismo viaje).
  String? _clienteViajeUbicacionEnsuringFor;

  /// Tras fallo de permiso o GPS apagado en este viaje, no reintentar en cada
  /// rebuild del stream; se limpia al [AppLifecycleState.resumed].
  String? _clienteViajeUbicacionPermisoDenegadoViajeId;

  /// Seguimiento automático de cámara al taxista (el usuario puede soltar con gesto en el mapa).
  bool _seguirTaxistaCamara = true;
  DateTime? _ultimoSeguimientoTaxistaMs;
  double? _ultimoSeguimientoTaxLat;
  double? _ultimoSeguimientoTaxLon;
  LatLng? _prevTaxistaMarkerPos;
  double _bearingTaxista = 0;
  static const String _kTaxistaAnimId = 'taxista';
  late final RaiLiveMarkerAnimator _taxistaAnim;
  late final RaiLiveDriverMapAnimator _poolDriverAnim;
  Viaje? _viajeCamaraFollowCache;
  String _estadoCamaraFollowCache = '';

  /// Cámara movida por código (no colapsar/expandir tarjeta como si fuera gesto del usuario).
  int _programmaticCameraDepth = 0;
  Timer? _mapGestureEndDebounce;

  /// Última fase en la que se auto-expandió el sheet (permite re-expandir al cambiar fase).
  String? _sheetAutoExpandFaseClave;

  /// Última fase UI del sheet (pickup vs a bordo) para re-expandir al marcar abordo.
  String? _sheetFaseUiViajeId;
  bool _sheetFaseUiEsAbordo = false;
  final DraggableScrollableController _viajeSheetCtrl =
      DraggableScrollableController();
  static const double _kViajeSheetMinNormal = 0.22;
static const double _kViajeSheetMinMultiparada = 0.30;

  /// Panel inicial con conductor asignado / en ruta.
  static const double _kViajeSheetInitial = 0.52;

  /// Fase pickup (taxista viene al cliente): sheet bajo para ver más mapa.
  static const double _kViajeSheetPickupCompact = 0.48;

  /// A bordo + PIN: altura inicial para ver código sin pelear con el scroll.
  static const double _kViajeSheetAbordoPin = 0.78;

  /// Mínimo en abordo+PIN: evita tarjeta tan baja que el gesto quede atascado.
  static const double _kViajeSheetMinAbordoPin = 0.40;

  /// Esperando que un taxista acepte: más alto para que el mensaje y acciones se lean bien.
  static const double _kViajeSheetEsperaConductor = 0.56;

  static const Duration _kViajeSheetSnapDuration =
      Duration(milliseconds: 360);

  static const Duration _kViajeSheetAnimDuration = _kViajeSheetSnapDuration;
  static const Curve _kViajeSheetAnimCurve = Curves.easeOutCubic;

  /// Snap graduado: varios escalones para que el arrastre se sienta suave.
  static List<double> _snapSizesViajeCliente({
    required double minSize,
    required List<double> hitos,
    double max = 0.94,
  }) {
    final Set<double> unicos = <double>{minSize, max};
    for (final double h in hitos) {
      unicos.add(h.clamp(minSize, max));
    }
    final List<double> orden = unicos.toList()..sort();
    final List<double> graduado = <double>[];
    for (int i = 0; i < orden.length; i++) {
      graduado.add(orden[i]);
      if (i < orden.length - 1) {
        final double a = orden[i];
        final double b = orden[i + 1];
        if (b - a > 0.11) {
          graduado.add(double.parse(((a + b) / 2).toStringAsFixed(3)));
        }
      }
    }
    return graduado.toSet().toList()..sort();
  }

  static const int _kSheetExpandMaxReintentos = 60;
  double _sheetExpandedTarget = _kViajeSheetInitial;

  /// Si el controlador no estaba listo, reintentar en el próximo frame.
  double? _sheetExpandPendienteTarget;

  /// Último gesto manual del usuario sobre el sheet (evita pelear con auto-expand).
  DateTime? _sheetUltimoGestUsuario;
  double? _sheetTamanoPrevio;

  /// Touch/scroll activo: bloquea animateTo programático (causa #1 de touch muerto en device).
  bool _sheetPointerActivo = false;
  bool _sheetScrollArrastrando = false;
  DateTime? _sheetUltimaRecuperacionAtascado;
  String? _sheetUltimoExpandSigProgramado;

  /// El cliente colapsó el sheet en abordo+PIN: no forzar re-expansión automática.
  bool _sheetAbordoColapsoUsuario = false;

  /// Evita re-forzar expand al mismo PIN en cada rebuild.
  String? _sheetPinAbordoExpandSig;

  /// Scroll interno del sheet (compartido con DraggableScrollableSheet).
  ScrollController? _viajeSheetScrollCtrl;

  /// Cache de fase abordo+PIN para callbacks del mapa (se actualiza en build).
  bool _faseAbordoPinUiCache = false;

  /// ETA taxista → pickup (Directions con tráfico, con fallback).
  String? _pickupEtaTitulo;
  String? _pickupEtaDetalle;
  bool _pickupEtaMinimizado = false;
  Timer? _pickupEtaDebounce;
  String _pickupEtaSigPendiente = '';
  DateTime? _pickupEtaUltimoHttp;
  String _pickupEtaSigUltimoHttp = '';

  // Variables para control de auto-centrado y cercanía
  bool _mostrarMensajeCercania = false;
  Timer? _mensajeCercaniaTimer;
  bool? _lastPickupProximity;
  bool _subiendoComprobanteTransfer = false;
  bool _cancelandoViajeCliente = false;
  bool _yendoAlInicio = false;
  bool _salidaAutoSinViajeDisparada = false;
  bool _clienteNavDestinoUsado = false;
  int _clienteNavOrientacionLegDismissed = -1;

  /// Re-asignación turismo tras cancelación del chofer (misma cadencia que [EsperaAsignacionTurismo]).
  Timer? _turismoReasignacionTimer;
  bool _turismoReasignacionEnCurso = false;
  String _turismoReasignacionViajeId = '';
  String? _turismoRedirEsperaViajeId;
  bool _turismoRedirEsperaEnCurso = false;

  /// Último viaje activo visto (para pantalla de cierre cuando `viajeActivoId` ya se limpió en servidor).
  String _lastNonEmptyViajeActivoId = '';
  String _bootstrapViajeIntentadoId = '';
  int _bootstrapViajeUltimoIntentoMs = 0;
  String _viajeDatosOfflineId = '';
  Map<String, dynamic>? _viajeDatosOffline;
  DocumentSnapshot<Map<String, dynamic>>? _viajeCierreDocSnap;
  String? _viajeCierreFetchKey;

  /// Evita abrir dos veces el flujo post-viaje para el mismo id.
  String? _navPostViajeParaId;
  bool _abriendoFlujoPostViaje = false;
  bool _postViajeRequiereAccionManual = false;
  String? _postViajeManualViajeId;
  Map<String, dynamic>? _postViajeManualSemilla;
  Timer? _postViajeTimeoutTimer;

  /// Tras cancelar desde esta pantalla: no abrir factura/post-viaje (solo completados).
  String? _viajeIdCanceladoPorCliente;

  /// Evita bucle irAlInicio ↔ overlay cuando el taxista cancela.
  String? _salidaCierreIniciadaParaViajeId;
  bool _snackCancelConductorMostrado = false;

  // Conductores disponibles (consulta geohash — escala)
  DriversLocationNearbySession? _nearbyDriversSession;
  List<DocumentSnapshot<Map<String, dynamic>>> _driversList = [];
  String _lastDriversPoolSig = '';
  Map<String, String?> _driverFotoPorUid = <String, String?>{};
  Timer? _fotosDebounce;
  late final AnimationController _radarCtrl;
  late final AnimationController _progresoBrilloCtrl;

  /// Evita spam del snack al volver de Waze/Maps.
  DateTime? _lastClienteNavResumeSnackAt;
  DateTime? _lastClienteGpsSistemaSnackAt;

  /// Tras retomar/remontar overlay, ignorar PopScope espurio un instante.
  bool _suprimirPopScopeAutomatico = true;
  Timer? _popScopeSuprimidoTimer;

  /// Mapa nativo: montar tras el 1.er frame. Si falla (ErrorWidget), reintento auto.
  bool _mapaPermitido = false;
  bool _mapaDesactivadoPorError = false;
  Timer? _mapaAutoRetryTimer;
  int _mapaAutoRetryIntentos = 0;
  static const int _kMapaAutoRetryMax = 6;

   @override
  void initState() {
    super.initState();
    final String vidInicial =
        ActiveTripService.resolverViajeIdClienteParaPausa();
    if (vidInicial.isNotEmpty) {
      _lastNonEmptyViajeActivoId = vidInicial;
      ActiveTripService.registrarViajeOperativoCliente(vidInicial);
    }
    PoolTimbreSessionGuard.activarSesionPasajero();
    NotificationService.I.suprimirTimbrePoolCliente();
    WidgetsBinding.instance.addObserver(this);
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _progresoBrilloCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _taxistaAnim = RaiLiveMarkerAnimator(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      onTick: () {
        if (!mounted) return;
        setState(() {});
        _actualizarCamaraSeguimientoAnimado();
      },
    );
    _poolDriverAnim = RaiLiveDriverMapAnimator(vsync: this)
      ..onFrame = () {
        if (mounted) setState(() {});
      };
    unawaited(RaiMapVehicleIcons.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    }));
    _enableMyLocation();
    _lastNotifiedState = '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Mapa entra al siguiente frame (evita setState en build). Si el shield
      // forzó sin mapa o ya falló, la ficha del viaje sigue visible.
      if (ViajeSinMapaScope.of(context)) {
        _marcarMapaFallido(programarReintento: true);
      } else {
        setState(() {
          _mapaPermitido = true;
          _mapaDesactivadoPorError = false;
          _mapaAutoRetryIntentos = 0;
        });
      }
      unawaited(_verificarViajeTerminadoAlAbrirCliente());
      unawaited(_bootstrapViajeClienteAlAbrir());
    });

    _viajeSheetCtrl.addListener(_onViajeSheetUsuarioGest);

    ActiveTripService.markClienteTripScreenMounted();
    final bool retomarActivo = ActiveTripService.retomarClienteEnCurso;
    _suprimirPopScopeAutomatico = true;
    _popScopeSuprimidoTimer = Timer(
      Duration(milliseconds: retomarActivo ? 12000 : 900),
      () {
      if (!mounted) return;
      setState(() => _suprimirPopScopeAutomatico = false);
    },
    );
  }

  void _marcarMapaFallido({bool programarReintento = true}) {
    if (!mounted) return;
    setState(() {
      _mapaDesactivadoPorError = true;
      _mapaPermitido = false;
    });
    if (programarReintento) {
      _programarReintentoMapaAutomatico();
    }
  }

  void _programarReintentoMapaAutomatico({
    Duration delay = const Duration(milliseconds: 1200),
    bool resetIntentos = false,
  }) {
    if (!mounted) return;
    if (resetIntentos) _mapaAutoRetryIntentos = 0;
    if (_mapaAutoRetryIntentos >= _kMapaAutoRetryMax) return;
    _mapaAutoRetryTimer?.cancel();
    _mapaAutoRetryTimer = Timer(delay, () {
      if (!mounted) return;
      _mapaAutoRetryIntentos++;
      setState(() {
        _mapaDesactivadoPorError = false;
        _mapaPermitido = true;
      });
    });
  }

  void _reintentarMapaViajeManual() {
    _mapaAutoRetryTimer?.cancel();
    _mapaAutoRetryIntentos = 0;
    if (!mounted) return;
    setState(() {
      _mapaDesactivadoPorError = false;
      _mapaPermitido = true;
    });
  }

  Future<void> _verificarViajeTerminadoAlAbrirCliente() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || !mounted) return;
    print('[VIAJE_ACTIVO] cliente en_curso init: verificar si viaje ya cerró');
    try {
      String resolvedViajeId =
          ActiveTripService.resolverViajeIdClienteParaPausa();
      if (resolvedViajeId.isEmpty) {
        resolvedViajeId = _lastNonEmptyViajeActivoId.trim();
      }

      final us = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(u.uid)
          .get(const GetOptions(source: Source.server));
      final String vidUsuario =
          (us.data()?['viajeActivoId'] ?? '').toString().trim();
      if (resolvedViajeId.isEmpty) {
        resolvedViajeId = vidUsuario;
      }
      if (resolvedViajeId.isNotEmpty) {
        _lastNonEmptyViajeActivoId = resolvedViajeId;
        ActiveTripService.registrarViajeOperativoCliente(resolvedViajeId);
      }

      Map<String, dynamic>? d;
      bool lecturaDenegada = false;

      if (resolvedViajeId.isNotEmpty) {
        try {
          final vs = await FirebaseFirestore.instance
              .collection('viajes')
              .doc(resolvedViajeId)
              .get(const GetOptions(source: Source.server));
          if (vs.exists) d = vs.data();
        } on FirebaseException catch (e) {
          if (_esPermisoDenegadoFirestore(e)) lecturaDenegada = true;
        } catch (e) {
          if (_esPermisoDenegadoFirestore(e)) lecturaDenegada = true;
        }
      }

      if (d == null && resolvedViajeId.isNotEmpty && !lecturaDenegada) {
        for (int i = 0; i < 3; i++) {
          await Future<void>.delayed(Duration(milliseconds: 350 * (i + 1)));
          if (!mounted) return;
          try {
            final DocumentSnapshot<Map<String, dynamic>> retry =
                await FirebaseFirestore.instance
                    .collection('viajes')
                    .doc(resolvedViajeId)
                    .get(const GetOptions(source: Source.server));
            if (retry.exists) {
              d = retry.data();
              break;
            }
          } catch (e) {
            if (_esPermisoDenegadoFirestore(e)) {
              lecturaDenegada = true;
              break;
            }
          }
        }
      }

      if (lecturaDenegada) {
        print(
          '[VIAJE_ACTIVO] cliente init: lectura viaje limitada, esperar stream',
        );
        return;
      }

      if (d == null || !mounted || resolvedViajeId.isEmpty) {
        if (mounted &&
            resolvedViajeId.isNotEmpty &&
            d == null &&
            !_yendoAlInicio) {
          unawaited(_salirTrasViajeDesaparecido(
            viajeId: resolvedViajeId,
            uid: u.uid,
            origen: 'initDocInexistente',
          ));
        }
        return;
      }

      _manejarViajeCerradoSiCorresponde(
        viajeId: resolvedViajeId,
        uid: u.uid,
        data: d,
        origen: 'init',
      );
    } catch (e) {
      if (_esPermisoDenegadoFirestore(e)) {
        print(
          '[VIAJE_ACTIVO] cliente init: usuarios/viaje limitado, esperar stream',
        );
        return;
      }
      print('[VIAJE_ACTIVO] cliente init check error: $e');
    }
  }



    @override
  void dispose() {
    _mapaAutoRetryTimer?.cancel();
    _map?.dispose();
    _routeDebounce?.cancel();
    _disposeDocWatch();
    _stopClienteUbicacionEnViaje();
    _mensajeCercaniaTimer?.cancel();
    _nearbyDriversSession?.dispose();
    _fotosDebounce?.cancel();
    _radarCtrl.dispose();
    _progresoBrilloCtrl.dispose();
    _pickupEtaDebounce?.cancel();
    _mapGestureEndDebounce?.cancel();
    _viajeSheetCtrl.removeListener(_onViajeSheetUsuarioGest);
    _viajeSheetCtrl.dispose();
    _taxistaAnim.dispose();
    _poolDriverAnim.dispose();
    _stopTurismoReasignacionTimer();
    _stopClienteViajeSyncPulse();
    _postViajeTimeoutTimer?.cancel();
    _popScopeSuprimidoTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);

    ActiveTripService.markClienteTripScreenUnmounted();
    super.dispose();
  }


  void _syncTaxistaAnimador(Viaje v) {
    if (v.uidTaxista.isEmpty || !_isValidCoord(v.latTaxista, v.lonTaxista)) {
      _taxistaAnim.clear();
      return;
    }
    final LatLng target = _latLng(v.latTaxista, v.lonTaxista);
    final double? nuevoBearing = RaiMapVehicleIcons.bearingEntre(
      _prevTaxistaMarkerPos,
      target,
    );
    if (nuevoBearing != null) _bearingTaxista = nuevoBearing;
    _prevTaxistaMarkerPos = target;
    _taxistaAnim.syncTargets(
      <String, LatLng>{_kTaxistaAnimId: target},
      headings: <String, double?>{_kTaxistaAnimId: _bearingTaxista},
    );
  }

  LatLng _posTaxistaAnimada(Viaje v) {
    if (!_isValidCoord(v.latTaxista, v.lonTaxista)) {
      return const LatLng(0, 0);
    }
    final LatLng raw = _latLng(v.latTaxista, v.lonTaxista);
    return _taxistaAnim.position(_kTaxistaAnimId, raw);
  }

  double _bearingTaxistaAnimado() {
    return _taxistaAnim.bearing(_kTaxistaAnimId, fallback: _bearingTaxista);
  }

  bool _clienteEnFlujoPostViajeOCompletado() {
    if (_abriendoFlujoPostViaje ||
        _navPostViajeParaId != null ||
        _postViajeFlujoIniciadoParaViajeId.isNotEmpty) {
      return true;
    }
    final Map<String, dynamic>? cache = _lastViajeUiCache?.data();
    if (cache != null && _viajeClienteCompletadoParaPostViaje(cache)) {
      return true;
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      print('[VIAJE_ACTIVO] cliente lifecycle resumed');
      ActiveTripService.mantenerOverlayViajeEnShell(
        NavigationService.kOverlayClienteViajeActivo,
      );
      if (_clienteEnFlujoPostViajeOCompletado()) {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
        return;
      }
      if (_mapaDesactivadoPorError || !_mapaPermitido) {
        _programarReintentoMapaAutomatico(
          delay: const Duration(milliseconds: 400),
          resetIntentos: true,
        );
      }
      _clienteViajeUbicacionPermisoDenegadoViajeId = null;
      // Al volver de la app taxista: cache→server y PIN sin salir/entrar.
      unawaited(_refrescarViajeActivoClienteResume());
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Mientras cambias a la app taxista, el pulso sigue activo si el SO lo permite.
      final String? vid = _syncPulseViajeId;
      if (vid != null && vid.isNotEmpty) {
        ActiveTripService.registrarViajeOperativoCliente(vid);
        final String? uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.trim().isNotEmpty) {
          unawaited(RaiLocalReadCache.rememberActiveTripId(uid, vid));
        }
        _startClienteViajeSyncPulse(vid, forceRestart: true, rapido: true);
      }
    }
  }

  void _stopClienteUbicacionEnViaje() {
    _clienteViajePosSub?.cancel();
    _clienteViajePosSub = null;
    _clienteViajePosViajeId = null;
    _clienteViajeUbicacionEnsuringFor = null;
    _clienteViajeUbicacionPermisoDenegadoViajeId = null;
  }

  void _maybeSnackActivarGpsSistemaCliente() {
    final DateTime now = DateTime.now();
    if (_lastClienteGpsSistemaSnackAt != null &&
        now.difference(_lastClienteGpsSistemaSnackAt!) <
            const Duration(seconds: 14)) {
      return;
    }
    _lastClienteGpsSistemaSnackAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Activa la ubicación del teléfono (GPS). Así el conductor puede verte.',
          ),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Ubicación',
            onPressed: () => unawaited(GpsService.openLocationSettings()),
          ),
        ),
      );
    });
  }

  Future<void> _ensureClienteUbicacionEnViaje(String viajeId) async {
    if (_clienteViajePosViajeId == viajeId && _clienteViajePosSub != null) {
      return;
    }
    if (_clienteViajeUbicacionPermisoDenegadoViajeId == viajeId) {
      return;
    }
    if (_clienteViajeUbicacionEnsuringFor == viajeId) {
      return;
    }
    _clienteViajeUbicacionEnsuringFor = viajeId;
    try {
      await _clienteViajePosSub?.cancel();
      _clienteViajePosSub = null;

      // Nunca [Geolocator.requestPermission] aquí: el builder puede re-ejecutar
      // al volver de segundo plano / Waze; solo lectura estabilizada.
      final ({bool serviceEnabled, LocationPermission permission}) snap =
          await GpsService.readServiceAndPermissionStabilizedNoRequest();
      if (!snap.serviceEnabled) {
        _clienteViajeUbicacionPermisoDenegadoViajeId = viajeId;
        _maybeSnackActivarGpsSistemaCliente();
        return;
      }
      final LocationPermission perm = snap.permission;
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _clienteViajeUbicacionPermisoDenegadoViajeId = viajeId;
        return;
      }

      _clienteViajePosViajeId = viajeId;

      final LocationSettings settings =
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
              ? AndroidSettings(
                  accuracy: LocationAccuracy.high,
                  distanceFilter: 8,
                  intervalDuration: const Duration(seconds: 2),
                )
              : const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  distanceFilter: 10,
                );

      final DocumentReference<Map<String, dynamic>> ref =
          FirebaseFirestore.instance.collection('viajes').doc(viajeId);
      _clienteViajePosSub =
          Geolocator.getPositionStream(locationSettings: settings).listen(
        (Position p) async {
          try {
            await ref.set(
              {
                'latCliente': p.latitude,
                'lonCliente': p.longitude,
                'updatedAt': FieldValue.serverTimestamp(),
                'actualizadoEn': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          } catch (_) {}
        },
        onError: (_) {},
      );
    } finally {
      if (_clienteViajeUbicacionEnsuringFor == viajeId) {
        _clienteViajeUbicacionEnsuringFor = null;
      }
    }
  }

  void _maybeAnimarCamaraAlTaxista(Viaje v, String estadoBase) {
    _viajeCamaraFollowCache = v;
    _estadoCamaraFollowCache = estadoBase;
    _ejecutarSeguimientoCamaraTaxista(v, estadoBase);
  }

  void _actualizarCamaraSeguimientoAnimado() {
    final Viaje? v = _viajeCamaraFollowCache;
    if (v == null) return;
    _ejecutarSeguimientoCamaraTaxista(v, _estadoCamaraFollowCache);
  }

  void _ejecutarSeguimientoCamaraTaxista(Viaje v, String estadoBase) {
    if (!_seguirTaxistaCamara) return;
    if (!_isValidCoord(v.latTaxista, v.lonTaxista)) return;
    if (v.uidTaxista.isEmpty) return;
    if (!(estadoBase == EstadosViaje.aceptado ||
        estadoBase == EstadosViaje.enCaminoPickup ||
        estadoBase == EstadosViaje.enCurso ||
        (estadoBase == EstadosViaje.aBordo && v.codigoVerificado))) {
      return;
    }

    final DateTime now = DateTime.now();
    if (_ultimoSeguimientoTaxistaMs != null &&
        now.difference(_ultimoSeguimientoTaxistaMs!) <
            const Duration(milliseconds: 520)) {
      return;
    }

    _syncTaxistaAnimador(v);
    final LatLng taxiPos = _posTaxistaAnimada(v);

    if (_ultimoSeguimientoTaxLat != null && _ultimoSeguimientoTaxLon != null) {
      final double dKm = _haversineKm(
        _ultimoSeguimientoTaxLat!,
        _ultimoSeguimientoTaxLon!,
        taxiPos.latitude,
        taxiPos.longitude,
      );
      if (dKm < 0.002) {
        return;
      }
    }

    _ultimoSeguimientoTaxistaMs = now;
    _ultimoSeguimientoTaxLat = taxiPos.latitude;
    _ultimoSeguimientoTaxLon = taxiPos.longitude;

    final GoogleMapController? c = _map;
    if (c == null) return;

    final List<LatLng> framePts = <LatLng>[taxiPos];
    final bool haciaDestino = estadoBase == EstadosViaje.enCurso ||
        (estadoBase == EstadosViaje.aBordo && v.codigoVerificado);
    if (haciaDestino && _isValidCoord(v.latDestino, v.lonDestino)) {
      framePts.add(_latLng(v.latDestino, v.lonDestino));
    } else if (_isValidCoord(v.latCliente, v.lonCliente)) {
      framePts.add(_latLng(v.latCliente, v.lonCliente));
    }

    _programmaticCameraDepth++;
    if (framePts.length >= 2) {
      final LatLngBounds bounds = RaiMapPresentation.boundsFromPoints(framePts);
      final double padding = haciaDestino ? 108.0 : 124.0;
      unawaited(
        RaiMapPresentation.fitBounds(
          c,
          bounds,
          padding: padding,
          maxZoom: haciaDestino ? 16.2 : 16.0,
        ).then((_) {}, onError: (_) {
          if (_programmaticCameraDepth > 0) _programmaticCameraDepth--;
        }),
      );
      return;
    }

    c
        .animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: taxiPos,
          zoom: RaiMapPresentation.followZoomDriver,
          bearing: _bearingTaxistaAnimado(),
          tilt: haciaDestino ? 0 : 28,
        ),
      ),
    )
        .then((_) {}, onError: (_) {
      if (_programmaticCameraDepth > 0) _programmaticCameraDepth--;
    });
  }

  void _onViajeSheetUsuarioGest() {
    if (!_viajeSheetCtrl.isAttached) return;
    final double size = _viajeSheetCtrl.size;
    final double? prev = _sheetTamanoPrevio;
    _sheetTamanoPrevio = size;
    if (prev != null && (size - prev).abs() > 0.008) {
      _sheetUltimoGestUsuario = DateTime.now();
      if (_sheetFaseUiEsAbordo) {
        _sheetAbordoColapsoUsuario = size < _kViajeSheetAbordoPin - 0.06;
      }
    }
  }

  /// Colapso por tap en mapa: posición compacta (~48%), no el mínimo absoluto.
  double _targetColapsoSheetPorTapMapa() {
    if (_sheetExpandedTarget >= _kViajeSheetInitial - 0.02) {
      return _kViajeSheetInitial;
    }
    if (_sheetExpandedTarget >= _kViajeSheetEsperaConductor - 0.02) {
      return _kViajeSheetEsperaConductor;
    }
    return _kViajeSheetPickupCompact;
  }

  bool _sheetUsuarioInteractuandoAhora() {
    return _sheetPointerActivo || _sheetScrollArrastrando;
  }

  void _finalizarInteraccionSheetUsuario() {
    _sheetPointerActivo = false;
    _sheetScrollArrastrando = false;
    if (_sheetFaseUiEsAbordo &&
        _viajeSheetCtrl.isAttached &&
        _viajeSheetCtrl.size < _kViajeSheetAbordoPin - 0.06) {
      _sheetAbordoColapsoUsuario = true;
      _sheetExpandPendienteTarget = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_usuarioAcabaDeAjustarSheet() || _sheetAbordoColapsoUsuario) {
        _sheetExpandPendienteTarget = null;
        return;
      }
      _procesarSheetExpandPendiente();
    });
  }

  bool _puedeAnimarSheetProgramatico({required bool forzar}) {
    if (_sheetUsuarioInteractuandoAhora()) return false;
    if (!forzar && _usuarioAcabaDeAjustarSheet()) return false;
    return true;
  }

  bool _usuarioAcabaDeAjustarSheet() {
    final DateTime? t = _sheetUltimoGestUsuario;
    if (t == null) return false;
    return DateTime.now().difference(t) < const Duration(seconds: 10);
  }

  void _colapsarSheetPorTapMapa({double? target}) {
    final DraggableScrollableController ctrl = _sheetCtrlActivoCliente();
    if (!ctrl.isAttached) return;
    if (_sheetUsuarioInteractuandoAhora()) return;
    ctrl.animateTo(
      target ?? _targetColapsoSheetPorTapMapa(),
      duration: _kViajeSheetAnimDuration,
      curve: _kViajeSheetAnimCurve,
    );
  }

  DraggableScrollableController _sheetCtrlActivoCliente() => _viajeSheetCtrl;

  /// Al mostrar PIN a bordo: expandir tarjeta y resetear scroll (zona fija arriba).
  void prepararSheetPinAbordoVisible({
    required String viajeId,
    required String pin,
    bool forzar = true,
  }) {
    final String id = viajeId.trim();
    if (id.isEmpty) return;
    final String sig = '$id|${pin.trim()}';
    if (_sheetPinAbordoExpandSig == sig && !forzar) return;
    _sheetPinAbordoExpandSig = sig;
    _sheetAbordoColapsoUsuario = false;
    _sheetUltimoGestUsuario = null;
    _sheetExpandedTarget = _kViajeSheetAbordoPin;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _solicitarExpandirSheetCliente(
        target: _kViajeSheetAbordoPin,
        forzar: true,
      );
      final ScrollController? sc = _viajeSheetScrollCtrl;
      if (sc != null && sc.hasClients) {
        sc.jumpTo(0);
      }
    });
  }

  void _solicitarExpandirSheetCliente({
    required double target,
    bool forzar = false,
    int intento = 0,
  }) {
    if (_sheetFaseUiEsAbordo &&
        _sheetAbordoColapsoUsuario &&
        !forzar &&
        target >= _kViajeSheetAbordoPin - 0.02) {
      return;
    }
    _sheetExpandedTarget = target;
    if (!_puedeAnimarSheetProgramatico(forzar: forzar)) {
      _sheetExpandPendienteTarget = target;
      return;
    }

    final DraggableScrollableController ctrl = _sheetCtrlActivoCliente();

    if (!ctrl.isAttached) {
      _sheetExpandPendienteTarget = target;
      if (intento >= _kSheetExpandMaxReintentos) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _solicitarExpandirSheetCliente(
            target: target,
            forzar: forzar,
            intento: intento + 1,
          );
        }
      });
      return;
    }

    _sheetExpandPendienteTarget = null;

    if (!forzar) {
      final double actual = ctrl.size;
      if ((actual - target).abs() < 0.02) return;
    }

    ctrl.animateTo(
      target,
      duration: _kViajeSheetAnimDuration,
      curve: _kViajeSheetAnimCurve,
    );
  }

  void _procesarSheetExpandPendiente() {
    if (_sheetUsuarioInteractuandoAhora()) return;
    if (_usuarioAcabaDeAjustarSheet() || _sheetAbordoColapsoUsuario) {
      _sheetExpandPendienteTarget = null;
      return;
    }
    final double? pendiente = _sheetExpandPendienteTarget;
    if (pendiente == null) return;
    _solicitarExpandirSheetCliente(target: pendiente, forzar: false);
  }

  /// Re-expande tras eventos (taxista más cerca, ETA) — con debounce para no pelear con touch.
  void _intentarRecuperarSheetTrasEvento({bool forzar = false}) {
    if (_sheetFaseUiEsAbordo && _sheetAbordoColapsoUsuario && !forzar) return;
    if (!forzar && _usuarioAcabaDeAjustarSheet()) return;
    if (_sheetUsuarioInteractuandoAhora()) return;
    final DateTime now = DateTime.now();
    if (!forzar &&
        _sheetUltimaRecuperacionAtascado != null &&
        now.difference(_sheetUltimaRecuperacionAtascado!) <
            const Duration(seconds: 4)) {
      return;
    }
    final double target = _sheetExpandedTarget;
    final DraggableScrollableController ctrl = _sheetCtrlActivoCliente();
    if (!ctrl.isAttached) {
      _sheetExpandPendienteTarget = target;
      return;
    }
    if (ctrl.size < target - 0.035) {
      _sheetUltimaRecuperacionAtascado = now;
      _solicitarExpandirSheetCliente(target: target, forzar: false);
    }
  }

  double? _targetSheetPorFaseCliente({
    required Viaje v,
    required String estadoBase,
    required bool faseAbordoPin,
    required bool codigoVerificado,
    required bool faseEnRuta,
  }) {
    final bool esperandoPool = !v.esTurismo &&
        v.uidTaxista.isEmpty &&
        (estadoBase == EstadosViaje.pendiente ||
            estadoBase == EstadosViaje.pendientePago);
    final bool turismoSinConductor = v.esTurismo &&
        v.uidTaxista.isEmpty &&
        !widget.delegarEsperaTurismoAlRouter;
    final bool fasePickup = v.uidTaxista.isNotEmpty &&
        !faseAbordoPin &&
        !codigoVerificado &&
        (estadoBase == EstadosViaje.aceptado ||
            estadoBase == EstadosViaje.enCaminoPickup);

    if (faseAbordoPin && !codigoVerificado) {
      return _kViajeSheetAbordoPin;
    }
    if (faseEnRuta) {
      return _kViajeSheetInitial;
    }
    if (fasePickup) {
      return _kViajeSheetPickupCompact;
    }
    if (esperandoPool || turismoSinConductor) {
      return _kViajeSheetEsperaConductor;
    }
    return null;
  }

  String? _claveFaseSheetCliente({
    required String viajeId,
    required bool faseAbordoPin,
    required bool codigoVerificado,
    required bool faseEnRuta,
    required bool fasePickup,
    required bool esperandoConductor,
  }) {
    if (faseAbordoPin && !codigoVerificado) return '$viajeId|abordo';
    if (faseEnRuta) return '$viajeId|en_curso';
    if (fasePickup) return '$viajeId|pickup';
    if (esperandoConductor) return '$viajeId|espera';
    return null;
  }

  bool _sheetClienteAtascado(double target) {
    if (!_viajeSheetCtrl.isAttached) return _sheetExpandPendienteTarget != null;
    final double size = _viajeSheetCtrl.size;
    return size < target - 0.035 || size <= _kViajeSheetMinNormal + 0.03;
  }

  void _expandirSheetTrasMapaInteract({int intento = 0, bool forzar = false}) {
    _solicitarExpandirSheetCliente(
      target: _sheetExpandedTarget,
      forzar: forzar,
      intento: intento,
    );
  }

  /// Auto-expande la tarjeta al cambiar de fase (espera → pickup → abordo → en curso)
  /// o si quedó atascada bajo el objetivo.
  void _maybeAutoExpandirSheetPorFaseCliente({
    required Viaje v,
    required String estadoBase,
    required bool faseAbordoPin,
    required bool codigoVerificado,
    required bool faseEnRuta,
    required bool fasePickupConductor,
    required bool esperandoConductor,
  }) {
    final double? target = _targetSheetPorFaseCliente(
      v: v,
      estadoBase: estadoBase,
      faseAbordoPin: faseAbordoPin,
      codigoVerificado: codigoVerificado,
      faseEnRuta: faseEnRuta,
    );
    final String? faseClave = _claveFaseSheetCliente(
      viajeId: v.id,
      faseAbordoPin: faseAbordoPin,
      codigoVerificado: codigoVerificado,
      faseEnRuta: faseEnRuta,
      fasePickup: fasePickupConductor,
      esperandoConductor: esperandoConductor,
    );

    if (target == null || faseClave == null) return;

    _sheetExpandedTarget = target;

    final bool faseCambio = _sheetAutoExpandFaseClave != faseClave;
    if (faseAbordoPin && faseCambio) {
      _sheetAbordoColapsoUsuario = false;
    }

    final bool sheetAtascado = _sheetClienteAtascado(target);

    if (!faseCambio && !sheetAtascado) return;
    if (!faseCambio && _usuarioAcabaDeAjustarSheet()) return;
    if (sheetAtascado && !faseCambio) {
      final DateTime now = DateTime.now();
      if (_sheetUltimaRecuperacionAtascado != null &&
          now.difference(_sheetUltimaRecuperacionAtascado!) <
              const Duration(seconds: 3)) {
        return;
      }
      _sheetUltimaRecuperacionAtascado = now;
    }

    _sheetAutoExpandFaseClave = faseClave;
    _sheetFaseUiViajeId = v.id;
    _sheetFaseUiEsAbordo = faseAbordoPin;

    // Abordo+PIN: forzar expand al entrar; resto solo en cambio de fase.
    _solicitarExpandirSheetCliente(
      target: target,
      forzar: faseCambio || (faseAbordoPin && !codigoVerificado),
    );

    if (fasePickupConductor &&
        faseCambio &&
        _isValidCoord(v.latTaxista, v.lonTaxista) &&
        !_seguirTaxistaCamara) {
      setState(() => _seguirTaxistaCamara = true);
    }
  }


  List<Widget> _buildClienteAbordoSheetBodyChildren({
    required Viaje v,
    required Map<String, dynamic> data,
    required String estadoBase,
    required String estadoEfectivo,
    required bool panelConductorAsignado,
    required bool mostrarCodigoCliente,
    required bool codigoVerificado,
    required String codigoVerificacion,
    required bool mostrarBotonTocaPinGrande,
    bool pinEnZonaFija = false,
  }) {
    final List<Widget> pagoYDetalles = <Widget>[
      _wrapSelectorMetodoPago(
        v: v,
        data: data,
        estadoEfectivo: estadoBase,
      ),
      if (_mostrarAvisoTarjetaPreAbordo(v, estadoBase, data))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.deepPurpleAccent.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              PagoTarjetaClienteGate.bloqueado
                  ? 'Pago con tarjeta (en desarrollo): cuando subas al vehículo y verifiques el código '
                      'con el conductor, verás el botón para pagar desde la app antes de llegar al destino.'
                  : 'Pago con tarjeta: cuando subas al vehículo y verifiques el código '
                      'con el conductor, verás el botón para pagar desde la app antes de llegar al destino.',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ),
      if (_mostrarAvisoTransferenciaPreAbordo(v, estadoBase, data))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.amberAccent.withValues(alpha: 0.35),
              ),
            ),
            child: const Text(
              'Pago por transferencia: cuando subas al vehículo verás '
              'la cuenta del conductor para transferir. Al finalizar el viaje '
              'también recibirás el comprobante oficial con los mismos datos.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ),
      if (_mostrarDatosTransferenciaCliente(v, estadoBase, data)) ...<Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10231A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.greenAccent.withValues(alpha: 0.35),
              ),
            ),
            child: const Text(
              'Ya estás a bordo o en camino al destino. '
              'Transferí a la cuenta del conductor abajo y conservá el comprobante. '
              'Al cerrar el viaje verás la factura oficial.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ),
        _buildDatosBancarios(
          v,
          _uidTaxistaDelViaje(v, data),
          v.precio,
          data,
        ),
        const SizedBox(height: 16),
      ],
      if (_mostrarPagoTarjetaCliente(
        v,
        estadoBase,
        data,
        codigoVerificado: codigoVerificado,
      )) ...<Widget>[
        const SizedBox(height: 12),
        RaiPagoTarjetaPanel(
          viajeId: v.id,
          viajeData: data,
          montoRd: v.precio,
          fondoOscuro: true,
          role: 'cliente',
          modoViajeEnCurso: true,
        ),
        const SizedBox(height: 16),
      ] else if (_mostrarTarjetaPagadaCliente(v, estadoBase, data)) ...<Widget>[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF10231A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.greenAccent.withValues(alpha: 0.45),
            ),
          ),
          child: const Row(
            children: <Widget>[
              Icon(Icons.check_circle_outline, color: Colors.greenAccent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pago con tarjeta confirmado. '
                  'Al finalizar el viaje verás tu recibo.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ] else if (_mostrarPagoEfectivoCliente(
        v,
        estadoBase,
        data,
        codigoVerificado: codigoVerificado,
      )) ...<Widget>[
        const SizedBox(height: 12),
        EfectivoPagoClienteBanner(
          montoRd: v.precio,
          desdeTarjeta: true,
        ),
        const SizedBox(height: 16),
      ],
    ];

    return <Widget>[
      if (panelConductorAsignado && pinEnZonaFija) ...<Widget>[
        _buildDriverCard(v, soloDatosConductor: true),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _llamarConductorCliente(v),
                icon: const Icon(Icons.phone, size: 18),
                label: const Text('Llamar'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _whatsAppConductorCliente(v),
                icon: const Icon(Icons.chat, size: 18),
                label: const Text('Chat'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ] else if (panelConductorAsignado) ...<Widget>[
        ClienteViajeConductorAsignadoPanel(
          viaje: v,
          estadoBase: estadoEfectivo,
          etaLinea: _lineaEtaPickupCliente(v, estadoEfectivo),
          etaTituloHttp: _pickupEtaTitulo,
          conductorCard: _buildDriverCard(v, soloDatosConductor: true),
          pinAbordo: null,
          onLlamar: () => _llamarConductorCliente(v),
          onWhatsApp: () => _whatsAppConductorCliente(v),
          onChat: () => _abrirChatConductorCliente(v),
          onVerEnMapa: () => _centrarEnTaxista(v),
          onCentrarMapa: _isValidCoord(v.latTaxista, v.lonTaxista)
              ? () => _centrarClienteYTaxista(v)
              : null,
        ),
      ],
      if (mostrarBotonTocaPinGrande && !mostrarCodigoCliente) ...<Widget>[
        const SizedBox(height: 10),
        _buildBotonTocaActualizarViaje(
          viajeId: v.id,
          enEsperaAbordo: false,
        ),
      ],
      if (pinEnZonaFija && pagoYDetalles.isNotEmpty)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.white12),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            collapsedIconColor: Colors.white54,
            iconColor: Colors.white70,
            title: const Text(
              'Pago y detalles del viaje',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              'Toca para ver método de pago y cuenta',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
              ),
            ),
            children: pagoYDetalles,
          ),
        )
      else ...pagoYDetalles,
    ];
  }

  Widget _viajeSheetHandleCliente({
    bool mostrarHintDeslizar = false,
    bool arrastreManualHabilitado = true,
    required double minSize,
    DraggableScrollableController? sheetController,
    double maxSize = 0.94,
  }) {
    Widget handle = Semantics(
      label: 'Deslizar tarjeta del viaje',
      child: SizedBox(
        width: double.infinity,
        height: mostrarHintDeslizar ? 56 : 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white38,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            if (mostrarHintDeslizar) ...[
              const SizedBox(height: 6),
              Text(
                'Desliza hacia arriba o abajo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.42),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (!arrastreManualHabilitado) return handle;

    return _wrapArrastreManualSheet(
      habilitado: true,
      minSize: minSize,
      maxSize: maxSize,
      sheetController: sheetController,
      child: handle,
    );
  }

  Widget _wrapArrastreManualSheet({
    required Widget child,
    required bool habilitado,
    required double minSize,
    DraggableScrollableController? sheetController,
    double maxSize = 0.94,
  }) {
    if (!habilitado) return child;

    final DraggableScrollableController ctrl =
        sheetController ?? _viajeSheetCtrl;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) {
        _sheetPointerActivo = true;
        _sheetUltimoGestUsuario = DateTime.now();
      },
      onVerticalDragUpdate: (DragUpdateDetails details) {
        if (!ctrl.isAttached) return;
        final double h = MediaQuery.sizeOf(context).height;
        if (h <= 0) return;
        final double next =
            (ctrl.size - details.delta.dy / h).clamp(minSize, maxSize);
        if (_sheetFaseUiEsAbordo && next < _kViajeSheetAbordoPin - 0.06) {
          _sheetAbordoColapsoUsuario = true;
          _sheetExpandPendienteTarget = null;
        }
        ctrl.jumpTo(next);
      },
      onVerticalDragEnd: (_) => _finalizarInteraccionSheetUsuario(),
      onVerticalDragCancel: () => _finalizarInteraccionSheetUsuario(),
      child: child,
    );
  }

  bool _sheetAutoExpandPorMapaPermitido({
    required bool esMotor,
    required bool faseAbordoPin,
    required bool fasePickupConductor,
  }) {
    return !esMotor && !faseAbordoPin && !fasePickupConductor;
  }

  void _colapsarSheetPorMapaEnFase({
    required bool fasePickupConductor,
    required bool faseAbordoPin,
    required bool faseEnRuta,
  }) {
    // En abordo+PIN el cliente debe ver el código: no colapsar por cámara/mapa.
    if (faseAbordoPin) return;
    final double? target = fasePickupConductor
        ? _kViajeSheetPickupCompact
        : (faseEnRuta ? _kViajeSheetInitial : null);
    _colapsarSheetPorTapMapa(target: target);
  }

  Widget _viajeSheetDivider([String label = 'Detalles del viaje']) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClienteZonaAccionesSticky(
    Viaje v,
    String estadoBase,
    bool cancelarHabilitado, {
    bool compacto = false,
    bool reforzarComunicacionEnSticky = false,
  }) {
    final bool multiparada = _clienteNavegacionMultiparadaActiva(v, estadoBase);
    final bool mostrarNavDestino = estadoBase == EstadosViaje.enCurso &&
        !multiparada &&
        (_isValidCoord(v.latDestino, v.lonDestino) || _simCasa);
    final bool tieneTaxista = v.uidTaxista.isNotEmpty;
    final String miUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final String nombreCond =
        v.nombreTaxista.isNotEmpty ? v.nombreTaxista : 'Conductor';
    final String telCond =
        v.telefonoTaxista.isNotEmpty ? v.telefonoTaxista : v.telefono.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!EstadosViaje.esTerminal(estadoBase)) ...[
          _botonVolverARaiEnPanel(v),
          const SizedBox(height: 10),
        ],
        if (multiparada) ...[
          _bloqueNavegacionMultiparadaCliente(v),
          const SizedBox(height: 10),
        ],
        if (mostrarNavDestino)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                if (_isValidCoord(v.latDestino, v.lonDestino)) {
                  abrirNavegacionAlDestino(v);
                } else if (_simCasa) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '[SIM CASA] Sin coords de destino en Firestore: '
                        'usa el mapa o finaliza desde el taxista.',
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.navigation, color: Colors.black, size: 24),
              label: const Text(
                'NAVEGAR AL DESTINO',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
        if (tieneTaxista && (!compacto || reforzarComunicacionEnSticky)) ...[
          if (mostrarNavDestino) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  context,
                  icon: Icons.phone,
                  label: 'Llamar',
                  onPressed: () async {
                    final String tc = telefonoNormalizarDigitos(telCond);
                    if (tc.isEmpty) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Número del conductor no disponible aún. Usa el chat.',
                          ),
                        ),
                      );
                      return;
                    }
                    unawaited(
                        ViajeComunicacionRepo.notificarIntentoComunicacion(
                      viajeId: v.id,
                      tipo: 'llamada',
                    ));
                    await telefonoLaunchUri(telefonoUriLlamada(tc));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  context,
                  icon: Icons.chat_bubble_outline,
                  label: 'WhatsApp',
                  onPressed: () async {
                    final String tc = telefonoNormalizarDigitos(telCond);
                    if (tc.isEmpty) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Número del conductor no disponible aún. Usa el chat.',
                          ),
                        ),
                      );
                      return;
                    }
                    unawaited(
                        ViajeComunicacionRepo.notificarIntentoComunicacion(
                      viajeId: v.id,
                      tipo: 'whatsapp',
                    ));
                    const String waMsg = 'Hola, soy tu cliente de RAI.';
                    if (await telefonoLaunchUri(
                        telefonoUriWhatsAppApp(tc, waMsg))) {
                      return;
                    }
                    await telefonoLaunchUri(telefonoUriWhatsAppWeb(tc, waMsg));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  context,
                  icon: Icons.chat,
                  label: 'Chat',
                  onPressed: () {
                    final String uidTx = _uidTaxistaDelViaje(v);
                    final String miUid =
                        FirebaseAuth.instance.currentUser?.uid ?? '';
                    unawaited(ChatViajeNav.abrir(
                      context: context,
                      miUid: miUid,
                      otroUid: uidTx,
                      otroNombre: nombreCond,
                      viajeId: v.id,
                    ));
                  },
                ),
              ),
            ],
          ),
          if (_isValidCoord(v.latTaxista, v.lonTaxista)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _centrarClienteYTaxista(v),
                    icon: const Icon(Icons.center_focus_strong),
                    label: const Text('Centrar mapa'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _centrarEnTaxista(v),
                    icon: const Icon(Icons.my_location),
                    label: const Text('Ver en vivo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (miUid.isNotEmpty) ...[
            const SizedBox(height: 10),
            ViajeChatMensajesEnVivo(
              viajeId: v.id,
              miUid: miUid,
              otroUid: v.uidTaxista,
              otroNombre: nombreCond,
            ),
          ],
        ],
        if (cancelarHabilitado) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _cancelandoViajeCliente
                  ? null
                  : () => _deleteOrCancelEstricto(v),
              icon: const Icon(Icons.cancel_outlined, size: 20),
              label: Text(
                _cancelandoViajeCliente ? 'Cancelando...' : 'Cancelar viaje',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent, width: 1.4),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _llamarConductorCliente(Viaje v) async {
    final String telCond =
        v.telefonoTaxista.isNotEmpty ? v.telefonoTaxista : v.telefono.trim();
    final String tc = telefonoNormalizarDigitos(telCond);
    if (tc.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Número del conductor no disponible aún. Usa el chat.',
          ),
        ),
      );
      return;
    }
    unawaited(ViajeComunicacionRepo.notificarIntentoComunicacion(
      viajeId: v.id,
      tipo: 'llamada',
    ));
    await telefonoLaunchUri(telefonoUriLlamada(tc));
  }

  Future<void> _whatsAppConductorCliente(Viaje v) async {
    final String telCond =
        v.telefonoTaxista.isNotEmpty ? v.telefonoTaxista : v.telefono.trim();
    final String tc = telefonoNormalizarDigitos(telCond);
    if (tc.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Número del conductor no disponible aún. Usa el chat.',
          ),
        ),
      );
      return;
    }
    unawaited(ViajeComunicacionRepo.notificarIntentoComunicacion(
      viajeId: v.id,
      tipo: 'whatsapp',
    ));
    const String waMsg = 'Hola, soy tu cliente de RAI.';
    if (await telefonoLaunchUri(telefonoUriWhatsAppApp(tc, waMsg))) {
      return;
    }
    await telefonoLaunchUri(telefonoUriWhatsAppWeb(tc, waMsg));
  }

  void _abrirChatConductorCliente(Viaje v) {
    final String nombreCond =
        v.nombreTaxista.isNotEmpty ? v.nombreTaxista : 'Conductor';
    final String uidTx = _uidTaxistaDelViaje(v);
    final String miUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    unawaited(ChatViajeNav.abrir(
      context: context,
      miUid: miUid,
      otroUid: uidTx,
      otroNombre: nombreCond,
      viajeId: v.id,
    ));
  }

  void _maybeColapsarSheetPickupNav(Viaje v, String estadoBase) {
    _maybeAutoExpandirSheetPorFaseCliente(
      v: v,
      estadoBase: estadoBase,
      faseAbordoPin: EstadosViaje.esAbordo(estadoBase) ||
          _clienteAbordoEnViajeDoc(
            <String, dynamic>{'estado': estadoBase},
            v,
          ),
      codigoVerificado: v.codigoVerificado,
      faseEnRuta: v.codigoVerificado &&
          EstadosViaje.esEnCurso(estadoBase),
      fasePickupConductor: v.uidTaxista.isNotEmpty &&
          !v.codigoVerificado &&
          (estadoBase == EstadosViaje.aceptado ||
              estadoBase == EstadosViaje.enCaminoPickup),
      esperandoConductor: v.uidTaxista.isEmpty &&
          (estadoBase == EstadosViaje.pendiente ||
              estadoBase == EstadosViaje.pendientePago),
    );
  }

  void _schedulePickupEtaRefresh(Viaje v, String estadoBase) {
    final bool fase = v.uidTaxista.isNotEmpty &&
        _isValidCoord(v.latTaxista, v.lonTaxista) &&
        _isValidCoord(v.latCliente, v.lonCliente) &&
        (estadoBase == EstadosViaje.aceptado ||
            estadoBase == EstadosViaje.enCaminoPickup);
    if (!fase) {
      _pickupEtaDebounce?.cancel();
      _pickupEtaSigPendiente = '';
      if (_pickupEtaTitulo != null || _pickupEtaDetalle != null) {
        if (mounted) {
          setState(() {
            _pickupEtaTitulo = null;
            _pickupEtaDetalle = null;
            _pickupEtaMinimizado = false;
          });
        }
      }
      return;
    }
    final String sig =
        '${v.latTaxista.toStringAsFixed(4)},${v.lonTaxista.toStringAsFixed(4)}';
    if (sig == _pickupEtaSigPendiente) return;
    _pickupEtaSigPendiente = sig;
    _pickupEtaDebounce?.cancel();
    _pickupEtaDebounce = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      unawaited(_fetchPickupEtaHttp(v, sig));
    });
  }

  Future<void> _fetchPickupEtaHttp(Viaje v, String sig) async {
    if (!mounted) return;
    final DateTime now = DateTime.now();
    if (_pickupEtaUltimoHttp != null &&
        now.difference(_pickupEtaUltimoHttp!) < const Duration(seconds: 24) &&
        sig == _pickupEtaSigUltimoHttp) {
      return;
    }
    _pickupEtaUltimoHttp = now;
    _pickupEtaSigUltimoHttp = sig;
    try {
      final DirectionsResult? dir = await DirectionsService.drivingDistanceKm(
        originLat: v.latTaxista,
        originLon: v.lonTaxista,
        destLat: v.latCliente,
        destLon: v.lonCliente,
        withTraffic: true,
        region: 'do',
      );
      if (!mounted) return;
      if (dir != null && dir.seconds > 0) {
        final int min = (dir.seconds / 60).ceil().clamp(1, 240);
        final String kmTxt =
            dir.distanceText ?? '${dir.km.toStringAsFixed(1)} km';
        setState(() {
          _pickupEtaTitulo = 'Tu conductor llega en unos $min min';
          _pickupEtaDetalle =
              dir.durationText != null ? '${dir.durationText} · $kmTxt' : kmTxt;
        });
        _intentarRecuperarSheetTrasEvento();
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    final double km = _haversineKm(
      v.latTaxista,
      v.lonTaxista,
      v.latCliente,
      v.lonCliente,
    );
    final int min = (km / 0.45).ceil().clamp(1, 240);
    setState(() {
      _pickupEtaTitulo = 'Tu conductor llega en unos $min min';
      _pickupEtaDetalle =
          '${km.toStringAsFixed(1)} km aprox. (sin tráfico en vivo)';
    });
    _intentarRecuperarSheetTrasEvento();
  }

  // 🚀 NUEVO: Iniciar escucha de conductores disponibles
  void _startListeningDrivers(
    double pickupLat,
    double pickupLon, {
    String? tipoServicioViaje,
  }) {
    if (_nearbyDriversSession != null) return;

    _nearbyDriversSession = DriversLocationNearbyRepo.createSession(
      initialCenter: LatLng(pickupLat, pickupLon),
      uidCliente: FirebaseAuth.instance.currentUser?.uid,
      tipoServicioViaje: tipoServicioViaje,
      radiusKm: _kRadioKmConductoresCerca,
      maxResultados: 50,
      onUpdate: (DriversLocationNearbyUpdate update) {
        _poolDriverAnim.syncTargets(update.conductores);
        final String sig = update.conductores
            .map(
              (RaiLiveDriverPoint d) =>
                  '${d.uid}:${d.position.latitude.toStringAsFixed(4)},${d.position.longitude.toStringAsFixed(4)}',
            )
            .join('|');
        if (sig == _lastDriversPoolSig) return;
        _lastDriversPoolSig = sig;
        if (mounted) {
          setState(() {
            _driversList = update.docs;
          });
          _schedulePrefetchDriverFotos();
        }
      },
    );
  }

  // 🚀 NUEVO: Detener escucha de conductores
  /// No llamar [setState] síncrono desde el builder del StreamBuilder (al aceptar
  /// el taxista, `esperandoTaxista` pasa a false y esto se invocaba en build → ErrorWidget).
  void _stopListeningDrivers({bool deferSetState = false}) {
    _fotosDebounce?.cancel();
    _fotosDebounce = null;
    _nearbyDriversSession?.dispose();
    _nearbyDriversSession = null;
    _poolDriverAnim.syncTargets(const <RaiLiveDriverPoint>[]);
    _lastDriversPoolSig = '';
    void clear() {
      if (!mounted) return;
      setState(() {
        _driversList = [];
        _driverFotoPorUid = <String, String?>{};
      });
    }

    if (!mounted) return;
    if (deferSetState) {
      WidgetsBinding.instance.addPostFrameCallback((_) => clear());
    } else {
      clear();
    }
  }

  void _schedulePrefetchDriverFotos() {
    _fotosDebounce?.cancel();
    _fotosDebounce =
        Timer(const Duration(milliseconds: 500), _prefetchDriverFotos);
  }

  Future<void> _prefetchDriverFotos() async {
    if (!mounted) return;
    final List<DocumentSnapshot<Map<String, dynamic>>> docs =
        List<DocumentSnapshot<Map<String, dynamic>>>.from(_driversList);
    if (docs.isEmpty) {
      if (mounted) setState(() => _driverFotoPorUid = <String, String?>{});
      return;
    }
    final List<String> ids = docs
        .map((DocumentSnapshot<Map<String, dynamic>> d) => d.id)
        .take(14)
        .toList(growable: false);
    final Map<String, String?> next = <String, String?>{};
    for (int i = 0; i < ids.length; i += 4) {
      final List<String> chunk =
          ids.sublist(i, i + 4 > ids.length ? ids.length : i + 4);
      await Future.wait(chunk.map((String uid) async {
        try {
          final DocumentSnapshot<Map<String, dynamic>> s =
              await FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uid)
                  .get();
          final String? url = s.data()?['fotoUrl']?.toString();
          if (url != null && url.isNotEmpty) {
            next[uid] = url;
          }
        } catch (_) {}
      }));
      if (!mounted) return;
    }
    if (!mounted) return;
    setState(() => _driverFotoPorUid = next);
  }

  /// Radio real (km) para “cerca de ti” — no contar todo el país.
  static const double _kRadioKmConductoresCerca = 20;

  List<DocumentSnapshot<Map<String, dynamic>>> _conductoresCercaPickup(
    Viaje v,
  ) {
    if (!_isValidCoord(v.latCliente, v.lonCliente)) {
      return const <DocumentSnapshot<Map<String, dynamic>>>[];
    }
    final List<DocumentSnapshot<Map<String, dynamic>>> near =
        <DocumentSnapshot<Map<String, dynamic>>>[];
    for (final DocumentSnapshot<Map<String, dynamic>> d in _driversList) {
      final Map<String, dynamic>? data = d.data();
      if (data == null) continue;
      if (data['tracking'] != true && data['online'] != true) continue;
      final GeoPoint? gp = _geoPointSeguro(data['location']);
      if (gp == null) continue;
      if (!_isValidCoord(gp.latitude, gp.longitude)) continue;
      final double km = DistanciaService.calcularDistancia(
        v.latCliente,
        v.lonCliente,
        gp.latitude,
        gp.longitude,
      );
      if (km <= _kRadioKmConductoresCerca) near.add(d);
    }
    return conductoresOrdenadosPorPickup(
      near,
      pickupLat: v.latCliente,
      pickupLon: v.lonCliente,
    );
  }

  Widget _radarSearchingOverlay() {
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 320,
          height: 320,
          child: AnimatedBuilder(
            animation: _radarCtrl,
            builder: (context, _) {
              final double t = _radarCtrl.value;
              Widget pulse(double phase, double baseSize, Color color) {
                final double p = (t + phase) % 1.0;
                final double size = baseSize + (180 * p);
                final double opacity = (1.0 - p) * 0.28;
                final Color waveColor = Color.lerp(
                      color,
                      Colors.purpleAccent,
                      (math.sin((t + phase) * math.pi * 2) + 1) / 2,
                    ) ??
                    color;
                return Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: waveColor.withValues(alpha: opacity),
                    border: Border.all(
                      color: waveColor.withValues(alpha: opacity + 0.06),
                      width: 1.2,
                    ),
                  ),
                );
              }

              return Stack(
                alignment: Alignment.center,
                children: [
                  pulse(0.00, 78, Colors.greenAccent),
                  pulse(0.33, 68, Colors.lightBlueAccent),
                  pulse(0.66, 58, Colors.greenAccent),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.greenAccent, width: 1.6),
                    ),
                    child: const Icon(
                      Icons.local_taxi,
                      color: Colors.greenAccent,
                      size: 36,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _enableMyLocation() async {
    // Solo lectura: el permiso se gestiona en bootstrap / solicitar viaje.
    final ({bool serviceEnabled, LocationPermission permission}) snap =
        await GpsService.readServiceAndPermissionStabilizedNoRequest();
    if (!mounted) return;
    if (!snap.serviceEnabled) {
      setState(() => _myLoc = false);
      _maybeSnackActivarGpsSistemaCliente();
      return;
    }
    final LocationPermission p = snap.permission;
    final bool denied = (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever);
    setState(() => _myLoc = !denied);
  }

  // Navegación externa
  String _fmtCoord(double v) => v.toStringAsFixed(6);

  Future<bool> _tryLaunch(Uri uri, {bool preferExternalApp = true}) async {
    try {
      if (kIsWeb) {
        if (uri.scheme != 'http' && uri.scheme != 'https') return false;
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank',
        );
      }
      final bool ok1 = await launchUrl(
        uri,
        mode: preferExternalApp
            ? LaunchMode.externalApplication
            : LaunchMode.platformDefault,
      );
      if (ok1) return true;

      final bool ok2 = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (ok2) return true;

      if (uri.scheme.startsWith('http')) {
        final bool ok3 =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok3) return true;
      }
    } catch (_) {}
    return false;
  }

  void _avisarDestinoSinCoordenadas() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'El destino no tiene coordenadas válidas. '
          'Selecciona un destino en el mapa antes de navegar.',
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _openGoogleMapsTo(double lat, double lon,
      {String? label}) async {
    if (!_isValidCoord(lat, lon)) {
      _avisarDestinoSinCoordenadas();
      return;
    }
    final String la = _fmtCoord(lat), lo = _fmtCoord(lon);
    final String qLabel = (label == null || label.trim().isEmpty)
        ? '$la,$lo'
        : Uri.encodeComponent('$la,$lo($label)');
    final Uri web = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$la,$lo&travelmode=driving');

    if (kIsWeb) {
      await _tryLaunch(web);
      return;
    }

    final Uri navIntent = Uri(
      scheme: 'google.navigation',
      queryParameters: {'q': '$la,$lo', 'mode': 'd'},
    );
    final Uri geoIntent = Uri.parse('geo:$la,$lo?q=$qLabel');

    if (await _tryLaunch(navIntent)) return;
    if (await _tryLaunch(geoIntent)) return;
    await _tryLaunch(web, preferExternalApp: false);
  }

  Future<void> _openWazeTo(double lat, double lon) async {
    if (!NavegacionExternaLauncher.coordsValidas(lat, lon)) {
      _avisarDestinoSinCoordenadas();
      return;
    }
    await NavegacionExternaLauncher.abrirWazeDestino(lat, lon);
  }

  /// Abre Google Maps en el punto del conductor (vista / marcador), sin forzar ruta en la app RAI.
  Future<void> _openGoogleMapsVerUbicacionConductor(
      double lat, double lon) async {
    final String la = _fmtCoord(lat), lo = _fmtCoord(lon);
    final Uri mapsSearch = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$la,$lo',
    );
    if (kIsWeb) {
      await _tryLaunch(mapsSearch);
      return;
    }
    final Uri geoIntent = Uri.parse('geo:$la,$lo');
    if (await _tryLaunch(geoIntent)) return;
    await _tryLaunch(mapsSearch, preferExternalApp: false);
  }

  Future<void> abrirNavegacionAlDestino(Viaje v) async {
    final destRes = ViajeNavegacionResolver.destino(v);
    if (destRes == null) {
      _avisarDestinoSinCoordenadas();
      return;
    }
    final double destLat = destRes.lat;
    final double destLon = destRes.lon;
    if (!mounted) return;
    _marcarClienteNavOrientacionOk();

    final origenRes = ViajeNavegacionResolver.origen(v);
    final double origenLat = origenRes?.lat ?? v.latCliente;
    final double origenLon = origenRes?.lon ?? v.lonCliente;

    final List<({double lat, double lon, String label})> paradas =
        _paradasIntermediasResueltas(v);
    final bool multi =
        paradas.isNotEmpty && _isValidCoord(origenLat, origenLon);

    if (multi) {
      await showNavegacionWazeMapsSheet(
        context,
        title: 'Navegar ruta con paradas',
        addressLine: '${v.origen} → ${paradas.length} parada(s) → ${v.destino}',
        tieneCoords: true,
        footerHint:
            'Google Maps abre la ruta completa. Waze navega al destino final.',
        onWaze: () => unawaited(_openWazeTo(destLat, destLon)),
        onMaps: () => unawaited(
          NavegacionExternaLauncher.abrirGoogleMapsRutaConParadas(
            origenLat: origenLat,
            origenLon: origenLon,
            destinoLat: destLat,
            destinoLon: destLon,
            paradas: paradas
                .map((p) => (lat: p.lat, lon: p.lon))
                .toList(growable: false),
          ),
        ),
      );
      return;
    }

    await showNavegacionWazeMapsSheet(
      context,
      title: 'Navegar al destino',
      addressLine: v.destino.trim().isNotEmpty ? 'Destino: ${v.destino}' : null,
      tieneCoords: true,
      gpsCoordinatesLine: 'GPS: ${_fmtCoord(destLat)}, ${_fmtCoord(destLon)}',
      footerHint: 'Elige Waze o Google Maps.',
      onWaze: () => unawaited(_openWazeTo(destLat, destLon)),
      onMaps: () => unawaited(
        _openGoogleMapsTo(destLat, destLon, label: v.destino),
      ),
    );
  }

  // ===== Centrar cámara en el taxista =====
  Future<void> _centrarEnTaxista(Viaje v) async {
    if (!mounted) return;
    final GoogleMapController? mapRef = _map;
    if (mapRef == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cargando mapa... intenta de nuevo.')),
      );
      return;
    }

    if (!_isValidCoord(v.latTaxista, v.lonTaxista)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Esperando ubicación GPS del conductor en tiempo real.'),
        ),
      );
      return;
    }

    setState(() => _seguirTaxistaCamara = true);
    _programmaticCameraDepth++;
    try {
      await mapRef.animateCamera(CameraUpdate.newLatLngZoom(
        LatLng(v.latTaxista, v.lonTaxista),
        16,
      ));
      _colapsarSheetPorTapMapa();
      HapticFeedback.lightImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            content: Text('Seguimiento en vivo activado'),
          ),
        );
    } catch (_) {
      if (_programmaticCameraDepth > 0) _programmaticCameraDepth--;
    }
  }

  Future<void> _centrarClienteYTaxista(Viaje v) async {
    final GoogleMapController? mapRef = _map;
    if (mapRef == null) return;
    if (!_isValidCoord(v.latCliente, v.lonCliente) ||
        !_isValidCoord(v.latTaxista, v.lonTaxista)) {
      await _fitBoundsFor(v);
      return;
    }
    final LatLng a = LatLng(v.latCliente, v.lonCliente);
    final LatLng b = LatLng(v.latTaxista, v.lonTaxista);
    final LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(
        math.min(a.latitude, b.latitude),
        math.min(a.longitude, b.longitude),
      ),
      northeast: LatLng(
        math.max(a.latitude, b.latitude),
        math.max(a.longitude, b.longitude),
      ),
    );
    try {
      _programmaticCameraDepth++;
      await mapRef.animateCamera(CameraUpdate.newLatLngBounds(bounds, 90));
    } catch (_) {
      if (_programmaticCameraDepth > 0) _programmaticCameraDepth--;
      await _fitBoundsFor(v);
    }
  }

  String _normEstadoViaje(Viaje v) {
    return EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
    );
  }

  bool _esViajeMultiparada(Viaje v) {
    if (v.multiparadaLegsTotal > 1) return true;
    return (v.waypoints?.isNotEmpty ?? false);
  }



  Map<String, dynamic> _viajeDocMultiparada(Viaje v) =>
      ViajeNavegacionResolver.documento(v);

  Map<String, dynamic> _viajeDocNavegacion(Viaje v) => _viajeDocMultiparada(v);

  List<({double lat, double lon, String label})> _paradasIntermediasResueltas(
    Viaje v,
  ) {
    return MultiparadaRutaHelper.paradasIntermediasParaNavegacion(
      viajeData: _viajeDocMultiparada(v),
      waypointsModel: v.waypoints,
    );
  }

  List<({double lat, double lon, String label, bool esFinal})>
      _destinosOrdenadosMultiparadaCliente(Viaje v) =>
          ViajeNavegacionResolver.legs(v);

  ({double lat, double lon, String label, bool esFinal})?
      _destinoMultiActualCliente(Viaje v) {
    final List<({double lat, double lon, String label, bool esFinal})> legs =
        _destinosOrdenadosMultiparadaCliente(v);
    if (_multiLegCompletadas >= legs.length) return null;
    return legs[_multiLegCompletadas];
  }

  bool _clienteNavegacionMultiparadaActiva(Viaje v, String estadoBase) {
    if (!_esViajeMultiparada(v)) return false;
    if (estadoBase == EstadosViaje.enCurso) return true;
    if (estadoBase == EstadosViaje.aBordo && v.codigoVerificado) return true;
    return false;
  }

  bool _multiparadaRutaCompletaCliente(Viaje v) {
    if (!_esViajeMultiparada(v)) return true;
    if (v.multiparadaCompleta) return true;
    final int total = _destinosOrdenadosMultiparadaCliente(v).length;
    if (total <= 0) return true;
    final visitados =
        multiparadaLegsVisitadosDesdeViaje(v, totalLegs: total);
    return visitados.length >= total;
  }

  void _syncMultiLegClienteDesdeViaje(Viaje v) {
    if (!_esViajeMultiparada(v)) {
      if (_multiLegCompletadas != 0) _multiLegCompletadas = 0;
      _clienteMultiNavLegIndices.clear();
      _clienteOrigenMultiNavAbierto = false;
      _clienteMultiNavViajeId = null;
      return;
    }
    if (_clienteMultiNavViajeId != v.id) {
      _clienteMultiNavLegIndices.clear();
      _clienteOrigenMultiNavAbierto = false;
      _clienteMultiNavViajeId = v.id;
    }
    final int total = _destinosOrdenadosMultiparadaCliente(v).length;
    final visitados =
        multiparadaLegsVisitadosDesdeViaje(v, totalLegs: total);
    final int fromServer = visitados.isNotEmpty
        ? visitados.length
        : v.multiparadaLegCompletadas.clamp(0, total);
    if (_multiLegCompletadas != fromServer) {
      _multiLegCompletadas = fromServer;
    }
  }

  void _marcarClienteNavOrientacionOk({bool multiparada = false}) {
    if (!mounted) return;
    setState(() {
      _clienteNavDestinoUsado = true;
      if (multiparada) {
        _clienteNavOrientacionLegDismissed = _multiLegCompletadas;
      }
    });
  }

  String? _mensajeOrientacionCliente(
    Viaje v,
    String estadoBase, {
    required bool mostrarCodigoCliente,
  }) {
    final bool multiparada = _clienteNavegacionMultiparadaActiva(v, estadoBase);
    final bool mostrarNavDestino = estadoBase == EstadosViaje.enCurso &&
        !multiparada &&
        (_isValidCoord(v.latDestino, v.lonDestino) || _simCasa);
    return viajeFlujoOrientacionMensajeCliente(
      estadoBase: estadoBase,
      codigoVerificado: v.codigoVerificado,
      mostrarCodigoCliente: mostrarCodigoCliente,
      mostrarNavDestino: mostrarNavDestino,
      clienteNavDestinoUsado: _clienteNavDestinoUsado,
      multiparadaActiva: multiparada,
      multiparadaCompleta: _multiparadaRutaCompletaCliente(v),
      multiparadaLegHechos: _multiLegCompletadas,
      clienteNavOrientacionLegDismissed: _clienteNavOrientacionLegDismissed,
      tieneTaxista: v.uidTaxista.isNotEmpty,
    );
  }

  Future<void> _navegarPuntoMultiparadaCliente(
    Viaje v, {
    required int? legIndex,
    required double lat,
    required double lon,
    required String label,
    required String tituloSheet,
    required int pasoEnTotal,
    required String tipoLeg,
  }) async {
    if (!mounted) return;
    if (!NavegacionExternaLauncher.coordsValidas(lat, lon)) {
      _avisarDestinoSinCoordenadas();
      return;
    }
    if (legIndex != null) {
      _marcarClienteNavOrientacionOk(multiparada: true);
    }
    await showNavegacionWazeMapsSheet(
      context,
      title: tituloSheet,
      addressLine: pasoEnTotal > 0
          ? '$label\n($pasoEnTotal · $tipoLeg)'
          : label,
      tieneCoords: true,
      gpsCoordinatesLine: 'GPS: ${_fmtCoord(lat)}, ${_fmtCoord(lon)}',
      footerHint:
          'Waze o Maps abren este punto. El conductor confirma cada parada en su app.',
      onWaze: () => unawaited(_openWazeTo(lat, lon)),
      onMaps: () => unawaited(_openGoogleMapsTo(lat, lon, label: label)),
    );
    if (!mounted) return;
    setState(() {
      if (legIndex == null) {
        _clienteOrigenMultiNavAbierto = true;
      } else {
        _clienteMultiNavLegIndices.add(legIndex);
      }
    });
  }

  List<MultiparadaNavegacionTarjetaModel> _tarjetasNavegacionMultiparadaCliente(
    Viaje v,
  ) {
    final legs = _destinosOrdenadosMultiparadaCliente(v);
    final visitados =
        multiparadaLegsVisitadosDesdeViaje(v, totalLegs: legs.length);
    final tarjetas = <MultiparadaNavegacionTarjetaModel>[];

    final origen = ViajeNavegacionResolver.origen(v);
    if (origen != null &&
        ViajeNavegacionResolver.coordsValidas(origen.lat, origen.lon)) {
      tarjetas.add(
        MultiparadaNavegacionTarjetaModel(
          titulo: 'Recogida',
          subtitulo: origen.label,
          accion: _clienteOrigenMultiNavAbierto
              ? 'Abierto en Waze/Maps'
              : 'Waze o Maps · Recogida',
          acento: const Color(0xFF0F766E),
          icono: Icons.flag_circle_rounded,
          navegadoEnSesion: _clienteOrigenMultiNavAbierto,
          onTap: () => unawaited(
            _navegarPuntoMultiparadaCliente(
              v,
              legIndex: null,
              lat: origen.lat,
              lon: origen.lon,
              label: origen.label,
              tituloSheet: 'Navegar a la recogida',
              pasoEnTotal: 0,
              tipoLeg: 'origen',
            ),
          ),
        ),
      );
    }

    for (var i = 0; i < legs.length; i++) {
      final leg = legs[i];
      if (!NavegacionExternaLauncher.coordsValidas(leg.lat, leg.lon)) continue;
      final bool visitado = visitados.contains(i);
      final bool navegado = _clienteMultiNavLegIndices.contains(i);
      tarjetas.add(
        MultiparadaNavegacionTarjetaModel(
          titulo: leg.esFinal ? 'Destino final' : 'Parada ${i + 1}',
          subtitulo: leg.label,
          accion: visitado
              ? 'Visitada (conductor confirmó)'
              : navegado
                  ? 'Abierto en Waze/Maps'
                  : 'Tocá para Waze o Maps',
          acento: kMultiparadaNavegacionAcentos[
              i % kMultiparadaNavegacionAcentos.length],
          icono:
              leg.esFinal ? Icons.flag_rounded : Icons.location_on_rounded,
          legIndex: i,
          visitado: visitado,
          navegadoEnSesion: navegado,
          onTap: visitado
              ? null
              : () => unawaited(
                    _navegarPuntoMultiparadaCliente(
                      v,
                      legIndex: i,
                      lat: leg.lat,
                      lon: leg.lon,
                      label: leg.label,
                      tituloSheet: leg.esFinal
                          ? 'Navegar al destino final'
                          : 'Navegar a la parada',
                      pasoEnTotal: i + 1,
                      tipoLeg:
                          leg.esFinal ? 'destino final' : 'parada ${i + 1}',
                    ),
                  ),
        ),
      );
    }
    return tarjetas;
  }

  Future<void> _abrirGoogleMapsRutaMultiRestanteCliente(Viaje v) async {
    final List<({double lat, double lon, String label, bool esFinal})> legs =
        _destinosOrdenadosMultiparadaCliente(v);
    if (legs.isEmpty || !mounted) return;
    final visitados =
        multiparadaLegsVisitadosDesdeViaje(v, totalLegs: legs.length);
    final List<({double lat, double lon, String label, bool esFinal})>
        remaining = <({double lat, double lon, String label, bool esFinal})>[];
    for (var i = 0; i < legs.length; i++) {
      if (!visitados.contains(i)) remaining.add(legs[i]);
    }
    if (remaining.isEmpty) return;

    final origenRes = ViajeNavegacionResolver.origen(v);
    if (!_isValidCoord(v.latCliente, v.lonCliente) && origenRes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Sin coordenadas de origen para la ruta.')),
      );
      return;
    }

    final double origenLat = origenRes?.lat ?? v.latCliente;
    final double origenLon = origenRes?.lon ?? v.lonCliente;

    final double dLat = remaining.last.lat;
    final double dLon = remaining.last.lon;
    if (!_isValidCoord(dLat, dLon)) {
      _avisarDestinoSinCoordenadas();
      return;
    }
    final List<({double lat, double lon})> paradas =
        <({double lat, double lon})>[];
    if (remaining.length > 1) {
      for (var i = 0; i < remaining.length - 1; i++) {
        paradas.add((lat: remaining[i].lat, lon: remaining[i].lon));
      }
    }

    await showNavegacionWazeMapsSheet(
      context,
      title: 'Ruta con paradas restantes',
      addressLine: '${v.origen} → ${paradas.length} parada(s) → ${v.destino}',
      tieneCoords: true,
      footerHint:
          'Google Maps: ruta completa. Waze: solo el último pin (usa las tarjetas parada a parada).',
      onWaze: () => unawaited(_openWazeTo(dLat, dLon)),
      onMaps: () => unawaited(
        NavegacionExternaLauncher.abrirGoogleMapsRutaConParadas(
          origenLat: origenLat,
          origenLon: origenLon,
          destinoLat: dLat,
          destinoLon: dLon,
          paradas: paradas,
        ),
      ),
    );
  }

  Widget _bloqueNavegacionMultiparadaCliente(Viaje v) {
    final List<({double lat, double lon, String label, bool esFinal})> legs =
        _destinosOrdenadosMultiparadaCliente(v);
    if (legs.isEmpty) return const SizedBox.shrink();

    final int total = legs.length;
    final visitados =
        multiparadaLegsVisitadosDesdeViaje(v, totalLegs: total);
    final int hechos = visitados.length.clamp(0, total);
    final bool completa = hechos >= total || v.multiparadaCompleta;

    return MultiparadaNavegacionTarjetasPanel(
      tituloProgreso: completa
          ? 'Tu ruta: todos los destinos ($hechos/$total)'
          : 'Tu ruta: $hechos de $total visitados',
      subtituloHint:
          'Seguí la ruta en Waze o Maps. El conductor confirma cada parada con ✓ en su app.',
      tarjetas: _tarjetasNavegacionMultiparadaCliente(v),
      accionesInferiores: completa
          ? const <Widget>[]
          : <Widget>[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () =>
                    unawaited(_abrirGoogleMapsRutaMultiRestanteCliente(v)),
                icon: const Icon(Icons.map, size: 20),
                label: const Text('Ver ruta completa restante (Google Maps)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.lightBlueAccent,
                  side: BorderSide(
                    color: Colors.lightBlueAccent.withValues(alpha: 0.5),
                  ),
                  minimumSize: const Size(double.infinity, 46),
                ),
              ),
            ],
    );
  }

  bool _mostrarRutaHaciaDestinoCliente(Viaje v) {
    final estado = _normEstadoViaje(v);
    if (estado == EstadosViaje.enCurso) return true;
    if (estado == EstadosViaje.aBordo && v.codigoVerificado) return true;
    // Multiparada: vista previa de la ruta completa en mapa al subir / validar PIN.
    if (_esViajeMultiparada(v) && estado == EstadosViaje.aBordo) return true;
    return false;
  }

  // Rutas / mapa
  void _scheduleDrawRoute(Viaje v) {
    _routeDebounce?.cancel();
    _routeDebounce =
        Timer(const Duration(milliseconds: 350), () => _drawRoutesForState(v));
  }

  Future<void> _drawRoutesForState(Viaje v) async {
    if (!mounted) return;

    final String estado = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.enCurso : EstadosViaje.pendiente)),
    );

    // Conservar polylines actuales hasta tener la nueva (evita mapa en blanco).
    final Map<PolylineId, Polyline> beforePolys =
        Map<PolylineId, Polyline>.from(_polylines);
    final Map<PolylineId, Polyline> nextPolys = <PolylineId, Polyline>{};

    if ((estado == EstadosViaje.aceptado ||
            estado == EstadosViaje.enCaminoPickup) &&
        _isValidCoord(v.latTaxista, v.lonTaxista) &&
        _isValidCoord(v.latCliente, v.lonCliente)) {
      await _drawRoute(
        _latLng(v.latTaxista, v.lonTaxista),
        _latLng(v.latCliente, v.lonCliente),
        id: 'pickup',
        into: nextPolys,
      );
    }

    if (_mostrarRutaHaciaDestinoCliente(v) &&
        _isValidCoord(v.latDestino, v.lonDestino)) {
      final bool multiEnCurso = _esViajeMultiparada(v) &&
          estado == EstadosViaje.enCurso &&
          !_multiparadaRutaCompletaCliente(v);
      if (multiEnCurso) {
        final leg = _destinoMultiActualCliente(v);
        final double oLat = _isValidCoord(v.latTaxista, v.lonTaxista)
            ? v.latTaxista
            : v.latCliente;
        final double oLon = _isValidCoord(v.latTaxista, v.lonTaxista)
            ? v.lonTaxista
            : v.lonCliente;
        if (leg != null &&
            _isValidCoord(oLat, oLon) &&
            _isValidCoord(leg.lat, leg.lon)) {
          await _drawRoute(
            _latLng(oLat, oLon),
            _latLng(leg.lat, leg.lon),
            id: 'ruta_leg_actual',
            into: nextPolys,
          );
        }
      } else if (_isValidCoord(v.latCliente, v.lonCliente)) {
        final List<({double lat, double lon})>? vias =
            _coordsWaypointsValidos(v);
        await _drawRoute(
          _latLng(v.latCliente, v.lonCliente),
          _latLng(v.latDestino, v.lonDestino),
          id: 'ruta',
          viaIntermediate: vias,
          into: nextPolys,
        );
      }
    }

    if (!mounted) return;
    if (nextPolys.isNotEmpty) {
      _polylines
        ..clear()
        ..addAll(nextPolys);
    }

    bool changed = beforePolys.length != _polylines.length;
    if (!changed) {
      for (final MapEntry<PolylineId, Polyline> e in _polylines.entries) {
        final Polyline? p0 = beforePolys[e.key];
        if (p0 == null || p0.points.length != e.value.points.length) {
          changed = true;
          break;
        }
      }
    }
    if (!changed) {
      for (final PolylineId id in beforePolys.keys) {
        if (!_polylines.containsKey(id)) {
          changed = true;
          break;
        }
      }
    }
    if (changed) {
      setState(() {});
    }
  }

  Future<void> _fitBoundsFor(Viaje v) async {
    final GoogleMapController? mapRef = _map;
    if (mapRef == null) return;

    final List<LatLng> pts = <LatLng>[
      if (_isValidCoord(v.latCliente, v.lonCliente))
        _latLng(v.latCliente, v.lonCliente),
      ...(() {
        if (!_mostrarRutaHaciaDestinoCliente(v)) {
          return const <LatLng>[];
        }
        return _paradasIntermediasResueltas(v)
            .map((p) => LatLng(p.lat, p.lon))
            .toList(growable: false);
      })(),
      if (_mostrarRutaHaciaDestinoCliente(v) &&
          _isValidCoord(v.latDestino, v.lonDestino))
        _latLng(v.latDestino, v.lonDestino),
      if (_isValidCoord(v.latTaxista, v.lonTaxista))
        _latLng(v.latTaxista, v.lonTaxista),
    ];
    if (pts.isEmpty) return;

    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final LatLng p in pts) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    final LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    final String estFit = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.enCurso : EstadosViaje.pendiente)),
    );
    final bool fasePickupCam = (estFit == EstadosViaje.aceptado ||
            estFit == EstadosViaje.enCaminoPickup) &&
        _isValidCoord(v.latTaxista, v.lonTaxista) &&
        _isValidCoord(v.latCliente, v.lonCliente);
    final double edgePad = fasePickupCam ? 128.0 : 104.0;

    try {
      _programmaticCameraDepth++;
      await RaiMapPresentation.fitBounds(
        mapRef,
        bounds,
        padding: edgePad,
        maxZoom: RaiMapPresentation.maxZoomTrip,
      );
    } catch (_) {
      if (_programmaticCameraDepth > 0) _programmaticCameraDepth--;
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      final GoogleMapController? mapRef2 = _map;
      if (mapRef2 != null) {
        try {
          _programmaticCameraDepth++;
          await RaiMapPresentation.fitBounds(
            mapRef2,
            bounds,
            padding: edgePad,
            maxZoom: RaiMapPresentation.maxZoomTrip,
          );
        } catch (_) {
          if (_programmaticCameraDepth > 0) _programmaticCameraDepth--;
        }
      }
    }
  }

  /// Para rutas con paradas: firma estable para redibujar si cambian coords en Firestore.
  String _firmaWaypointsViaje(Viaje v) {
    final List<({double lat, double lon, String label})> paradas =
        _paradasIntermediasResueltas(v);
    if (paradas.isEmpty) return '';
    final StringBuffer b = StringBuffer();
    for (final ({double lat, double lon, String label}) p in paradas) {
      b.write('${p.lat.toStringAsFixed(5)},${p.lon.toStringAsFixed(5)};');
    }
    return b.toString();
  }

  double? _coordDoubleMap(dynamic x) {
    if (x is num) return x.toDouble();
    if (x is String) return double.tryParse(x);
    return null;
  }

  List<({double lat, double lon})>? _coordsWaypointsValidos(Viaje v) {
    final List<({double lat, double lon, String label})> paradas =
        _paradasIntermediasResueltas(v);
    if (paradas.isEmpty) return null;
    return paradas.map((p) => (lat: p.lat, lon: p.lon)).toList(growable: false);
  }

  Future<void> _drawRoute(
    LatLng a,
    LatLng b, {
    required String id,
    Color color = const Color(0xFF0A0A0A),
    int width = 18,
    List<({double lat, double lon})>? viaIntermediate,
    Map<PolylineId, Polyline>? into,
  }) async {
    final Map<PolylineId, Polyline> target = into ?? _polylines;
    try {
      final dynamic dir = await DirectionsService.drivingDistanceKm(
        originLat: a.latitude,
        originLon: a.longitude,
        destLat: b.latitude,
        destLon: b.longitude,
        waypoints: (viaIntermediate != null && viaIntermediate.isNotEmpty)
            ? viaIntermediate
            : null,
        withTraffic: true,
        region: 'do',
      );

      List<LatLng> pts = const <LatLng>[];
      try {
        if (dir?.path is List<LatLng>) {
          pts = dir.path as List<LatLng>;
        } else if (dir?.polylinePoints is List) {
          final List<dynamic> raw = dir.polylinePoints as List;
          final List<LatLng> parsed = <LatLng>[];
          for (final dynamic e in raw) {
            try {
              if (e is Map) {
                final double la = (e['lat'] as num).toDouble();
                final double lo = ((e['lng'] ?? e['lon']) as num).toDouble();
                parsed.add(LatLng(la, lo));
              } else {
                final double la = (e.lat as num).toDouble();
                final double lo = (e.lng ?? e.lon as num).toDouble();
                parsed.add(LatLng(la, lo));
              }
            } catch (_) {}
          }
          pts = parsed;
        }
      } catch (_) {}

      final List<LatLng> path = pts.isNotEmpty ? pts : [a, b];
      // Cinta negra gruesa (glow + núcleo) — misma estética en cliente y taxista.
      target[PolylineId('${id}_glow')] = Polyline(
        polylineId: PolylineId('${id}_glow'),
        width: 30,
        points: path,
        geodesic: true,
        color: const Color(0xB3000000),
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      );
      target[PolylineId(id)] = Polyline(
        polylineId: PolylineId(id),
        width: width.clamp(16, 22),
        points: path,
        geodesic: true,
        color: const Color(0xFF0A0A0A),
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      );
    } catch (_) {
      final List<LatLng> path = [a, b];
      target[PolylineId('${id}_glow')] = Polyline(
        polylineId: PolylineId('${id}_glow'),
        width: 30,
        points: path,
        geodesic: true,
        color: const Color(0xB3000000),
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      );
      target[PolylineId(id)] = Polyline(
        polylineId: PolylineId(id),
        width: width.clamp(16, 22),
        points: path,
        geodesic: true,
        color: color,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      );
    }
  }

  // Cancelación
  Future<int> _segundosRestantesBorradoDesdeServidor(String viajeId) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> ds = await FirebaseFirestore
          .instance
          .collection('viajes')
          .doc(viajeId)
          .get();
      if (!ds.exists) return 0;
      final Map<String, dynamic> d = ds.data() ?? {};
      Timestamp? baseTs;

      final dynamic creadoEn = d['creadoEn'];
      final dynamic createdAt = d['createdAt'];
      final dynamic fechaCreacion = d['fechaCreacion'];
      final dynamic aceptadoEn = d['aceptadoEn'];

      if (creadoEn is Timestamp) {
        baseTs = creadoEn;
      } else if (createdAt is Timestamp) {
        baseTs = createdAt;
      } else if (fechaCreacion is Timestamp) {
        baseTs = fechaCreacion;
      } else if (aceptadoEn is Timestamp) {
        baseTs = aceptadoEn;
      }

      if (baseTs == null) return 0;
      final DateTime limite = baseTs.toDate().add(const Duration(seconds: 60));
      final int rest = limite.difference(DateTime.now()).inSeconds;
      return rest > 0 ? rest : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _limpiarActivoDelUsuario(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'viajeActivoId': '',
        'siguienteViajeId': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Tras un fallo (p. ej. permiso al limpiar `usuarios/`), el viaje ya pudo quedar `cancelado` en `viajes/`.
  Future<bool> _viajeQuedoCanceladoEnServidor(String viajeId) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> ds = await FirebaseFirestore
          .instance
          .collection('viajes')
          .doc(viajeId)
          .get();
      if (!ds.exists) return true;
      final String est =
          EstadosViaje.normalizar((ds.data()?['estado'] ?? '').toString());
      return est == EstadosViaje.cancelado || est == EstadosViaje.rechazado;
    } catch (_) {
      return false;
    }
  }

  void _limpiarCacheCierreViaje() {
    _lastNonEmptyViajeActivoId = '';
    _viajeCierreDocSnap = null;
    _viajeCierreFetchKey = null;
    _lastViajeUiCache = null;
  }

  /// Viaje borrado en consola / `viajeActivoId` huérfano: no quedarse en carga infinita.
  Future<bool> _confirmarViajeAusenteEnServidor(String viajeId) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    return ActiveTripService.confirmarViajeAusenteEnFirestore(
      viajeId,
      uid: uid,
    );
  }

  Future<void> _salirTrasViajeDesaparecido({
    required String viajeId,
    required String uid,
    String origen = 'viajeEliminado',
  }) async {
    final String id = viajeId.trim();
    if (id.isNotEmpty && _salidaCierreIniciadaParaViajeId == id) return;

    if (id.isNotEmpty) {
      final bool ausente = await _confirmarViajeAusenteEnServidor(id);
      if (!ausente || !mounted) return;
    }

    if (id.isNotEmpty) _salidaCierreIniciadaParaViajeId = id;

    print('[VIAJE_ACTIVO] cliente $origen: viaje ausente ($id) → inicio');
    await ActiveTripService.liberarClienteTrasViajeEliminado(
      id,
      uid: uid.trim(),
    );
    _stopClienteUbicacionEnViaje();
    _limpiarCacheCierreViaje();

    if (!mounted) return;
    try {
      await _irAlInicioSeguro(
        forzarLimpiarViajeActivo: true,
        omitirSnackViajeEliminado: true,
      );
      if (mounted) {
        NavigationService.snackViajeYaNoDisponible(context: context);
      }
    } catch (_) {}
  }

  Future<void> _cargarDocCierreViajePerdido({
    required String uid,
    required String viajeId,
  }) async {
    final String lost = viajeId.trim();
    if (lost.isEmpty) return;
    try {
      final DocumentSnapshot<Map<String, dynamic>> d = await FirebaseFirestore
          .instance
          .collection('viajes')
          .doc(lost)
          .get()
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() => _viajeCierreDocSnap = d);
      if (!d.exists) {
        unawaited(_salirTrasViajeDesaparecido(
          viajeId: lost,
          uid: uid,
          origen: 'cierreFetchInexistente',
        ));
      }
    } catch (e) {
      print('[VIAJE_ACTIVO] cliente cierre fetch error: $e');
      if (!mounted) return;
      setState(() => _viajeCierreFetchKey = null);
      // Sin red: no echar al inicio; el stream o un reintento lo resolverá.
    }
  }

  Future<void> _irAlInicioSeguro({
    bool forzarLimpiarViajeActivo = false,
    bool omitirSnackViajeEliminado = false,
  }) async {
    if (_yendoAlInicio) return;
    if (!mounted) return;
    setState(() => _yendoAlInicio = true);
    _disposeDocWatch();
    _stopClienteUbicacionEnViaje();
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    try {
      String viajeId = _lastNonEmptyViajeActivoId.trim();
      if (viajeId.isEmpty) {
        viajeId = ActiveTripService.viajeOperativoClienteConocido;
      }
      final String? uid = FirebaseAuth.instance.currentUser?.uid;

      if (!forzarLimpiarViajeActivo &&
          uid != null &&
          uid.trim().isNotEmpty &&
          viajeId.isNotEmpty) {
        final bool operativo =
            await ActiveTripService.viajeDocSigueOperativoParaCliente(
          viajeId,
          uid.trim(),
        );
        if (operativo) {
          forzarLimpiarViajeActivo = false;
        }
      }

      if (!forzarLimpiarViajeActivo && uid != null && uid.trim().isNotEmpty) {
        if (ActiveTripService.debeForzarInicioClienteShell) {
          await NavigationService.irAlInicioCliente(
            context: context,
            viajeId: viajeId.isNotEmpty ? viajeId : null,
            forzarLimpiarViajeActivo: false,
          ).timeout(const Duration(seconds: 12));
          _lastNonEmptyViajeActivoId = '';
          return;
        }

        final String? reparado =
            await ActiveTripService.repararViajeActivoClienteSiHuerfano(
          uid.trim(),
          viajeIdHint: viajeId.isNotEmpty ? viajeId : null,
        );
        if (reparado != null && reparado.isNotEmpty) {
          ActiveTripService.cancelarForzarInicioClienteShellForzado();
          ActiveTripService.mantenerOverlayViajeEnShell(
            NavigationService.kOverlayClienteViajeActivo,
          );
          ActiveTripService.notificarRebuildShell();
          if (mounted) {
            setState(() => _yendoAlInicio = false);
          }
          return;
        }
      }

      await NavigationService.irAlInicioCliente(
        context: context,
        viajeId: viajeId.isNotEmpty ? viajeId : null,
        forzarLimpiarViajeActivo: forzarLimpiarViajeActivo,
        omitirGuardOperativo: false,
      ).timeout(const Duration(seconds: 12));
      _lastNonEmptyViajeActivoId = '';
      if (forzarLimpiarViajeActivo && !omitirSnackViajeEliminado) {
        NavigationService.snackViajeYaNoDisponible(context: context);
      }
    } catch (e) {
      print('[VIAJE_ACTIVO] _irAlInicioSeguro error: $e');
    } finally {
      if (mounted) {
        setState(() => _yendoAlInicio = false);
      }
    }
  }

  void _avisoViajeSigueActivo() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Tu viaje sigue activo. Si no ves el mapa, abre «Mis viajes → Viaje en curso».',
        ),
        duration: Duration(seconds: 4),
        backgroundColor: Color(0xFF1B5E20),
      ),
    );
  }

  Widget _botonVolverARaiEnPanel(Viaje v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _yendoAlInicio ? null : _avisoViajeSigueActivo,
            icon: const Icon(Icons.home_work_rounded, size: 20),
            label: Text(
              _yendoAlInicio ? 'Volviendo a RAI…' : 'Volver a RAI',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(
            'Tu viaje sigue activo. Usa «Mis viajes → Viaje en curso» si necesitas volver al mapa.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  void _programarSalidaAutomaticaSinViaje({bool forzarLimpiar = false}) {
    if (_salidaAutoSinViajeDisparada || _yendoAlInicio) return;
    if (ActiveTripService.debeForzarInicioClienteShell) {
      return;
    }
    _salidaAutoSinViajeDisparada = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _ejecutarSalidaAutomaticaSinViaje(forzarLimpiarInicial: forzarLimpiar),
      );
    });
  }

  /// Solo limpia `viajeActivoId` si el servidor confirma que no hay viaje operativo.
  Future<void> _ejecutarSalidaAutomaticaSinViaje({
    bool forzarLimpiarInicial = false,
  }) async {
    if (!mounted) return;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    String hint = _lastNonEmptyViajeActivoId.trim();
    if (hint.isEmpty) {
      hint = ActiveTripService.viajeOperativoClienteConocido;
    }
    if (hint.isEmpty) {
      hint = ActiveTripService.viajeIdPausaVoluntariaCliente;
    }

    bool forzarLimpiar = forzarLimpiarInicial;
    final String u = uid?.trim() ?? '';

    if (u.isNotEmpty) {
      if (hint.isNotEmpty) {
        final bool operativo =
            await ActiveTripService.viajeDocSigueOperativoParaCliente(hint, u);
        if (operativo) {
          forzarLimpiar = false;
        }
      }
      if (!forzarLimpiar) {
        final String? reparado =
            await ActiveTripService.repararViajeActivoClienteSiHuerfano(
          u,
          viajeIdHint: hint.isNotEmpty ? hint : null,
        );
        if (reparado != null && reparado.isNotEmpty) {
          if (!mounted) return;
          _salidaAutoSinViajeDisparada = false;
          ActiveTripService.mantenerOverlayViajeEnShell(
            NavigationService.kOverlayClienteViajeActivo,
          );
          ActiveTripService.notificarRebuildShell();
          return;
        }
      }
    }

    if (!mounted) return;
    try {
      await _irAlInicioSeguro(forzarLimpiarViajeActivo: forzarLimpiar);
    } finally {
      if (mounted) {
        _salidaAutoSinViajeDisparada = false;
      }
    }
  }

  Widget _cargaViajeConEscape({
    required String mensaje,
    required String viajeId,
    VoidCallback? onReintentar,
  }) {
    return _ClienteCargaViajeGate(
      mensaje: mensaje,
      onVolverInicio: () {
        if (!mounted) return;
        NavigationService.retomarViajeActivoCliente();
      },
      onReintentar: onReintentar ??
          () {
            if (!mounted) return;
            setState(() => _lastViajeUiCache = null);
          },
    );
  }

  Widget _bodyViajeSincronizacionLimitada({
    required String viajeId,
    String mensaje = 'Conectando con tu viaje…',
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.greenAccent,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Tu solicitud sigue activa. Si tarda mucho, reintenta o vuelve al inicio '
              '(no cancela el viaje).',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  if (!mounted) return;
                  setState(() => _lastViajeUiCache = null);
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reintentar'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _yendoAlInicio
                    ? null
                    : () => NavigationService.retomarViajeActivoCliente(),
                icon: const Icon(Icons.home_rounded, size: 18),
                label: const Text('Volver al inicio'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bodySinViajeActivo({required String mensaje}) {
    final String hint = _lastNonEmptyViajeActivoId.trim().isNotEmpty
        ? _lastNonEmptyViajeActivoId.trim()
        : ActiveTripService.viajeOperativoClienteConocido;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (ActiveTripService.debeForzarInicioClienteShell) {
      // Pausa voluntaria: el shell ya muestra inicio + banner; no cancelar la pausa.
      return const SizedBox.shrink();
    }
    return FutureBuilder<String?>(
      future: uid == null || uid.isEmpty
          ? Future<String?>.value(null)
          : ActiveTripService.repararViajeActivoClienteSiHuerfano(
              uid,
              viajeIdHint: hint.isNotEmpty ? hint : null,
            ),
      builder: (BuildContext context, AsyncSnapshot<String?> snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _cargaLinealOscura(mensaje: 'Sincronizando tu viaje…');
        }

        final String? viajeRecuperado = snap.data;
        if (viajeRecuperado != null && viajeRecuperado.isNotEmpty) {
          if (ActiveTripService.flujoPostViajeClienteActivo) {
            return _bodySinViajeActivo(
              mensaje: 'Preparando resumen del viaje…',
            );
          }
          if (ActiveTripService.debeForzarInicioClienteShell) {
            return const SizedBox.shrink();
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ActiveTripService.cancelarForzarInicioClienteShellForzado();
            ActiveTripService.mantenerOverlayViajeEnShell(
              NavigationService.kOverlayClienteViajeActivo,
            );
            ActiveTripService.notificarRebuildShell();
          });
          return _cargaLinealOscura(mensaje: 'Retomando tu viaje…');
        }

        if (hint.isEmpty) {
          _programarSalidaAutomaticaSinViaje();
        } else {
          return _cargaViajeConEscape(
            mensaje: 'Conectando con tu viaje…',
            viajeId: hint,
          );
        }

        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mensaje,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                if (hint.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Si tu conductor sigue esperando, retoma el viaje. '
                    'No se cancela solo por volver al inicio.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (hint.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _yendoAlInicio
                          ? null
                          : NavigationService.retomarViajeActivoCliente,
                      icon: const Icon(Icons.local_taxi_rounded, size: 20),
                      label: const Text('Retomar viaje'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                if (hint.isNotEmpty) const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _yendoAlInicio ? null : _avisoViajeSigueActivo,
                    icon: _yendoAlInicio
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white70,
                            ),
                          )
                        : const Icon(Icons.home_work_rounded, size: 20),
                    label: Text(
                      _yendoAlInicio ? 'Volviendo…' : 'Volver a RAI',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _abrirFlujoPostViaje({
    required String viajeId,
    required String uid,
    Map<String, dynamic>? viajeDataSemilla,
  }) async {
    ActiveTripService.marcarFlujoPostViajeCliente(viajeId);
    if (await CorporativoTaxistaService.debeOcultarEnAppClientePorId(
      viajeId,
      semilla: viajeDataSemilla,
    )) {
      await ClientePostViajeReopenGuard.markCompleted(
        viajeId: viajeId,
        uidCliente: uid.trim().isEmpty ? null : uid,
      );
      return;
    }

    if (_postViajeFlujoIniciadoParaViajeId == viajeId) return;
    if (ClientePostViajeReopenGuard.shouldSuppress(
      viajeId,
      viajeData: viajeDataSemilla,
    )) {
      return;
    }
    if (await ClientePostViajeReopenGuard.shouldSuppressAsync(
      viajeId,
      viajeData: viajeDataSemilla,
    )) {
      return;
    }

    _postViajeRequiereAccionManual = false;
    _postViajeManualViajeId = null;
    _postViajeManualSemilla = null;
    ClientePostViajeReopenGuard.markOpened(viajeId);

    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();

    try {
      // Factura primero (navigator raíz): no depende del overlay del shell.
      await PostViajeClienteNav.abrirFacturaYFlujo(
        context: context,
        viajeId: viajeId,
        viajeDataSemilla: viajeDataSemilla,
      );
      _postViajeFlujoIniciadoParaViajeId = viajeId;
      final String? uidCierre = uid.trim().isNotEmpty ? uid : null;
      await ClientePostViajeReopenGuard.markCompleted(
        viajeId: viajeId,
        uidCliente: uidCierre,
      );
    } catch (e, st) {
      debugPrint('[PostViaje] navegación post-viaje falló: $e\n$st');
      _postViajeFlujoIniciadoParaViajeId = '';
      _navPostViajeParaId = null;
      _postViajeRequiereAccionManual = true;
      _postViajeManualViajeId = viajeId;
      _postViajeManualSemilla = viajeDataSemilla != null
          ? Map<String, dynamic>.from(viajeDataSemilla)
          : null;
      if (mounted) setState(() {});
    } finally {
      ActiveTripService.cancelarMantenimientoOverlayViaje();
      try {
        await ActiveTripService.prepararSalidaClienteAlInicio(
          uid: uid,
          viajeId: viajeId,
          forzarLimpieza: true,
        ).timeout(
          const Duration(seconds: 12),
          onTimeout: () {},
        );
      } catch (_) {}
      if (mounted) setState(_limpiarCacheCierreViaje);
    }
  }

  Future<void> _reintentarPostViajeManual() async {
    final String viajeId = (_postViajeManualViajeId ?? '').trim();
    if (viajeId.isEmpty || _abriendoFlujoPostViaje) return;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    _postViajeRequiereAccionManual = false;
    _navPostViajeParaId = viajeId;
    _abriendoFlujoPostViaje = true;
    try {
      await _abrirFlujoPostViaje(
        viajeId: viajeId,
        uid: uid,
        viajeDataSemilla: _postViajeManualSemilla,
      );
    } finally {
      _abriendoFlujoPostViaje = false;
    }
  }

  bool _viajeClienteCompletadoParaPostViaje(Map<String, dynamic> d) {
    if (d['completado'] == true) return true;
    final String st = EstadosViaje.normalizar((d['estado'] ?? '').toString());
    return st == EstadosViaje.completado;
  }

  bool _viajeClienteCanceladoORechazado(Map<String, dynamic> d) {
    final String st = EstadosViaje.normalizar((d['estado'] ?? '').toString());
    if (st == EstadosViaje.cancelado || st == EstadosViaje.rechazado) {
      return true;
    }
    // Legado: taxista cancelaba republicando a pendiente — igual es cierre.
    final String canceladoPor = (d['canceladoPor'] ?? '').toString().trim();
    if (canceladoPor == 'taxista' || canceladoPor == 'taxista_forzado') {
      return st == EstadosViaje.pendiente || st == 'pendiente_admin';
    }
    return false;
  }

  Widget _pantallaTransicionCierre({
    required String mensaje,
    bool mostrarBotonInicio = false,
  }) {
    if (mostrarBotonInicio) {
      _programarSalidaAutomaticaSinViaje();
    }
    return ColoredBox(
      color: const Color(0xFF0A0A0A),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!mostrarBotonInicio)
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.greenAccent,
                    ),
                  ),
                if (!mostrarBotonInicio) const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    mensaje,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ),
                if (mostrarBotonInicio) ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _yendoAlInicio
                            ? null
                            : () => unawaited(
                                  _irAlInicioSeguro(
                                      forzarLimpiarViajeActivo: true),
                                ),
                        icon: _yendoAlInicio
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.home_rounded, size: 20),
                        label: Text(
                          _yendoAlInicio ? 'Volviendo…' : 'Volver al inicio',
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                ],
                if (_postViajeRequiereAccionManual &&
                    (_postViajeManualViajeId ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _abriendoFlujoPostViaje
                            ? null
                            : () => unawaited(_reintentarPostViajeManual()),
                        icon: const Icon(Icons.receipt_long_rounded),
                        label: const Text('Ver recibo del viaje'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _yendoAlInicio
                            ? null
                            : () => unawaited(
                                  _irAlInicioSeguro(
                                      forzarLimpiarViajeActivo: true),
                                ),
                        icon: const Icon(Icons.home_rounded),
                        label: const Text('Volver al inicio'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Una sola salida al inicio tras cancelación (evita pestañeo por streams).
  Future<void> _iniciarSalidaTrasCancelacion({
    required String viajeId,
    required Map<String, dynamic> data,
    required String origen,
  }) async {
    final String id = viajeId.trim();
    if (id.isEmpty) return;
    if (_salidaCierreIniciadaParaViajeId == id) return;
    _salidaCierreIniciadaParaViajeId = id;

    print('[VIAJE_ACTIVO] cliente $origen: salida única tras cancelación $id');
    ActiveTripService.liberarClienteTrasCancelacionOViajeTerminal(id);
    _stopClienteUbicacionEnViaje();
    _limpiarCacheCierreViaje();

    final String canceladoPor = (data['canceladoPor'] ?? '').toString().trim();
    final bool porConductor =
        canceladoPor == 'taxista' || canceladoPor == 'taxista_forzado';
    final String estN =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Limpieza en paralelo; no bloquear la navegación.
    unawaited(() async {
      if (uid.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
            'viajeActivoId': '',
            'siguienteViajeId': '',
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).timeout(const Duration(seconds: 6));
        } catch (_) {}
      }
      if (porConductor &&
          (estN == EstadosViaje.pendiente || estN == 'pendiente_admin')) {
        try {
          await FirebaseFirestore.instance.collection('viajes').doc(id).set({
            'estado': EstadosViaje.cancelado,
            'aceptado': false,
            'rechazado': true,
            'activo': false,
            'republicado': false,
            'uidTaxista': '',
            'taxistaId': '',
            'canceladoPor': 'taxista',
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).timeout(const Duration(seconds: 6));
        } catch (_) {}
      }
    }());

    if (!mounted) return;
    if (porConductor && !_snackCancelConductorMostrado) {
      _snackCancelConductorMostrado = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El conductor canceló el viaje.'),
          backgroundColor: Color(0xFFB45309),
          duration: Duration(seconds: 3),
        ),
      );
    }

    if (!mounted) return;
    try {
      await _irAlInicioSeguro(forzarLimpiarViajeActivo: true);
    } catch (_) {}
  }

  bool _viajeClienteSigueOperativoEnPantalla(Map<String, dynamic> data) {
    if (_viajeClienteCompletadoParaPostViaje(data)) return false;
    if (_viajeClienteCanceladoORechazado(data)) return false;
    final String st =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    if (EstadosViaje.esAceptado(st) ||
        EstadosViaje.esEnCaminoPickup(st) ||
        EstadosViaje.esAbordo(st) ||
        EstadosViaje.esEnCurso(st)) {
      return true;
    }
    final String tid =
        (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString().trim();
    // Claim en curso: el taxista ya está, el estado puede ir un snapshot atrasado.
    return tid.isNotEmpty;
  }

  void _manejarViajeCerradoSiCorresponde({
    required String viajeId,
    required String uid,
    required Map<String, dynamic> data,
    required String origen,
  }) {
    if (_viajeIdCanceladoPorCliente == viajeId) {
      return;
    }
    // Aceptación / pickup / a bordo / en curso: permanecer en viaje en curso.
    if (_viajeClienteSigueOperativoEnPantalla(data)) {
      return;
    }
    if (!_viajeClienteCompletadoParaPostViaje(data) &&
        !_viajeClienteCanceladoORechazado(data)) {
      return;
    }
    if (_viajeClienteCompletadoParaPostViaje(data)) {
      ActiveTripService.marcarFlujoPostViajeCliente(viajeId);
      print('[VIAJE_ACTIVO] cliente $origen: viaje completado → post-viaje');
      _programarFlujoPostViaje(
        viajeId: viajeId,
        uid: uid,
        viajeDataSemilla: Map<String, dynamic>.from(data),
      );
      return;
    }
    if (_viajeClienteCanceladoORechazado(data)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_iniciarSalidaTrasCancelacion(
          viajeId: viajeId,
          data: data,
          origen: origen,
        ));
      });
    }
  }

  Future<void> _salirTrasCancelacionExitosa() async {
    if (!mounted) return;
    final String vidCancelado = (_viajeIdCanceladoPorCliente ?? '').trim();
    if (vidCancelado.isNotEmpty) {
      ActiveTripService.liberarClienteTrasCancelacionOViajeTerminal(
        vidCancelado,
      );
    }
    setState(() {
      _cancelandoViajeCliente = false;
      _limpiarCacheCierreViaje();
    });
    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Viaje cancelado correctamente.'),
        backgroundColor: Color(0xFF166534),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    await _irAlInicioSeguro(forzarLimpiarViajeActivo: true);
    _viajeIdCanceladoPorCliente = null;
  }

  Future<bool> _cancelacionYaAplicadaEnServidor(String viajeId) async {
    return _viajeQuedoCanceladoEnServidor(viajeId);
  }

  void _programarFlujoPostViaje({
    required String viajeId,
    required String uid,
    Map<String, dynamic>? viajeDataSemilla,
  }) {
    if (_abriendoFlujoPostViaje) return;
    if (_navPostViajeParaId == viajeId) return;
    if (ClientePostViajeReopenGuard.shouldSuppress(
      viajeId,
      viajeData: viajeDataSemilla,
    )) {
      return;
    }
    _navPostViajeParaId = viajeId;
    _abriendoFlujoPostViaje = true;
    ActiveTripService.marcarFlujoPostViajeCliente(viajeId);
    _postViajeTimeoutTimer?.cancel();
    _postViajeTimeoutTimer = Timer(const Duration(seconds: 18), () {
      if (!mounted) return;
      if (_postViajeFlujoIniciadoParaViajeId == viajeId) return;
      if (_postViajeRequiereAccionManual) return;
      _postViajeRequiereAccionManual = true;
      _postViajeManualViajeId = viajeId;
      _postViajeManualSemilla = viajeDataSemilla != null
          ? Map<String, dynamic>.from(viajeDataSemilla)
          : null;
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;
        await _abrirFlujoPostViaje(
          viajeId: viajeId,
          uid: uid,
          viajeDataSemilla: viajeDataSemilla,
        );
      } finally {
        _postViajeTimeoutTimer?.cancel();
        _abriendoFlujoPostViaje = false;
      }
    });
  }

  String _uidTaxistaDelViaje(Viaje v, [Map<String, dynamic>? data]) {
    final String a = v.uidTaxista.trim();
    if (a.isNotEmpty) return a;
    final String b = v.taxistaId.trim();
    if (b.isNotEmpty) return b;
    if (data == null) return '';
    return (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString().trim();
  }

  /// Pago AZUL: solo después de abordar (código verificado o en ruta).
  bool _mostrarSelectorMetodoPagoCliente(
    Viaje v,
    String estadoBase,
    Map<String, dynamic> data,
  ) {
    if (_uidTaxistaDelViaje(v, data).isEmpty) return false;
    if (EstadosViaje.esTerminal(estadoBase)) return false;
    if (MetodoPagoViaje.tarjetaPagadoVerificado(data)) return false;
    return EstadosViaje.esAceptado(estadoBase) ||
        EstadosViaje.esEnCaminoPickup(estadoBase) ||
        EstadosViaje.esAbordo(estadoBase) ||
        EstadosViaje.esEnCurso(estadoBase);
  }

  /// Pago AZUL: solo después de abordar (código verificado o en ruta).
  bool _mostrarPagoTarjetaCliente(
    Viaje v,
    String estadoBase,
    Map<String, dynamic> data, {
    required bool codigoVerificado,
  }) {
    if (!MetodoPagoViaje.esTarjeta(_metodoPagoViaje(v, data))) return false;
    if (_uidTaxistaDelViaje(v, data).isEmpty) return false;
    if (EstadosViaje.esTerminal(estadoBase)) return false;
    if (MetodoPagoViaje.tarjetaPagadoVerificado(data)) return false;
    if (codigoVerificado) return true;
    return EstadosViaje.esAbordo(estadoBase) ||
        EstadosViaje.esEnCurso(estadoBase);
  }

  /// Aviso previo: conductor asignado pero cliente aún no subió.
  bool _mostrarAvisoTarjetaPreAbordo(
    Viaje v,
    String estadoBase,
    Map<String, dynamic> data,
  ) {
    if (!MetodoPagoViaje.esTarjeta(_metodoPagoViaje(v, data))) return false;
    if (_uidTaxistaDelViaje(v, data).isEmpty) return false;
    if (EstadosViaje.esTerminal(estadoBase)) return false;
    if (MetodoPagoViaje.tarjetaPagadoVerificado(data)) return false;
    if (EstadosViaje.esAbordo(estadoBase) ||
        EstadosViaje.esEnCurso(estadoBase)) {
      return false;
    }
    return EstadosViaje.esAceptado(estadoBase) ||
        EstadosViaje.esEnCaminoPickup(estadoBase);
  }

  bool _mostrarTarjetaPagadaCliente(
    Viaje v,
    String estadoBase,
    Map<String, dynamic> data,
  ) {
    if (!MetodoPagoViaje.esTarjeta(_metodoPagoViaje(v, data))) return false;
    if (EstadosViaje.esTerminal(estadoBase)) return false;
    return MetodoPagoViaje.tarjetaPagadoVerificado(data);
  }

  bool _mostrarPagoEfectivoCliente(
    Viaje v,
    String estadoBase,
    Map<String, dynamic> data, {
    required bool codigoVerificado,
  }) {
    final String metodo = _metodoPagoViaje(v, data);
    if (!MetodoPagoViaje.esEfectivo(metodo)) return false;
    if (_uidTaxistaDelViaje(v, data).isEmpty) return false;
    if (EstadosViaje.esTerminal(estadoBase)) return false;
    if (!MetodoPagoViaje.cambioDesdeTarjetaAEfectivo(data)) return false;
    return codigoVerificado ||
        EstadosViaje.esAbordo(estadoBase) ||
        EstadosViaje.esEnCurso(estadoBase);
  }

  String _metodoPagoViaje(Viaje v, Map<String, dynamic> data) {
    return ClienteMetodoPagoViajeUi.resolver(
      viajeId: v.id,
      metodoRemoto: (data['metodoPago'] ?? v.metodoPago).toString(),
    );
  }

  /// El selector ya guardó la elección en [ClienteMetodoPagoViajeUi]; aquí solo
  /// se repinta el sheet (datos de transferencia, avisos de tarjeta, etc.).
  void _aplicarMetodoPagoUiOptimista(String categoria) {
    if (!mounted) return;
    setState(() {});
  }

  Widget _wrapSelectorMetodoPago({
    required Viaje v,
    required Map<String, dynamic> data,
    required String estadoEfectivo,
  }) {
    if (!_mostrarSelectorMetodoPagoCliente(v, estadoEfectivo, data)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ViajeMetodoPagoSelector(
        viajeId: v.id,
        metodoPagoActual: (data['metodoPago'] ?? v.metodoPago).toString(),
        fondoOscuro: true,
        onMetodoSeleccionado: _aplicarMetodoPagoUiOptimista,
      ),
    );
  }

  List<Widget> _buildClienteBloqueTransferenciaActivaWidgets({
    required Viaje v,
    required Map<String, dynamic> data,
    required String estadoEfectivo,
  }) {
    if (!_mostrarDatosTransferenciaCliente(v, estadoEfectivo, data)) {
      return const <Widget>[];
    }
    return <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF10231A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.greenAccent.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            EstadosViaje.esAbordo(estadoEfectivo) ||
                    EstadosViaje.esEnCurso(estadoEfectivo)
                ? 'Ya estás a bordo o en camino al destino. '
                    'Transferí a la cuenta del conductor abajo y conservá el comprobante. '
                    'Al cerrar el viaje verás la factura oficial.'
                : 'Conductor asignado. Transferí a la cuenta de abajo '
                    'cuando quieras; conservá el comprobante.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
      ),
      _buildDatosBancarios(
        v,
        _uidTaxistaDelViaje(v, data),
        v.precio,
        data,
      ),
      const SizedBox(height: 12),
    ];
  }

  /// Cuenta del conductor: en cuanto hay taxista asignado y pago transferencia.
  bool _mostrarDatosTransferenciaCliente(
    Viaje v,
    String estadoBase,
    Map<String, dynamic> data,
  ) {
    if (!MetodoPagoViaje.esTransferencia(_metodoPagoViaje(v, data))) {
      return false;
    }
    if (_uidTaxistaDelViaje(v, data).isEmpty) return false;
    if (EstadosViaje.esTerminal(estadoBase)) return false;
    return EstadosViaje.esAceptado(estadoBase) ||
        EstadosViaje.esEnCaminoPickup(estadoBase) ||
        EstadosViaje.esAbordo(estadoBase) ||
        EstadosViaje.esEnCurso(estadoBase);
  }

  /// Sin conductor aún: aviso breve (sin números de cuenta).
  bool _mostrarAvisoTransferenciaPreAbordo(
    Viaje v,
    String estadoBase,
    Map<String, dynamic> data,
  ) {
    if (!MetodoPagoViaje.esTransferencia(_metodoPagoViaje(v, data))) {
      return false;
    }
    if (_uidTaxistaDelViaje(v, data).isNotEmpty) return false;
    if (EstadosViaje.esTerminal(estadoBase)) return false;
    return EstadosViaje.esPendiente(estadoBase) ||
        estadoBase.trim().toLowerCase() == 'pendiente_admin';
  }

  Future<void> _deleteOrCancelEstricto(Viaje v) async {
    if (_cancelandoViajeCliente) return;
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    final TextEditingController motivoCtrl = TextEditingController();
    String? errorMotivo;
    String? motivo;
    try {
      motivo = await showDialog<String>(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext ctx) {
          final cs = Theme.of(ctx).colorScheme;
          final onSurface = cs.onSurface;
          return StatefulBuilder(
            builder:
                (BuildContext ctx, void Function(void Function()) setLocal) {
              return AlertDialog(
                backgroundColor: cs.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    Icon(Icons.cancel_outlined,
                        color: Colors.redAccent.shade200, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Cancelar viaje',
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Solo puedes cancelar antes de que el viaje esté a bordo o en ruta. '
                        'Si ya vas en marcha con el conductor, usa soporte ante una emergencia real.',
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Si cancelas ahora:',
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _cancelBullet(
                        'Si hay conductor asignado, recibirá la cancelación.',
                        onSurface,
                      ),
                      _cancelBullet(
                        'Las cancelaciones frecuentes o sin causa clara pueden revisarse y afectar el uso de la app.',
                        onSurface,
                      ),
                      _cancelBullet(
                        'En los primeros 60 s el pedido a veces se elimina; después queda registro de cancelación.',
                        onSurface,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Escribe el motivo (obligatorio, mínimo 12 caracteres):',
                        style: TextStyle(
                            color: onSurface.withValues(alpha: 0.85),
                            fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: motivoCtrl,
                        maxLines: 3,
                        style: TextStyle(color: onSurface),
                        decoration: InputDecoration(
                          hintText:
                              'Ej.: Cambio de planes / dirección incorrecta / demora…',
                          hintStyle: TextStyle(
                              color: onSurface.withValues(alpha: 0.45)),
                          filled: true,
                          fillColor: onSurface.withValues(alpha: 0.06),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          errorText: errorMotivo,
                        ),
                        onChanged: (_) {
                          if (errorMotivo != null) {
                            setLocal(() => errorMotivo = null);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop<String>(ctx),
                    style: TextButton.styleFrom(foregroundColor: cs.primary),
                    child: const Text('No, conservar viaje'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      final t = motivoCtrl.text.trim();
                      if (t.length < 12) {
                        setLocal(() => errorMotivo =
                            'Indica un motivo de al menos 12 caracteres.');
                        return;
                      }
                      Navigator.pop<String>(ctx, t);
                    },
                    child: const Text('Confirmar cancelación'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      // No liberar el controlador de inmediato: al cerrar el diálogo aún corre
      // su animación de salida y el TextField se reconstruye. Si se hace dispose
      // sincrónico, usa un controlador ya destruido y rompe la pantalla.
      // Se espera a que termine la transición de cierre.
      Future<void>.delayed(
        const Duration(milliseconds: 500),
        motivoCtrl.dispose,
      );
    }

    if (motivo == null || motivo.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _cancelandoViajeCliente = true;
        _viajeIdCanceladoPorCliente = v.id;
      });
    }

    try {
      await _runWithBlocking(() async {
        // Siempre cancelar vía CF/repo (delete de viajes está denegado en rules).
        await ViajesRepo.cancelarPorCliente(
          viajeId: v.id,
          uidCliente: uid,
          motivo: motivo,
        );

        await _limpiarActivoDelUsuario(uid);
      });
    } on FirebaseException catch (e) {
      if (await _cancelacionYaAplicadaEnServidor(v.id)) {
        await _salirTrasCancelacionExitosa();
        return;
      }
      if (!mounted) return;
      final String detalle = errorAuthEs(e);
      _viajeIdCanceladoPorCliente = null;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              e.code == 'permission-denied'
                  ? 'No se pudo cancelar: permiso denegado. Si acabas de entrar, vuelve a iniciar sesión o prueba otra red.'
                  : 'No se pudo cancelar: $detalle',
            ),
          ),
        );
      if (mounted) setState(() => _cancelandoViajeCliente = false);
      return;
    } on TimeoutException catch (e) {
      if (await _cancelacionYaAplicadaEnServidor(v.id)) {
        await _salirTrasCancelacionExitosa();
        return;
      }
      if (!mounted) return;
      _viajeIdCanceladoPorCliente = null;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
              content: Text(e.message ?? 'La cancelación tardó demasiado.')),
        );
      if (mounted) setState(() => _cancelandoViajeCliente = false);
      return;
    } catch (e) {
      final String lower = e.toString().toLowerCase();
      if ((lower.contains('permission-denied') ||
              lower.contains('permission_denied') ||
              lower.contains('ya está cerrado') ||
              lower.contains('cerrado')) &&
          await _cancelacionYaAplicadaEnServidor(v.id)) {
        await _salirTrasCancelacionExitosa();
        return;
      }
      if (!mounted) return;
      _viajeIdCanceladoPorCliente = null;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('No se pudo cancelar el viaje: $e')),
        );
      if (mounted) setState(() => _cancelandoViajeCliente = false);
      return;
    }

    await _salirTrasCancelacionExitosa();
  }

  // Watch viaje doc
  void _stopTurismoReasignacionTimer() {
    _turismoReasignacionTimer?.cancel();
    _turismoReasignacionTimer = null;
    _turismoReasignacionViajeId = '';
  }

  void _syncTurismoReasignacion(String viajeId, Map<String, dynamic> d) {
    if (ClientePantallaViajeActivo.debeMostrarEsperaTurismo(d)) {
      _stopTurismoReasignacionTimer();
      return;
    }
    if (!AsignacionTurismoRepo.estadoPermiteAutoAsignacionTurismo(d)) {
      _stopTurismoReasignacionTimer();
      return;
    }
    if (_turismoReasignacionTimer != null &&
        _turismoReasignacionViajeId == viajeId) {
      return;
    }
    _stopTurismoReasignacionTimer();
    _turismoReasignacionViajeId = viajeId;
    unawaited(_intentarTurismoReasignacionSilenciosa(viajeId));
    _turismoReasignacionTimer = Timer.periodic(
      const Duration(seconds: 35),
      (_) => unawaited(_intentarTurismoReasignacionSilenciosa(viajeId)),
    );
  }

  Future<void> _intentarTurismoReasignacionSilenciosa(String viajeId) async {
    if (_turismoReasignacionEnCurso || !mounted) return;
    _turismoReasignacionEnCurso = true;
    try {
      await AsignacionTurismoRepo.intentarAsignacionAutomatica(
        viajeId: viajeId,
        radioKm: 55,
      );
    } catch (_) {
      // El stream del viaje reflejará nueva asignación o pool turístico.
    } finally {
      _turismoReasignacionEnCurso = false;
    }
  }

  void _intentarRedirigirEsperaTurismo(
    String viajeId,
    Map<String, dynamic> data,
  ) {
    if (!ClientePantallaViajeActivo.debeMostrarEsperaTurismo(data)) {
      if (_turismoRedirEsperaViajeId == viajeId) {
        _turismoRedirEsperaViajeId = null;
      }
      return;
    }
    if (_turismoRedirEsperaViajeId == viajeId || _turismoRedirEsperaEnCurso) {
      return;
    }
    _turismoRedirEsperaViajeId = viajeId;
    _stopTurismoReasignacionTimer();

    if (widget.delegarEsperaTurismoAlRouter) {
      return;
    }

    _turismoRedirEsperaEnCurso = true;
    final NavigatorState? navRoot = Navigator.of(context, rootNavigator: true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await NavigationService.clearAndGoPage(
          preNav: navRoot,
          page: const ClientePantallaViajeActivo(),
        );
      } finally {
        if (mounted) _turismoRedirEsperaEnCurso = false;
      }
    });
  }


  /// Si el conductor cancela: una sola salida (sin bucle de streams).
  void _avisarSiConductorCancelo(
    Map<String, dynamic> d,
    String estN,
    String viajeIdWatch,
  ) {
    final String canceladoPor = (d['canceladoPor'] ?? '').toString().trim();
    if (canceladoPor != 'taxista' && canceladoPor != 'taxista_forzado') return;

    final dynamic ts = d['canceladoTaxistaEn'];
    DateTime? cancelTs;
    if (ts is Timestamp) cancelTs = ts.toDate();
    if (ts is DateTime) cancelTs = ts;
    if (cancelTs == null) return;

    final bool reciente =
        DateTime.now().difference(cancelTs) < const Duration(minutes: 5);
    final bool yaAvisado = _cancelacionTaxistaAvisada == cancelTs;
    if (!reciente || yaAvisado) return;
    _cancelacionTaxistaAvisada = cancelTs;

    final bool salirYa = estN == EstadosViaje.cancelado ||
        estN == EstadosViaje.pendiente ||
        estN == 'pendiente_admin' ||
        estN == EstadosViaje.rechazado;
    if (!salirYa || !mounted) return;

    final String viajeId = viajeIdWatch.trim();
    if (viajeId.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_iniciarSalidaTrasCancelacion(
        viajeId: viajeId,
        data: d,
        origen: 'watchDocCancelTaxista',
      ));
    });
  }

  List<Widget> _buildClientePantallaAbordoWidgets({
    required Viaje v,
    required Map<String, dynamic> data,
    required String estadoEfectivo,
    required String codigoVerificacion,
    required bool codigoVerificado,
    required bool mostrarCodigoCliente,
  }) {
    return <Widget>[
      const ClienteViajeProgresoStepper(pasoActivo: 3),
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF1A2E1A), Color(0xFF0F1A12)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.45)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.airline_seat_recline_normal_rounded,
                    color: Colors.greenAccent, size: 24),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ya estás a bordo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Dicta el código de 6 dígitos a tu conductor. Él lo ingresa en su '
              'app para iniciar el viaje. Abajo eliges cómo pagar.',
              style:
                  TextStyle(color: Colors.white70, height: 1.4, fontSize: 13.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _buildCodigoVerificacionClienteSection(
        codigoVerificacion: codigoVerificacion,
  codigoVerificado: codigoVerificado,
  estadoBase: estadoEfectivo,
  mostrarCodigo: mostrarCodigoCliente,
  esMotor: v.esMotor,
  viajeIdParaActualizar: v.id,
),
      _viajeSheetDivider('Forma de pago'),
      _wrapSelectorMetodoPago(
        v: v,
        data: data,
        estadoEfectivo: estadoEfectivo,
      ),
      ..._buildClienteBloqueTransferenciaActivaWidgets(
        v: v,
        data: data,
        estadoEfectivo: estadoEfectivo,
      ),
      if (_mostrarPagoTarjetaCliente(
        v,
        estadoEfectivo,
        data,
        codigoVerificado: codigoVerificado,
      )) ...[
        RaiPagoTarjetaPanel(
          viajeId: v.id,
          viajeData: data,
          montoRd: v.precio,
          fondoOscuro: true,
          role: 'cliente',
          modoViajeEnCurso: true,
        ),
        const SizedBox(height: 12),
      ] else if (MetodoPagoViaje.esTarjeta(_metodoPagoViaje(v, data))) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.deepPurpleAccent.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              PagoTarjetaClienteGate.bloqueado
                  ? 'Pago con tarjeta (en desarrollo): por ahora usá efectivo o '
                      'transferencia al conductor. Cuando AZUL esté activo podrás '
                      'pagar aquí antes de llegar al destino.'
                  : 'Pago con tarjeta: al verificar el código con el '
                      'conductor podrás pagar desde aquí antes de llegar al destino.',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _llamarConductorCliente(v),
              icon: const Icon(Icons.phone_rounded, size: 18),
              label: const Text('Llamar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _whatsAppConductorCliente(v),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: const Text('WhatsApp'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
    ];
  }

  /// Pago durante pickup (conductor en camino): PIN + forma de pago.
  List<Widget> _buildClienteSeccionPagoPickupWidgets({
    required Viaje v,
    required Map<String, dynamic> data,
    required String estadoEfectivo,
    required String codigoVerificacion,
    required bool codigoVerificado,
    required bool mostrarCodigoCliente,
  }) {
    return <Widget>[
      _viajeSheetDivider('Forma de pago'),
      _wrapSelectorMetodoPago(
        v: v,
        data: data,
        estadoEfectivo: estadoEfectivo,
      ),
      if (_mostrarAvisoTarjetaPreAbordo(v, estadoEfectivo, data))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.deepPurpleAccent.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              PagoTarjetaClienteGate.bloqueado
                  ? 'Pago con tarjeta (en desarrollo): al subir al vehículo verás el '
                      'código. Por ahora elegí efectivo o transferencia al conductor.'
                  : 'Pago con tarjeta: al subir al vehículo verás el código y podrás '
                      'pagar con AZUL desde esta pantalla.',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ),
      if (_mostrarAvisoTransferenciaPreAbordo(v, estadoEfectivo, data))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.amberAccent.withValues(alpha: 0.35),
              ),
            ),
            child: const Text(
              'Pago por transferencia: al subir verás la cuenta del conductor '
              'para transferirle directamente.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ),
      ..._buildClienteBloqueTransferenciaActivaWidgets(
        v: v,
        data: data,
        estadoEfectivo: estadoEfectivo,
      ),
    ];
  }

  List<Widget> _buildClienteSeccionPinYPagoWidgets({
    required Viaje v,
    required Map<String, dynamic> data,
    required String estadoEfectivo,
    required String codigoVerificacion,
    required bool codigoVerificado,
    required bool mostrarCodigoCliente,
    required bool incluirTarjetaConductor,
  }) {
    return <Widget>[
      if (incluirTarjetaConductor) ...[
        _buildDriverCard(v, soloDatosConductor: true),
        const SizedBox(height: 16),
      ],
      _buildCodigoVerificacionClienteSection(
        codigoVerificacion: codigoVerificacion,
  codigoVerificado: codigoVerificado,
  estadoBase: estadoEfectivo,   
  mostrarCodigo: mostrarCodigoCliente,
  esMotor: v.esMotor,
  viajeIdParaActualizar: v.id,
),
      _wrapSelectorMetodoPago(
        v: v,
        data: data,
        estadoEfectivo: estadoEfectivo,
      ),
      if (_mostrarAvisoTarjetaPreAbordo(v, estadoEfectivo, data))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.deepPurpleAccent.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              PagoTarjetaClienteGate.bloqueado
                  ? 'Pago con tarjeta (en desarrollo): cuando subas al vehículo '
                      'verás el código. Por ahora usá efectivo o transferencia al conductor.'
                  : 'Pago con tarjeta: cuando subas al vehículo y verifiques el código '
                      'con el conductor, verás el botón para pagar desde la app.',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ),
      if (_mostrarAvisoTransferenciaPreAbordo(v, estadoEfectivo, data))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1F2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.amberAccent.withValues(alpha: 0.35),
              ),
            ),
            child: const Text(
              'Pago por transferencia: en cuanto se asigne un conductor '
              'verás aquí su cuenta bancaria para transferirle directamente.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ),
      ..._buildClienteBloqueTransferenciaActivaWidgets(
        v: v,
        data: data,
        estadoEfectivo: estadoEfectivo,
      ),
      if (_mostrarPagoTarjetaCliente(
        v,
        estadoEfectivo,
        data,
        codigoVerificado: codigoVerificado,
      )) ...[
        const SizedBox(height: 12),
        RaiPagoTarjetaPanel(
          viajeId: v.id,
          viajeData: data,
          montoRd: v.precio,
          fondoOscuro: true,
          role: 'cliente',
          modoViajeEnCurso: true,
        ),
        const SizedBox(height: 16),
      ] else if (_mostrarTarjetaPagadaCliente(v, estadoEfectivo, data)) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF10231A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.greenAccent.withValues(alpha: 0.45),
            ),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.greenAccent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pago con tarjeta confirmado. '
                  'Al finalizar el viaje verás tu recibo.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ] else if (_mostrarPagoEfectivoCliente(
        v,
        estadoEfectivo,
        data,
        codigoVerificado: codigoVerificado,
      )) ...[
        const SizedBox(height: 12),
        EfectivoPagoClienteBanner(
          montoRd: v.precio,
          desdeTarjeta: true,
        ),
        const SizedBox(height: 16),
      ],
    ];
  }


  /// Ida y vuelta: el cliente pagó el regreso, así que tiene que ver en qué
  /// tramo va y que el chofer está obligado a devolverlo.
  Widget _bannerIdaYVuelta(Viaje v) {
    if (!v.idaYVuelta) return const SizedBox.shrink();
    if (!EstadosViaje.esEnCurso(_normEstadoViaje(v))) {
      return const SizedBox.shrink();
    }
    final bool volviendo = v.regresoEnCurso;
    if (!volviendo && !v.regresoPendiente) return const SizedBox.shrink();

    final Color color =
        volviendo ? Colors.lightBlueAccent : Colors.amberAccent;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              volviendo ? Icons.u_turn_left_rounded : Icons.swap_horiz_rounded,
              color: color,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                volviendo
                    ? 'De regreso a ${v.origen}. Este viaje incluye la vuelta.'
                    : 'Viaje ida y vuelta: el regreso ya está pagado. '
                        'Tu chofer te lleva de vuelta cuando estés listo.',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget de paradas
  Widget _buildParadasWidget(Viaje v) {
    final List<({double lat, double lon, String label})> paradas =
        _paradasIntermediasResueltas(v);
    if (paradas.isEmpty) {
      return const SizedBox.shrink();
    }

    final int hechos = v.multiparadaLegCompletadas.clamp(0, paradas.length + 1);
    final bool rutaEnCurso = EstadosViaje.esEnCurso(_normEstadoViaje(v));

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.route, size: 16, color: Colors.blueAccent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '📍 Ruta con paradas:',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.flag_circle, size: 14, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Origen: ${v.origen}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          ...paradas.asMap().entries.map((entry) {
            final int index = entry.key + 1;
            final String label = entry.value.label;
            final int legIndex = entry.key;
            final bool visitada = hechos > legIndex;
            final bool actual = rutaEnCurso && hechos == legIndex;
            return Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4, top: 2),
              child: Row(
                children: [
                  Icon(
                    visitada
                        ? Icons.check_circle
                        : (actual
                            ? Icons.radio_button_checked
                            : Icons.flag_circle),
                    size: 14,
                    color: visitada
                        ? Colors.greenAccent
                        : (actual ? Colors.orangeAccent : Colors.orange),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Parada $index: $label',
                      style: TextStyle(
                        color: actual ? Colors.white : Colors.white70,
                        fontSize: 13,
                        fontWeight:
                            actual ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Row(
              children: [
                Icon(
                  hechos >= paradas.length + 1 || v.multiparadaCompleta
                      ? Icons.check_circle
                      : (rutaEnCurso && hechos == paradas.length
                          ? Icons.radio_button_checked
                          : Icons.flag_circle),
                  size: 14,
                  color: hechos >= paradas.length + 1 || v.multiparadaCompleta
                      ? Colors.greenAccent
                      : (rutaEnCurso && hechos == paradas.length
                          ? Colors.orangeAccent
                          : Colors.red),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Destino: ${v.destino}',
                    style: TextStyle(
                      color: rutaEnCurso && hechos == paradas.length
                          ? Colors.white
                          : Colors.white70,
                      fontSize: 13,
                      fontWeight: rutaEnCurso && hechos == paradas.length
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runWithBlocking(Future<void> Function() task) async {
    if (!mounted) return;
    final barrier = Theme.of(context).brightness == Brightness.dark
        ? Colors.black54
        : Colors.black26;
    BuildContext? loaderContext;
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: barrier,
      builder: (BuildContext dialogContext) {
        loaderContext = dialogContext;
        final ColorScheme cs = Theme.of(dialogContext).colorScheme;
        return PopScope(
          canPop: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      color: cs.primary,
                      backgroundColor:
                          cs.surfaceContainerHighest.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Cancelando viaje…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.88),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    try {
      await task().timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException(
          'Tiempo de espera agotado. Verifica tu conexión e inténtalo de nuevo.',
        ),
      );
    } finally {
      final BuildContext? lc = loaderContext;
      if (lc != null && lc.mounted) {
        try {
          final NavigatorState nav = Navigator.of(lc, rootNavigator: true);
          if (nav.mounted) {
            nav.pop();
          }
        } catch (_) {
          if (mounted) {
            try {
              Navigator.of(context, rootNavigator: true).maybePop();
            } catch (_) {}
          }
        }
      }
    }
  }

  String _labelEstado(String e) {
    if (e.trim().toLowerCase() == 'pendiente_admin') {
      return 'Solicitud enviada';
    }
    final String s = EstadosViaje.normalizar(e);
    if (s == EstadosViaje.pendiente) return 'Pendiente';
    if (s == EstadosViaje.aceptado) return 'Aceptado';
    if (s == EstadosViaje.enCaminoPickup) return 'Conductor en camino';
    if (s == EstadosViaje.aBordo) return 'A bordo';
    if (s == EstadosViaje.enCurso) return 'En curso';
    if (s == EstadosViaje.completado) return 'Completado';
    if (s == EstadosViaje.cancelado) return 'Cancelado';
    return e;
  }

  int _etapaActualViajeCliente(String estadoBase) {
    if (EstadosViaje.esCompletado(estadoBase)) return 4;
    if (EstadosViaje.esEnCurso(estadoBase)) return 3;
    if (EstadosViaje.esAbordo(estadoBase)) return 2;
    if (EstadosViaje.esEnCaminoPickup(estadoBase) ||
        EstadosViaje.esAceptado(estadoBase)) {
      return 1;
    }
    return 0;
  }

  Widget _progresoOperativoCliente(String estadoBase) {
    final int etapa = _etapaActualViajeCliente(estadoBase);
    const List<String> labels = <String>[
      'Aceptado',
      'Pickup',
      'A bordo',
      'En ruta',
      'Finalizado',
    ];
    final ColorScheme cs = Theme.of(context).colorScheme;
    final double progress = (etapa + 1) / labels.length;

    // La tarjeta de información del viaje usa panel oscuro: neutros claros para contraste.
    // El brillo animado usa el ColorScheme (se adapta al tema claro/oscuro de la app).
    final Color tituloProgreso = Colors.white.withValues(alpha: 0.58);
    final Color trackColor = Colors.white.withValues(alpha: 0.12);
    final Color chipBgIdle = Colors.white.withValues(alpha: 0.08);
    final Color chipBorderIdle = Colors.white.withValues(alpha: 0.24);
    final Color textoChipPendiente = Colors.white.withValues(alpha: 0.68);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PROGRESO DEL VIAJE',
          style: TextStyle(
              color: tituloProgreso, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: trackColor),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedBuilder(
                    animation: _progresoBrilloCtrl,
                    builder: (BuildContext context, Widget? child) {
                      final double t = _progresoBrilloCtrl.value;
                      final double sweep = -1.15 + 2.5 * t;
                      return FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(sweep, 0),
                              end: Alignment(sweep + 0.9, 0),
                              colors: <Color>[
                                cs.primary.withValues(alpha: 0.55),
                                Color.lerp(cs.primary, cs.tertiary, 0.45)!,
                                const Color(0xFF69F0AE),
                                Color.lerp(cs.tertiary, cs.primary, 0.35)!,
                                cs.primary.withValues(alpha: 0.75),
                              ],
                              stops: const <double>[0.0, 0.28, 0.48, 0.72, 1.0],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List<Widget>.generate(labels.length, (int i) {
            final bool done = i <= etapa;
            final bool activo = i == etapa;
            return AnimatedBuilder(
              animation: _progresoBrilloCtrl,
              builder: (BuildContext context, Widget? child) {
                final double t = _progresoBrilloCtrl.value;
                final double pulse = activo
                    ? (0.45 + 0.55 * (0.5 + 0.5 * math.sin(t * math.pi * 2)))
                    : 0.0;
                final Color fillDone = Color.lerp(
                  cs.primary.withValues(alpha: 0.22),
                  cs.tertiary.withValues(alpha: 0.28),
                  0.5 + 0.5 * math.sin(t * math.pi * 2),
                )!;
                final Color borderDone =
                    Color.lerp(cs.primary, cs.tertiary, t)!;
                final Color textoDone = Color.lerp(
                    cs.primary,
                    const Color(0xFF69F0AE),
                    0.35 + 0.25 * math.sin(t * math.pi * 2))!;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: done ? fillDone : chipBgIdle,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: done
                          ? borderDone.withValues(alpha: 0.75 + 0.2 * pulse)
                          : chipBorderIdle,
                      width: activo ? 1.4 : 1,
                    ),
                    boxShadow: activo
                        ? <BoxShadow>[
                            BoxShadow(
                              color: cs.primary
                                  .withValues(alpha: 0.12 + 0.22 * pulse),
                              blurRadius: 10 + 6 * pulse,
                              spreadRadius: 0.5 * pulse,
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: done ? textoDone : textoChipPendiente,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ],
    );
  }

  Widget _cancelBullet(String text, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.45),
              height: 1.35,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.72),
                height: 1.35,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _pasajerosDesdeExtras(Viaje v) {
    final Map<String, dynamic>? ex = v.extras;
    if (ex == null) return null;
    final dynamic p =
        ex['pasajeros'] ?? ex['numPasajeros'] ?? ex['pasajeros_count'];
    if (p == null) return null;
    final String t = p.toString().trim();
    return t.isEmpty ? null : t;
  }

  Widget _buildTripInfoCard(Viaje v, String estadoBase) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ORIGEN',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 4),
                    RaiViajeEnCursoUi.ellipsizedText(
                      v.origen,
                      maxLines: 3,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.greenAccent),
                  ),
                  child: Text(
                    _labelEstado(estadoBase),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.arrow_downward, size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DESTINO',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(v.destino,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('FECHA',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(_safeFecha(v.fechaHora),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('TOTAL',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(_safeMoney(v.precio),
                      style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('MÉTODO DE PAGO',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            v.metodoPago.trim().isEmpty ? '—' : v.metodoPago,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          _progresoOperativoCliente(estadoBase),
          if (_pasajerosDesdeExtras(v) != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.people_outline,
                    color: Colors.white54, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pasajeros: ${_pasajerosDesdeExtras(v)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// ETA aproximada hacia el punto de recogida (solo lectura; ~28 km/h urbano RD).
  String _lineaEtaPickupCliente(Viaje v, String estadoBase) {
    if (!_isValidCoord(v.latTaxista, v.lonTaxista) ||
        !_isValidCoord(v.latCliente, v.lonCliente)) {
      return 'Ubicación del conductor actualizándose…';
    }
    final double km = DistanciaService.calcularDistancia(
      v.latTaxista,
      v.lonTaxista,
      v.latCliente,
      v.lonCliente,
    );
    if (estadoBase == EstadosViaje.aceptado ||
        estadoBase == EstadosViaje.enCaminoPickup) {
      // En pruebas reales (o cuando ya está al frente), evita texto ambiguo.
      if (km <= 0.03) {
        return 'Tu conductor ya llegó a tu ubicación';
      }
      final int min = (km / 28.0 * 60).clamp(1, 180).round();
      final String distTxt =
          km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';
      return 'Llega en ~$min min · te queda $distTxt';
    }
    if (estadoBase == EstadosViaje.aBordo) {
      return 'A bordo · confirma el código con tu conductor si aplica';
    }
    if (estadoBase == EstadosViaje.enCurso) {
      return 'Viaje en marcha hacia tu destino';
    }
    return 'Conductor asignado';
  }

  Widget _buildDriverCard(Viaje v, {bool soloDatosConductor = false}) {
    final ColorScheme csRoot = Theme.of(context).colorScheme;
    if (v.uidTaxista.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: csRoot.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: csRoot.outlineVariant),
        ),
        child: Center(
          child: Text(
            'Buscando conductor...',
            style: TextStyle(color: csRoot.onSurfaceVariant, fontSize: 16),
          ),
        ),
      );
    }

    final DocumentReference<Map<String, dynamic>> taxistaRef =
        FirebaseFirestore.instance.collection('usuarios').doc(v.uidTaxista);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: taxistaRef.snapshots().distinct(),
      builder: (context, snap) {
        final Map<String, dynamic> tx = (snap.hasData && snap.data!.exists)
            ? (snap.data!.data() ?? const {})
            : const {};

        final String nombre = v.nombreTaxista.isNotEmpty
            ? v.nombreTaxista
            : (tx['nombre'] ?? tx['displayName'] ?? '').toString();

        final String telFromViaje =
            v.telefonoTaxista.isNotEmpty ? v.telefonoTaxista : v.telefono;
        String tel = telFromViaje.trim();
        if (tel.isEmpty) {
          tel = telefonoCrudoDesdeMapa(tx);
        }

        final String tipo = _s(v.tipoVehiculo).trim().isNotEmpty
            ? _s(v.tipoVehiculo).trim()
            : _s(tx['tipoVehiculo']).trim();
        final String marca = _s((v as dynamic).marca).trim().isNotEmpty
            ? _s((v as dynamic).marca).trim()
            : _s(tx['marca']).trim().isNotEmpty
                ? _s(tx['marca']).trim()
                : _s(tx['vehiculoMarca']).trim();
        final String modelo = _s((v as dynamic).modelo).trim().isNotEmpty
            ? _s((v as dynamic).modelo).trim()
            : _s(tx['modelo']).trim().isNotEmpty
                ? _s(tx['modelo']).trim()
                : _s(tx['vehiculoModelo']).trim();
        final String color = _s((v as dynamic).color).trim().isNotEmpty
            ? _s((v as dynamic).color).trim()
            : _s(tx['color']).trim().isNotEmpty
                ? _s(tx['color']).trim()
                : _s(tx['vehiculoColor']).trim();
        final String placa = _s((v as dynamic).placa).trim().isNotEmpty
            ? _s((v as dynamic).placa).trim()
            : _s(tx['placa']).trim();

        final String vehiculoLinea = <String>[
          if (tipo.isNotEmpty) tipo,
          if (marca.isNotEmpty) marca,
          if (modelo.isNotEmpty) modelo,
        ].join(' · ');

        final ColorScheme cs = Theme.of(context).colorScheme;
        final String estCard = EstadosViaje.normalizar(v.estado);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cs.surfaceContainerHighest,
                Color.lerp(
                    cs.surfaceContainerHighest, cs.primaryContainer, 0.08)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: cs.surfaceContainerHigh,
                        backgroundImage: tx['fotoUrl'] != null &&
                                tx['fotoUrl'].toString().isNotEmpty
                            ? NetworkImage(tx['fotoUrl'].toString())
                            : null,
                        child: tx['fotoUrl'] == null ||
                                tx['fotoUrl'].toString().isEmpty
                            ? Icon(Icons.person,
                                color: cs.onSurfaceVariant, size: 30)
                            : null,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: cs.surfaceContainerHighest, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                nombre.isEmpty ? 'Tu conductor' : nombre,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: cs.onSurface,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.bolt, size: 14, color: cs.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'En vivo',
                                    style: TextStyle(
                                      color: cs.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          vehiculoLinea.isEmpty ? 'Vehículo' : vehiculoLinea,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 14),
                        ),
                        if (color.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Color $color',
                            style: TextStyle(
                                color:
                                    cs.onSurfaceVariant.withValues(alpha: 0.85),
                                fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (placa.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: cs.primary.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.directions_car_filled,
                          color: cs.primary, size: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PLACAS',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.2,
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              placa.toUpperCase(),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (!soloDatosConductor) ...[
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: _progresoBrilloCtrl,
                  builder: (BuildContext context, Widget? _) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _isValidCoord(v.latTaxista, v.lonTaxista)
                          ? () => _centrarEnTaxista(v)
                          : null,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: Color.lerp(
                            const Color(0xFF0E1F16),
                            const Color(0xFF152B1F),
                            _progresoBrilloCtrl.value,
                          ),
                          border: Border.all(
                              color:
                                  Colors.greenAccent.withValues(alpha: 0.28)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.route_rounded,
                                color: Colors.greenAccent.shade200, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _lineaEtaPickupCliente(v, estCard),
                                key: ValueKey<String>(
                                  '${v.latTaxista}_${v.lonTaxista}_${v.latCliente}_${v.lonCliente}_$estCard',
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _actionButton(
                        context,
                        icon: Icons.phone,
                        label: 'Llamar',
                        onPressed: () async {
                          final String raw = tel.trim().isNotEmpty
                              ? tel
                              : telefonoCrudoDesdeMapa(tx);
                          final String tc = telefonoNormalizarDigitos(raw);
                          if (tc.isEmpty) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Número del conductor no disponible aún. Usa el chat o espera unos segundos.',
                                ),
                              ),
                            );
                            return;
                          }
                          unawaited(ViajeComunicacionRepo
                              .notificarIntentoComunicacion(
                            viajeId: v.id,
                            tipo: 'llamada',
                          ));
                          await telefonoLaunchUri(telefonoUriLlamada(tc));
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionButton(
                        context,
                        icon: Icons.chat_bubble_outline,
                        label: 'WhatsApp',
                        onPressed: () async {
                          final String raw = tel.trim().isNotEmpty
                              ? tel
                              : telefonoCrudoDesdeMapa(tx);
                          final String tc = telefonoNormalizarDigitos(raw);
                          if (tc.isEmpty) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Número del conductor no disponible aún. Usa el chat o espera unos segundos.',
                                ),
                              ),
                            );
                            return;
                          }
                          unawaited(ViajeComunicacionRepo
                              .notificarIntentoComunicacion(
                            viajeId: v.id,
                            tipo: 'whatsapp',
                          ));
                          const String waMsg = 'Hola, soy tu cliente de RAI.';
                          if (await telefonoLaunchUri(
                            telefonoUriWhatsAppApp(tc, waMsg),
                          )) {
                            return;
                          }
                          await telefonoLaunchUri(
                            telefonoUriWhatsAppWeb(tc, waMsg),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionButton(
                        context,
                        icon: Icons.chat,
                        label: 'Chat',
                        onPressed: () {
                          final String uidTx = _uidTaxistaDelViaje(v);
                          final String miUid =
                              FirebaseAuth.instance.currentUser?.uid ?? '';
                          unawaited(ChatViajeNav.abrir(
                            context: context,
                            miUid: miUid,
                            otroUid: uidTx,
                            otroNombre: nombre,
                            viajeId: v.id,
                          ));
                        },
                      ),
                    ),
                  ],
                ),
                if (v.uidTaxista.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ViajeChatMensajesEnVivo(
                    viajeId: v.id,
                    miUid: FirebaseAuth.instance.currentUser?.uid ?? '',
                    otroUid: v.uidTaxista,
                    otroNombre: nombre,
                  ),
                ],
                const SizedBox(height: 10),
                if (_isValidCoord(v.latTaxista, v.lonTaxista)) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _centrarEnTaxista(v),
                      icon: Icon(Icons.navigation, color: cs.primary),
                      label: Text(
                        'Ver conductor en tiempo real',
                        style: TextStyle(color: cs.primary),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: cs.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          unawaited(_openGoogleMapsVerUbicacionConductor(
                        v.latTaxista,
                        v.lonTaxista,
                      )),
                      icon:
                          Icon(Icons.map_outlined, color: cs.onSurfaceVariant),
                      label: Text(
                        'Ver ubicación en Google Maps',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: cs.outlineVariant),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        splashColor: cs.primary.withValues(alpha: 0.12),
        highlightColor: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: onPressed == null
                      ? cs.onSurface.withValues(alpha: 0.38)
                      : cs.primary,
                  size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: onPressed == null
                      ? cs.onSurface.withValues(alpha: 0.38)
                      : cs.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _subirComprobanteTransferencia({
    required String viajeId,
  }) async {
    final User? u = FirebaseAuth.instance.currentUser;
    if (u == null) return null;
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (file == null) return null;

    final Uint8List bytes = await file.readAsBytes();
    final String path =
        'comprobantes/${u.uid}/$viajeId/transfer_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<void> _reportarTransferencia({
    required Viaje v,
  }) async {
    if (_subiendoComprobanteTransfer) return;
    setState(() => _subiendoComprobanteTransfer = true);
    try {
      final String? comprobanteUrl =
          await _subirComprobanteTransferencia(viajeId: v.id);
      if (comprobanteUrl == null || comprobanteUrl.isEmpty) return;
      await ViajesRepo.marcarTransferenciaReportadaCliente(
        viajeId: v.id,
        comprobanteUrl: comprobanteUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comprobante enviado. Admin lo validara en breve.'),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error (${e.code}): ${e.message ?? ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo subir comprobante: $e')),
      );
    } finally {
      if (mounted) setState(() => _subiendoComprobanteTransfer = false);
    }
  }

  Future<void> _abrirWhatsAppPago({
    required Viaje v,
  }) async {
    final String telClean = telefonoNormalizarDigitos(
      v.telefonoTaxista.isNotEmpty ? v.telefonoTaxista : v.telefono,
    );
    if (telClean.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('El taxista no tiene WhatsApp configurado.')),
      );
      return;
    }
    final String waMsg =
        'Hola, ya realice la transferencia del viaje #${v.id.substring(0, 6).toUpperCase()} y subi el comprobante en la app.';
    if (await telefonoLaunchUri(telefonoUriWhatsAppApp(telClean, waMsg))) {
      return;
    }
    await telefonoLaunchUri(telefonoUriWhatsAppWeb(telClean, waMsg));
  }

  // Datos bancarios del conductor (snapshot en viaje al finalizar + perfil en vivo).
  Widget _buildDatosBancarios(
      Viaje v, String taxistaId, double monto, Map<String, dynamic> viajeData) {
    return TransferenciaRecaudoUi.panel(
      viajeData: viajeData,
      uidTaxista: taxistaId,
      montoRd: monto,
      fondoOscuro: true,
      tituloConductor: 'DATOS PARA TRANSFERENCIA AL CONDUCTOR',
      tituloRai: 'PAGAR A RAI (TRANSFERENCIA)',
      footer: Builder(
        builder: (_) {
          final String estadoPago =
              (viajeData['estadoPago'] ?? '').toString().trim().toLowerCase();
          final String paymentStatus = (viajeData['payment']?['status'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final String comprobante =
              (viajeData['comprobanteTransferenciaUrl'] ?? '').toString();
          final String motivoRechazo =
              (viajeData['motivoRechazoTransferencia'] ?? '').toString().trim();
          final bool confirmada = viajeData['transferenciaConfirmada'] == true;
          if (confirmada || estadoPago == 'verificado') {
            return const Text(
              'Transferencia validada por Administracion.',
              style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.w700,
              ),
            );
          }
          if (estadoPago == 'pagado' ||
              paymentStatus == 'pending_admin_confirmation') {
            return const Text(
              'Comprobante enviado. Pendiente de validacion.',
              style: TextStyle(
                color: Colors.amberAccent,
                fontWeight: FontWeight.w700,
              ),
            );
          }
          if (paymentStatus == 'bank_transfer_rejected') {
            return Column(
              children: [
                Text(
                  motivoRechazo.isEmpty
                      ? 'Transferencia rechazada por administración. Revisa el comprobante y vuelve a enviarlo.'
                      : 'Transferencia rechazada: $motivoRechazo',
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _subiendoComprobanteTransfer
                      ? null
                      : () => _reportarTransferencia(v: v),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reenviar comprobante'),
                ),
              ],
            );
          }
          return SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: _subiendoComprobanteTransfer
                      ? null
                      : () => _reportarTransferencia(v: v),
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                    _subiendoComprobanteTransfer
                        ? 'Subiendo comprobante...'
                        : (comprobante.isNotEmpty
                            ? 'Reenviar comprobante'
                            : 'Subir comprobante de transferencia'),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _abrirWhatsAppPago(v: v),
                  icon: const Icon(Icons.chat),
                  label: const Text('Avisar por WhatsApp al taxista'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

 @override
Widget build(BuildContext context) {
  final User? u = FirebaseAuth.instance.currentUser;

return PopScope(
  canPop: false,
  onPopInvokedWithResult: (bool didPop, Object? result) {
    if (didPop ||
        _yendoAlInicio ||
        _suprimirPopScopeAutomatico ||
        ActiveTripService.retomarClienteEnCurso ||
        ActiveTripService.pausaClienteBloqueadaPorRetomar()) {
      return;
    }
    print('[VIAJE_ACTIVO] PopScope back → viaje pegado (sin pausa)');
    _avisoViajeSigueActivo();
  },
  child: Scaffold(
      backgroundColor: Colors.black,
      appBar: RaiAppBar(
        title: 'Mi viaje en curso',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
          onPressed: _yendoAlInicio ? null : _avisoViajeSigueActivo,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: (u == null)
          ? const Center(
              child: Text('Inicia sesión para ver tu viaje.',
                  style: TextStyle(color: Colors.white70)),
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(u.uid)
                  .snapshots()
                  .distinct(),
              builder: (context, userSnap) {
                final bool usuarioStreamFallo = userSnap.hasError;
                if (!usuarioStreamFallo) {
                  if (userSnap.connectionState == ConnectionState.waiting &&
                      !userSnap.hasData) {
                    return _cargaLinealOscura();
                  }
                  if (!userSnap.hasData || !userSnap.data!.exists) {
                    return _bodySinViajeActivo(
                        mensaje: 'No tienes viaje activo.');
                  }
                } else if (userSnap.connectionState ==
                    ConnectionState.waiting) {
                  return _cargaLinealOscura(
                    mensaje: 'Conectando con tu viaje…',
                  );
                }

                final Map<String, dynamic> userData =
                    userSnap.hasData && userSnap.data!.exists
                        ? (userSnap.data!.data() ?? <String, dynamic>{})
                        : <String, dynamic>{};
                final String viajeIdUsuario =
                    (userData['viajeActivoId'] ?? '').toString().trim();
                String viajeIdSeguimiento = viajeIdUsuario;
                if (viajeIdSeguimiento.isEmpty) {
                  viajeIdSeguimiento = _lastNonEmptyViajeActivoId.trim();
                }
                if (viajeIdSeguimiento.isEmpty) {
                  viajeIdSeguimiento =
                      ActiveTripService.viajeOperativoClienteConocido;
                }
                if (viajeIdSeguimiento.isEmpty) {
                  viajeIdSeguimiento =
                      ActiveTripService.viajeIdPausaVoluntariaCliente;
                }

                if (viajeIdSeguimiento.isEmpty) {
                  _disposeDocWatch();
                  _stopClienteUbicacionEnViaje();
                  if (ActiveTripService.viajeOperativoClienteConocido.isNotEmpty) {
                    return _cargaLinealOscura(
                      mensaje: 'Conectando con tu viaje…',
                    );
                  }
                  return _bodySinViajeActivo(
                    mensaje: 'No tienes viaje activo en este momento.',
                  );
                }

                // Si `viajeActivoId` se borró por error pero el viaje sigue (p. ej. taxista
                // marcó abordo), seguimos escuchando Firestore en tiempo real y reparamos el enlace.
                if (viajeIdUsuario.isEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    unawaited(
                      ActiveTripService.repararViajeActivoClienteSiHuerfano(
                        u.uid,
                        viajeIdHint: viajeIdSeguimiento,
                      ),
                    );
                  });
                }

                if (_viajeCierreDocSnap != null &&
                    _viajeCierreDocSnap!.id != viajeIdSeguimiento) {
                  _viajeCierreDocSnap = null;
                  _viajeCierreFetchKey = null;
                }
                if (_lastNonEmptyViajeActivoId.isNotEmpty &&
                    _lastNonEmptyViajeActivoId != viajeIdSeguimiento) {
                  _navPostViajeParaId = null;
                  _lastViajeUiCache = null;
                }
                _lastNonEmptyViajeActivoId = viajeIdSeguimiento;

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('viajes')
                      .doc(viajeIdSeguimiento)
                      .snapshots(includeMetadataChanges: true),
                  builder: (context, vSnap) {
                    if (ActiveTripService.flujoPostViajeClienteBloquea(
                      viajeIdSeguimiento,
                    )) {
                      return const SizedBox.shrink();
                    }
                    // Mantener el último frame del viaje (mapa) si el stream reconecta.
                    if (vSnap.connectionState == ConnectionState.waiting &&
                        !vSnap.hasData) {
                      final bool tieneDatosLocales =
                          _lastViajeUiCache != null ||
                              (_viajeDatosOfflineId == viajeIdSeguimiento &&
                                  _viajeDatosOffline != null) ||
                              (_syncPulseViajeId == viajeIdSeguimiento &&
                                  _syncPulseViajeData != null);
                      if (!tieneDatosLocales) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          unawaited(_bootstrapViajeClienteAlAbrir());
                        });
                        return _cargaViajeConEscape(
                          mensaje: 'Conectando con tu viaje…',
                          viajeId: viajeIdSeguimiento,
                        );
                      }
                    }

                    if (vSnap.hasData &&
                        vSnap.data != null &&
                        !vSnap.data!.exists) {
                      _lastViajeUiCache = null;
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        if (!mounted) return;
                        bool ausente = false;
                        try {
                          final DocumentSnapshot<Map<String, dynamic>>
                              server = await FirebaseFirestore.instance
                                  .collection('viajes')
                                  .doc(viajeIdSeguimiento)
                                  .get(const GetOptions(
                                      source: Source.server));
                          ausente = !server.exists;
                        } catch (_) {
                          ausente = await ActiveTripService
                              .confirmarViajeAusenteEnFirestore(
                            viajeIdSeguimiento,
                            uid: u.uid,
                          );
                        }
                        if (!mounted || !ausente) return;
                        unawaited(_salirTrasViajeDesaparecido(
                          viajeId: viajeIdSeguimiento,
                          uid: u.uid,
                          origen: 'streamViajeEliminado',
                        ));
                      });
                      return _pantallaTransicionCierre(
                        mensaje:
                            'El viaje ya no está disponible. Volviendo al inicio…',
                        mostrarBotonInicio: true,
                      );
                    }

                    if ((vSnap.hasError || !vSnap.hasData) &&
                        _lastViajeUiCache == null &&
                        !(_viajeDatosOfflineId == viajeIdSeguimiento &&
                            _viajeDatosOffline != null) &&
                        !(_syncPulseViajeId == viajeIdSeguimiento &&
                            _syncPulseViajeData != null)) {
                      if (ActiveTripService.viajeClienteDescartadoEnSesion(
                        viajeIdSeguimiento,
                      )) {
                        return _bodySinViajeActivo(
                          mensaje: 'No tienes viaje activo en este momento.',
                        );
                      }
                      if (vSnap.hasError &&
                          _esPermisoDenegadoFirestore(vSnap.error)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          unawaited(_bootstrapViajeClienteAlAbrir());
                        });
                      }
                      final bool tieneDatosLocales =
                          (_viajeDatosOfflineId == viajeIdSeguimiento &&
                              _viajeDatosOffline != null) ||
                          (_syncPulseViajeId == viajeIdSeguimiento &&
                              _syncPulseViajeData != null);
                      if (!tieneDatosLocales) {
                        if (vSnap.hasError &&
                            _esPermisoDenegadoFirestore(vSnap.error)) {
                          return _bodyViajeSincronizacionLimitada(
                            viajeId: viajeIdSeguimiento,
                            mensaje: 'Sincronizando tu viaje…',
                          );
                        }
                        return _cargaViajeConEscape(
                          mensaje: 'Conectando con tu viaje…',
                          viajeId: viajeIdSeguimiento,
                        );
                      }
                    }

                    final DocumentSnapshot<Map<String, dynamic>>?
                        docViajeRaw = (vSnap.hasData &&
                                vSnap.data != null &&
                                vSnap.data!.exists)
                            ? vSnap.data
                            : _lastViajeUiCache;
                    final bool usarDatosOffline =
                        (docViajeRaw == null || !docViajeRaw.exists) &&
                            _viajeDatosOfflineId == viajeIdSeguimiento &&
                            _viajeDatosOffline != null;
                    final bool usarPulso =
                        (docViajeRaw == null || !docViajeRaw.exists) &&
                            !usarDatosOffline &&
                            _syncPulseViajeId == viajeIdSeguimiento &&
                            _syncPulseViajeData != null;
                    if ((docViajeRaw == null || !docViajeRaw.exists) &&
                        !usarDatosOffline &&
                        !usarPulso) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        unawaited(_bootstrapViajeClienteAlAbrir());
                      });
                      return _cargaViajeConEscape(
                        mensaje: 'Conectando con tu viaje…',
                        viajeId: viajeIdSeguimiento,
                      );
                    }
                    final String viajeDocId = (docViajeRaw != null &&
                            docViajeRaw.exists)
                        ? docViajeRaw.id
                        : viajeIdSeguimiento;
                    final Map<String, dynamic> streamDataBase =
                        Map<String, dynamic>.from(
                      docViajeRaw != null && docViajeRaw.exists
                          ? (docViajeRaw.data() ?? <String, dynamic>{})
                          : usarDatosOffline
                              ? _viajeDatosOffline!
                              : _syncPulseViajeData!,
                    );
                    if (_sheetFaseUiViajeId != null &&
                        _sheetFaseUiViajeId != viajeDocId) {
                      _sheetFaseUiViajeId = null;
                      _sheetAutoExpandFaseClave = null;
                      _sheetUltimoExpandSigProgramado = null;
                      _sheetFaseUiEsAbordo = false;
                      _sheetAbordoColapsoUsuario = false;
                      _sheetExpandPendienteTarget = null;
                      _sheetPinAbordoExpandSig = null;
                      _pinAbordoLiveViajeId = null;
                      _snackPinAbordoLiveMostrado = null;
                    }
                    if (vSnap.hasData &&
                        vSnap.data != null &&
                        vSnap.data!.exists) {
                      _lastViajeUiCache = vSnap.data;
                    }

                    _startClienteViajeSyncPulse(viajeDocId);

                    final Map<String, dynamic> streamData =
                        Map<String, dynamic>.from(streamDataBase);
                    _maybeForzarPulseServidorPorStreamAtrasado(
                      viajeId: viajeDocId,
                      streamData: streamData,
                    );

                    final Map<String, dynamic> data =
                        _mergeViajeDataConPulsoServidor(
                      viajeDocId,
                      streamData,
                    );
                    _encolarAbordoPinEnVivoDesdeBuild(
                      viajeId: viajeDocId,
                      d: data,
                    );
                    _syncTurismoReasignacion(viajeDocId, data);

                    final Viaje v;
                    try {
                      v = Viaje.fromMap(
                        viajeDocId,
                        Map<String, dynamic>.from(data),
                      );
                    } catch (e, st) {
                      debugPrint(
                        '[VIAJE_ACTIVO] cliente Viaje.fromMap: $e\n$st',
                      );
                      return _ClienteCargaViajeGate(
                        mensaje: 'Cargando datos del viaje…',
                        onVolverInicio: () => unawaited(
                          _irAlInicioSeguro(forzarLimpiarViajeActivo: true),
                        ),
                        onReintentar: () {
                          if (!mounted) return;
                          setState(() {
                            _lastViajeUiCache = null;
                          });
                        },
                      );
                    }

                    final String uidClienteViaje =
                        ViajesRepo.uidClienteDesdeDocViaje(data);
                    if (uidClienteViaje.isNotEmpty &&
                        uidClienteViaje != u.uid) {
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        ActiveTripService.prepararSalidaClientePostViaje(
                          viajeId: viajeIdSeguimiento,
                        );
                        await _limpiarActivoDelUsuario(u.uid);
                      });
                      return _bodySinViajeActivo(
                        mensaje: 'No tienes viaje activo en este momento.',
                      );
                    }

                    _watchViajeDoc(v.id);

                    if (_multiNavLoadedForViajeId != v.id) {
                      _multiNavLoadedForViajeId = v.id;
                      _clienteNavDestinoUsado = false;
                      _clienteNavOrientacionLegDismissed = -1;
                      _syncMultiLegClienteDesdeViaje(v);
                    } else {
                      _syncMultiLegClienteDesdeViaje(v);
                    }

                    final String estadoBase = EstadosViaje.normalizar(
                      v.estado.isNotEmpty
                          ? v.estado
                          : (v.completado
                              ? EstadosViaje.completado
                              : (v.aceptado
                                  ? EstadosViaje.aceptado
                                  : EstadosViaje.pendiente)),
                    );
                    final String estadoEfectivo =
                        _estadoEfectivoFlujoCliente(v, data);

                    if (_viajeClienteCompletadoParaPostViaje(data)) {
                      ActiveTripService.marcarFlujoPostViajeCliente(v.id);
                      _stopClienteViajeSyncPulse();
                      _stopClienteUbicacionEnViaje();
                      _programarFlujoPostViaje(
                        viajeId: v.id,
                        uid: u.uid,
                        viajeDataSemilla: Map<String, dynamic>.from(data),
                      );
                      return _pantallaTransicionCierre(
                        mensaje: 'Preparando resumen del viaje…',
                      );
                    }
                    if (_viajeClienteCanceladoORechazado(data)) {
                      _stopClienteUbicacionEnViaje();
                      if (_viajeIdCanceladoPorCliente != v.id) {
                        _manejarViajeCerradoSiCorresponde(
                          viajeId: v.id,
                          uid: u.uid,
                          data: data,
                          origen: 'streamViaje',
                        );
                      }
                      return _pantallaTransicionCierre(
                        mensaje: 'Viaje cancelado. Volviendo al inicio…',
                        mostrarBotonInicio: true,
                      );
                    }

                    // Viaje propio, no terminal: libera el candado post-viaje
                    // si venía de un viaje anterior (shell y PIN de abordaje).
                    ActiveTripService.registrarViajeOperativoCliente(v.id);
                    ActiveTripService.mantenerOverlayViajeEnShell(
                      NavigationService.kOverlayClienteViajeActivo,
                    );

                    // Ubicación del cliente en Firestore en tiempo real durante el viaje activo.
                    _ensureClienteUbicacionEnViaje(v.id);

                    // Pool de conductores: solo viajes normales/motor en espera (turismo va por ADM)
                    final bool esperandoTaxista = !v.esTurismo &&
                        v.uidTaxista.isEmpty &&
                        (estadoBase == EstadosViaje.pendiente ||
                            estadoBase == EstadosViaje.pendientePago);

                    // Iniciar o detener escucha de conductores según corresponda.
                    // Nunca setState síncrono aquí: al aceptar el taxista se corta
                    // el pool y antes crasheaba con ErrorWidget.
                    if (esperandoTaxista &&
                        _nearbyDriversSession == null &&
                        _isValidCoord(v.latCliente, v.lonCliente)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _startListeningDrivers(
                            v.latCliente,
                            v.lonCliente,
                            tipoServicioViaje: v.tipoServicio,
                          );
                        }
                      });
                    } else if (!esperandoTaxista &&
                        _nearbyDriversSession != null) {
                      _stopListeningDrivers(deferSetState: true);
                    }

                    final bool faseRecogidaTaxista =
                        RaiMapVehicleIcons.faseRecogidaDesdeEstado(
                            estadoEfectivo);
                    if (v.uidTaxista.isNotEmpty &&
                        _isValidCoord(v.latTaxista, v.lonTaxista)) {
                      _syncTaxistaAnimador(v);
                    }
                    final LatLng? posTaxistaMapa = v.uidTaxista.isNotEmpty &&
                            _isValidCoord(v.latTaxista, v.lonTaxista)
                        ? _posTaxistaAnimada(v)
                        : null;
                    final BitmapDescriptor? iconoTaxistaAsignado =
                        v.uidTaxista.isNotEmpty &&
                                _isValidCoord(v.latTaxista, v.lonTaxista)
                            ? RaiMapVehicleIcons.iconoVistaCliente(
                                esMiConductor: true,
                                faseRecogida: faseRecogidaTaxista,
                              )
                            : null;

                    final Set<Marker> markers = <Marker>{
                      if (_isValidCoord(v.latDestino, v.lonDestino))
                        Marker(
                          markerId: const MarkerId('destino'),
                          position: _latLng(v.latDestino, v.lonDestino),
                          infoWindow: InfoWindow(
                            title: 'DESTINO',
                            snippet: v.destino.trim().isEmpty
                                ? 'Punto de llegada'
                                : v.destino,
                          ),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueGreen),
                          zIndexInt: 6,
                        ),
                      if (_isValidCoord(v.latCliente, v.lonCliente))
                        Marker(
                          markerId: const MarkerId('pickup'),
                          position: _latLng(v.latCliente, v.lonCliente),
                          infoWindow: InfoWindow(
                            title: 'ORIGEN · Recogida',
                            snippet: v.origen.trim().isEmpty
                                ? 'Punto de recogida'
                                : v.origen,
                          ),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueAzure),
                          zIndexInt: 5,
                        ),
                      ..._paradasIntermediasResueltas(v).asMap().entries.map(
                        (MapEntry<int,
                                ({double lat, double lon, String label})>
                            e) {
                          return Marker(
                            markerId: MarkerId('parada_${e.key}'),
                            position: LatLng(e.value.lat, e.value.lon),
                            infoWindow: InfoWindow(
                              title: 'PARADA ${e.key + 1}',
                              snippet: e.value.label,
                            ),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueOrange,
                            ),
                            zIndexInt: 4,
                          );
                        },
                      ),
                      if (posTaxistaMapa != null)
                        Marker(
                          markerId: const MarkerId('taxista'),
                          position: posTaxistaMapa,
                          infoWindow: InfoWindow(
                            title: faseRecogidaTaxista
                                ? 'Tu conductor viene hacia ti'
                                : 'Tu conductor',
                          ),
                          icon: iconoTaxistaAsignado ??
                              BitmapDescriptor.defaultMarkerWithHue(
                                _taxistaHueByEstado(estadoBase),
                              ),
                          rotation: iconoTaxistaAsignado != null
                              ? RaiMapVehicleIcons.rotationTaxiCliente(
                                  _bearingTaxistaAnimado(),
                                )
                              : 0,
                          flat: iconoTaxistaAsignado != null,
                          anchor: iconoTaxistaAsignado != null
                              ? const Offset(0.5, 0.5)
                              : const Offset(0.5, 1.0),
                          zIndexInt: 8,
                        ),
                    };
                    final Set<Circle> circles = <Circle>{
                      if (_isValidCoord(v.latCliente, v.lonCliente))
                        Circle(
                          circleId: const CircleId('halo_origen'),
                          center: _latLng(v.latCliente, v.lonCliente),
                          radius: 55,
                          fillColor: const Color(0x4400B0FF),
                          strokeColor: const Color(0xFF00B0FF),
                          strokeWidth: 3,
                          zIndex: 1,
                        ),
                      if (_isValidCoord(v.latDestino, v.lonDestino))
                        Circle(
                          circleId: const CircleId('halo_destino'),
                          center: _latLng(v.latDestino, v.lonDestino),
                          radius: 55,
                          fillColor: const Color(0x4400C853),
                          strokeColor: const Color(0xFF00C853),
                          strokeWidth: 3,
                          zIndex: 1,
                        ),
                    };

                    // Conductores en pool: solo los cerca del pickup (coherente / real).
                    final List<DocumentSnapshot<Map<String, dynamic>>>
                        driversSortedMapa = esperandoTaxista &&
                                _isValidCoord(v.latCliente, v.lonCliente)
                            ? _conductoresCercaPickup(v)
                            : const <DocumentSnapshot<
                                Map<String, dynamic>>>[];

                    if (esperandoTaxista) {
                      for (final DocumentSnapshot<Map<String, dynamic>> doc
                          in driversSortedMapa) {
                        final Map<String, dynamic>? docData = doc.data();
                        final GeoPoint? location =
                            _geoPointSeguro(docData?['location']);
                        if (location != null &&
                            _isValidCoord(
                                location.latitude, location.longitude)) {
                          final double? heading = (docData?['heading'] is num)
                              ? (docData!['heading'] as num).toDouble()
                              : null;
                          final bool enViaje = (docData?['viajeId'] ?? '')
                              .toString()
                              .trim()
                              .isNotEmpty;
                          final LatLng pos = _poolDriverAnim
                                  .displayPositions[doc.id] ??
                              LatLng(location.latitude, location.longitude);
                          final double poolHeading =
                              _poolDriverAnim.bearingFor(
                            doc.id,
                            fallback: heading ?? 0,
                          );
                          markers.add(
                            Marker(
                              markerId: MarkerId('pool_${doc.id}'),
                              position: pos,
                              icon: RaiMapVehicleIcons.taxiCliente ??
                                  BitmapDescriptor.defaultMarkerWithHue(
                                    BitmapDescriptor.hueGreen,
                                  ),
                              rotation: RaiMapVehicleIcons.taxiCliente != null
                                  ? RaiMapVehicleIcons.rotationTaxiCliente(
                                      poolHeading,
                                    )
                                  : 0,
                              flat: RaiMapVehicleIcons.taxiCliente != null,
                              anchor: RaiMapVehicleIcons.taxiCliente != null
                                  ? const Offset(0.5, 0.5)
                                  : const Offset(0.5, 1.0),
                              infoWindow: InfoWindow(
                                title: enViaje ? 'Ocupado' : 'Disponible',
                              ),
                              zIndexInt: enViaje ? 1 : 2,
                            ),
                          );
                        }
                      }
                    }

                    // Banner / FABs: conductor yendo al pickup o en viaje al destino.
                    final bool pulsoTaxistaEnMapa = v.uidTaxista.isNotEmpty &&
                        _isValidCoord(v.latTaxista, v.lonTaxista) &&
                        (estadoBase == EstadosViaje.aceptado ||
                            estadoBase == EstadosViaje.enCaminoPickup ||
                            estadoBase == EstadosViaje.enCurso);

                    final LatLng initialTarget =
                        _isValidCoord(v.latCliente, v.lonCliente)
                            ? _latLng(v.latCliente, v.lonCliente)
                            : (_isValidCoord(v.latDestino, v.lonDestino)
                                ? _latLng(v.latDestino, v.lonDestino)
                                : const LatLng(18.4861, -69.9312));

                    // No incluir GPS del taxista: cada ping redibujaba Directions y vaciaba el mapa.
                    // Redibuja al aceptar (aparece tid) o al cambiar estado / origen-destino.
                    final String tidRuta =
                        (v.uidTaxista.isNotEmpty ? v.uidTaxista : v.taxistaId)
                            .trim();
                    final String routeKey =
                        '${v.id}|${EstadosViaje.normalizar(v.estado)}|'
                        '${v.latCliente.toStringAsFixed(4)},${v.lonCliente.toStringAsFixed(4)}|'
                        '${v.latDestino.toStringAsFixed(4)},${v.lonDestino.toStringAsFixed(4)}|'
                        '${tidRuta.isEmpty ? '0' : '1'}|'
                        '${_firmaWaypointsViaje(v)}|'
                        '${v.multiparadaLegCompletadas}|${v.multiparadaCompleta}';
                    if (routeKey != _lastRouteKey) {
                      _lastRouteKey = routeKey;
                      _scheduleDrawRoute(v);
                    }

                    // Encuadre automático: NO incluir cada ping del taxista (provoca zoom in/out
                    // compitiendo con «Seguir conductor» y parpadeo). El movimiento del conductor
                    // se refleja en marcador + [_maybeAnimarCamaraAlTaxista]; «Centrar ambos» sigue
                    // disponible para ver pickup+conductor en una vista.
                    final String boundsKey =
                        '${v.id}|$estadoBase|${v.latCliente},${v.lonCliente}|'
                        '${v.latDestino},${v.lonDestino}|'
                        '${_firmaWaypointsViaje(v)}';
                    if (_map != null && boundsKey != _lastBoundsKey) {
                      _lastBoundsKey = boundsKey;
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _fitBoundsFor(v));
                    }

                    final bool cancelarHabilitado =
                        EstadosViaje.clientePuedeCancelarViajeDesdeApp(
                            estadoEfectivo);
                    final String codigoVerificacion =
                        _codigoVerificacionDesdeDoc(v, data);
                    final bool codigoVerificado =
                        _codigoVerificadoEnDoc(v, data);
                   final bool mostrarCodigoCliente =
  (_pinAbordoLiveViajeId == v.id && !codigoVerificado) ||
  _clienteDebeMostrarCodigoVerificacion(
    v,
    estadoBase,
    codigoVerificacion,
    data,
  ) ||
  (_clienteAbordoEnViajeDoc(data, v) && !codigoVerificado);
                    _solicitarEnsureCodigoSiFalta(
                        v, codigoVerificacion, data);
                    final String? orientacionFlujo =
                        _mensajeOrientacionCliente(
                      v,
                      estadoEfectivo,
                      mostrarCodigoCliente: mostrarCodigoCliente,
                    );

                    final bool esperandoConductor = v.uidTaxista.isEmpty &&
                        (estadoBase == EstadosViaje.pendiente ||
                            estadoBase == EstadosViaje.pendientePago ||
                            estadoBase == 'pendiente_admin' ||
                            (v.esTurismo &&
                                !widget.delegarEsperaTurismoAlRouter));
                    final bool panelConductorAsignado =
                        v.uidTaxista.isNotEmpty &&
                            !EstadosViaje.esTerminal(estadoEfectivo);
                    final bool fasePickupConductor = panelConductorAsignado &&
                        !codigoVerificado &&
                        (estadoEfectivo == EstadosViaje.aceptado ||
                            estadoEfectivo == EstadosViaje.enCaminoPickup);
                    final bool faseEnRuta = panelConductorAsignado &&
                        codigoVerificado &&
                        EstadosViaje.esEnCurso(estadoEfectivo);
                    final bool faseAbordoPin = panelConductorAsignado &&
                        (EstadosViaje.esAbordo(estadoEfectivo) ||
                            _clienteAbordoEnViajeDoc(data, v) ||
                            _pinAbordoLiveViajeId == v.id) &&
                        !codigoVerificado;
                    _faseAbordoPinUiCache = faseAbordoPin;
                    final bool mostrarBotonTocaPin =
                        panelConductorAsignado &&
                            !codigoVerificado &&
                            (fasePickupConductor || faseAbordoPin);
                    final bool mostrarBotonTocaPinGrande =
                        mostrarBotonTocaPin &&
                            (fasePickupConductor || !mostrarCodigoCliente);
                    final bool mostrarBotonTocaPinEnMapa =
                        mostrarBotonTocaPin && !mostrarCodigoCliente;
                    _ajustarSyncPulseParaFaseAbordoPin(
                      viajeId: v.id,
                      esperandoPinAbordo: faseAbordoPin,
                      codigoVerificado: codigoVerificado,
                    );
                    final DateTime inicioEsperaBusqueda =
                        ViajeEsperaTiempoResolver.inicioBusqueda(data);
                    final DateTime inicioCaminoConductor =
                        ViajeEsperaTiempoResolver.inicioConductor(data);
                    final double sheetInitial = esperandoConductor
                        ? _kViajeSheetEsperaConductor
                        : (fasePickupConductor
                            ? _kViajeSheetPickupCompact
                            : (faseAbordoPin
                                ? _kViajeSheetAbordoPin
                                : (faseEnRuta
                                    ? _kViajeSheetInitial
                                    : _kViajeSheetInitial)));
                    final double minSize = _esViajeMultiparada(v)
                        ? _kViajeSheetMinMultiparada
                        : _kViajeSheetMinNormal;
                    final double sheetMinChild =
                        faseAbordoPin && mostrarCodigoCliente
                            ? (minSize > _kViajeSheetMinAbordoPin
                                ? minSize
                                : _kViajeSheetMinAbordoPin)
                            : minSize;

                    if (faseAbordoPin &&
                        mostrarCodigoCliente &&
                        !codigoVerificado) {
                      prepararSheetPinAbordoVisible(
                        viajeId: v.id,
                        pin: codigoVerificacion,
                      );
                    }

final List<double> sheetSnapSizes = esperandoConductor
  ? _snapSizesViajeCliente(
      minSize: sheetMinChild,
      hitos: <double>[
        0.34,
        0.42,
        0.48,
        _kViajeSheetEsperaConductor,
        0.64,
        0.74,
        0.84,
      ],
    )
  : fasePickupConductor
      ? _snapSizesViajeCliente(
          minSize: minSize,
          hitos: <double>[
            0.32,
            0.40,
            _kViajeSheetPickupCompact,
            0.55,
            0.64,
            0.74,
            0.84,
          ],
        )
      : faseAbordoPin
          ? _snapSizesViajeCliente(
              minSize: sheetMinChild,
              hitos: <double>[
                sheetMinChild,
                0.48,
                0.58,
                _kViajeSheetAbordoPin,
                0.84,
                0.90,
              ],
            )
          : _snapSizesViajeCliente(
              minSize: minSize,
              hitos: <double>[
                0.30,
                0.36,
                0.44,
                _kViajeSheetInitial,
                0.58,
                0.66,
                0.74,
                0.84,
              ],
            );

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _maybeAnimarCamaraAlTaxista(v, estadoEfectivo);
                      _schedulePickupEtaRefresh(v, estadoEfectivo);
                    });

                    final String? faseClaveSheet = _claveFaseSheetCliente(
                      viajeId: v.id,
                      faseAbordoPin: faseAbordoPin,
                      codigoVerificado: codigoVerificado,
                      faseEnRuta: faseEnRuta,
                      fasePickup: fasePickupConductor,
                      esperandoConductor: esperandoConductor,
                    );
                    final double? targetSheetFase = _targetSheetPorFaseCliente(
                      v: v,
                      estadoBase: estadoEfectivo,
                      faseAbordoPin: faseAbordoPin,
                      codigoVerificado: codigoVerificado,
                      faseEnRuta: faseEnRuta,
                    );
                    final bool sheetAtascadoAhora = targetSheetFase != null &&
                        _sheetClienteAtascado(targetSheetFase);
                    final String expandSig =
                        '${faseClaveSheet ?? 'na'}|$codigoVerificado|$sheetAtascadoAhora|${_sheetExpandPendienteTarget != null}';
                    if (faseClaveSheet != null &&
                        (_sheetUltimoExpandSigProgramado != expandSig ||
                            _sheetExpandPendienteTarget != null)) {
                      _sheetUltimoExpandSigProgramado = expandSig;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _procesarSheetExpandPendiente();
                        _maybeAutoExpandirSheetPorFaseCliente(
                          v: v,
                          estadoBase: estadoEfectivo,
                          faseAbordoPin: faseAbordoPin,
                          codigoVerificado: codigoVerificado,
                          faseEnRuta: faseEnRuta,
                          fasePickupConductor: fasePickupConductor,
                          esperandoConductor: esperandoConductor,
                        );
                      });
                    }

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || _yendoAlInicio) return;
                      if (ActiveTripService.debeForzarInicioClienteShell) {
                        return;
                      }
                      if (ActiveTripService.flujoPostViajeClienteBloquea(
                            v.id,
                          ) ||
                          _viajeClienteCompletadoParaPostViaje(data)) {
                        return;
                      }
                      if (_clienteAbordoEnViajeDoc(data, v) &&
                          !codigoVerificado) {
                        ActiveTripService.cancelarForzarInicioClienteShellForzado();
                        ActiveTripService.mantenerOverlayViajeEnShell(
                          NavigationService.kOverlayClienteViajeActivo,
                        );
                      }
                    });

                    // ===== DETECCIÓN DE CERCANÍA (solo fase pickup; en `en_curso` el cliente en
                    // Firestore puede quedar congelado si la app pasajero no está en primer plano
                    // → la distancia taxista-cliente salta y el banner parpadea). =====
                    if ((estadoEfectivo == EstadosViaje.aceptado ||
                            estadoEfectivo == EstadosViaje.enCaminoPickup) &&
                        !codigoVerificado &&
                        _isValidCoord(v.latTaxista, v.lonTaxista) &&
                        _isValidCoord(v.latCliente, v.lonCliente)) {
                      final double distanciaTaxista =
                          DistanciaService.calcularDistancia(
                        v.latTaxista,
                        v.lonTaxista,
                        v.latCliente,
                        v.lonCliente,
                      );
                      final bool cerca = _debugConductorCercaPickup ||
                          distanciaTaxista < 0.2; // 200 metros
                      if (_lastPickupProximity != cerca) {
                        _lastPickupProximity = cerca;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          if (cerca && !_mostrarMensajeCercania) {
                            setState(() => _mostrarMensajeCercania = true);
                            _mensajeCercaniaTimer?.cancel();
                            _mensajeCercaniaTimer =
                                Timer(const Duration(seconds: 10), () {
                              if (mounted) {
                                setState(
                                    () => _mostrarMensajeCercania = false);
                              }
                            });
                          } else if (!cerca && _mostrarMensajeCercania) {
                            setState(() => _mostrarMensajeCercania = false);
                            _mensajeCercaniaTimer?.cancel();
                          }
                          _intentarRecuperarSheetTrasEvento();
                        });
                      }
                    }

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              RepaintBoundary(
                                child: (!_mapaPermitido ||
                                        _mapaDesactivadoPorError)
                                    ? ColoredBox(
                                        color: const Color(0xFF0A0A0A),
                                        child: Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  _mapaDesactivadoPorError
                                                      ? 'Mapa no disponible ahora.\nAbajo tienes llamar, WhatsApp y chat con tu conductor.'
                                                      : 'Cargando mapa…',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.white54,
                                                    height: 1.35,
                                                  ),
                                                ),
                                                if (_mapaDesactivadoPorError) ...[
                                                  const SizedBox(height: 16),
                                                  FilledButton.icon(
                                                    onPressed:
                                                        _reintentarMapaViajeManual,
                                                    icon:
                                                        const Icon(Icons.map),
                                                    label: const Text(
                                                        'Reintentar mapa'),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    : (kIsWeb
                                        ? MapaTiempoReal(
                                            key: ValueKey<String>(
                                                'osm-viaje-${v.id}'),
                                            origen: _isValidCoord(
                                                    v.latCliente,
                                                    v.lonCliente)
                                                ? _latLng(v.latCliente,
                                                    v.lonCliente)
                                                : null,
                                            destino: _isValidCoord(
                                                    v.latDestino,
                                                    v.lonDestino)
                                                ? _latLng(v.latDestino,
                                                    v.lonDestino)
                                                : null,
                                            ubicacionTaxista: posTaxistaMapa,
                                            // Pins vienen en overlay (origen/destino/paradas/pool).
                                            mostrarOrigen: false,
                                            mostrarDestino: false,
                                            mostrarTaxista: false,
                                            esCliente: true,
                                            esTaxista: false,
                                            overlayMarkers: markers,
                                            overlayPolylines:
                                                Set<Polyline>.of(
                                                    _polylines.values),
                                            onUserInteractWithMap: () =>
                                                _colapsarSheetPorMapaEnFase(
                                                  fasePickupConductor:
                                                      fasePickupConductor,
                                                  faseAbordoPin: faseAbordoPin,
                                                  faseEnRuta: faseEnRuta,
                                                ),
                                            onUserMapGestureEnd: v.esMotor ||
                                                    !_sheetAutoExpandPorMapaPermitido(
                                                      esMotor: v.esMotor,
                                                      faseAbordoPin:
                                                          faseAbordoPin,
                                                      fasePickupConductor:
                                                          fasePickupConductor,
                                                    )
                                                ? null
                                                : () =>
                                                    _expandirSheetTrasMapaInteract(),
                                          )
                                        : GoogleMap(
                                            key: ValueKey<String>(
                                                'gmap-${v.id}'),
                                            padding: EdgeInsets.only(
                                              top: MediaQuery.of(context)
                                                      .padding
                                                      .top +
                                                  56,
                                              bottom: MediaQuery.of(context)
                                                      .size
                                                      .height *
                                                  0.40,
                                              left: 32,
                                              right: 32,
                                            ),
                                            initialCameraPosition:
                                                CameraPosition(
                                                    target: initialTarget,
                                                    zoom: 14),
                                            onMapCreated:
                                                (GoogleMapController c) {
                                              _map = c;
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback(
                                                      (_) async {
                                                final GoogleMapController?
                                                    mapRef = _map;
                                                if (!mounted ||
                                                    mapRef == null) return;
                                                try {
                                                  _programmaticCameraDepth++;
                                                  await mapRef.animateCamera(
                                                      CameraUpdate
                                                          .newLatLngZoom(
                                                              initialTarget,
                                                              14));
                                                } catch (_) {
                                                  if (_programmaticCameraDepth >
                                                      0) {
                                                    _programmaticCameraDepth--;
                                                  }
                                                }
                                                final String bk =
                                                    '${v.id}|$estadoBase|${v.latCliente},${v.lonCliente}|'
                                                    '${v.latDestino},${v.lonDestino}|'
                                                    '${_firmaWaypointsViaje(v)}';
                                                if (_lastBoundsKey != bk) {
                                                  _lastBoundsKey = bk;
                                                  await _fitBoundsFor(v);
                                                }
                                              });
                                            },
                                            onCameraMoveStarted: () {
                                              _mapGestureEndDebounce
                                                  ?.cancel();
                                              if (_programmaticCameraDepth ==
                                                  0) {
                                                _colapsarSheetPorMapaEnFase(
                                                  fasePickupConductor:
                                                      fasePickupConductor,
                                                  faseAbordoPin: faseAbordoPin,
                                                  faseEnRuta: faseEnRuta,
                                                );
                                              }
                                              if (_seguirTaxistaCamara) {
                                                setState(() =>
                                                    _seguirTaxistaCamara =
                                                        false);
                                              }
                                            },
                                            onCameraIdle: () {
                                              if (_programmaticCameraDepth >
                                                  0) {
                                                _programmaticCameraDepth--;
                                                return;
                                              }
                                              _mapGestureEndDebounce
                                                  ?.cancel();
                                              if (_sheetAutoExpandPorMapaPermitido(
                                                esMotor: v.esMotor,
                                                faseAbordoPin: faseAbordoPin,
                                                fasePickupConductor:
                                                    fasePickupConductor,
                                              )) {
                                                _expandirSheetTrasMapaInteract();
                                              }
                                            },
                                            onTap: (_) {
                                              if (_programmaticCameraDepth >
                                                  0) return;
                                              _colapsarSheetPorMapaEnFase(
                                                fasePickupConductor:
                                                    fasePickupConductor,
                                                faseAbordoPin: faseAbordoPin,
                                                faseEnRuta: faseEnRuta,
                                              );
                                              _mapGestureEndDebounce
                                                  ?.cancel();
                                              if (_sheetAutoExpandPorMapaPermitido(
                                                esMotor: v.esMotor,
                                                faseAbordoPin: faseAbordoPin,
                                                fasePickupConductor:
                                                    fasePickupConductor,
                                              )) {
                                                _mapGestureEndDebounce =
                                                    Timer(
                                                  const Duration(
                                                      milliseconds: 420),
                                                  () {
                                                    if (mounted) {
                                                      _expandirSheetTrasMapaInteract();
                                                    }
                                                  },
                                                );
                                              }
                                            },
                                            myLocationEnabled: _myLoc,
                                            myLocationButtonEnabled: false,
                                            zoomControlsEnabled: true,
                                            markers: markers,
                                            circles: circles,
                                            polylines: Set<Polyline>.of(
                                                _polylines.values),
                                            compassEnabled: true,
                                            mapToolbarEnabled: false,
                                            trafficEnabled: true,
                                          )),
                              ),
                              // ===== BOTÓN FLOTANTE "VER TAXISTA" (siempre visible) =====
                              if (pulsoTaxistaEnMapa)
                                Positioned(
                                  top: 0,
                                  left: 10,
                                  right: 10,
                                  child: SafeArea(
                                    bottom: false,
                                    child: Material(
                                      color: Colors.black
                                          .withValues(alpha: 0.88),
                                      elevation: 6,
                                      borderRadius: BorderRadius.circular(16),
                                      child: InkWell(
                                        borderRadius:
                                            BorderRadius.circular(16),
                                        onTap: () => setState(
                                          () => _pickupEtaMinimizado =
                                              !_pickupEtaMinimizado,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.local_taxi_rounded,
                                                    color: Color(0xFF49F18B),
                                                    size: 22,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: AnimatedSwitcher(
                                                      duration:
                                                          const Duration(
                                                              milliseconds:
                                                                  280),
                                                      switchInCurve:
                                                          Curves.easeOutCubic,
                                                      switchOutCurve:
                                                          Curves.easeInCubic,
                                                      transitionBuilder:
                                                          (child, animation) {
                                                        return FadeTransition(
                                                          opacity: animation,
                                                          child:
                                                              SlideTransition(
                                                            position: Tween<
                                                                Offset>(
                                                              begin:
                                                                  const Offset(
                                                                      0,
                                                                      0.08),
                                                              end:
                                                                  Offset.zero,
                                                            ).animate(
                                                                animation),
                                                            child: child,
                                                          ),
                                                        );
                                                      },
                                                      child: Text(
                                                        estadoBase ==
                                                                EstadosViaje
                                                                    .enCurso
                                                            ? 'Viaje en marcha · conductor en tiempo real'
                                                            : (_pickupEtaTitulo ??
                                                                'Tu conductor va hacia tu punto de recogida'),
                                                        key: ValueKey<String>(
                                                          estadoBase ==
                                                                  EstadosViaje
                                                                      .enCurso
                                                              ? 'en-curso-title'
                                                              : (_pickupEtaTitulo ??
                                                                  'pickup-title-default'),
                                                        ),
                                                        style:
                                                            const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          fontSize: 15,
                                                          height: 1.25,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Icon(
                                                    _pickupEtaMinimizado
                                                        ? Icons
                                                            .expand_more_rounded
                                                        : Icons
                                                            .expand_less_rounded,
                                                    color: Colors.white70,
                                                  ),
                                                ],
                                              ),
                                              if (fasePickupConductor)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 10),
                                                  child:
                                                      ClienteViajeEsperaCronometro(
                                                    inicio:
                                                        inicioCaminoConductor,
                                                    modo:
                                                        ClienteViajeEsperaCronometroModo
                                                            .conductorEnCamino,
                                                    compacto: true,
                                                    mostrarEnVivo: false,
                                                  ),
                                                ),
                                              if (!_pickupEtaMinimizado &&
                                                  (estadoBase ==
                                                          EstadosViaje
                                                              .enCurso ||
                                                      _pickupEtaDetalle !=
                                                          null ||
                                                      _pickupEtaTitulo ==
                                                          null))
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 8),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      AnimatedSwitcher(
                                                        duration:
                                                            const Duration(
                                                                milliseconds:
                                                                    260),
                                                        switchInCurve: Curves
                                                            .easeOutCubic,
                                                        switchOutCurve: Curves
                                                            .easeInCubic,
                                                        transitionBuilder:
                                                            (child,
                                                                animation) {
                                                          return FadeTransition(
                                                            opacity:
                                                                animation,
                                                            child: child,
                                                          );
                                                        },
                                                        child: Text(
                                                          estadoBase ==
                                                                  EstadosViaje
                                                                      .enCurso
                                                              ? 'Seguí la ubicación del conductor en el mapa; '
                                                                  'tocá «Seguir conductor» si soltaste el seguimiento.'
                                                              : (_pickupEtaDetalle ??
                                                                  'Deslizá el panel inferior para ver todos los detalles del viaje.'),
                                                          key: ValueKey<
                                                              String>(
                                                            estadoBase ==
                                                                    EstadosViaje
                                                                        .enCurso
                                                                ? 'en-curso-detail'
                                                                : (_pickupEtaDetalle ??
                                                                    'pickup-detail-default'),
                                                          ),
                                                          style:
                                                              const TextStyle(
                                                            color: Colors
                                                                .white70,
                                                            fontSize: 13,
                                                            height: 1.35,
                                                          ),
                                                        ),
                                                      ),
                                                      if (_isValidCoord(
                                                          v.latTaxista,
                                                          v.lonTaxista))
                                                        Align(
                                                          alignment: Alignment
                                                              .centerLeft,
                                                          child:
                                                              TextButton.icon(
                                                            onPressed: () =>
                                                                unawaited(
                                                              _openGoogleMapsVerUbicacionConductor(
                                                                v.latTaxista,
                                                                v.lonTaxista,
                                                              ),
                                                            ),
                                                            style: TextButton
                                                                .styleFrom(
                                                              foregroundColor:
                                                                  const Color(
                                                                      0xFF49F18B),
                                                              padding: const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      0,
                                                                  vertical:
                                                                      6),
                                                              tapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap,
                                                            ),
                                                            icon: const Icon(
                                                                Icons
                                                                    .map_rounded,
                                                                size: 18),
                                                            label: const Text(
                                                              'Navegar con mapa',
                                                              style:
                                                                  TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (_isValidCoord(v.latTaxista, v.lonTaxista) &&
                                  !faseAbordoPin)
                                Positioned(
                                  top: pulsoTaxistaEnMapa ? 108 : 16,
                                  right: 16,
                                  child: FloatingActionButton.extended(
                                    onPressed: () => _centrarEnTaxista(v),
                                    icon: const Icon(Icons.my_location,
                                        color: Colors.white),
                                    label: const Text('Seguir conductor',
                                        style:
                                            TextStyle(color: Colors.white)),
                                    backgroundColor: Colors.black87,
                                    heroTag: null,
                                  ),
                                ),
                              KeyedSubtree(
                                key: ValueKey<String>(
                                  'pin-flotante-${v.id}-$mostrarCodigoCliente-$codigoVerificacion',
                                ),
                                child: _buildPinFlotanteEnMapa(
                                  viajeId: v.id,
                                  codigoVerificacion: codigoVerificacion,
                                  mostrar: mostrarCodigoCliente &&
                                      !panelConductorAsignado,
                                  cargando: _pinEnsureEnCurso,
                                  esMotor: v.esMotor,
                                ),
                              ),
                              if (mostrarBotonTocaPinEnMapa && !faseAbordoPin)
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: MediaQuery.of(context).size.height *
                                      0.24,
                                  child: KeyedSubtree(
                                    key: ValueKey<String>(
                                      'toca-pin-mapa-${v.id}-$fasePickupConductor-$faseAbordoPin',
                                    ),
                                    child: _buildBotonTocaActualizarViajeFlotante(
                                      viajeId: v.id,
                                      enEsperaAbordo: fasePickupConductor,
                                    ),
                                  ),
                                ),
                              if (_isValidCoord(v.latTaxista, v.lonTaxista) &&
                                  _seguirTaxistaCamara)
                                Positioned(
                                  top: pulsoTaxistaEnMapa ? 108 : 16,
                                  left: 16,
                                  child: AnimatedBuilder(
                                    animation: _radarCtrl,
                                    builder: (_, __) {
                                      final double t = _radarCtrl.value;
                                      final double pulso = 0.55 +
                                          (0.45 * math.sin(t * 2 * math.pi))
                                              .abs();
                                      return AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 220),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0D2B1A)
                                              .withValues(
                                            alpha: 0.78 + (0.18 * pulso),
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border: Border.all(
                                            color:
                                                Colors.greenAccent.withValues(
                                              alpha: 0.55 + (0.4 * pulso),
                                            ),
                                            width: 1.1,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.greenAccent
                                                  .withValues(
                                                alpha: 0.12 + (0.22 * pulso),
                                              ),
                                              blurRadius: 8 + (8 * pulso),
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons
                                                  .fiber_manual_record_rounded,
                                              size: 12,
                                              color: Colors.greenAccent,
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              'EN VIVO',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              if (_isValidCoord(v.latTaxista, v.lonTaxista) &&
                                  !faseAbordoPin)
                                Positioned(
                                  top: pulsoTaxistaEnMapa ? 164 : 72,
                                  right: 16,
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final bool narrow =
                                          MediaQuery.sizeOf(context).width <
                                              360;
                                      if (narrow) {
                                        return FloatingActionButton(
                                          onPressed: () =>
                                              _centrarClienteYTaxista(v),
                                          tooltip: 'Centrar ambos',
                                          backgroundColor: Colors.black54,
                                          heroTag: null,
                                          child: const Icon(
                                            Icons.center_focus_strong,
                                            color: Colors.white,
                                          ),
                                        );
                                      }
                                      return FloatingActionButton.extended(
                                        onPressed: () =>
                                            _centrarClienteYTaxista(v),
                                        icon: const Icon(
                                            Icons.center_focus_strong,
                                            color: Colors.white),
                                        label: const Text('Centrar ambos',
                                            style: TextStyle(
                                                color: Colors.white)),
                                        backgroundColor: Colors.black54,
                                        heroTag: null,
                                      );
                                    },
                                  ),
                                ),
                              // ===== MENSAJE DE CERCANÍA =====
                              if (_mostrarMensajeCercania)
                                Positioned(
                                  top: pulsoTaxistaEnMapa ? 188 : 80,
                                  left: 16,
                                  right: 16,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.greenAccent,
                                      borderRadius: BorderRadius.circular(30),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x42000000),
                                          blurRadius: 10,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Text(
                                      '🚕 Tu conductor está llegando',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              if (esperandoTaxista) _radarSearchingOverlay(),
                              if (esperandoTaxista)
                                Positioned(
                                  top: 0,
                                  left: 10,
                                  right: 10,
                                  child: SafeArea(
                                    bottom: false,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: ClienteViajeEsperaCronometro(
                                        inicio: inicioEsperaBusqueda,
                                        modo: ClienteViajeEsperaCronometroModo
                                            .busquedaConductor,
                                      ),
                                    ),
                                  ),
                                ),
                              if (pulsoTaxistaEnMapa)
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 10,
                                  child: Material(
                                    elevation: 8,
                                    borderRadius: BorderRadius.circular(14),
                                    color:
                                        Colors.black.withValues(alpha: 0.88),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.local_taxi,
                                              color: Colors.greenAccent,
                                              size: 22),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _lineaEtaPickupCliente(
                                                  v, estadoBase),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                height: 1.25,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              if (!esperandoTaxista &&
                                  v.uidTaxista.isNotEmpty &&
                                  (FirebaseAuth.instance.currentUser?.uid ??
                                          '')
                                      .isNotEmpty)
                                ViajeChatMapaOverlay(
                                  viajeId: v.id,
                                  miUid: FirebaseAuth
                                      .instance.currentUser!.uid,
                                  otroUid: _uidTaxistaDelViaje(v, data),
                                  otroNombre: v.nombreTaxista.isNotEmpty
                                      ? v.nombreTaxista
                                      : 'Conductor',
                                  bottom: pulsoTaxistaEnMapa ? 78 : 12,
                                ),
                            ],
                          ),
                        ),
                        if (orientacionFlujo != null)
                          Positioned(
                            top: MediaQuery.paddingOf(context).top + 8,
                            left: 12,
                            right: 12,
                            child: ViajeFlujoOrientacionBanner(
                              mensaje: orientacionFlujo,
                            ),
                          ),
                        DraggableScrollableSheet(
                          key: ValueKey<String>('viaje-sheet-${v.id}'),
                          controller: _viajeSheetCtrl,
                          expand: true,
                          minChildSize: sheetMinChild,
                          maxChildSize: 0.94,
                          initialChildSize: sheetInitial,
                          snap: true,
                          snapAnimationDuration: _kViajeSheetSnapDuration,
                          snapSizes: sheetSnapSizes,
                          builder: (sheetCtx, scrollController) {
                            _viajeSheetScrollCtrl = scrollController;
                            final double bottomInset =
                                MediaQuery.viewPaddingOf(sheetCtx).bottom;
                            return RepaintBoundary(
                              child: DecoratedBox(
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(16)),
                                border: Border(
                                    top:
                                        BorderSide(color: Color(0x22FFFFFF))),
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x66000000),
                                    blurRadius: 16,
                                    offset: Offset(0, -4),
                                  ),
                                ],
                              ),
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (ScrollNotification n) {
                                  if (n is ScrollStartNotification &&
                                      n.dragDetails != null) {
                                    _sheetScrollArrastrando = true;
                                    _sheetUltimoGestUsuario = DateTime.now();
                                  } else if (n is ScrollEndNotification) {
                                    _sheetScrollArrastrando = false;
                                    _finalizarInteraccionSheetUsuario();
                                  }
                                  return false;
                                },
                                child: CustomScrollView(
                                  controller: scrollController,
                                  // DraggableScrollableSheet enlaza el arrastre al ScrollController;
                                  // debe ser AlwaysScrollable o el touch muere en device real.
                                  physics: const AlwaysScrollableScrollPhysics(
                                    parent: ClampingScrollPhysics(),
                                  ),
                                  slivers: <Widget>[
                                    SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 8, 16, 0),
                                        child: _viajeSheetHandleCliente(
                                          mostrarHintDeslizar:
                                              fasePickupConductor ||
                                                  esperandoConductor ||
                                                  faseEnRuta ||
                                                  faseAbordoPin,
                                          minSize: sheetMinChild,
                                        ),
                                      ),
                                    ),
                                    if (faseAbordoPin)
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            0,
                                            16,
                                            0,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: <Widget>[
                                              _buildClienteZonaAccionesSticky(
                                                v,
                                                estadoEfectivo,
                                                cancelarHabilitado,
                                                compacto: true,
                                                reforzarComunicacionEnSticky:
                                                    false,
                                              ),
                                              if (mostrarCodigoCliente)
                                                _buildCodigoVerificacionClienteSection(
                                                  codigoVerificacion:
                                                      codigoVerificacion,
                                                  codigoVerificado:
                                                      codigoVerificado,
                                                  estadoBase: estadoBase,
                                                  mostrarCodigo:
                                                      mostrarCodigoCliente,
                                                  esMotor: v.esMotor,
                                                  viajeIdParaActualizar: v.id,
                                                  integradoEnPanelConductor:
                                                      true,
                                                ),
                                              _viajeSheetDivider(
                                                'Desliza abajo para más detalles',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    SliverPadding(
                                      padding: EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        12 + bottomInset,
                                      ),
                                      sliver: SliverList(
                                        delegate: SliverChildListDelegate(
                                          <Widget>[
                                  if (!faseAbordoPin) ...<Widget>[
                                  _buildClienteZonaAccionesSticky(
                                    v,
                                    estadoEfectivo,
                                    cancelarHabilitado,
                                    compacto: panelConductorAsignado,
                                    // El panel del conductor ya incluye Llamar/WA/Chat;
                                    // no duplicar arriba (tapaba el mapa y congelaba el scroll).
                                    reforzarComunicacionEnSticky: false,
                                  ),
                                  _viajeSheetDivider(),
                                  ],

                                  if (faseAbordoPin)
                                    ..._buildClienteAbordoSheetBodyChildren(
                                      v: v,
                                      data: data,
                                      estadoBase: estadoBase,
                                      estadoEfectivo: estadoEfectivo,
                                      panelConductorAsignado:
                                          panelConductorAsignado,
                                      mostrarCodigoCliente:
                                          mostrarCodigoCliente,
                                      codigoVerificado: codigoVerificado,
                                      codigoVerificacion: codigoVerificacion,
                                      mostrarBotonTocaPinGrande:
                                          mostrarBotonTocaPinGrande,
                                      pinEnZonaFija: mostrarCodigoCliente,
                                    )
                                  else ...<Widget>[

                                  if (mostrarCodigoCliente) ...[
                                    _buildCodigoVerificacionClienteSection(
                                      codigoVerificacion: codigoVerificacion,
                                      codigoVerificado: codigoVerificado,
                                      estadoBase: estadoBase,
                                      mostrarCodigo: mostrarCodigoCliente,
                                      esMotor: v.esMotor,
                                      viajeIdParaActualizar: v.id,
                                      integradoEnPanelConductor: true,
                                    ),
                                    const SizedBox(height: 12),
                                  ],

                                  // Mensaje solo para reservas futuras (no motor/taxi «ahora» en pool)
                                  if (estadoBase == EstadosViaje.pendiente &&
                                      v.uidTaxista.isEmpty &&
                                      v.programado &&
                                      !v.esAhora)
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      margin:
                                          const EdgeInsets.only(bottom: 16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E1A0F),
                                        borderRadius:
                                            BorderRadius.circular(16),
                                        border: Border.all(
                                            color: Colors.orangeAccent
                                                .withAlpha(120)),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.schedule,
                                              color: Colors.orangeAccent),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Tu viaje está programado. Te avisaremos cuando un taxista lo acepte.',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight:
                                                      FontWeight.w700),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  if (esperandoTaxista)
                                    ClienteEsperaTaxistaPanel(
                                      viaje: v,
                                      esMotor: v.esMotor,
                                      conductoresCerca:
                                          driversSortedMapa.length,
                                      docsOrdenados: driversSortedMapa,
                                      fotoPorUid: _driverFotoPorUid,
                                      inicioEspera: inicioEsperaBusqueda,
                                    ),

                                  _wrapSelectorMetodoPago(
                                    v: v,
                                    data: data,
                                    estadoEfectivo: estadoBase,
                                  ),

                                  if (panelConductorAsignado)
                                    ClienteViajeConductorAsignadoPanel(
                                      viaje: v,
                                      estadoBase: estadoEfectivo,
                                      etaLinea: _lineaEtaPickupCliente(
                                        v,
                                        estadoEfectivo,
                                      ),
                                      etaTituloHttp: _pickupEtaTitulo,
                                      conductorCard: _buildDriverCard(
                                        v,
                                        soloDatosConductor: true,
                                      ),
                                      pinAbordo: mostrarCodigoCliente &&
                                              !faseAbordoPin
                                          ? _buildCodigoVerificacionClienteSection(
                                              codigoVerificacion:
                                                  codigoVerificacion,
                                              codigoVerificado:
                                                  codigoVerificado,
                                              estadoBase: estadoBase,
                                              mostrarCodigo:
                                                  mostrarCodigoCliente,
                                              esMotor: v.esMotor,
                                              viajeIdParaActualizar: v.id,
                                              integradoEnPanelConductor: true,
                                            )
                                          : null,
                                      onLlamar: () =>
                                          _llamarConductorCliente(v),
                                      onWhatsApp: () =>
                                          _whatsAppConductorCliente(v),
                                      onChat: () =>
                                          _abrirChatConductorCliente(v),
                                      onVerEnMapa: () => _centrarEnTaxista(v),
                                      onCentrarMapa: _isValidCoord(
                                              v.latTaxista, v.lonTaxista)
                                          ? () => _centrarClienteYTaxista(v)
                                          : null,
                                      inicioCamino: fasePickupConductor
                                          ? inicioCaminoConductor
                                          : null,
                                    ),
                                  if (mostrarBotonTocaPinGrande && fasePickupConductor) ...[
                                    const SizedBox(height: 10),
                                    _buildBotonTocaActualizarViaje(
                                      viajeId: v.id,
                                      enEsperaAbordo: true,
                                    ),
                                  ],
                                  if (v.uidTaxista.isNotEmpty &&
                                      !panelConductorAsignado &&
                                      _isValidCoord(
                                          v.latTaxista, v.lonTaxista))
                                    Container(
                                      margin:
                                          const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF0F3B27),
                                            Color(0xFF0B261A),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(18),
                                        border: Border.all(
                                          color: Colors.greenAccent
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Row(
                                            children: [
                                              Icon(Icons.local_taxi_rounded,
                                                  color: Colors.greenAccent,
                                                  size: 22),
                                              SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Ahi viene tu taxi',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _lineaEtaPickupCliente(
                                                v, estadoBase),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  if (_mostrarAvisoTarjetaPreAbordo(
                                      v, estadoBase, data))
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1A1F2E),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.deepPurpleAccent
                                                .withValues(alpha: 0.35),
                                          ),
                                        ),
                                        child: Text(
                                          PagoTarjetaClienteGate.bloqueado
                                              ? 'Pago con tarjeta (en desarrollo): cuando subas al vehículo y verifiques el código '
                                                  'con el conductor, verás el botón para pagar desde la app antes de llegar al destino.'
                                              : 'Pago con tarjeta: cuando subas al vehículo y verifiques el código '
                                                  'con el conductor, verás el botón para pagar desde la app antes de llegar al destino.',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_mostrarAvisoTransferenciaPreAbordo(
                                      v, estadoBase, data))
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1A1F2E),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.amberAccent
                                                .withValues(alpha: 0.35),
                                          ),
                                        ),
                                        child: const Text(
                                          'Pago por transferencia: cuando subas al vehículo verás '
                                          'la cuenta del conductor para transferir. Al finalizar el viaje '
                                          'también recibirás el comprobante oficial con los mismos datos.',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_mostrarDatosTransferenciaCliente(
                                      v, estadoBase, data)) ...[
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10231A),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.greenAccent
                                                .withValues(alpha: 0.35),
                                          ),
                                        ),
                                        child: const Text(
                                          'Ya estás a bordo o en camino al destino. '
                                          'Transferí a la cuenta del conductor abajo y conservá el comprobante. '
                                          'Al cerrar el viaje verás la factura oficial.',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ),
                                    _buildDatosBancarios(
                                      v,
                                      _uidTaxistaDelViaje(v, data),
                                      v.precio,
                                      data,
                                    ),
                                    const SizedBox(height: 16),
                                  ],

                                  if (v.uidTaxista.isNotEmpty &&
                                      !panelConductorAsignado) ...[
                                    _buildDriverCard(v,
                                        soloDatosConductor: true),
                                    const SizedBox(height: 16),
                                    _buildCodigoVerificacionClienteSection(
                                      codigoVerificacion: codigoVerificacion,
codigoVerificado: codigoVerificado,
estadoBase: estadoBase,
mostrarCodigo: mostrarCodigoCliente,
esMotor: v.esMotor,
viajeIdParaActualizar: v.id,
),
                                  ],
                                  if (panelConductorAsignado) ...[
                                    if (mostrarBotonTocaPinGrande &&
                                        faseAbordoPin &&
                                        !mostrarCodigoCliente) ...[
                                      const SizedBox(height: 10),
                                      _buildBotonTocaActualizarViaje(
                                        viajeId: v.id,
                                        enEsperaAbordo: false,
                                      ),
                                    ],
                                  ],
                                  if (_mostrarPagoTarjetaCliente(
                                    v,
                                    estadoBase,
                                    data,
                                    codigoVerificado: codigoVerificado,
                                  )) ...[
                                    const SizedBox(height: 12),
                                    RaiPagoTarjetaPanel(
                                      viajeId: v.id,
                                      viajeData: data,
                                      montoRd: v.precio,
                                      fondoOscuro: true,
                                      role: 'cliente',
                                      modoViajeEnCurso: true,
                                    ),
                                    const SizedBox(height: 16),
                                  ] else if (_mostrarTarjetaPagadaCliente(
                                      v, estadoBase, data)) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10231A),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.greenAccent
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.check_circle_outline,
                                              color: Colors.greenAccent),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Pago con tarjeta confirmado. '
                                              'Al finalizar el viaje verás tu recibo.',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13,
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ] else if (_mostrarPagoEfectivoCliente(
                                    v,
                                    estadoBase,
                                    data,
                                    codigoVerificado: codigoVerificado,
                                  )) ...[
                                    const SizedBox(height: 12),
                                    EfectivoPagoClienteBanner(
                                      montoRd: v.precio,
                                      desdeTarjeta: true,
                                    ),
                                    const SizedBox(height: 16),
                                  ],

                                  // Tarjeta de información del viaje (omitida si panel compacto ya resume origen/destino)
                                  if (!panelConductorAsignado)
                                    _buildTripInfoCard(v, estadoEfectivo),

                                  if (_simCasa) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3E2723),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.deepOrangeAccent
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            '[SIM CASA] Prueba sin moverte',
                                            style: TextStyle(
                                              color: Colors.deepOrangeAccent,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Activo: kDebugMode o '
                                            '--dart-define=FLYGO_SIM_CASA=true',
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.75),
                                              fontSize: 11,
                                              height: 1.3,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          TextButton.icon(
                                            onPressed: () {
                                              setState(() {
                                                _debugConductorCercaPickup =
                                                    !_debugConductorCercaPickup;
                                              });
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    _debugConductorCercaPickup
                                                        ? 'Simulación: conductor “cerca” del pickup.'
                                                        : 'Simulación pickup desactivada.',
                                                  ),
                                                  duration: const Duration(
                                                    seconds: 2,
                                                  ),
                                                ),
                                              );
                                            },
                                            icon: Icon(
                                              _debugConductorCercaPickup
                                                  ? Icons.gps_off
                                                  : Icons.near_me,
                                              color: Colors.deepOrangeAccent,
                                            ),
                                            label: Text(
                                              _debugConductorCercaPickup
                                                  ? 'Quitar “conductor cerca”'
                                                  : 'Simular conductor cerca del pickup',
                                              style: const TextStyle(
                                                color:
                                                    Colors.deepOrangeAccent,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],

                                  ],

                                  if (_paradasIntermediasResueltas(v)
                                          .isNotEmpty &&
                                      !_clienteNavegacionMultiparadaActiva(
                                          v, estadoBase)) ...[
                                    const SizedBox(height: 16),
                                    _buildParadasWidget(v),
                                  ],
                                  _bannerIdaYVuelta(v),
                                          ],
                                        ),
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
                    );
                  },
                );
              },
            ),
    ),
);
  }
}

class _ClienteCargaViajeGate extends StatefulWidget {
  const _ClienteCargaViajeGate({
    required this.mensaje,
    required this.onVolverInicio,
    this.onReintentar,
  });

  final String mensaje;
  final VoidCallback onVolverInicio;
  final VoidCallback? onReintentar;

  @override
  State<_ClienteCargaViajeGate> createState() => _ClienteCargaViajeGateState();
}

class _ClienteCargaViajeGateState extends State<_ClienteCargaViajeGate> {
  static const Duration _kTimeout = Duration(seconds: 12);
  Timer? _timer;
  bool _mostrarEscape = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_kTimeout, () {
      if (!mounted) return;
      setState(() => _mostrarEscape = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.greenAccent,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (_mostrarEscape) ...[
              const SizedBox(height: 20),
              if (widget.onReintentar != null) ...[
                OutlinedButton.icon(
                  onPressed: widget.onReintentar,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reintentar'),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: widget.onVolverInicio,
                icon: const Icon(Icons.home_rounded, size: 18),
                label: const Text('Ir al inicio'),
              ),
            ],
          ],
        ),
      ),
    );
  }
} 
