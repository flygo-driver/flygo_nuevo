// lib/pantallas/taxista/viaje_en_curso_taxista.dart
// ignore_for_file: avoid_print -- [VIAJE_ACTIVO] / [FINALIZAR] / [FINALIZAR_VIAJE]

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui show ImageByteFormat, PictureRecorder;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        debugPrint,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/config/plataforma_economia.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/widgets/viaje_overlay_error_shield.dart';
import 'package:flygo_nuevo/pantallas/chat/chat_screen.dart';
import 'package:flygo_nuevo/pantallas/taxista/mis_rutas_corporativas_page.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/gps_service.dart';
import 'package:flygo_nuevo/servicios/error_reporting.dart';
import 'package:flygo_nuevo/servicios/error_auth_es.dart';
import 'package:flygo_nuevo/navegacion/post_viaje_taxista_nav.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/navegacion_externa_launcher.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/utils/viaje_navegacion_resolver.dart';
import 'package:flygo_nuevo/widgets/multiparada_navegacion_tarjetas.dart';
import 'package:flygo_nuevo/servicios/corporativo_fase_a_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart'; // 🔥 ESTA LÍNEA
import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/corporativo_espera_codigo_constants.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/widgets/tarjeta_pago_estado_viaje.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/release_build_flags.dart';
import 'package:flygo_nuevo/utils/telefono_viaje.dart';
import 'package:flygo_nuevo/utils/ux_log.dart';
import 'package:flygo_nuevo/servicios/viaje_comunicacion_repo.dart';
import 'package:flygo_nuevo/shell/taxista_shell.dart';
import 'package:flygo_nuevo/widgets/cliente_perfil_conductor_chip.dart';
import 'package:flygo_nuevo/widgets/mapa_tiempo_real.dart';
import 'package:flygo_nuevo/widgets/rai_viaje_en_curso_ui.dart';
import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/widgets/viaje_chat_mensajes_en_vivo.dart';
import 'package:flygo_nuevo/widgets/cola_siguiente_viaje_banner.dart';
import 'package:flygo_nuevo/servicios/corporativo_taxista_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_viaje_gps_tracker.dart';
import 'package:flygo_nuevo/servicios/rai_ubicacion_taxista_service.dart';
import 'package:flygo_nuevo/servicios/ubicacion_taxista.dart';
import 'package:flygo_nuevo/widgets/corporativo_abordaje_chofer_panel.dart';
import 'package:flygo_nuevo/widgets/corporativo_pasajeros_chofer_card.dart';
import 'package:flygo_nuevo/widgets/navegacion_waze_maps_sheet.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_map_alert.dart';
import 'package:flygo_nuevo/widgets/rai_ubicacion_rol.dart';
import 'package:flygo_nuevo/widgets/taxista_pickup_cliente_panel.dart';
import 'package:flygo_nuevo/widgets/viaje_flujo_orientacion.dart';
import 'package:flygo_nuevo/widgets/viaje_flujo_profesional_taxista_header.dart';
import 'package:flygo_nuevo/widgets/viajes_cercanos_taxista.dart';

String _safeFechaViaje(DateTime? dt) {
  try {
    return dt == null ? '—' : DateFormat('dd/MM/yyyy - HH:mm').format(dt);
  } catch (_) {
    return '—';
  }
}

String _safeMoneyViaje(num? n) {
  try {
    final double v = (n ?? 0).toDouble();
    if (!v.isFinite) return FormatosMoneda.rd(0);
    return FormatosMoneda.rd(v);
  } catch (_) {
    return FormatosMoneda.rd(0);
  }
}

/// Tras [finalizarViajeSeguro]: no reintentar escrituras legacy en billetera.
bool _pagoYaAsentadoPorServidor(Map<String, dynamic> data) {
  if (data['comision_cents'] is num && (data['comision_cents'] as num) > 0) {
    return true;
  }
  if (data['facturaSaldoPrepagoComisionRd'] != null) {
    return true;
  }
  final String st =
      EstadosViaje.normalizar((data['estado'] ?? '').toString());
  return data['completado'] == true && st == EstadosViaje.completado;
}

void logDbg(String msg) {
  if (kDebugMode) debugPrint('[VIAJE_TX] $msg');
}

const bool _diagTripFlow =
    bool.fromEnvironment('TRIP_FLOW_DIAG', defaultValue: false);
void _diag(String msg) {
  if (_diagTripFlow) debugPrint('[TRIP_FLOW][en_curso] $msg');
}

/// Solo en debug/profile: ignorar distancias muy pequeñas (mismo dispositivo).
const double kDebugMinDistance = 0.01; // ~10 m

/// Radio máximo para habilitar el botón **Finalizar** (Geolocator vs pin de destino).
const double kFinalizarRadioMetros = 50;

class ViajeEnCursoTaxista extends StatefulWidget {
  const ViajeEnCursoTaxista({super.key});
  @override
  State<ViajeEnCursoTaxista> createState() => _ViajeEnCursoTaxistaState();
}

class _ViajeEnCursoTaxistaState extends State<ViajeEnCursoTaxista>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  /// Pruebas en silla: solo debug/profile con define; nunca en Play Store.
  bool get _flygoSimCasa => ReleaseBuildFlags.simCasaEnabled;

  /// Pruebas en casa: abrir Maps y finalizar sin recorrer distancia real.
  bool _permitePruebaSinRecorrido(Viaje v) => _flygoSimCasa;

  /// Atajo QA corporativo (solo debug / SIM CASA): mapa → código sin km reales.
  bool _permiteAtajoPruebaCorp(Viaje v) =>
      _permitePruebaSinRecorrido(v) &&
      CorporativoPasajerosChoferCard.esViajeCorporativo(v);

  /// Copy del sheet: SIM CASA en debug sin mezclar productos.
  String _hintPruebaSinRecorrido(
    Viaje v, {
    required bool trasIniciarRuta,
  }) {
    if (CorporativoPasajerosChoferCard.esViajeCorporativo(v)) {
      return trasIniciarRuta
          ? 'Prueba corporativo: no hace falta recorrer km. '
              'Confirmá cada parada o finalizá directo.'
          : 'Prueba corporativo: abrí Waze/Maps y al volver aparece el código. '
              'Si manejás, el GPS graba la ruta igual.';
    }
    return trasIniciarRuta
        ? 'Modo prueba (SIM CASA): no hace falta recorrer km. '
            'Tras iniciar ruta podés finalizar sin recorrer.'
        : 'Modo prueba (SIM CASA): abrí mapa o continuá sin mapa; '
            'luego aparece «Finalizar viaje».';
  }

  /// GPS en vivo para el doc del viaje; abrir Waze/Maps no lo exige en prueba.
  Future<bool> _gpsListoParaAbrirNavegacionExterna(Viaje v) async {
    if (_permitePruebaSinRecorrido(v) || kIsWeb) return true;
    return _asegurarGps(v.id);
  }

  @override
  bool get wantKeepAlive => true;

  /// Evita leer SharedPreferences en cada frame del stream.
  String? _navPickupPrefsLoadedForId;
  String? _navDestinoPrefsLoadedForId;

  /// Antispam del snackbar al volver de Waze/Maps (resumed).
  DateTime? _lastNavResumeSnackAt;

  GoogleMapController? _map;

  // ===== GPS =====
  StreamSubscription<Position>? _gpsSub;
  String? _gpsParaViajeId;
  bool _gpsActivo = false;

  /// Reintento acotado si el stream de posición falla (p. ej. GPS apagado).
  static const int _kMaxGpsStreamRecoveryIntentos = 3;
  static const Duration _kGpsStreamRecoveryDelay = Duration(seconds: 5);
  int _gpsStreamRecoveryIntentos = 0;
  Timer? _gpsStreamRecoveryTimer;

  // ===== Acciones =====
  bool _actionBusy = false;

  // ===== Remoción / cancelación remota =====
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _cancelSub;
  bool _procesandoRemocion = false;
  DateTime? _cancelListenerIniciadoEn;

  // ===== Controlador para código de verificación =====
  final TextEditingController _codigoCtrl = TextEditingController();
  final FocusNode _corpPinFocusNode = FocusNode();

  // ===== Polylines para rutas =====
  final Set<Polyline> _polylines = <Polyline>{};
  /// Recorrido real GPS (corporativo en curso) — se dibuja encima del plan.
  final List<LatLng> _gpsTrailPoints = <LatLng>[];
  static const int _kMaxGpsTrailPoints = 600;
  static const double _kGpsAccuracyMaxMetros = 75;
  int _drawRoutesGeneration = 0;
  /// Solo corporativo: pins de cada parada en el mapa RAI (no afecta Waze/Maps).
  Set<Marker> _corpMapMarkers = <Marker>{};
  final Map<String, BitmapDescriptor> _corpPinIconCache = <String, BitmapDescriptor>{};
  Timer? _routeDebounce;

  // ===== Viajes cercanos / cola: aislado en [ViajesCercanosTaxistaLayer] (no setState aquí) =====
  final ViajesCercanosTaxistaController _viajesCercanosCtl =
      ViajesCercanosTaxistaController();
  final ValueNotifier<bool> _viajesCercanosEscucha = ValueNotifier<bool>(false);
  final ValueNotifier<(double, double)?> _taxistaPosCola =
      ValueNotifier<(double, double)?>(null);
  final ValueNotifier<ColaCercaniaReferencia?> _colaReferenciaOrden =
      ValueNotifier<ColaCercaniaReferencia?>(null);
  final ValueNotifier<double?> _distanciaDestinoNotifier =
      ValueNotifier<double?>(null);

  // 🚀 Variables para detección de cercanía del cliente
  bool _clienteCerca = false;
  bool _navegacionIniciada = false;
  bool _navegacionDestinoIniciada = false;
  /// Legs multiparada con Waze/Maps abiertos en sesión (orden libre, estilo corp.).
  final Set<int> _multiLegNavAbiertaIndices = <int>{};
  bool _origenMultiNavAbierto = false;
  bool _selectorNavegacionAbierto = false;
  /// Evita ver la tarjeta del viaje y el modal Waze/Maps apilados a la vez.
  bool _viajeSheetOcultoPorModalNav = false;
  final DraggableScrollableController _viajeSheetCtrl =
      DraggableScrollableController();
  static const double _kViajeSheetMin = 0.22;
  static const double _kViajeSheetInitial = 0.48;
  /// Fase pickup al cliente: sheet bajo para ver más mapa.
  static const double _kViajeSheetPickupCompact = 0.36;
  static const double _kViajeSheetPin = 0.74;
  String? _viajeSheetAseguradoParaId;
  String? _ultimoSnackEncadenadoViajeId;
  static const double DISTANCIA_CERCANIA_KM = 0.1;

  // Cache del viaje actual
  Viaje? _cachedViaje;
  bool _isUpdatingLocation = false;

  /// Evita spinner infinito si el stream no emite el viaje (p. ej. corporativo).
  Timer? _cargaViajeTimer;
  Timer? _cargaViajeRescueTimer;
  Timer? _cargaViajeTickTimer;
  bool _cargaViajeExpirada = false;
  String? _corporativoAunNoHoraMsg;
  String? _chatAseguradoParaViajeId;

  /// Corporativo: cuenta regresiva en origen e intentos de PIN.
  Timer? _corpCodigoTimeoutTicker;
  Duration _corpTiempoRestanteCodigo =
      CorporativoEsperaCodigoConstants.timeout;
  int _corpIntentosFallidos = 0;
  /// Tras «Cliente a bordo» corporativo: mostrar PIN aunque Firestore tarde.
  bool _corpPinUiActivo = false;
  bool _corpPinSheetExpandido = false;
  ScrollController? _viajeSheetScrollCtrl;

  final RaiUbicacionTaxistaService _ubicacionTaxistaSvc =
      RaiUbicacionTaxistaService.instance;

  /// Distancia al pin de destino (último waypoint o destino); solo en `en_curso`.
  double? _distanciaMetrosAlDestino;

  /// Multiparada: cuántos destinos (paradas + final) ya confirmó el taxista.
  int _multiLegCompletadas = 0;
  String? _multiNavViajeId;
  /// Evita disparar factura automática dos veces para el mismo viaje.
  String? _multiparadaAutoFacturaViajeId;

  /// Un solo ticker para "tiempo en ruta" (evita recrear Stream.periodic en cada rebuild).
  late final Stream<DateTime> _duracionEnRutaTicker =
      Stream<DateTime>.periodic(
        const Duration(seconds: 1),
        (_) => DateTime.now(),
      ).asBroadcastStream();

  // ===== Stream principal (una sola suscripción; recrearlo en build parpadea toda la pantalla) =====
  Stream<Viaje?>? _viajeEnCursoStream;
  Timer? _viajeNullConfirmTimer;
  static const Duration _kViajeNullConfirmDelay = Duration(seconds: 2);

  void _initViajeEnCursoStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _viajeEnCursoStream = const Stream<Viaje?>.empty();
      return;
    }
    _viajeEnCursoStream ??=
        ViajesRepo.streamViajeEnCursoPorTaxista(uid)
            .distinct(_mismoViajeParaUiTaxista);
  }

  void _scheduleSyncEsperaCargaViaje(bool esperando) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncEsperaCargaViaje(esperando);
    });
  }

  void _cancelarDebounceViajeNull() {
    _viajeNullConfirmTimer?.cancel();
    _viajeNullConfirmTimer = null;
  }

  void _programarConfirmacionViajeNull() {
    if (_viajeNullConfirmTimer != null) return;
    _viajeNullConfirmTimer = Timer(_kViajeNullConfirmDelay, () {
      _viajeNullConfirmTimer = null;
      if (!mounted) return;
      unawaited(_verificarYLimpiarViajeCacheSiAusente());
    });
  }

  /// El stream puede emitir `null` un instante (reconciliación / red). No vaciar la UI
  /// hasta confirmar en servidor que el viaje ya no existe.
  Future<void> _verificarYLimpiarViajeCacheSiAusente() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final Viaje? cached = _cachedViaje;
    if (uid == null || cached == null || !mounted) return;
    try {
      final DocumentSnapshot<Map<String, dynamic>> us =
          await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      final Map<String, dynamic> u = us.data() ?? <String, dynamic>{};
      for (final raw in <dynamic>[u['viajeActivoId'], u['siguienteViajeId']]) {
        final String vid = (raw ?? '').toString().trim();
        if (vid.isEmpty || vid != cached.id) continue;
        final DocumentSnapshot<Map<String, dynamic>> vs =
            await FirebaseFirestore.instance.collection('viajes').doc(vid).get();
        if (!vs.exists) continue;
        final Map<String, dynamic> d = vs.data() ?? <String, dynamic>{};
        if (ViajesRepo.viajeVisibleEnCursoTaxista(d, uid)) {
          if (!mounted) return;
          setState(() => _cachedViaje = Viaje.fromMap(vs.id, d));
          return;
        }
      }
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _cachedViaje = null;
      _navPickupPrefsLoadedForId = null;
      _navDestinoPrefsLoadedForId = null;
      _distanciaMetrosAlDestino = null;
    });
    _stopGps();
    _syncEsperaCargaViaje(false);
  }

  static bool _mismoViajeParaUiTaxista(Viaje? a, Viaje? b) =>
      _firmaViajeUiTaxista(a) == _firmaViajeUiTaxista(b);

  static String _firmaViajeUiTaxista(Viaje? v) {
    if (v == null) return '';
    final est = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
    );
    String r6(double x) => (x.isFinite) ? x.toStringAsFixed(6) : 'x';
    final int wp = v.waypoints?.length ?? 0;
    // No incluir latTaxista/lonTaxista: este taxista escribe el GPS en el mismo doc y cada
    // actualización dispararía StreamBuilder + Column completa. La posición se mantiene en
    // _cachedViaje vía copyWith en el listener GPS.
    // Cliente/destino con 6 decimales para ver movimiento en tiempo real en el mapa.
    return '${v.id}|$est|${r6(v.latCliente)}|${r6(v.lonCliente)}|${r6(v.latDestino)}|${r6(v.lonDestino)}|'
        '${v.codigoVerificado}|${v.uidTaxista}|${v.completado}|$wp|${v.multiparadaLegCompletadas}|${v.multiparadaCompleta}|'
        '${_firmaPasajerosCorpTaxista(v)}|${(v.extras?['corporativoPasajerosActualizadosEn'] ?? '').toString()}';
  }

  /// Cambios en pasajeros/paradas corp deben refrescar UI (lista, mapa, multiparada).
  static String _firmaPasajerosCorpTaxista(Viaje v) {
    if (!CorporativoPasajerosChoferCard.esViajeCorporativo(v)) return '';
    final pas = CorporativoPasajerosChoferCard.pasajerosDesdeViaje(v);
    if (pas.isEmpty) return 'corp0';
    final buf = StringBuffer('corp${pas.length}|');
    for (final p in pas) {
      buf.write('${p.orden}:${p.id}:');
      buf.write('${p.lat.toStringAsFixed(5)},${p.lon.toStringAsFixed(5)}:');
      buf.write('${p.nombre.trim()}|${p.destinoLabel.trim()};');
    }
    return buf.toString();
  }

  /// Solo campos que afectan polilíneas hacia el cliente o destino.
  static String _firmaRutaMapaTaxista(Viaje v) {
    String r6(double x) => (x.isFinite) ? x.toStringAsFixed(6) : 'x';
    final est = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
    );
    return '$est|${r6(v.latCliente)}|${r6(v.lonCliente)}|${r6(v.latDestino)}|${r6(v.lonDestino)}|'
        '${v.codigoVerificado}|${v.multiparadaLegCompletadas}|${v.multiparadaCompleta}|'
        '${_firmaPasajerosCorpTaxista(v)}';
  }

  // ===== Utilidades =====
  bool _coordsValid(double lat, double lon) =>
      lat.isFinite &&
      lon.isFinite &&
      !(lat == 0 && lon == 0) &&
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180;

  String _cleanPhone(String raw) => telefonoNormalizarDigitos(raw);

  String _digitsOnlyCode(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');

  bool _codigoEsperadoValido(String? codigo) =>
      _digitsOnlyCode(codigo).length == 6;

  void _tripFlowSnack(String msg, {Color backgroundColor = Colors.orange}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  double? _waypointLat(Map<String, dynamic> w) {
    for (final k in ['lat', 'latitude', 'latitud']) {
      final x = w[k];
      if (x is num && x.isFinite) return x.toDouble();
      final d = double.tryParse('$x');
      if (d != null && d.isFinite) return d;
    }
    return null;
  }

  double? _waypointLon(Map<String, dynamic> w) {
    for (final k in ['lon', 'lng', 'longitude', 'longitud']) {
      final x = w[k];
      if (x is num && x.isFinite) return x.toDouble();
      final d = double.tryParse('$x');
      if (d != null && d.isFinite) return d;
    }
    return null;
  }

  bool _esMultiparada(Viaje v) {
    if (v.multiparadaLegsTotal > 1) return true;
    final List<Map<String, dynamic>>? wps = v.waypoints;
    if (wps != null && wps.isNotEmpty) return true;
    final dynamic rp = v.extras?['rutaPuntos'];
    if (rp is! List) return false;
    for (final dynamic item in rp) {
      if (item is! Map) continue;
      final String rol = (item['rol'] ?? '').toString().toLowerCase();
      if (rol == 'parada') return true;
    }
    return false;
  }

  List<({double lat, double lon, String label})> _paradasIntermediasDesdeViaje(
    Viaje v,
  ) {
    final List<({double lat, double lon, String label})> out =
        <({double lat, double lon, String label})>[];
    final List<Map<String, dynamic>>? raw = v.waypoints;
    if (raw != null) {
      for (final Map<String, dynamic> m in raw) {
        final double? lat = _waypointLat(m);
        final double? lon = _waypointLon(m);
        if (lat == null || lon == null || !_coordsValid(lat, lon)) continue;
        final String label = (m['label'] ?? '').toString().trim();
        out.add((
          lat: lat,
          lon: lon,
          label: label.isEmpty ? 'Parada ${out.length + 1}' : label,
        ));
      }
    }
    if (out.isNotEmpty) return out;

    final dynamic rp = v.extras?['rutaPuntos'];
    if (rp is List) {
      for (final dynamic item in rp) {
        if (item is! Map) continue;
        final String rol = (item['rol'] ?? '').toString().toLowerCase();
        if (rol == 'origen' || rol == 'destino' || rol == 'destino_final') {
          continue;
        }
        final double? lat = _waypointLat(Map<String, dynamic>.from(item));
        final double? lon = _waypointLon(Map<String, dynamic>.from(item));
        if (lat == null || lon == null || !_coordsValid(lat, lon)) continue;
        final String label = (item['label'] ?? 'Parada').toString().trim();
        out.add((
          lat: lat,
          lon: lon,
          label: label.isEmpty ? 'Parada ${out.length + 1}' : label,
        ));
      }
    }
    if (out.isEmpty && CorporativoPasajerosChoferCard.esViajeCorporativo(v)) {
      final pas = CorporativoPasajerosChoferCard.pasajerosDesdeViaje(v)
        ..sort((a, b) {
          final oa = a.orden > 0 ? a.orden : 999;
          final ob = b.orden > 0 ? b.orden : 999;
          return oa.compareTo(ob);
        });
      for (var i = 0; i < pas.length - 1; i++) {
        final p = pas[i];
        if (!_coordsValid(p.lat, p.lon)) continue;
        final label = [
          if (p.nombre.trim().isNotEmpty) p.nombre.trim(),
          if (p.destinoLabel.trim().isNotEmpty) p.destinoLabel.trim(),
        ].join(' · ');
        out.add((
          lat: p.lat,
          lon: p.lon,
          label: label.isEmpty ? 'Parada ${out.length + 1}' : label,
        ));
      }
    }
    return out;
  }

  List<({double lat, double lon, String label, bool esFinal})>
      _destinosOrdenadosCorporativo(Viaje v) {
    final pas = CorporativoPasajerosChoferCard.pasajerosDesdeViaje(v);
    if (pas.isEmpty) return _destinosOrdenadosMultiparada(v);

    final sorted = List<CorporativoPasajero>.from(pas)
      ..sort((a, b) {
        final oa = a.orden > 0 ? a.orden : 999;
        final ob = b.orden > 0 ? b.orden : 999;
        return oa.compareTo(ob);
      });

    final out = <({double lat, double lon, String label, bool esFinal})>[];
    for (var i = 0; i < sorted.length; i++) {
      final p = sorted[i];
      if (!_coordsValid(p.lat, p.lon)) continue;
      final parts = <String>[
        if (p.nombre.trim().isNotEmpty) p.nombre.trim(),
        if (p.destinoLabel.trim().isNotEmpty)
          p.destinoLabel.trim()
        else if (p.sector.trim().isNotEmpty)
          p.sector.trim(),
      ];
      out.add((
        lat: p.lat,
        lon: p.lon,
        label: parts.isEmpty ? 'Pasajero ${out.length + 1}' : parts.join(' · '),
        esFinal: i == sorted.length - 1,
      ));
    }
    return out;
  }

  /// Paradas ordenadas: corporativo usa pasajeros; resto multiparada estándar.
  List<({double lat, double lon, String label, bool esFinal})>
      _destinosOrdenadosParaMapa(Viaje v) {
    if (CorporativoPasajerosChoferCard.esViajeCorporativo(v)) {
      return _destinosOrdenadosCorporativo(v);
    }
    return _destinosOrdenadosMultiparada(v);
  }

  /// Legs para navegación, progreso multiparada y UI de paradas (corp incluido).
  List<({double lat, double lon, String label, bool esFinal})>
      _legsNavegacionMultiparada(Viaje v) => _destinosOrdenadosParaMapa(v);

  List<({double lat, double lon, String label, bool esFinal})>
      _destinosOrdenadosMultiparada(Viaje v) {
    final List<({double lat, double lon, String label, bool esFinal})> out =
        <({double lat, double lon, String label, bool esFinal})>[];
    for (final ({double lat, double lon, String label}) p
        in _paradasIntermediasDesdeViaje(v)) {
      out.add((lat: p.lat, lon: p.lon, label: p.label, esFinal: false));
    }
    if (_coordsValid(v.latDestino, v.lonDestino)) {
      final String dest = v.destino.trim();
      out.add((
        lat: v.latDestino,
        lon: v.lonDestino,
        label: dest.isNotEmpty ? dest : 'Destino final',
        esFinal: true,
      ));
    } else {
      final dynamic rp = v.extras?['rutaPuntos'];
      if (rp is List) {
        for (final dynamic item in rp.reversed) {
          if (item is! Map) continue;
          final Map<String, dynamic> m = Map<String, dynamic>.from(item);
          final String rol = (m['rol'] ?? '').toString().toLowerCase();
          if (rol != 'destino' && rol != 'destino_final') continue;
          final double? lat = _waypointLat(m);
          final double? lon = _waypointLon(m);
          if (lat == null || lon == null || !_coordsValid(lat, lon)) continue;
          final String label = (m['label'] ?? v.destino).toString().trim();
          out.add((
            lat: lat,
            lon: lon,
            label: label.isNotEmpty ? label : 'Destino final',
            esFinal: true,
          ));
          break;
        }
      }
    }
    return out;
  }

  ({double lat, double lon, String label, bool esFinal})? _destinoMultiActual(
      Viaje v) {
    final List<({double lat, double lon, String label, bool esFinal})> legs =
        _legsNavegacionMultiparada(v);
    if (_multiLegCompletadas >= legs.length) return null;
    return legs[_multiLegCompletadas];
  }

  bool _multiparadaRutaCompleta(Viaje v) {
    if (!_esMultiparada(v)) return true;
    if (v.multiparadaCompleta) return true;
    final int total = _legsNavegacionMultiparada(v).length;
    if (total <= 0) return true;
    final visitados =
        multiparadaLegsVisitadosDesdeViaje(v, totalLegs: total);
    return visitados.length >= total || _multiLegCompletadas >= total;
  }

  void _aplicarProgresoMultiparadaDesdeViaje(Viaje v) {
    if (!_esMultiparada(v)) {
      if (_multiLegCompletadas != 0 || _multiNavViajeId != null) {
        _multiLegCompletadas = 0;
        _multiNavViajeId = null;
      }
      return;
    }
    final int total = _legsNavegacionMultiparada(v).length;
    final int fromServer = v.multiparadaLegCompletadas.clamp(0, total);
    if (_multiNavViajeId != v.id) {
      _multiLegNavAbiertaIndices.clear();
      _origenMultiNavAbierto = false;
      _multiNavViajeId = v.id;
      _multiLegCompletadas = fromServer;
    } else if (_multiLegCompletadas != fromServer) {
      _multiLegCompletadas = fromServer;
    }
    final abiertos =
        multiparadaLegsAbiertosDesdeViaje(v, totalLegs: total);
    _multiLegNavAbiertaIndices.addAll(abiertos);
    if (multiparadaRecogidaAbiertaDesdeViaje(v)) {
      _origenMultiNavAbierto = true;
    }
  }

  bool _puedeFinalizarViajeMultiparada(Viaje v) =>
      !_esMultiparada(v) || _multiparadaRutaCompleta(v);

  void _liberarGuardAutoFacturaMultiparada(String viajeId) {
    if (_multiparadaAutoFacturaViajeId == viajeId) {
      _multiparadaAutoFacturaViajeId = null;
    }
  }

  /// Tras confirmar el último destino: abre factura/comisión sin diálogo extra.
  void _programarAutoFacturaMultiparadaSiCorresponde(Viaje v) {
    if (!mounted) return;
    if (!_esMultiparada(v) || v.completado) return;
    if (!_multiparadaRutaCompleta(v)) return;
    if (_multiparadaAutoFacturaViajeId == v.id) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final Viaje? actual =
          _cachedViaje?.id == v.id ? _cachedViaje : v;
      if (actual == null || actual.completado) return;
      if (!_multiparadaRutaCompleta(actual)) return;
      if (_multiparadaAutoFacturaViajeId == actual.id) return;
      unawaited(
        _finalizarViaje(
          actual,
          trasConfirmarUltimaParadaMultiparada: true,
        ),
      );
    });
  }

  /// Al volver de Waze/Maps: confirma con ✓ el leg pendiente que ya se abrió.
  Future<void> _autoConfirmarLegMultiparadaPendienteTrasResume(Viaje v) async {
    if (_actionBusy || !_esMultiparada(v) || v.completado) return;
    final int total = _legsNavegacionMultiparada(v).length;
    if (total <= 0) return;
    final Set<int> visitados =
        multiparadaLegsVisitadosDesdeViaje(v, totalLegs: total);
    final Set<int> abiertos =
        multiparadaLegsAbiertosDesdeViaje(v, totalLegs: total);
    for (var i = 0; i < total; i++) {
      if (visitados.contains(i)) continue;
      final bool navAbierta =
          abiertos.contains(i) || _multiLegNavAbiertaIndices.contains(i);
      if (!navAbierta) return;
      await _confirmarLegMultiparadaTaxista(v, i);
      return;
    }
  }

  bool _esViajeCorporativo(Viaje v) =>
      CorporativoPasajerosChoferCard.esViajeCorporativo(v);

  bool _esViajeTurismo(Viaje v) =>
      v.esTurismo || AsignacionTurismoRepo.esDocumentoViajeTurismo(v.toMap());

  bool _docEsViajeTurismo(Map<String, dynamic> d) =>
      AsignacionTurismoRepo.esDocumentoViajeTurismo(d);

  bool _docEsViajeCorporativo(Map<String, dynamic> d, String uidTaxista) =>
      CorporativoTaxistaService.esViajeCorporativoAsignado(d, uidTaxista);

  /// Tipo de `viajeActivoId` en servidor (turismo / corporativo / pool).
  Future<String?> _tipoServicioViajeActivo(String uid) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> us =
          await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
      final String vid =
          (us.data()?['viajeActivoId'] ?? '').toString().trim();
      if (vid.isEmpty) return null;
      final DocumentSnapshot<Map<String, dynamic>> vs =
          await FirebaseFirestore.instance.collection('viajes').doc(vid).get();
      if (!vs.exists) return null;
      return (vs.data()?['tipoServicio'] ?? '').toString().trim();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _viajeActivoEsTurismo(String uid) async {
    final String? tipo = await _tipoServicioViajeActivo(uid);
    return tipo == 'turismo';
  }

  void _aplicarViajeRescatadoEnCache(Viaje viaje) {
    setState(() {
      _cachedViaje = viaje;
      _cargaViajeExpirada = false;
      _corporativoAunNoHoraMsg = null;
    });
    _syncEsperaCargaViaje(false);
  }

  /// Turismo: chat solo tras aceptar el viaje (evita error de permisos en cola/pool).
  bool _chatViajeHabilitadoParaTaxista(Viaje v, String estadoBase) {
    if (v.tipoServicio == 'turismo') {
      return v.uidCliente.isNotEmpty &&
          (v.aceptado || EstadosViaje.activos.contains(estadoBase));
    }
    return v.uidCliente.isNotEmpty;
  }

  String _estadoBaseViaje(Viaje v) => EstadosViaje.estadoOperativoViaje(
        estadoRaw: v.estado,
        aceptado: v.aceptado,
        completado: v.completado,
      );

  Map<String, dynamic> _mapViajeParaCorp(Viaje v) {
    final data = Map<String, dynamic>.from(v.toMap());
    data['id'] = v.id;
    final ex = v.extras;
    if (ex != null) {
      data['extras'] = Map<String, dynamic>.from(ex);
      if (ex['corporativoModoInformativo'] != null) {
        data['corporativoModoInformativo'] = ex['corporativoModoInformativo'];
      }
    }
    return data;
  }

  /// Ruta corporativa informativa (piloto): nunca en «Mi viaje en curso».
  bool _esCorpInformativoExcluido(Viaje v) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return CorporativoTaxistaService.corpDebeUsarPantallaDestinosChofer(
      _mapViajeParaCorp(v),
      uidTaxista: uid,
    );
  }

  Future<void> _salirSiSoloCorpInformativo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    if (await ActiveTripService.usuarioTieneViajeEnSeguimiento(uid)) return;
    final corpId =
        await CorporativoTaxistaService.idViajeCorporativoOperativoParaChofer(
      uid,
    );
    if (corpId == null || corpId.isEmpty) return;
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    ActiveTripService.cancelarBloqueoShellTaxista();
    ActiveTripService.notificarRebuildShell();
    if (!mounted) return;
    setState(() {
      _cachedViaje = null;
      _cargaViajeExpirada = false;
      _corporativoAunNoHoraMsg = null;
    });
  }

  /// Corporativo: finalizar solo tras navegar y confirmar destino(s).
  bool _mostrarBotonFinalizarViaje(Viaje v, {String? estadoBase}) {
    if (_esViajeCorporativo(v)) {
      final String st = estadoBase ?? EstadosViaje.normalizar(v.estado);
      return _corpMostrarBotonFinalizar(v, st);
    }
    if (_esMultiparada(v)) return _multiparadaRutaCompleta(v);
    return _navegacionDestinoIniciada;
  }

  bool _puedePulsarFinalizarViaje(Viaje v) {
    if (_actionBusy) return false;
    if (_esViajeCorporativo(v)) return _corpFinalizarHabilitado(v);
    return _puedeFinalizarViajeMultiparada(v);
  }

  /// Corporativo: Maps/Waze a la empresa solo en fase de recogida.
  bool _corpMapsWazeHabilitados(Viaje v, String estadoBase) =>
      _corpEnFasePickup(v, estadoBase);

  bool _corpMostrarNavPickup(Viaje v, String estadoBase) =>
      _corpMapsWazeHabilitados(v, estadoBase);

  bool _corpSinPin(Viaje v) {
    if (!_esViajeCorporativo(v) &&
        !CorporativoPasajerosChoferCard.esViajeCorporativo(v)) {
      return false;
    }
    final data = Map<String, dynamic>.from(v.toMap());
    data['id'] = v.id;
    return CorporativoTaxistaService.corpSinPinVerificacionChofer(
      data,
      uidTaxista: FirebaseAuth.instance.currentUser?.uid,
    );
  }

  Future<void> _limpiarCorpDeViajeEnCursoAlEntrar() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    await ViajesRepo.limpiarViajeActivoSiNoOperativo(uid);
    // Turismo y pool normal: sin reglas corporativas (Mis rutas / revertir promo).
    if (await _viajeActivoEsTurismo(uid)) return;
    await _salirSiSoloCorpInformativo();
    if (!mounted) return;
    if (_cachedViaje != null && _esCorpInformativoExcluido(_cachedViaje!)) {
      setState(() => _cachedViaje = null);
    }
  }

  bool _corpRutaOperativa(Viaje v) =>
      v.codigoVerificado || _corpSinPin(v);

  bool _corpFasePostPin(Viaje v) =>
      _esViajeCorporativo(v) && _corpRutaOperativa(v);

  /// Corporativo: Maps/Waze al destino solo en «en ruta» (no multiparada: usa su bloque).
  bool _corpMostrarNavDestino(Viaje v, String estadoBase) {
    if (!_corpFasePostPin(v)) return false;
    if (_corpDebeMostrarPanelPin(v, estadoBase)) return false;
    if (_corpEnFasePickup(v, estadoBase)) return false;
    return true;
  }

  /// Corporativo: paradas multiparada tras código verificado y ruta iniciada.
  bool _corpMultiparadaHabilitada(Viaje v, String estadoBase) {
    if (!_corpFasePostPin(v) || !_esMultiparada(v)) return false;
    if (_corpDebeMostrarPanelPin(v, estadoBase)) return false;
    return true;
  }

  /// Panel de paradas visible (chofer ya validó PIN o corp. post-PIN).
  bool _multiparadaPanelVisible(Viaje v, String estadoBase) {
    if (!_esMultiparada(v) || _multiparadaRutaCompleta(v)) return false;
    if (_corpDebeMostrarPanelPin(v, estadoBase)) return false;
    if (_corpEnFasePickup(v, estadoBase)) return false;
    if (_esViajeCorporativo(v)) {
      return _corpMultiparadaHabilitada(v, estadoBase);
    }
    return v.codigoVerificado &&
        (EstadosViaje.esAbordo(estadoBase) ||
            EstadosViaje.esEnCurso(estadoBase));
  }

  /// Tarjetas interactivas (Waze/Maps + ✓).
  bool _multiparadaNavegacionInteractiva(Viaje v, String estadoBase) {
    if (!_multiparadaPanelVisible(v, estadoBase)) return false;
    if (_esViajeCorporativo(v)) {
      return _corpMultiparadaHabilitada(v, estadoBase);
    }
    return true;
  }

  /// Primera parada pendiente (orden libre) para banner y navegación rápida.
  ({double lat, double lon, String label, bool esFinal, int index})?
      _proximoLegMultiparadaPendiente(Viaje v) {
    final List<({double lat, double lon, String label, bool esFinal})> legs =
        _legsNavegacionMultiparada(v);
    if (legs.isEmpty) return null;
    final visitados =
        multiparadaLegsVisitadosDesdeViaje(v, totalLegs: legs.length);
    for (var i = 0; i < legs.length; i++) {
      if (visitados.contains(i)) continue;
      final leg = legs[i];
      if (!_coordsValid(leg.lat, leg.lon)) continue;
      return (
        lat: leg.lat,
        lon: leg.lon,
        label: leg.label,
        esFinal: leg.esFinal,
        index: i,
      );
    }
    return null;
  }

  void _snackMultiparadaConfirmarBloqueado() {
    _tripFlowSnack(
      'Primero tocá la parada y abrí Waze o Maps. Después confirmá con ✓.',
      backgroundColor: Colors.orange,
    );
  }

  /// Corporativo: finalizar solo con código OK, navegación al destino y paradas hechas.
  bool _corpFinalizarHabilitado(Viaje v) {
    if (!_corpRutaOperativa(v)) return false;
    if (!_puedeFinalizarViajeMultiparada(v)) return false;
    if (_permitePruebaSinRecorrido(v)) return true;
    if (_esMultiparada(v)) return _multiparadaRutaCompleta(v);
    return _navegacionDestinoIniciada;
  }

  bool _corpMostrarBotonFinalizar(Viaje v, String estadoBase) {
    if (!_corpRutaOperativa(v)) return false;
    if (_permitePruebaSinRecorrido(v)) {
      return EstadosViaje.esEnCurso(estadoBase) || _navegacionDestinoIniciada;
    }
    if (_esMultiparada(v)) return _multiparadaRutaCompleta(v);
    return _navegacionDestinoIniciada;
  }

  /// Pruebas corporativas (SIM CASA): registra paradas pendientes antes de finalizar.
  Future<Viaje> _completarParadasCorporativoPendientes(Viaje v) async {
    if (!_permitePruebaSinRecorrido(v)) return v;
    if (!_esViajeCorporativo(v) || !_esMultiparada(v)) return v;
    Viaje actual = v;
    for (int guard = 0; guard < 24; guard++) {
      _aplicarProgresoMultiparadaDesdeViaje(actual);
      if (_multiparadaRutaCompleta(actual)) return actual;
      if (!actual.codigoVerificado) return actual;
      final int total = _legsNavegacionMultiparada(actual).length;
      if (total <= 0) return actual;
      if (_multiLegCompletadas >= total) return actual;

      final String st = EstadosViaje.normalizar(actual.estado);
      if (st != EstadosViaje.enCurso) {
        final String? uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null || uid.isEmpty) return actual;
        if (st == EstadosViaje.aBordo && actual.codigoVerificado) {
          await ViajesRepo.iniciarViaje(viajeId: actual.id, uidTaxista: uid);
        } else {
          break;
        }
      }

      final (double, double)? ping = _taxistaPosCola.value;
      await ViajesRepo.registrarLegMultiparadaCompletada(
        viajeId: actual.id,
        latConfirmacion: ping?.$1,
        lonConfirmacion: ping?.$2,
      );
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance.collection('viajes').doc(actual.id).get();
      if (!snap.exists) break;
      actual = Viaje.fromMap(actual.id, snap.data() ?? <String, dynamic>{});
      if (mounted) {
        setState(() {
          _aplicarProgresoMultiparadaDesdeViaje(actual);
          _cachedViaje = actual;
        });
      }
    }
    return actual;
  }

  ({double lat, double lon})? _coordsLegMultiActual(Viaje v) {
    final leg = _destinoMultiActual(v);
    if (leg != null) return (lat: leg.lat, lon: leg.lon);
    return _coordsDestinoParaFinalizar(v);
  }

  Future<Viaje> _asegurarEnCursoParaMultiparada(Viaje v) async {
    final String st = EstadosViaje.normalizar(v.estado);
    if (st == EstadosViaje.enCurso) return v;
    if (st != EstadosViaje.aBordo || !v.codigoVerificado) {
      throw Exception(
        'Iniciá la ruta al destino antes de confirmar paradas.',
      );
    }
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Sesión inválida');
    }
    await ViajesRepo.iniciarViaje(viajeId: v.id, uidTaxista: uid);
    final DocumentSnapshot<Map<String, dynamic>> snap =
        await FirebaseFirestore.instance.collection('viajes').doc(v.id).get();
    if (!snap.exists) throw Exception('Viaje no encontrado');
    final iniciado = Viaje.fromMap(v.id, snap.data() ?? <String, dynamic>{});
    await _corpGpsOnEnCurso(iniciado);
    return iniciado;
  }

  Future<void> _abrirMapsLegMultiparada(
    double lat,
    double lon,
    String label,
  ) async {
    await NavegacionExternaLauncher.abrirGoogleMapsDestino(lat, lon);
    _tripFlowSnack(
      'Navegación al pin: $label',
      backgroundColor: Colors.lightBlueAccent,
    );
  }

  Future<bool> _navegarDestinoMultiparadaActual(Viaje v) async {
    final pendiente = _proximoLegMultiparadaPendiente(v);
    if (pendiente == null) {
      if (mounted) {
        _tripFlowSnack(
          'No hay parada con coordenadas para navegar. '
          'Revisá los destinos de los pasajeros.',
          backgroundColor: Colors.orange,
        );
      }
      return false;
    }
    final int total = _legsNavegacionMultiparada(v).length;
    await _navegarPuntoMultiparadaTaxista(
      v,
      legIndex: pendiente.index,
      lat: pendiente.lat,
      lon: pendiente.lon,
      label: pendiente.label,
      tituloSheet: pendiente.esFinal
          ? 'Navegar al destino final'
          : 'Navegar a la parada',
      pasoEnTotal: pendiente.index + 1,
      tipoLeg: pendiente.esFinal
          ? 'destino final'
          : 'parada ${pendiente.index + 1}',
    );
    return _multiLegNavAbiertaIndices.contains(pendiente.index) ||
        multiparadaLegsAbiertosDesdeViaje(v, totalLegs: total)
            .contains(pendiente.index);
  }

  Future<void> _navegarPuntoMultiparadaTaxista(
    Viaje v, {
    required int? legIndex,
    required double lat,
    required double lon,
    required String label,
    required String tituloSheet,
    required int pasoEnTotal,
    required String tipoLeg,
  }) async {
    if (_actionBusy || _selectorNavegacionAbierto) return;
    _actionBusy = true;
    try {
      if (_esViajeCorporativo(v)) {
        final okGps = await _gpsListoParaAbrirNavegacionExterna(v);
        if (!okGps) {
          if (mounted) {
            _tripFlowSnack(
              'Activa el GPS para abrir Waze o Maps.',
              backgroundColor: Colors.orange,
            );
          }
          return;
        }
      }
      final opened = await _selectorNavegacionDestino(
        lat,
        lon,
        titulo: tituloSheet,
        addressLine: pasoEnTotal > 0
            ? '$label\n($pasoEnTotal · $tipoLeg)'
            : label,
        footerHint:
            'Waze o Maps abren este punto exacto. Marcá ✓ al llegar (orden libre).',
        viajeParaPersistirDestino: v,
      );
      if (opened && mounted) {
        if (legIndex != null) {
          _marcarNavegacionDestinoLista(v);
        }
        setState(() {
          if (legIndex == null) {
            _origenMultiNavAbierto = true;
          } else {
            _multiLegNavAbiertaIndices.add(legIndex);
          }
        });
        try {
          await ViajesRepo.marcarMultiparadaNavAbierta(
            viajeId: v.id,
            legIndex: legIndex,
          );
        } catch (e) {
          if (mounted) {
            _tripFlowSnack(
              'No se pudo registrar la navegación: $e',
              backgroundColor: Colors.orange,
            );
          }
        }
      }
    } finally {
      if (mounted) _actionBusy = false;
    }
  }

  List<MultiparadaNavegacionTarjetaModel> _tarjetasNavegacionMultiparadaTaxista(
    Viaje v, {
    required bool habilitado,
  }) {
    final List<({double lat, double lon, String label, bool esFinal})> legs =
        _legsNavegacionMultiparada(v);
    final visitados =
        multiparadaLegsVisitadosDesdeViaje(v, totalLegs: legs.length);
    final abiertos =
        multiparadaLegsAbiertosDesdeViaje(v, totalLegs: legs.length);
    final tarjetas = <MultiparadaNavegacionTarjetaModel>[];

    final origen = ViajeNavegacionResolver.origen(v);
    if (origen != null &&
        ViajeNavegacionResolver.coordsValidas(origen.lat, origen.lon)) {
      final bool recogidaAbierta = multiparadaRecogidaAbiertaDesdeViaje(v) ||
          _origenMultiNavAbierto;
      tarjetas.add(
        MultiparadaNavegacionTarjetaModel(
          titulo: 'Recogida',
          subtitulo: origen.label,
          accion: recogidaAbierta
              ? 'Abierto en Waze/Maps'
              : 'Waze o Maps · Recogida',
          acento: const Color(0xFF0F766E),
          icono: Icons.flag_circle_rounded,
          navegadoEnSesion: recogidaAbierta,
          onTap: habilitado && !_actionBusy && !_selectorNavegacionAbierto
              ? () => unawaited(
                    _navegarPuntoMultiparadaTaxista(
                      v,
                      legIndex: null,
                      lat: origen.lat,
                      lon: origen.lon,
                      label: origen.label,
                      tituloSheet: 'Navegar a la recogida',
                      pasoEnTotal: 0,
                      tipoLeg: 'origen',
                    ),
                  )
              : null,
        ),
      );
    }

    for (var i = 0; i < legs.length; i++) {
      final leg = legs[i];
      if (!_coordsValid(leg.lat, leg.lon)) continue;
      final bool visitado = visitados.contains(i);
      final bool navegado =
          abiertos.contains(i) || _multiLegNavAbiertaIndices.contains(i);
      final bool prueba = _permitePruebaSinRecorrido(v);
      tarjetas.add(
        MultiparadaNavegacionTarjetaModel(
          titulo: leg.esFinal ? 'Destino final' : 'Parada ${i + 1}',
          subtitulo: leg.label,
          accion: visitado
              ? 'Parada confirmada'
              : navegado
                  ? 'Paso 3: confirmá con ✓'
                  : 'Paso 1: tocá para Waze o Maps',
          acento: kMultiparadaNavegacionAcentos[
              i % kMultiparadaNavegacionAcentos.length],
          icono:
              leg.esFinal ? Icons.flag_rounded : Icons.location_on_rounded,
          legIndex: i,
          visitado: visitado,
          navegadoEnSesion: navegado,
          confirmacionHabilitada: navegado || prueba,
          onTap: habilitado &&
                  !_actionBusy &&
                  !_selectorNavegacionAbierto &&
                  !visitado
              ? () => unawaited(
                    _navegarPuntoMultiparadaTaxista(
                      v,
                      legIndex: i,
                      lat: leg.lat,
                      lon: leg.lon,
                      label: leg.label,
                      tituloSheet: leg.esFinal
                          ? 'Navegar al destino final'
                          : 'Navegar a la parada',
                      pasoEnTotal: i + 1,
                      tipoLeg: leg.esFinal ? 'destino final' : 'parada ${i + 1}',
                    ),
                  )
              : null,
          onMarcarHecha: habilitado && !_actionBusy && !visitado
              ? () => unawaited(_confirmarLegMultiparadaTaxista(v, i))
              : null,
          onConfirmarBloqueado: habilitado && !_actionBusy && !visitado
              ? _snackMultiparadaConfirmarBloqueado
              : null,
        ),
      );
    }
    return tarjetas;
  }

  ({double lat, double lon, String label})? _corpCoordsDestinoSimple(Viaje v) {
    if (_coordsValid(v.latDestino, v.lonDestino)) {
      final String label = v.destino.trim();
      return (
        lat: v.latDestino,
        lon: v.lonDestino,
        label: label.isEmpty ? 'Destino' : label,
      );
    }
    for (final p in CorporativoPasajerosChoferCard.pasajerosDesdeViaje(v)) {
      if (!_coordsValid(p.lat, p.lon)) continue;
      final parts = <String>[
        if (p.nombre.trim().isNotEmpty) p.nombre.trim(),
        if (p.destinoLabel.trim().isNotEmpty) p.destinoLabel.trim(),
      ];
      return (
        lat: p.lat,
        lon: p.lon,
        label: parts.isEmpty ? 'Destino' : parts.join(' · '),
      );
    }
    return null;
  }

  Future<Viaje?> _corpRefrescarViajeDesdeFirestore(String viajeId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get();
      if (!snap.exists || !mounted) return null;
      final actualizado =
          Viaje.fromMap(viajeId, snap.data() ?? <String, dynamic>{});
      setState(() {
        _cachedViaje = actualizado;
        _aplicarProgresoMultiparadaDesdeViaje(actualizado);
      });
      return actualizado;
    } catch (_) {
      return null;
    }
  }

  Future<void> _corpAsegurarViajeEnCurso(Viaje v) async {
    final String st = EstadosViaje.normalizar(v.estado);
    if (EstadosViaje.esEnCurso(st)) return;
    if (!v.codigoVerificado) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await ViajesRepo.iniciarViaje(viajeId: v.id, uidTaxista: uid);
    } catch (e, st) {
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: corp asegurar en curso',
      );
    }
  }

  /// Punto único para abrir Waze/Maps al destino o parada actual (corp).
  Future<bool> _corpAbrirNavegacionDestinoActual(Viaje v) async {
    if (!mounted || _selectorNavegacionAbierto) return false;
    final okGps = await _gpsListoParaAbrirNavegacionExterna(v);
    if (!okGps) {
      if (mounted) {
        _tripFlowSnack(
          'Activa el GPS para abrir Waze o Maps.',
          backgroundColor: Colors.orange,
        );
      }
      return false;
    }
    if (!mounted) return false;
    if (_esMultiparada(v)) {
      return _navegarDestinoMultiparadaActual(v);
    }
    final dest = _corpCoordsDestinoSimple(v);
    if (dest == null) {
      if (mounted) {
        _tripFlowSnack(
          'Sin coordenadas de destino. Revisá los pasajeros de la ruta.',
          backgroundColor: Colors.orange,
        );
      }
      return false;
    }
    return _selectorNavegacionDestino(
      dest.lat,
      dest.lon,
      titulo: 'Navegar al destino',
      addressLine: dest.label,
      viajeParaPersistirDestino: v,
    );
  }

  Future<void> _confirmarLegMultiparadaTaxista(Viaje v, int legIndex) async {
    if (_actionBusy) return;
    final int total = _legsNavegacionMultiparada(v).length;
    if (legIndex < 0 || legIndex >= total) return;
    final visitados =
        multiparadaLegsVisitadosDesdeViaje(v, totalLegs: total);
    if (visitados.contains(legIndex)) {
      if (_multiparadaRutaCompleta(v) && !v.completado) {
        _programarAutoFacturaMultiparadaSiCorresponde(v);
      }
      return;
    }
    if (v.multiparadaCompleta && !v.completado) {
      _programarAutoFacturaMultiparadaSiCorresponde(v);
      return;
    }
    if (v.multiparadaCompleta) return;
    final abiertos =
        multiparadaLegsAbiertosDesdeViaje(v, totalLegs: total);
    if (!_permitePruebaSinRecorrido(v) &&
        !abiertos.contains(legIndex) &&
        !_multiLegNavAbiertaIndices.contains(legIndex)) {
      _tripFlowSnack(
        'Abrí Waze o Maps a esta parada antes de confirmar la llegada.',
        backgroundColor: Colors.orange,
      );
      return;
    }
    _actionBusy = true;
    Viaje? viajeTrasCierreMultiparada;
    try {
      if (_permitePruebaSinRecorrido(v) &&
          !abiertos.contains(legIndex) &&
          !_multiLegNavAbiertaIndices.contains(legIndex)) {
        await ViajesRepo.marcarMultiparadaNavAbierta(
          viajeId: v.id,
          legIndex: legIndex,
        );
      }
      Viaje operativo = await _asegurarEnCursoParaMultiparada(v);
      if (!mounted) return;
      setState(() {
        _aplicarProgresoMultiparadaDesdeViaje(operativo);
        _cachedViaje = operativo;
      });
      final int totalOperativo =
          _legsNavegacionMultiparada(operativo).length;
      Viaje actualizado = operativo;
      if (!operativo.multiparadaCompleta) {
        final (double, double)? ping = _taxistaPosCola.value;
        await ViajesRepo.registrarLegMultiparadaCompletada(
          viajeId: operativo.id,
          legIndex: legIndex,
          latConfirmacion: ping?.$1,
          lonConfirmacion: ping?.$2,
        );
        if (_esViajeCorporativo(operativo)) {
          await _corpGpsCheckpoint(
            operativo,
            'parada',
            lat: ping?.$1,
            lon: ping?.$2,
          );
          _marcarNavegacionDestinoLista(operativo);
        }
        if (!mounted) return;
        final snap = await FirebaseFirestore.instance
            .collection('viajes')
            .doc(operativo.id)
            .get();
        if (!mounted) return;
        final data = snap.data();
        if (data == null) return;
        actualizado = Viaje.fromMap(operativo.id, data);
      }
      setState(() {
        _aplicarProgresoMultiparadaDesdeViaje(actualizado);
        _cachedViaje = actualizado;
        _multiLegNavAbiertaIndices.remove(legIndex);
      });
      _sincronizarReferenciaOrdenCola(actualizado);
      _recalcDistanciaDestino();
      _scheduleDrawRoute();
      final int visitadosCount = multiparadaLegsVisitadosDesdeViaje(
        actualizado,
        totalLegs: totalOperativo,
      ).length;
      final bool rutaCompleta = visitadosCount >= totalOperativo ||
          actualizado.multiparadaCompleta ||
          _multiparadaRutaCompleta(actualizado);
      if (rutaCompleta) {
        viajeTrasCierreMultiparada = actualizado;
        _tripFlowSnack(
          'Todos los destinos confirmados. Abriendo factura…',
          backgroundColor: Colors.greenAccent,
        );
      } else {
        _tripFlowSnack(
          'Parada confirmada (${visitadosCount}/$totalOperativo).',
          backgroundColor: Colors.lightBlueAccent,
        );
      }
    } catch (e) {
      if (mounted) {
        _tripFlowSnack(
          'No se pudo registrar la parada: $e',
          backgroundColor: Colors.redAccent,
        );
      }
    } finally {
      if (mounted) _actionBusy = false;
    }
    final Viaje? cerrar = viajeTrasCierreMultiparada;
    if (cerrar != null && mounted) {
      _programarAutoFacturaMultiparadaSiCorresponde(cerrar);
    }
  }

  Future<void> _confirmarLlegadaDestinoMulti(Viaje v) async {
    final int total = _legsNavegacionMultiparada(v).length;
    final visitados =
        multiparadaLegsVisitadosDesdeViaje(v, totalLegs: total);
    for (var i = 0; i < total; i++) {
      if (!visitados.contains(i)) {
        await _confirmarLegMultiparadaTaxista(v, i);
        return;
      }
    }
  }

  Future<void> _abrirGoogleMapsRutaMultiRestante(Viaje v) async {
    final List<({double lat, double lon, String label, bool esFinal})> legs =
        _legsNavegacionMultiparada(v);
    if (legs.isEmpty) return;
    final visitados =
        multiparadaLegsVisitadosDesdeViaje(v, totalLegs: legs.length);
    final List<({double lat, double lon, String label, bool esFinal})>
        remaining = <({double lat, double lon, String label, bool esFinal})>[];
    for (var i = 0; i < legs.length; i++) {
      if (!visitados.contains(i)) remaining.add(legs[i]);
    }
    if (remaining.isEmpty) return;

    double oLat = v.latCliente;
    double oLon = v.lonCliente;
    if (!_coordsValid(oLat, oLon)) {
      final ping = _taxistaPosCola.value;
      if (ping != null) {
        oLat = ping.$1;
        oLon = ping.$2;
      } else if (_coordsValid(v.latTaxista, v.lonTaxista)) {
        oLat = v.latTaxista;
        oLon = v.lonTaxista;
      }
    }
    if (!_coordsValid(oLat, oLon)) {
      _tripFlowSnack('Sin ubicación de origen para la ruta.');
      return;
    }

    final double dLat = remaining.last.lat;
    final double dLon = remaining.last.lon;
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
      addressLine:
          'Google Maps: ${paradas.length} parada(s) + destino final.',
      tieneCoords: true,
      footerHint:
          'Waze solo admite un destino; usa los botones «Navegar» parada a parada.',
      onWaze: () => unawaited(
        NavegacionExternaLauncher.abrirWazeDestino(dLat, dLon),
      ),
      onMaps: () => unawaited(
        NavegacionExternaLauncher.abrirGoogleMapsRutaConParadas(
          origenLat: oLat,
          origenLon: oLon,
          destinoLat: dLat,
          destinoLon: dLon,
          paradas: paradas,
        ),
      ),
    );
  }

  List<Widget> _bloqueNavegacionMultiparada(Viaje v, {bool habilitado = true}) {
    final List<({double lat, double lon, String label, bool esFinal})> legs =
        _legsNavegacionMultiparada(v);
    if (legs.isEmpty) return const <Widget>[];

    final int total = legs.length;
    final visitados =
        multiparadaLegsVisitadosDesdeViaje(v, totalLegs: total);
    final int hechos = visitados.length.clamp(0, total);
    final bool completa = hechos >= total || v.multiparadaCompleta;

    return <Widget>[
      MultiparadaNavegacionTarjetasPanel(
        tituloProgreso: completa
            ? 'Multiparada: todos los destinos visitados ($hechos/$total)'
            : 'Multiparada: $hechos de $total confirmados',
        subtituloHint: completa
            ? 'Factura y comisión al confirmar el último destino con ✓.'
            : 'Podés ir en el orden que quieras. Cada parada: navegá y confirmá con ✓.',
        tarjetas: _tarjetasNavegacionMultiparadaTaxista(
          v,
          habilitado: habilitado,
        ),
        accionesInferiores: completa
            ? const <Widget>[]
            : <Widget>[
                ElevatedButton.icon(
                  onPressed: habilitado
                      ? () => unawaited(_abrirGoogleMapsRutaMultiRestante(v))
                      : null,
                  icon: const Icon(Icons.alt_route, size: 24),
                  label: const Text(
                    'Ver ruta completa restante (Google Maps)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    elevation: 3,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Encadena paradas pendientes en un solo mapa.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
      ),
    ];
  }

  /// Punto de cierre del viaje: destino final del documento (no la última parada intermedia).
  ({double lat, double lon})? _coordsDestinoParaFinalizar(Viaje v) {
    if (_coordsValid(v.latDestino, v.lonDestino)) {
      return (lat: v.latDestino, lon: v.lonDestino);
    }
    final dynamic rp = v.extras?['rutaPuntos'];
    if (rp is List) {
      for (final dynamic item in rp.reversed) {
        if (item is! Map) continue;
        final Map<String, dynamic> m = Map<String, dynamic>.from(item);
        final String rol = (m['rol'] ?? '').toString().toLowerCase();
        if (rol != 'destino' && rol != 'destino_final') continue;
        final double? lat = _waypointLat(m);
        final double? lon = _waypointLon(m);
        if (lat != null && lon != null && _coordsValid(lat, lon)) {
          return (lat: lat, lon: lon);
        }
      }
    }
    return null;
  }

  /// Punto desde el que ordenar candidatos de cola: destino/parada actual si va con cliente; si no, GPS.
  void _sincronizarReferenciaOrdenCola(Viaje? v) {
    ColaCercaniaReferencia? next;
    if (v != null) {
      final String estadoBase = EstadosViaje.normalizar(
        v.estado.isNotEmpty
            ? v.estado
            : (v.completado
                ? EstadosViaje.completado
                : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
      );
      final bool rutaAlDestino = EstadosViaje.esEnCurso(estadoBase) ||
          (EstadosViaje.esAbordo(estadoBase) && v.codigoVerificado);
      if (rutaAlDestino) {
        final ({double lat, double lon})? dest =
            _esMultiparada(v) && !_multiparadaRutaCompleta(v)
                ? _coordsLegMultiActual(v)
                : _coordsDestinoParaFinalizar(v);
        if (dest != null) {
          final String destLabel = (v.destino.isNotEmpty
                  ? v.destino
                  : (v.extras?['destinoLabel'] ?? ''))
              .toString()
              .trim();
          next = ColaCercaniaReferencia(
            lat: dest.lat,
            lon: dest.lon,
            porDestinoViajeActivo: true,
            destinoEtiqueta: destLabel,
          );
        }
      }
    }
    if (next == null) {
      final (double, double)? ping = _taxistaPosCola.value;
      if (ping != null && _coordsValid(ping.$1, ping.$2)) {
        next = ColaCercaniaReferencia(
          lat: ping.$1,
          lon: ping.$2,
          porDestinoViajeActivo: false,
        );
      } else if (v != null && _coordsValid(v.latTaxista, v.lonTaxista)) {
        next = ColaCercaniaReferencia(
          lat: v.latTaxista,
          lon: v.lonTaxista,
          porDestinoViajeActivo: false,
        );
      }
    }
    final ColaCercaniaReferencia? prev = _colaReferenciaOrden.value;
    if (prev != null &&
        next != null &&
        prev.lat == next.lat &&
        prev.lon == next.lon &&
        prev.porDestinoViajeActivo == next.porDestinoViajeActivo) {
      return;
    }
    if (prev == null && next == null) return;
    _colaReferenciaOrden.value = next;
  }

  ({double lat, double lon})? _origenRutaEnCursoTaxista(Viaje v) {
    final (double, double)? ping = _taxistaPosCola.value;
    if (ping != null && _coordsValid(ping.$1, ping.$2)) {
      return (lat: ping.$1, lon: ping.$2);
    }
    if (_coordsValid(v.latTaxista, v.lonTaxista)) {
      return (lat: v.latTaxista, lon: v.lonTaxista);
    }
    if (_cachedViaje != null &&
        _coordsValid(_cachedViaje!.latTaxista, _cachedViaje!.lonTaxista)) {
      return (
        lat: _cachedViaje!.latTaxista,
        lon: _cachedViaje!.lonTaxista,
      );
    }
    if (_coordsValid(v.latCliente, v.lonCliente)) {
      return (lat: v.latCliente, lon: v.lonCliente);
    }
    return null;
  }

  /// Mejor distancia al pin de destino: primero el ping **en vivo** del stream (navegación en curso),
  /// luego lecturas puntuales y la posición guardada en el viaje.
  Future<double?> _menorDistanciaMetrosAlDestinoParaFinalizar(
    Viaje v,
    ({double lat, double lon}) destino, {
    (double, double)? pingStreamLatLon,
  }) async {
    final List<({double lat, double lon})> pts = [];

    if (pingStreamLatLon != null) {
      final double a = pingStreamLatLon.$1;
      final double b = pingStreamLatLon.$2;
      if (_coordsValid(a, b)) pts.add((lat: a, lon: b));
    }

    try {
      final Position? last = await Geolocator.getLastKnownPosition();
      if (last != null && _coordsValid(last.latitude, last.longitude)) {
        pts.add((lat: last.latitude, lon: last.longitude));
      }
    } catch (e) {
      uxLog('GPS_FINALIZAR', 'getLastKnownPosition', e);
    }

    for (final LocationAccuracy acc in [
      LocationAccuracy.high,
      LocationAccuracy.medium,
      LocationAccuracy.low,
    ]) {
      try {
        final Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: acc,
        );
        if (_coordsValid(pos.latitude, pos.longitude)) {
          pts.add((lat: pos.latitude, lon: pos.longitude));
        }
      } catch (e) {
        uxLog('GPS_FINALIZAR', 'getCurrentPosition acc=$acc', e);
      }
    }

    if (_coordsValid(v.latTaxista, v.lonTaxista)) {
      pts.add((lat: v.latTaxista, lon: v.lonTaxista));
    }
    if (_cachedViaje != null &&
        _coordsValid(_cachedViaje!.latTaxista, _cachedViaje!.lonTaxista)) {
      pts.add((lat: _cachedViaje!.latTaxista, lon: _cachedViaje!.lonTaxista));
    }

    if (pts.isEmpty) return null;

    double minM = double.infinity;
    for (final ({double lat, double lon}) p in pts) {
      final double d = Geolocator.distanceBetween(
        p.lat,
        p.lon,
        destino.lat,
        destino.lon,
      );
      if (d < minM) minM = d;
    }
    return minM;
  }

  /// Actualiza [_distanciaMetrosAlDestino] desde la posición en vivo (cola GPS).
  void _recalcDistanciaDestino() {
    final v = _cachedViaje;
    if (v == null || !mounted) return;
    final estadoBase = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
    );
    // Misma lógica que la ruta verde al destino: empieza a medir en cuanto el PIN
    // quedó verificado, aunque Firestore tarde un instante en pasar a `en_curso`.
    final bool rutaAlDestino = EstadosViaje.esEnCurso(estadoBase) ||
        (EstadosViaje.esAbordo(estadoBase) && v.codigoVerificado);
    if (!rutaAlDestino) {
      if (_distanciaMetrosAlDestino != null) {
        setState(() => _distanciaMetrosAlDestino = null);
      }
      if (_distanciaDestinoNotifier.value != null) {
        _distanciaDestinoNotifier.value = null;
      }
      return;
    }
    final dest = _esMultiparada(v) && !_multiparadaRutaCompleta(v)
        ? _coordsLegMultiActual(v)
        : _coordsDestinoParaFinalizar(v);
    if (dest == null) {
      if (_distanciaMetrosAlDestino != null) {
        setState(() => _distanciaMetrosAlDestino = null);
      }
      if (_distanciaDestinoNotifier.value != null) {
        _distanciaDestinoNotifier.value = null;
      }
      return;
    }
    // Ping en vivo del stream; si aún no hay fix, usar posición del doc (Firestore).
    (double, double)? ping = _taxistaPosCola.value;
    if (ping == null && _coordsValid(v.latTaxista, v.lonTaxista)) {
      ping = (v.latTaxista, v.lonTaxista);
    }
    if (ping == null &&
        _cachedViaje != null &&
        _coordsValid(_cachedViaje!.latTaxista, _cachedViaje!.lonTaxista)) {
      ping = (_cachedViaje!.latTaxista, _cachedViaje!.lonTaxista);
    }
    if (ping == null) {
      if (_distanciaMetrosAlDestino != null) {
        setState(() => _distanciaMetrosAlDestino = null);
      }
      if (_distanciaDestinoNotifier.value != null) {
        _distanciaDestinoNotifier.value = null;
      }
      return;
    }
    final d = Geolocator.distanceBetween(
      ping.$1,
      ping.$2,
      dest.lat,
      dest.lon,
    );
    final prev = _distanciaMetrosAlDestino;
    if (prev == null || (d - prev).abs() > 3) {
      setState(() => _distanciaMetrosAlDestino = d);
      _distanciaDestinoNotifier.value = d;
    }
  }

  Future<void> _sembrarViajeActivoDesdeServidor() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || _cachedViaje != null) return;
    try {
      final DocumentSnapshot<Map<String, dynamic>> us =
          await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(uid)
              .get(const GetOptions(source: Source.server));
      final String vid =
          (us.data()?['viajeActivoId'] ?? '').toString().trim();
      if (vid.isEmpty || !mounted) return;
      final DocumentSnapshot<Map<String, dynamic>> vs =
          await FirebaseFirestore.instance
              .collection('viajes')
              .doc(vid)
              .get(const GetOptions(source: Source.server));
      if (!vs.exists || !mounted) return;
      final Map<String, dynamic> d = vs.data() ?? <String, dynamic>{};
      if (!ViajesRepo.viajeVisibleEnCursoTaxista(d, uid)) return;
      setState(() {
        _cachedViaje = Viaje.fromMap(vs.id, d);
        _cargaViajeExpirada = false;
        _corporativoAunNoHoraMsg = null;
      });
      ActiveTripService.registrarViajeOperativoTaxista(vs.id);
      _syncEsperaCargaViaje(false);
    } catch (e) {
      debugPrint('[VIAJE_ACTIVO] sembrar viaje activo: $e');
    }
  }

  Future<void> _refrescarViajeDocDesdeFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      print('[VIAJE_ACTIVO] resume refresh skip (sin uid)');
      return;
    }
    String? vid = _cachedViaje?.id;
    if (vid == null || vid.isEmpty) {
      try {
        final us = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid)
            .get();
        vid = (us.data()?['viajeActivoId'] ?? '').toString().trim();
      } catch (_) {}
    }
    if (vid == null || vid.isEmpty) {
      print('[VIAJE_ACTIVO] resume refresh skip (sin viajeId)');
      return;
    }
    print('[VIAJE_ACTIVO] resume refresh GET viajes/$vid');
    try {
      final snap =
          await FirebaseFirestore.instance.collection('viajes').doc(vid).get();
      if (!snap.exists || !mounted) return;
      final fresh = Viaje.fromMap(snap.id, snap.data()!);
      setState(() {
        _cachedViaje = fresh.copyWith(
          latTaxista: _cachedViaje?.latTaxista ?? fresh.latTaxista,
          lonTaxista: _cachedViaje?.lonTaxista ?? fresh.lonTaxista,
        );
      });
      _aplicarProgresoMultiparadaDesdeViaje(fresh);
      _programarAutoFacturaMultiparadaSiCorresponde(fresh);
      _recalcDistanciaDestino();
      print(
          '[VIAJE_ACTIVO] resume refresh OK estado=${fresh.estado} completado=${fresh.completado}');
    } catch (e, st) {
      print('[VIAJE_ACTIVO] resume refresh error $e $st');
    }
  }

  static String _textoDistanciaAlPin(double metros) {
    if (metros < 1000) {
      return '${metros.round()} m';
    }
    return '${(metros / 1000).toStringAsFixed(1)} km';
  }

  /// Diálogo según proximidad: en zona → cierre para factura/pago; fuera/sin GPS → confirmación explícita.
  Future<bool?> _dialogoConfirmarFinalizarViaje(
    BuildContext context, {
    required bool hayPinDestino,
    double? distanciaMetrosMin,
  }) {
    late final String body;

    if (!hayPinDestino) {
      body =
          'No hay coordenadas de destino en este viaje. ¿Confirmás que ya terminó el servicio para emitir la factura al cliente?';
    } else if (distanciaMetrosMin == null) {
      body =
          'No pudimos contrastar tu ubicación con el mapa (GPS). Si ya están en el punto de bajada y el cliente va a pagar o hacer una transferencia, podés finalizar para que vea el monto en la factura.';
    } else if (distanciaMetrosMin <= kFinalizarRadioMetros) {
      body =
          'Tu posición está cerca del destino del viaje (cliente a bordo y en ruta). '
          'Al finalizar, el cliente verá la factura con el monto y podrá pagar o transferir. ¿Finalizamos?';
    } else {
      final String dTxt = _textoDistanciaAlPin(distanciaMetrosMin);
      body =
          'Tu posición aparece a unos $dTxt del punto de destino guardado en el viaje (referencia de GPS, no es una ruta que “te falte” recorrer). '
          'Si ya estás en el lugar de bajada y el pasajero va a pagar o transferir, podés finalizar igual para que salga la factura.';
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'Finalizar viaje',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          body,
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ahora no', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, finalizar'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _dialogoTarjetaPendienteAntesFinalizar(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'Tarjeta sin cobrar',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'AZUL no confirmó el cobro con tarjeta. Pedile al cliente que toque '
          '«Pagar en efectivo» en su app o que pague con otra tarjeta. '
          'Si lo dejás salir sin cobro verificado ni cambio a efectivo, '
          'vos NO cobrás este viaje.',
          style: TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Esperar pago', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalizar igual'),
          ),
        ],
      ),
    );
  }

  String _uidClienteDe(Viaje v) {
    final a = (v.clienteId).toString().trim();
    if (a.isNotEmpty) return a;
    final b = (v.uidCliente).toString().trim();
    return b;
  }

  String _labelVerOtro(Viaje v) =>
      _esViajeCorporativo(v) ? 'Ver encargado' : 'Ver cliente';

  String _labelContactar(Viaje v) =>
      _esViajeCorporativo(v) ? 'Chat encargado' : 'Contactar';

  void _asegurarChatCorporativo(Viaje v) {
    if (!_esViajeCorporativo(v)) return;
    if (_chatAseguradoParaViajeId == v.id) return;
    _chatAseguradoParaViajeId = v.id;
    unawaited(ViajesRepo.ensureChatDocForViaje(v.id));
  }

  void _verificarCercaniaCliente(double latTaxista, double lonTaxista,
      double latCliente, double lonCliente) {
    if (!_coordsValid(latTaxista, lonTaxista) ||
        !_coordsValid(latCliente, lonCliente)) {
      return;
    }

    final distancia =
        _calcularDistanciaKm(latTaxista, lonTaxista, latCliente, lonCliente);
    final bool ahoraCerca = distancia <= DISTANCIA_CERCANIA_KM;

    // Modo desarrollo: ignorar distancias muy pequeñas (mismo dispositivo)
    if (kDebugMode && distancia < kDebugMinDistance) {
      logDbg(
          '⚠️ Modo desarrollo: ignorando distancia muy pequeña (${(distancia * 1000).toStringAsFixed(0)}m)');
      return;
    }

    if (ahoraCerca != _clienteCerca && mounted && !_isUpdatingLocation) {
      _isUpdatingLocation = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _clienteCerca = ahoraCerca;
          });
          _isUpdatingLocation = false;

          if (ahoraCerca) {
            final bool corpLlegada = _cachedViaje != null &&
                CorporativoPasajerosChoferCard.esViajeCorporativo(
                    _cachedViaje!);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        corpLlegada
                            ? '🚕 ¡Llegaste a la empresa! Toca «Cliente a bordo».'
                            : '🚕 ¡Has llegado! El cliente está cerca. Toca «Cliente a bordo».',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 5),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          }
        } else {
          _isUpdatingLocation = false;
        }
      });
      logDbg(
          '🎯 Cambio de cercanía: $ahoraCerca, distancia: ${(distancia * 1000).toStringAsFixed(0)}m');
    }
  }

  double _calcularDistanciaKm(
      double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371.0;
    final double dLat = (lat2 - lat1) * pi / 180.0;
    final double dLon = (lon2 - lon1) * pi / 180.0;
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) *
            cos(lat2 * pi / 180.0) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  Future<void> _corpGpsCheckpoint(
    Viaje v,
    String tipo, {
    double? lat,
    double? lon,
    double? accuracy,
  }) async {
    if (!_esViajeCorporativo(v)) return;
    final ping = _taxistaPosCola.value;
    final la = lat ?? ping?.$1;
    final lo = lon ?? ping?.$2;
    if (la == null || lo == null) return;
    await CorporativoViajeGpsTracker.instance.recordCheckpoint(
      viajeId: v.id,
      tipo: tipo,
      lat: la,
      lon: lo,
      accuracy: accuracy,
    );
  }

  Future<void> _corpGpsOnEnCurso(Viaje v) async {
    if (!_esViajeCorporativo(v)) return;
    await CorporativoViajeGpsTracker.instance.start(v.id);
    await _corpGpsCheckpoint(v, 'inicio');
  }

  // ===== GPS control =====
  void _programarRecuperacionGpsStream(String viajeId, Object error) {
    logDbg('GPS stream error → recuperación programada: $error');
    unawaited(_gpsSub?.cancel());
    _gpsSub = null;
    _gpsActivo = false;

    if (!mounted) return;
    final Viaje? v = _cachedViaje;
    if (v == null || v.id != viajeId) return;

    final String est = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
    );
    final bool enRuta = EstadosViaje.esEnCurso(est) ||
        (EstadosViaje.esAbordo(est) && v.codigoVerificado);
    if (!enRuta) {
      _gpsStreamRecoveryIntentos = 0;
      return;
    }

    _gpsStreamRecoveryIntentos++;
    if (_gpsStreamRecoveryIntentos > _kMaxGpsStreamRecoveryIntentos) {
      logDbg(
          '🛑 GPS stream: máximo $_kMaxGpsStreamRecoveryIntentos reintentos alcanzado',
      );
      return;
    }

    _gpsStreamRecoveryTimer?.cancel();
    _gpsStreamRecoveryTimer = Timer(_kGpsStreamRecoveryDelay, () {
      _gpsStreamRecoveryTimer = null;
      if (!mounted) return;
      unawaited(() async {
        final bool ok = await _asegurarGps(viajeId);
        if (ok && mounted) {
          _gpsStreamRecoveryIntentos = 0;
        }
      }());
    });
  }

  Future<void> _startGpsFor(String viajeId) async {
    logDbg('_startGpsFor($viajeId)');
    if (_gpsParaViajeId == viajeId && _gpsSub != null) return;
    await _gpsSub?.cancel();
    _gpsParaViajeId = viajeId;

    final ref = FirebaseFirestore.instance.collection('viajes').doc(viajeId);
    final LocationSettings gpsSettings =
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            ? AndroidSettings(
                accuracy: LocationAccuracy.bestForNavigation,
                distanceFilter: 8,
                intervalDuration: const Duration(seconds: 2),
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.bestForNavigation,
                distanceFilter: 8,
              );
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: gpsSettings,
    ).listen(
      (p) async {
        try {
          _gpsStreamRecoveryTimer?.cancel();
          _gpsStreamRecoveryTimer = null;
          _gpsStreamRecoveryIntentos = 0;

          await ref.update({
            'latTaxista': p.latitude,
            'lonTaxista': p.longitude,
            'driverLat': p.latitude,
            'driverLon': p.longitude,
            'updatedAt': FieldValue.serverTimestamp(),
            'actualizadoEn': FieldValue.serverTimestamp(),
          });
          final String? uidTax = FirebaseAuth.instance.currentUser?.uid;
          if (uidTax != null) {
            unawaited(
              UbicacionTaxista.publicarPingDesdeViajeActivo(
                uid: uidTax,
                lat: p.latitude,
                lon: p.longitude,
                viajeId: viajeId,
                clienteId: _cachedViaje?.uidCliente,
                heading: p.heading.isFinite && p.heading >= 0
                    ? p.heading
                    : null,
              ),
            );
          }
          logDbg('📍 Ubicación enviada: ${p.latitude}, ${p.longitude}');
          _taxistaPosCola.value = (p.latitude, p.longitude);
          _sincronizarReferenciaOrdenCola(_cachedViaje);

          final Viaje? cv = _cachedViaje;
          if (cv != null &&
              cv.id == viajeId &&
              _esViajeCorporativo(cv) &&
              EstadosViaje.esEnCurso(EstadosViaje.normalizar(cv.estado))) {
            if (_gpsPrecisionAceptable(p.accuracy)) {
              _appendGpsTrailPoint(p.latitude, p.longitude);
              _syncGpsTrailEnMapa();
              unawaited(
                CorporativoViajeGpsTracker.instance.onPosition(
                  viajeId: viajeId,
                  lat: p.latitude,
                  lon: p.longitude,
                  accuracy: p.accuracy,
                ),
              );
            }
          }

          if (mounted && _cachedViaje != null && _cachedViaje!.id == viajeId) {
            _cachedViaje = _cachedViaje!
                .copyWith(latTaxista: p.latitude, lonTaxista: p.longitude);
          }
          _recalcDistanciaDestino();

          if (mounted &&
              _cachedViaje != null &&
              _coordsValid(_cachedViaje!.latCliente, _cachedViaje!.lonCliente)) {
            _verificarCercaniaCliente(p.latitude, p.longitude,
                _cachedViaje!.latCliente, _cachedViaje!.lonCliente);
            _scheduleDrawRoute();
          }
        } catch (e) {
          logDbg('Error actualizando Firestore: $e');
        }
      },
      onError: (Object e) => _programarRecuperacionGpsStream(viajeId, e),
      cancelOnError: false,
    );
  }

  void _stopGps() {
    _gpsStreamRecoveryTimer?.cancel();
    _gpsStreamRecoveryTimer = null;
    _gpsStreamRecoveryIntentos = 0;
    _gpsSub?.cancel();
    _gpsSub = null;
    _gpsActivo = false;
    _gpsParaViajeId = null;
    unawaited(CorporativoViajeGpsTracker.instance.stop());
    logDbg('🛑 GPS detenido');
  }

  Future<bool> _asegurarGps(
    String viajeId, {
    bool allowPermissionDialog = true,
  }) async {
    if (kIsWeb) {
      // Laptop/web: no spamear diálogo del navegador; el mapa usa posición del doc del viaje.
      allowPermissionDialog = false;
    }
    logDbg(
      '_asegurarGps($viajeId) allowPermissionDialog=$allowPermissionDialog '
      '_gpsActivo: $_gpsActivo',
    );

    if (_gpsActivo && _gpsParaViajeId == viajeId) {
      logDbg('✅ GPS ya activo');
      return true;
    }

    final ({bool serviceEnabled, LocationPermission permission}) snap =
        // Explícito: solo cuando el taxista inicia GPS del viaje con diálogo permitido.
        // resumed / reanudación usa allowPermissionDialog:false → readNoRequest.
        allowPermissionDialog
            ? await GpsService.checkServiceThenRequestPermissionIfNeeded()
            : await GpsService.readServiceAndPermissionStabilizedNoRequest();
    if (!snap.serviceEnabled) {
      if (!mounted) return false;
      if (!kIsWeb) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Activa la ubicación del teléfono (GPS).'),
                action: SnackBarAction(
                  label: 'Ubicación',
                  onPressed: () => unawaited(GpsService.openLocationSettings()),
                ),
              ),
            );
          }
        });
      }
      logDbg('❌ GPS apagado');
      return false;
    }

    final LocationPermission perm = snap.permission;
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (!mounted) return false;
      if (!kIsWeb) {
        if (allowPermissionDialog) {
          await _ubicacionTaxistaSvc.activarUbicacionDesdeApp(context: context);
          final ({bool serviceEnabled, LocationPermission permission}) snap2 =
              await GpsService.readServiceAndPermissionStabilizedNoRequest();
          if (snap2.serviceEnabled &&
              GpsService.permissionUsable(snap2.permission)) {
            await _startGpsFor(viajeId);
            _gpsActivo = true;
            final Viaje? cv = _cachedViaje;
            if (cv != null &&
                cv.id == viajeId &&
                _esViajeCorporativo(cv) &&
                EstadosViaje.esEnCurso(
                    EstadosViaje.normalizar(cv.estado))) {
              unawaited(CorporativoViajeGpsTracker.instance.start(viajeId));
              unawaited(
                  CorporativoViajeGpsTracker.instance.flushPending(viajeId));
            }
            logDbg('✅ GPS activado tras permiso desde viaje en curso');
            return true;
          }
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    'Activa la ubicación para registrar la ruta del viaje.',
                  ),
                  action: SnackBarAction(
                    label: 'Activar',
                    onPressed: () => unawaited(
                      _ubicacionTaxistaSvc.activarUbicacionDesdeApp(
                        context: context,
                      ),
                    ),
                  ),
                ),
              );
            }
          });
        }
      }
      logDbg('❌ Permiso denegado');
      return false;
    }

    if (kIsWeb) {
      // En web el stream GPS del navegador no es fiable; no reescribir Firestore en bucle.
      logDbg('web: viaje $viajeId sin stream GPS local (mapa usa doc del viaje)');
      return false;
    }

    await _startGpsFor(viajeId);
    _gpsActivo = true;
    final Viaje? cv = _cachedViaje;
    if (cv != null &&
        cv.id == viajeId &&
        _esViajeCorporativo(cv) &&
        EstadosViaje.esEnCurso(EstadosViaje.normalizar(cv.estado))) {
      unawaited(CorporativoViajeGpsTracker.instance.start(viajeId));
      unawaited(CorporativoViajeGpsTracker.instance.flushPending(viajeId));
    }
    logDbg('✅ GPS activado correctamente');
    return true;
  }

  // ===== RUTAS =====
  bool _gpsPrecisionAceptable(double? accuracy) {
    if (accuracy == null || !accuracy.isFinite) return true;
    return accuracy <= _kGpsAccuracyMaxMetros;
  }

  void _appendGpsTrailPoint(double lat, double lon) {
    if (!_coordsValid(lat, lon)) return;
    final pt = LatLng(lat, lon);
    if (_gpsTrailPoints.isNotEmpty) {
      final last = _gpsTrailPoints.last;
      if ((last.latitude - lat).abs() < 0.00003 &&
          (last.longitude - lon).abs() < 0.00003) {
        return;
      }
    }
    _gpsTrailPoints.add(pt);
    while (_gpsTrailPoints.length > _kMaxGpsTrailPoints) {
      _gpsTrailPoints.removeAt(0);
    }
  }

  void _aplicarPolilineaRecorridoGps(Set<Polyline> target) {
    target.removeWhere((p) => p.polylineId.value == 'gps_recorrido');
    if (_gpsTrailPoints.length < 2) return;
    target.add(
      Polyline(
        polylineId: const PolylineId('gps_recorrido'),
        points: List<LatLng>.from(_gpsTrailPoints),
        width: 7,
        color: const Color(0xFF2DD4BF),
        geodesic: true,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        zIndex: 3,
      ),
    );
  }

  void _syncGpsTrailEnMapa() {
    if (!mounted) return;
    final next = Set<Polyline>.from(_polylines);
    _aplicarPolilineaRecorridoGps(next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _polylines
          ..clear()
          ..addAll(next);
      });
    });
  }

  void _scheduleDrawRoute() {
    _routeDebounce?.cancel();
    _routeDebounce =
        Timer(const Duration(milliseconds: 500), () => _drawRoutes());
  }

  Future<void> _drawRoutes() async {
    if (!mounted || _cachedViaje == null) return;

    final gen = ++_drawRoutesGeneration;
    final v = _cachedViaje!;

    final estadoBase = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
    );

    final nextPolylines = <Polyline>{};
    Set<Marker> nextCorpMarkers = <Marker>{};

    final bool corp = CorporativoPasajerosChoferCard.esViajeCorporativo(v);
    final bool rutaAlDestino = EstadosViaje.esEnCurso(estadoBase) ||
        (EstadosViaje.esAbordo(estadoBase) && v.codigoVerificado);
    final bool fasePickup = !rutaAlDestino &&
        (EstadosViaje.esAceptado(estadoBase) ||
            EstadosViaje.esEnCaminoPickup(estadoBase) ||
            _corpEnFasePickup(v, estadoBase));

    if (fasePickup &&
        _coordsValid(v.latTaxista, v.lonTaxista) &&
        _coordsValid(v.latCliente, v.lonCliente)) {
      await _drawRoute(
        nextPolylines,
        LatLng(v.latTaxista, v.lonTaxista),
        LatLng(v.latCliente, v.lonCliente),
        id: 'to_cliente',
        color: const Color(0xFF0A0A0A),
        width: 18,
        estiloCintaNegra: true,
      );
      if (gen != _drawRoutesGeneration || !mounted) return;
    }

    if (corp) {
      nextCorpMarkers = await _buildCorpParadaMarkers(v);
    } else {
      nextCorpMarkers = _buildTripPointMarkers(v);
    }
    if (gen != _drawRoutesGeneration || !mounted) return;

    if (corp && rutaAlDestino) {
      final legs = _destinosOrdenadosParaMapa(v);
      if (legs.isNotEmpty && _coordsValid(v.latCliente, v.lonCliente)) {
        final ultimo = legs.last;
        final vias = <({double lat, double lon})>[];
        for (var i = 0; i < legs.length - 1; i++) {
          vias.add((lat: legs[i].lat, lon: legs[i].lon));
        }
        await _drawRoute(
          nextPolylines,
          LatLng(v.latCliente, v.lonCliente),
          LatLng(ultimo.lat, ultimo.lon),
          id: 'corp_ruta',
          color: const Color(0xFF0A0A0A),
          width: 18,
          viaIntermediate: vias.isEmpty ? null : vias,
          estiloCintaNegra: true,
        );
      } else if (_coordsValid(v.latCliente, v.lonCliente) &&
          _coordsValid(v.latDestino, v.lonDestino)) {
        await _drawRoute(
          nextPolylines,
          LatLng(v.latCliente, v.lonCliente),
          LatLng(v.latDestino, v.lonDestino),
          id: 'corp_ruta',
          color: const Color(0xFF0A0A0A),
          width: 18,
          estiloCintaNegra: true,
        );
      }
      if (gen != _drawRoutesGeneration || !mounted) return;
    } else if (!corp && rutaAlDestino) {
      if (_esMultiparada(v) && !_multiparadaRutaCompleta(v)) {
        final leg = _destinoMultiActual(v);
        final origen = _origenRutaEnCursoTaxista(v);
        if (leg != null &&
            origen != null &&
            _coordsValid(leg.lat, leg.lon)) {
          await _drawRoute(
            nextPolylines,
            LatLng(origen.lat, origen.lon),
            LatLng(leg.lat, leg.lon),
            id: 'to_leg_actual',
            color: const Color(0xFF0A0A0A),
            width: 18,
            estiloCintaNegra: true,
          );
        }
      } else if (_coordsValid(v.latCliente, v.lonCliente) &&
          _coordsValid(v.latDestino, v.lonDestino)) {
        List<({double lat, double lon})>? vias;
        if (_esMultiparada(v)) {
          vias = <({double lat, double lon})>[];
          for (final leg in _legsNavegacionMultiparada(v)) {
            if (!leg.esFinal) {
              vias.add((lat: leg.lat, lon: leg.lon));
            }
          }
          if (vias.isEmpty) vias = null;
        }
        final origen = _origenRutaEnCursoTaxista(v) ??
            (lat: v.latCliente, lon: v.lonCliente);
        await _drawRoute(
          nextPolylines,
          LatLng(origen.lat, origen.lon),
          LatLng(v.latDestino, v.lonDestino),
          id: 'to_destino',
          color: const Color(0xFF0A0A0A),
          width: 18,
          viaIntermediate: vias,
          estiloCintaNegra: true,
        );
      }
      if (gen != _drawRoutesGeneration || !mounted) return;
    }

    _aplicarPolilineaRecorridoGps(nextPolylines);

    if (gen != _drawRoutesGeneration || !mounted) return;

    final polylinesCopy = Set<Polyline>.from(nextPolylines);
    final markersCopy = Set<Marker>.from(nextCorpMarkers);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _drawRoutesGeneration) return;
      setState(() {
        _polylines
          ..clear()
          ..addAll(polylinesCopy);
        _corpMapMarkers = markersCopy;
      });
    });
  }

  Set<Marker> _buildTripPointMarkers(Viaje v) {
    final out = <Marker>{};
    if (_coordsValid(v.latCliente, v.lonCliente)) {
      out.add(
        Marker(
          markerId: const MarkerId('trip_origen'),
          position: LatLng(v.latCliente, v.lonCliente),
          infoWindow: InfoWindow(
            title: 'ORIGEN · Recoger',
            snippet: v.origen.trim().isEmpty ? 'Punto de recogida' : v.origen,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          zIndexInt: 5,
        ),
      );
    }
    final legs = _legsNavegacionMultiparada(v);
    if (legs.isEmpty) {
      if (_coordsValid(v.latDestino, v.lonDestino)) {
        out.add(
          Marker(
            markerId: const MarkerId('trip_destino'),
            position: LatLng(v.latDestino, v.lonDestino),
            infoWindow: InfoWindow(
              title: 'DESTINO',
              snippet:
                  v.destino.trim().isEmpty ? 'Punto de llegada' : v.destino,
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen),
            zIndexInt: 6,
          ),
        );
      }
      return out;
    }
    for (var i = 0; i < legs.length; i++) {
      final leg = legs[i];
      if (!_coordsValid(leg.lat, leg.lon)) continue;
      final n = i + 1;
      final esFinal = leg.esFinal;
      out.add(
        Marker(
          markerId: MarkerId('trip_parada_$n'),
          position: LatLng(leg.lat, leg.lon),
          infoWindow: InfoWindow(
            title: esFinal ? 'DESTINO $n' : 'PARADA $n',
            snippet: leg.label,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            esFinal ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueOrange,
          ),
          zIndexInt: esFinal ? 6 : 4,
        ),
      );
    }
    return out;
  }

  /// Pins rojos grandes por pasajero (mapa RAI del chofer, solo corporativo).
  Future<Set<Marker>> _buildCorpParadaMarkers(Viaje v) async {
    final out = <Marker>{};
    if (_coordsValid(v.latCliente, v.lonCliente)) {
      out.add(
        Marker(
          markerId: const MarkerId('corp_origen'),
          position: LatLng(v.latCliente, v.lonCliente),
          infoWindow: InfoWindow(
            title: 'EMPRESA · Recoger',
            snippet: v.origen.trim().isEmpty ? 'Punto de recogida' : v.origen,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          zIndexInt: 5,
        ),
      );
    }
    final legs = _destinosOrdenadosParaMapa(v);
    for (var i = 0; i < legs.length; i++) {
      final leg = legs[i];
      if (!_coordsValid(leg.lat, leg.lon)) continue;
      final n = i + 1;
      final icon = await _iconoParadaRojaGrande(n);
      out.add(
        Marker(
          markerId: MarkerId('corp_parada_$n'),
          position: LatLng(leg.lat, leg.lon),
          infoWindow: InfoWindow(
            title: leg.esFinal ? 'DESTINO $n' : 'PARADA $n',
            snippet: leg.label,
          ),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: leg.esFinal ? 8 : 7,
        ),
      );
    }
    return out;
  }

  /// Mientras cargan los iconos grandes, pins rojos estándar con cada pasajero.
  Set<Marker> _buildCorpParadaMarkersSync(Viaje v) {
    final out = <Marker>{};
    if (_coordsValid(v.latCliente, v.lonCliente)) {
      out.add(
        Marker(
          markerId: const MarkerId('corp_origen'),
          position: LatLng(v.latCliente, v.lonCliente),
          infoWindow: InfoWindow(
            title: 'EMPRESA · Recoger',
            snippet: v.origen.trim().isEmpty ? 'Punto de recogida' : v.origen,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          zIndexInt: 5,
        ),
      );
    }
    final legs = _destinosOrdenadosParaMapa(v);
    for (var i = 0; i < legs.length; i++) {
      final leg = legs[i];
      if (!_coordsValid(leg.lat, leg.lon)) continue;
      final n = i + 1;
      out.add(
        Marker(
          markerId: MarkerId('corp_parada_$n'),
          position: LatLng(leg.lat, leg.lon),
          infoWindow: InfoWindow(
            title: leg.esFinal ? 'DESTINO $n' : 'PARADA $n',
            snippet: leg.label,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          zIndexInt: leg.esFinal ? 8 : 7,
        ),
      );
    }
    return out;
  }

  Future<BitmapDescriptor> _iconoParadaRojaGrande(int numero) async {
    final key = 'r$numero';
    final cached = _corpPinIconCache[key];
    if (cached != null) return cached;

    const double size = 64;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    const double outerR = 28;
    const double innerR = 22;

    canvas.drawCircle(center, outerR, Paint()..color = Colors.white);
    canvas.drawCircle(center, innerR, Paint()..color = const Color(0xFFD32F2F));

    final tp = TextPainter(
      text: TextSpan(
        text: '$numero',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: painting.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));

    final img =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    final icon = BitmapDescriptor.bytes(bd!.buffer.asUint8List());
    _corpPinIconCache[key] = icon;
    return icon;
  }

  bool _polylinesEquals(Set<Polyline> a, Set<Polyline> b) {
    if (a.length != b.length) return false;
    int puntos(Set<Polyline> s) =>
        s.fold<int>(0, (n, p) => n + p.points.length);
    if (puntos(a) != puntos(b)) return false;
    final aIds = a.map((p) => p.polylineId.value).toSet();
    final bIds = b.map((p) => p.polylineId.value).toSet();
    return aIds.containsAll(bIds) && bIds.containsAll(aIds);
  }

  Future<void> _drawRoute(
    Set<Polyline> out,
    LatLng a,
    LatLng b, {
    required String id,
    required Color color,
    int width = 5,
    List<({double lat, double lon})>? viaIntermediate,
    bool estiloCintaNegra = false,
  }) async {
    try {
      final result = await DirectionsService.drivingDistanceKm(
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

      List<LatLng> points = [];
      if (result != null && result.path != null && result.path!.isNotEmpty) {
        points = result.path!;
      }
      final pts = points.isNotEmpty ? points : [a, b];

      if (estiloCintaNegra) {
        out.add(
          Polyline(
            polylineId: PolylineId('${id}_glow'),
            points: pts,
            width: 32,
            color: const Color(0xB3000000),
            geodesic: true,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        );
        out.add(
          Polyline(
            polylineId: PolylineId(id),
            points: pts,
            width: 18,
            color: const Color(0xFF0A0A0A),
            geodesic: true,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        );
      } else {
        out.add(
          Polyline(
            polylineId: PolylineId('${id}_glow'),
            points: pts,
            width: 32,
            color: const Color(0xB3000000),
            geodesic: true,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        );
        out.add(
          Polyline(
            polylineId: PolylineId(id),
            points: pts,
            width: 18,
            color: const Color(0xFF0A0A0A),
            geodesic: true,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        );
      }
    } catch (e) {
      final pts = [a, b];
      out.add(
        Polyline(
          polylineId: PolylineId('${id}_glow'),
          points: pts,
          width: 32,
          color: const Color(0xB3000000),
          geodesic: true,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
      out.add(
        Polyline(
          polylineId: PolylineId(id),
          points: pts,
          width: 18,
          color: const Color(0xFF0A0A0A),
          geodesic: true,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    }
  }

  static String _prefKeyNavPickup(String viajeId) => 'vctx_nav_pickup_$viajeId';

  static String _prefKeyNavDestino(String viajeId) => 'vctx_nav_destino_$viajeId';

  Future<void> _persistNavPickupFlag(String viajeId, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (value) {
        await p.setBool(_prefKeyNavPickup(viajeId), true);
      } else {
        await p.remove(_prefKeyNavPickup(viajeId));
      }
    } catch (e, st) {
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: persist nav pickup',
      );
    }
  }

  Future<void> _persistNavDestinoFlag(String viajeId, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (value) {
        await p.setBool(_prefKeyNavDestino(viajeId), true);
      } else {
        await p.remove(_prefKeyNavDestino(viajeId));
      }
    } catch (e, st) {
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: persist nav destino',
      );
    }
  }

  Future<void> _loadNavDestinoPrefs(Viaje v, {bool force = false}) async {
    final estadoBase = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado
                  ? EstadosViaje.aceptado
                  : EstadosViaje.pendiente)),
    );
    if (!EstadosViaje.esEnCurso(estadoBase)) {
      _navDestinoPrefsLoadedForId = null;
      if (mounted && _navegacionDestinoIniciada) {
        setState(() => _navegacionDestinoIniciada = false);
      }
      try {
        final p = await SharedPreferences.getInstance();
        if (p.containsKey(_prefKeyNavDestino(v.id))) {
          await p.remove(_prefKeyNavDestino(v.id));
        }
      } catch (_) {}
      return;
    }
    if (!force && _navDestinoPrefsLoadedForId == v.id) return;

    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getBool(_prefKeyNavDestino(v.id)) ?? false;
      _navDestinoPrefsLoadedForId = v.id;
      if (mounted && saved && !_navegacionDestinoIniciada) {
        setState(() => _navegacionDestinoIniciada = true);
      }
    } catch (e, st) {
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: load nav destino prefs',
      );
    }
  }

  void _marcarNavegacionDestinoLista(Viaje v) {
    unawaited(_persistNavDestinoFlag(v.id, true));
    if (mounted) setState(() => _navegacionDestinoIniciada = true);
  }

  /// Tras volver de Waze/Maps o del sistema: restauramos «navegación iniciada» para no bloquear «Cliente a bordo».
  Future<void> _loadNavPickupPrefs(Viaje v, {bool force = false}) async {
    final estadoBase = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado
                  ? EstadosViaje.aceptado
                  : EstadosViaje.pendiente)),
    );
    if (!EstadosViaje.esAceptado(estadoBase)) {
      _navPickupPrefsLoadedForId = null;
      try {
        final p = await SharedPreferences.getInstance();
        if (p.containsKey(_prefKeyNavPickup(v.id))) {
          await p.remove(_prefKeyNavPickup(v.id));
        }
      } catch (e, st) {
        await ErrorReporting.reportError(
          e,
          stack: st,
          context: 'viaje_en_curso_taxista: clear stale nav pickup pref',
        );
      }
      return;
    }
    if (!force && _navPickupPrefsLoadedForId == v.id) return;

    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getBool(_prefKeyNavPickup(v.id)) ?? false;
      _navPickupPrefsLoadedForId = v.id;
      if (mounted && saved) {
        setState(() => _navegacionIniciada = true);
      }
    } catch (e, st) {
      await ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: load nav pickup prefs',
      );
    }
  }

  Future<void> _handleAppResumedTrasNavegacionExterna() async {
    if (!mounted) return;
    final v = _cachedViaje;
    if (v == null) return;
    await _loadNavPickupPrefs(v, force: true);
    await _loadNavDestinoPrefs(v, force: true);
    if (!mounted) return;

    final estadoBase = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado
                  ? EstadosViaje.aceptado
                  : EstadosViaje.pendiente)),
    );
    final bool enPickup = EstadosViaje.esAceptado(estadoBase);
    final bool enRutaDestino = EstadosViaje.esEnCurso(estadoBase);
    if (!enPickup && !enRutaDestino) return;

    final now = DateTime.now();
    if (_lastNavResumeSnackAt != null &&
        now.difference(_lastNavResumeSnackAt!) < const Duration(seconds: 6)) {
      return;
    }

    _lastNavResumeSnackAt = now;
    if (!_viajeSheetOcultoPorModalNav && !_selectorNavegacionAbierto) {
      _expandirViajeSheetTrasMapa();
    }

    if (enPickup) {
      if (!_navegacionIniciada) return;
      _tripFlowSnack(
        _permiteAtajoPruebaCorp(v)
            ? 'Volviste a RAI Driver. Tocá «Cliente a bordo (paso 2)».'
            : (_permitePruebaSinRecorrido(v)
                ? 'Volviste a RAI Driver. Siguiente: «Cliente a bordo (paso 2)».'
                : 'Volviste a RAI Driver. Continúa: Cliente a bordo → código → destino.'),
        backgroundColor: Colors.blueGrey.shade800,
      );
      return;
    }

    // Multiparada: cada parada abre Waze por separado (no marca _navegacionDestinoIniciada).
    if (_esMultiparada(v) &&
        !v.completado &&
        EstadosViaje.esEnCurso(estadoBase)) {
      await _autoConfirmarLegMultiparadaPendienteTrasResume(v);
      if (!mounted) return;
      final Viaje? trasConfirm = _cachedViaje ?? v;
      if (trasConfirm != null &&
          _multiparadaRutaCompleta(trasConfirm) &&
          !trasConfirm.completado) {
        _programarAutoFacturaMultiparadaSiCorresponde(trasConfirm);
        return;
      }
      final int totalMulti = _legsNavegacionMultiparada(v).length;
      final bool hayNavMulti = _multiLegNavAbiertaIndices.isNotEmpty ||
          multiparadaLegsAbiertosDesdeViaje(v, totalLegs: totalMulti).isNotEmpty;
      if (hayNavMulti) {
        _tripFlowSnack(
          'Volviste a RAI Driver. Confirmá la parada con ✓ para seguir.',
          backgroundColor: const Color(0xFF2E7D32),
        );
        return;
      }
    }

    if (!_navegacionDestinoIniciada && _permitePruebaSinRecorrido(v)) {
      _tripFlowSnack(
        'Volviste a RAI Driver. Abrí «Navegar al destino» o tocá «Continuar sin mapa».',
        backgroundColor: Colors.blueGrey.shade800,
      );
      return;
    }

    if (!_navegacionDestinoIniciada) {
      _tripFlowSnack(
        'Volviste a RAI Driver. Abrí «Navegar al destino» y al llegar finalizá el viaje.',
        backgroundColor: Colors.blueGrey.shade800,
      );
      return;
    }

    _tripFlowSnack(
      'Volviste a RAI Driver. Siguiente paso: «Finalizar viaje».',
      backgroundColor: const Color(0xFF2E7D32),
    );
  }

  /// Mapa: montar tras el 1.er frame. Si Google/OSM tira, UI sin mapa.
  bool _mapaPermitido = false;
  bool _mapaDesactivadoPorError = false;
  final ValueNotifier<int> _cargaViajeSegundosN = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ActiveTripService.markTaxistaTripScreenMounted();
    unawaited(_ubicacionTaxistaSvc.ensureStarted());
    _ubicacionTaxistaSvc.modo.addListener(_onUbicacionTaxistaModoChanged);
    _initViajeEnCursoStream();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_sembrarViajeActivoDesdeServidor());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ViajeSinMapaScope.of(context) || _mapaDesactivadoPorError) {
        setState(() {
          _mapaDesactivadoPorError = true;
          _mapaPermitido = false;
        });
      } else {
        setState(() => _mapaPermitido = true);
      }
      unawaited(_verificarViajeTerminadoAlEntrarTaxista());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_limpiarCorpDeViajeEnCursoAlEntrar());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        unawaited(ViajesRepo.ensureSiguienteCoherente(uid));
      }
    });
    _scheduleSyncEsperaCargaViaje(true);
  }

  void _onUbicacionTaxistaModoChanged() {
    if (!mounted) return;
    if (_ubicacionTaxistaSvc.modo.value == RaiUbicacionTaxistaModo.listo) {
      final Viaje? v = _cachedViaje;
      if (v != null && !_gpsActivo) {
        unawaited(_asegurarGps(v.id, allowPermissionDialog: false));
      }
    }
    setState(() {});
  }

  bool get _mostrarAlertaUbicacionEnViaje =>
      !kIsWeb &&
      (_ubicacionTaxistaSvc.bannerActivo || !_gpsActivo);

  Widget _buildAlertaUbicacionViaje({bool mapFloating = false}) {
    if (!_mostrarAlertaUbicacionEnViaje) {
      return const SizedBox.shrink();
    }
    return RaiUbicacionMapAlert(
      rol: RaiUbicacionRol.taxista,
      mapFloating: mapFloating,
      enViajeEnCurso: true,
      obteniendoGps: _ubicacionTaxistaSvc.ubicacionLista && !_gpsActivo,
    );
  }

  Widget _buildUbicacionEnSheetViaje() {
    if (!_mostrarAlertaUbicacionEnViaje) {
      return const SizedBox.shrink();
    }
    return RaiUbicacionMapAlert(
      rol: RaiUbicacionRol.taxista,
      enViajeEnCurso: true,
      mapFloating: true,
      obteniendoGps: _ubicacionTaxistaSvc.ubicacionLista && !_gpsActivo,
    );
  }

  Widget _viajeSheetHandle() {
    return _wrapTaxistaSheetHandleDrag(
      child: Column(
        children: [
          const SizedBox(height: 6),
          Center(
            child: Container(
              width: 72,
              height: 36,
              alignment: Alignment.center,
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: RaiDsColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Desliza hacia arriba o abajo',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _wrapTaxistaSheetHandleDrag({required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (DragUpdateDetails details) {
        if (!_viajeSheetCtrl.isAttached) return;
        final double h = MediaQuery.sizeOf(context).height;
        if (h <= 0) return;
        final double next = (_viajeSheetCtrl.size - details.delta.dy / h)
            .clamp(_kViajeSheetMin, 1.0);
        _viajeSheetCtrl.jumpTo(next);
      },
      child: child,
    );
  }

  Widget _buildViajeDraggableSheet({
    required BuildContext context,
    required Viaje viaje,
    required String estadoBase,
    required bool esCorpMapa,
    required bool mostrarPinCorp,
    required String? uid,
  }) {
    final bool compactoPickup =
        _esPickupClienteSheetCompacto(viaje, estadoBase);
    final double sheetInitial = compactoPickup
        ? _kViajeSheetPickupCompact
        : _kViajeSheetInitial;
    final List<double> snapSizes = compactoPickup
        ? <double>[
            _kViajeSheetMin,
            _kViajeSheetPickupCompact,
            0.52,
            1.0,
          ]
        : const <double>[
            _kViajeSheetMin,
            _kViajeSheetInitial,
            _kViajeSheetPin,
            1.0,
          ];
    final String uidCli = _uidClienteDe(viaje);

    return DraggableScrollableSheet(
      key: ValueKey<String>('viaje-sheet-${viaje.id}'),
      controller: _viajeSheetCtrl,
      expand: true,
      minChildSize: _kViajeSheetMin,
      maxChildSize: 1.0,
      initialChildSize: sheetInitial,
      snap: true,
      snapAnimationDuration: const Duration(milliseconds: 220),
      snapSizes: snapSizes,
      builder: (sheetCtx, scrollController) {
        _viajeSheetScrollCtrl = scrollController;
        final double bottomInset = MediaQuery.viewPaddingOf(sheetCtx).bottom;
        final double keyboardInset = MediaQuery.viewInsetsOf(sheetCtx).bottom;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: RaiViajeEnCursoUi.sheetBg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(RaiViajeEnCursoUi.sheetRadius),
            ),
            border: const Border(
              top: BorderSide(color: RaiViajeEnCursoUi.sheetBorder),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              4,
              16,
              12 + bottomInset + keyboardInset,
            ),
            children: [
              _viajeSheetHandle(),
              if (compactoPickup) ...<Widget>[
                TaxistaPickupClientePanel(
                  viaje: viaje,
                  navegacionIniciada: _navegacionIniciada,
                  clienteCerca: _clienteCerca,
                  onVerCliente: uidCli.isEmpty
                      ? null
                      : () => _verInfoCliente(uidCliente: uidCli),
                  onContactar: uidCli.isEmpty
                      ? null
                      : () => _contactarCliente(
                            uidCliente: uidCli,
                            viajeId: viaje.id,
                            viaje: viaje,
                          ),
                ),
              ] else ...<Widget>[
                _buildViajeSheetResumenMinimo(viaje, estadoBase),
                if (!esCorpMapa && !mostrarPinCorp) ...<Widget>[
                  const SizedBox(height: 10),
                  ViajeFlujoProfesionalTaxistaHeader(
                    viajeId: viaje.id,
                    estadoBase: estadoBase,
                    metodoPagoFallback: viaje.metodoPago,
                    codigoVerificado: viaje.codigoVerificado,
                    montoFallback: viaje.precio,
                    codigoEsperado: viaje.codigoVerificacion,
                  ),
                ],
              ],
              const SizedBox(height: 10),
              if (!esCorpMapa) ...[
                _buildUbicacionEnSheetViaje(),
                if (_mostrarAlertaUbicacionEnViaje) const SizedBox(height: 10),
              ],
              if (esCorpMapa && !mostrarPinCorp) ...[
                CorporativoPasajerosChoferCard(
                  key: ValueKey<String>(
                    'corp-acc-${viaje.id}-${_firmaPasajerosCorpTaxista(viaje)}',
                  ),
                  viaje: viaje,
                  estilo: CorporativoCardEstilo.acciones,
                  navegacionPickupHabilitada:
                      _corpMostrarNavPickup(viaje, estadoBase),
                  navegacionDestinoHabilitada:
                      _corpMostrarNavDestino(viaje, estadoBase),
                  onChatTap: viaje.uidCliente.isNotEmpty
                      ? () => _contactarCliente(
                            uidCliente: viaje.uidCliente,
                            viajeId: viaje.id,
                            viaje: viaje,
                          )
                      : null,
                  onNavegacionExternaTap: () =>
                      _onNavegacionExternaDesdeCardCorp(viaje),
                  onWazeTap: _corpMostrarNavDestino(viaje, estadoBase)
                      ? () => _corpAbrirNavegacionDestinoActual(viaje)
                      : null,
                ),
                const SizedBox(height: 10),
              ],
              if (mostrarPinCorp)
                _buildCorporativoPinIngresoPanel(viaje)
              else
                _actionBar(viaje, estadoBase),
              if (esCorpMapa && !mostrarPinCorp) ...[
                const SizedBox(height: 10),
                CorporativoPasajerosChoferCard(
                  key: ValueKey<String>(
                    'corp-lista-${viaje.id}-${_firmaPasajerosCorpTaxista(viaje)}',
                  ),
                  viaje: viaje,
                  estilo: CorporativoCardEstilo.lista,
                ),
                if (viaje.codigoVerificado &&
                    EstadosViaje.esEnCurso(estadoBase)) ...[
                  CorporativoAbordajeChoferPanel(
                    key: ValueKey<String>(
                      'corp-abord-${viaje.id}-${_firmaPasajerosCorpTaxista(viaje)}',
                    ),
                    viaje: viaje,
                  ),
                ],
              ],
              if (!mostrarPinCorp && !esCorpMapa &&
                  !compactoPickup &&
                  _chatViajeHabilitadoParaTaxista(viaje, estadoBase) &&
                  uid != null) ...[
                const SizedBox(height: 10),
                ViajeChatMensajesEnVivo(
                  viajeId: viaje.id,
                  miUid: uid,
                  otroUid: viaje.uidCliente,
                  otroNombre: 'Cliente',
                  esCorporativo: false,
                ),
              ],
              if (!mostrarPinCorp && !compactoPickup) ...[
                _viajeSheetDivider(),
                ViajesCercanosTaxistaSheetButton(
                  controller: _viajesCercanosCtl,
                  escuchaActiva: _viajesCercanosEscucha,
                  referenciaOrdenCola: _colaReferenciaOrden,
                ),
                const SizedBox(height: 10),
                if (uid != null)
                  ColaSiguienteViajeBannerTaxista(
                    uidTaxista: uid,
                    referenciaOrden: _colaReferenciaOrden,
                  ),
                if (uid != null) const SizedBox(height: 12),
                _buildDetallesViajePanel(viaje, estadoBase),
                const SizedBox(height: 12),
                _tarjetaVehiculoVisibleAlCliente(viaje),
              ],
              if (!mostrarPinCorp && compactoPickup) ...[
                const SizedBox(height: 10),
                Text(
                  'Deslizá hacia arriba para ver más detalles del viaje.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.42),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildViajeSheetResumenMinimo(Viaje v, String estadoBase) {
    final bool corp = CorporativoPasajerosChoferCard.esViajeCorporativo(v);
    final String? empresa = CorporativoPasajerosChoferCard.empresaNombreDe(v);
    String estadoLabel = _labelEstado(estadoBase, viaje: v);
    if (corp && v.codigoVerificado && !EstadosViaje.esEnCurso(estadoBase)) {
      estadoLabel = 'Código OK · listo para ruta';
    }
    final String titulo = corp
        ? '${empresa ?? 'Ruta corporativa'} · $estadoLabel'
        : '${v.origen} → $estadoLabel';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        titulo,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Future<void> _verificarViajeTerminadoAlEntrarTaxista() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !mounted) return;
    print('[VIAJE_ACTIVO] taxista pantalla init: verificar si viaje ya cerró');
    try {
      final us = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();
      final vid = (us.data()?['viajeActivoId'] ?? '').toString().trim();
      if (vid.isEmpty) return;
      final vs =
          await FirebaseFirestore.instance.collection('viajes').doc(vid).get();
      if (!vs.exists || !mounted) return;
      final d = vs.data() ?? <String, dynamic>{};
      final st = EstadosViaje.normalizar((d['estado'] ?? '').toString());
      final done = d['completado'] == true ||
          st == EstadosViaje.completado ||
          st == EstadosViaje.cancelado ||
          st == EstadosViaje.rechazado;
      if (done) {
        print('[VIAJE_ACTIVO] taxista init: viaje terminal → salir de pantalla');
        if (mounted) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
      }
    } catch (e) {
      print('[VIAJE_ACTIVO] taxista init check error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      print('[VIAJE_ACTIVO] taxista lifecycle resumed');
      ActiveTripService.bloquearShellTaxistaTrasAceptar(
        const Duration(minutes: 30),
        viajeId: _cachedViaje?.id,
      );
      ActiveTripService.notificarRebuildShell();
      // resumed: GPS se reanuda con _asegurarGps(..., allowPermissionDialog:false) → readNoRequest, sin diálogo del SO.
      unawaited(() async {
        await _refrescarViajeDocDesdeFirestore();
        if (!mounted) return;
        await _reanudarGpsSiEnCursoTrasResume();
        if (!mounted) return;
        await _handleAppResumedTrasNavegacionExterna();
      }());
    }
  }

  /// Tras volver de Waze/Maps o del sistema: si el viaje va al destino pero el
  /// stream GPS quedó caído, reintenta [_asegurarGps] una vez (sin bucles).
  Future<void> _reanudarGpsSiEnCursoTrasResume() async {
    final Viaje? v = _cachedViaje;
    if (v == null) return;
    final String estadoBase = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado ? EstadosViaje.aceptado : EstadosViaje.pendiente)),
    );
    if (!EstadosViaje.taxistaReanudaGpsStreamTrasResume(estadoBase,
        codigoVerificado: v.codigoVerificado)) {
      return;
    }
    if (_gpsActivo) return;
    logDbg(
        '[VIAJE_ACTIVO] resume: reintentar GPS (en_curso o a_bordo+PIN) viaje=${v.id} (_gpsActivo=false)',
    );
    await _asegurarGps(v.id, allowPermissionDialog: false);
  }

  void _colapsarViajeSheetPorMapa() {
    if (!_viajeSheetCtrl.isAttached) return;
    final double actual = _viajeSheetCtrl.size;
    if (actual <= _kViajeSheetMin + 0.02) return;
    unawaited(
      _viajeSheetCtrl.animateTo(
        _kViajeSheetMin,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _expandirViajeSheetTrasMapa() {
    _asegurarSheetExpandido();
  }

  void _asegurarSheetExpandido({bool forzar = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (!mounted || !_viajeSheetCtrl.isAttached) return;
        final double actual = _viajeSheetCtrl.size;
        if (!forzar && actual >= _kViajeSheetInitial - 0.04) return;
        unawaited(
          _viajeSheetCtrl.animateTo(
            _kViajeSheetInitial,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        );
      });
    });
  }

  void _restablecerSheetTrasPinCorp() {
    _corpPinSheetExpandido = false;
    _resetViajeSheetScroll();
    _asegurarSheetExpandido(forzar: true);
  }

  void _resetViajeSheetScroll() {
    final scroll = _viajeSheetScrollCtrl;
    if (scroll == null || !scroll.hasClients) return;
    try {
      scroll.jumpTo(0);
    } catch (_) {}
  }

  void _expandirSheetParaPinCorp() {
    if (_corpPinSheetExpandido) {
      _resetViajeSheetScroll();
      return;
    }
    _corpPinSheetExpandido = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _resetViajeSheetScroll();
      if (!_viajeSheetCtrl.isAttached) return;
      unawaited(
        _viajeSheetCtrl.animateTo(
          _kViajeSheetPin,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
      Future<void>.delayed(const Duration(milliseconds: 380), () {
        if (!mounted) return;
        _corpPinFocusNode.requestFocus();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resetViajeSheetScroll();
      });
    });
  }

  bool _corpClienteAbordoConfirmado(Viaje v) =>
      v.extras?['clienteAbordo'] == true;

  /// Viaje normal en fase pickup: panel compacto (sin duplicar pago ni detalles).
  bool _esPickupClienteSheetCompacto(Viaje v, String estadoBase) {
    if (CorporativoPasajerosChoferCard.esViajeCorporativo(v)) return false;
    if (_esViajeCorporativo(v)) return false;
    return EstadosViaje.esAceptado(estadoBase) ||
        EstadosViaje.esEnCaminoPickup(estadoBase);
  }

  /// Corporativo: estado de código en Firestore sin abordo real → tratar como pickup.
  bool _corpEnFasePickup(Viaje v, String estadoBase) {
    if (!CorporativoPasajerosChoferCard.esViajeCorporativo(v)) return false;
    if (v.codigoVerificado) return false;
    if (_corpClienteAbordoConfirmado(v) || _corpPinUiActivo) return false;
    if (EstadosViaje.esAceptado(estadoBase) ||
        EstadosViaje.esEnCaminoPickup(estadoBase)) {
      return true;
    }
    return estadoBase == EstadosViaje.enOrigenEsperandoCodigo ||
        estadoBase == EstadosViaje.pendienteCodigo ||
        estadoBase == EstadosViaje.esperandoCodigoEncargado;
  }

  bool _corpDebeMostrarPanelPin(Viaje v, String estadoBase) {
    if (_corpSinPin(v)) return false;
    if (!CorporativoPasajerosChoferCard.esViajeCorporativo(v)) return false;
    if (v.codigoVerificado) return false;
    if (_corpEnFasePickup(v, estadoBase)) return false;
    if (_corpPinUiActivo) return true;
    if (!_corpClienteAbordoConfirmado(v)) return false;
    return estadoBase == EstadosViaje.enOrigenEsperandoCodigo ||
        estadoBase == EstadosViaje.pendienteCodigo ||
        (EstadosViaje.esAbordo(estadoBase) && !v.codigoVerificado);
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

  void _syncEsperaCargaViaje(bool esperando) {
    if (!esperando) {
      _cargaViajeTimer?.cancel();
      _cargaViajeTimer = null;
      _cargaViajeRescueTimer?.cancel();
      _cargaViajeRescueTimer = null;
      _cargaViajeTickTimer?.cancel();
      _cargaViajeTickTimer = null;
      if (_cargaViajeSegundosN.value != 0) {
        _cargaViajeSegundosN.value = 0;
      }
      if (_cargaViajeExpirada && mounted) {
        setState(() => _cargaViajeExpirada = false);
      }
      return;
    }
    if (_cargaViajeTimer != null) return;
    _cargaViajeTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _cargaViajeSegundosN.value++;
    });
    _cargaViajeRescueTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_intentarRescateViajeAtascado());
    });
    _cargaViajeTimer = Timer(const Duration(seconds: 8), () {
      unawaited(_manejarTimeoutCargaViaje());
    });
  }

  Future<void> _manejarTimeoutCargaViaje() async {
    if (!mounted) return;
    if (_cachedViaje != null) return;
    await _intentarRescateViajeAtascado();
    if (!mounted || _cachedViaje != null) return;
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    // Turismo: nunca revertir promoción corporativa ni mostrar «Aún no es hora».
    if (await _viajeActivoEsTurismo(uid)) {
      if (!mounted) return;
      setState(() {
        _cargaViajeExpirada = true;
        _corporativoAunNoHoraMsg = null;
      });
      return;
    }

    final String? msg = await _detectarMensajeCorporativoAunNoEsHora();
    if (!mounted) return;
    setState(() {
      _cargaViajeExpirada = true;
      _corporativoAunNoHoraMsg = msg;
    });
    if (msg == null) return;
    ActiveTripService.cancelarMantenimientoOverlayViaje();
    try {
      final DocumentSnapshot<Map<String, dynamic>> us =
          await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(uid)
              .get(const GetOptions(source: Source.server));
      final String vid =
          (us.data()?['viajeActivoId'] ?? '').toString().trim();
      if (vid.isEmpty) return;
      final DocumentSnapshot<Map<String, dynamic>> vs =
          await FirebaseFirestore.instance
              .collection('viajes')
              .doc(vid)
              .get(const GetOptions(source: Source.server));
      final Map<String, dynamic> d = vs.data() ?? <String, dynamic>{};
      if (!_docEsViajeCorporativo(d, uid)) return;
      final bool yaPromovido = d['activo'] == true && d['aceptado'] == true;
      if (!yaPromovido) {
        await CorporativoTaxistaService.revertirPromocionCorporativaTemprana(
          uidTaxista: uid,
        );
      }
    } catch (_) {
      await CorporativoTaxistaService.revertirPromocionCorporativaTemprana(
        uidTaxista: uid,
      );
    }
  }

  Future<String?> _detectarMensajeCorporativoAunNoEsHora() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final us = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      final u = us.data() ?? <String, dynamic>{};
      for (final raw in <dynamic>[
        u['viajeActivoId'],
        u['siguienteViajeId'],
      ]) {
        final vid = (raw ?? '').toString().trim();
        if (vid.isEmpty) continue;
        final vs = await FirebaseFirestore.instance
            .collection('viajes')
            .doc(vid)
            .get(const GetOptions(source: Source.server));
        if (!vs.exists) continue;
        final d = vs.data() ?? <String, dynamic>{};
        if (!CorporativoTaxistaService.esViajeCorporativoAsignado(d, uid)) {
          continue;
        }
        final opListo =
            await CorporativoTaxistaService.choferOperacionMarcaListo(uid, vid);
        if (!CorporativoTaxistaService.corporativoListoParaAbrirEnCurso(
          d,
          listoSegunOperacion: opListo,
        )) {
          return CorporativoTaxistaService.mensajeCorporativoAunNoEsHora(d);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _intentarRescateViajeAtascado() async {
    if (!mounted || _cachedViaje != null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final us = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      final u = us.data() ?? <String, dynamic>{};
      for (final raw in <dynamic>[
        u['viajeActivoId'],
        u['siguienteViajeId'],
      ]) {
        final vid = (raw ?? '').toString().trim();
        if (vid.isEmpty) continue;
        final vs = await FirebaseFirestore.instance
            .collection('viajes')
            .doc(vid)
            .get(const GetOptions(source: Source.server));
        if (!vs.exists) continue;
        final d = vs.data() ?? <String, dynamic>{};
        if (_docEsViajeTurismo(d)) {
          if (!ViajesRepo.viajeVisibleEnCursoTaxista(d, uid)) continue;
          if (!mounted) return;
          _aplicarViajeRescatadoEnCache(Viaje.fromMap(vs.id, d));
          return;
        }
        if (_docEsViajeCorporativo(d, uid)) {
          final bool opListo =
              await CorporativoTaxistaService.choferOperacionMarcaListo(uid, vid);
          if (!CorporativoTaxistaService.corporativoListoParaAbrirEnCurso(
            d,
            listoSegunOperacion: opListo,
          )) {
            final bool yaPromovido = d['activo'] == true &&
                (d['aceptado'] == true ||
                    EstadosViaje.normalizar((d['estado'] ?? '').toString()) ==
                        EstadosViaje.aceptado);
            if (yaPromovido || opListo) {
              if (!mounted) return;
              _aplicarViajeRescatadoEnCache(Viaje.fromMap(vs.id, d));
              return;
            }
            if (!mounted) return;
            setState(() {
              _corporativoAunNoHoraMsg =
                  CorporativoTaxistaService.mensajeCorporativoAunNoEsHora(d);
              _cargaViajeExpirada = true;
            });
            ActiveTripService.cancelarMantenimientoOverlayViaje();
            await CorporativoTaxistaService.revertirPromocionCorporativaTemprana(
              uidTaxista: uid,
              viajeId: vid,
            );
            return;
          }
        }
        if (!ViajesRepo.viajeVisibleEnCursoTaxista(d, uid)) continue;
        if (!mounted) return;
        _aplicarViajeRescatadoEnCache(Viaje.fromMap(vs.id, d));
        return;
      }
    } catch (e) {
      debugPrint('[VIAJE_ACTIVO] rescate viaje atascado: $e');
    }
  }

  Widget _buildCargandoViajeOError() {
    if (_cargaViajeExpirada) {
      if (_corporativoAunNoHoraMsg != null) {
        return _panelCorporativoAunNoEsHora(_corporativoAunNoHoraMsg!);
      }
      return _panelErrorCargaTurismoOPool();
    }
    return _widgetEntrandoViajeTurismoOPool();
  }

  Widget _widgetEntrandoViajeTurismoOPool() {
    return ValueListenableBuilder<int>(
      valueListenable: _cargaViajeSegundosN,
      builder: (context, seg, _) {
        return ColoredBox(
          color: const Color(0xFF0A0A0A),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.greenAccent,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Cargando tu viaje…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    seg > 0
                        ? 'Esperando datos ($seg s)…'
                        : 'Viaje aceptado — preparando pantalla…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white54,
                      height: 1.35,
                      fontSize: 13,
                    ),
                  ),
                ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _panelCorporativoAunNoEsHora(String mensaje) {
    return ColoredBox(
      color: const Color(0xFF0A0A0A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.schedule_outlined,
                color: Color(0xFF5EEAD4),
                size: 52,
              ),
              const SizedBox(height: 16),
              const Text(
                'Aún no es hora',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.45,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    ActiveTripService.cancelarMantenimientoOverlayViaje();
                    unawaited(
                      NavigationService.clearAndGo(
                        const MisRutasCorporativasPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.route),
                  label: const Text('Mis rutas corporativas'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    ActiveTripService.cancelarMantenimientoOverlayViaje();
                    unawaited(NavigationService.irAlInicioTaxista());
                  },
                  child: const Text('Volver al pool'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelErrorCargaTurismoOPool() {
    return ColoredBox(
      color: const Color(0xFF0A0A0A),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.beach_access,
                  color: Colors.purpleAccent,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  'No pudimos cargar el viaje',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'El viaje fue aceptado pero los datos tardaron en llegar. '
                  'Tocá «Reintentar» o volvé a Servicios → Pool turístico.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    height: 1.4,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _cargaViajeExpirada = false;
                        _corporativoAunNoHoraMsg = null;
                      });
                      _syncEsperaCargaViaje(true);
                      unawaited(_sembrarViajeActivoDesdeServidor());
                      unawaited(_intentarRescateViajeAtascado());
                      ActiveTripService.mantenerOverlayViajeEnShell(
                        const Duration(seconds: 120),
                      );
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      ActiveTripService.cancelarMantenimientoOverlayViaje();
                      ActiveTripService.cancelarBloqueoShellTaxista();
                      unawaited(NavigationService.irAlInicioTaxista());
                    },
                    child: const Text('Volver a Servicios'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cargaViajeTimer?.cancel();
    _cargaViajeTimer = null;
    _cargaViajeRescueTimer?.cancel();
    _cargaViajeRescueTimer = null;
    _cargaViajeTickTimer?.cancel();
    _cargaViajeTickTimer = null;
    _cancelarDebounceViajeNull();
    _cargaViajeSegundosN.dispose();
    _ubicacionTaxistaSvc.modo.removeListener(_onUbicacionTaxistaModoChanged);
    WidgetsBinding.instance.removeObserver(this);
    ActiveTripService.markTaxistaTripScreenUnmounted();
    _cancelSub?.cancel();
    _viajeSheetCtrl.dispose();
    _map?.dispose();
    _gpsStreamRecoveryTimer?.cancel();
    _gpsStreamRecoveryTimer = null;
    _stopGps();
    _codigoCtrl.dispose();
    _corpPinFocusNode.dispose();
    _routeDebounce?.cancel();
    _corpCodigoTimeoutTicker?.cancel();
    _corpCodigoTimeoutTicker = null;
    _viajesCercanosEscucha.dispose();
    _viajesCercanosCtl.dispose();
    _taxistaPosCola.dispose();
    _colaReferenciaOrden.dispose();
    _distanciaDestinoNotifier.dispose();
    super.dispose();
  }

  Widget _mapaOPlaceholder({required Widget mapa}) {
    if (!_mapaPermitido || _mapaDesactivadoPorError) {
      return ColoredBox(
        color: RaiDsColors.bg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _mapaDesactivadoPorError
                      ? 'Mapa no disponible ahora.\nAbajo tienes las acciones del viaje.'
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
                    onPressed: () {
                      setState(() {
                        _mapaDesactivadoPorError = false;
                        _mapaPermitido = true;
                      });
                    },
                    icon: const Icon(Icons.map),
                    label: const Text('Reintentar mapa'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return mapa;
  }

  // ===================== Acciones Principales =====================

  Future<void> _iniciarNavegacionPickup(Viaje v) async {
    if (_actionBusy) return;
    _actionBusy = true;

    final bool corpPickup =
        CorporativoPasajerosChoferCard.esViajeCorporativo(v);
    final Map<String, dynamic> corpData = corpPickup
        ? CorporativoTaxistaService.mapaNavegacionDesdeViaje(v.toMap())
        : const <String, dynamic>{};
    final int paradasCorp = corpPickup
        ? CorporativoTaxistaService.contarParadasRuta(corpData)
        : 0;

    try {
      // Si el backend ya está en `en_camino_pickup`, el botón no debe fallar.
      // Esto evita que `marcarEnCaminoPickup()` intente una transición inválida
      // (de `en_camino_pickup` a `en_camino_pickup`) y dispare el snackbar genérico.
      final estadoN = EstadosViaje.normalizar(v.estado);
      final bool yaEnCaminoPickup = estadoN == EstadosViaje.enCaminoPickup;
      if (estadoN == EstadosViaje.cancelado ||
          estadoN == EstadosViaje.completado) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El viaje ya no está disponible.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        });
        return;
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (!yaEnCaminoPickup) {
        if (uid != null) {
          try {
            await ViajesRepo.marcarEnCaminoPickup(
              viajeId: v.id,
              uidTaxista: uid,
            );
          } catch (e) {
            // Robustez: si el backend ya está en `en_camino_pickup`,
            // `marcarEnCaminoPickup` puede lanzar "Estado inválido".
            // Tampoco bloqueamos por permission-denied residual (GPS/Maps igual se abren).
            final msg = e.toString().toLowerCase();
            final isFirebaseDenied = e is FirebaseException &&
                e.code == 'permission-denied';
            if (msg.contains('estado inválido') ||
                msg.contains('estado invalido') ||
                msg.contains('estado inválido para en_camino_pickup') ||
                msg.contains('estado invalido para en_camino_pickup') ||
                isFirebaseDenied ||
                msg.contains('permission-denied') ||
                msg.contains('permiso denegado')) {
              logDbg(
                'marcarEnCaminoPickup no bloquea navegación: $e',
              );
            } else {
              rethrow;
            }
          }
        }
      }

      final gpsOk = await _gpsListoParaAbrirNavegacionExterna(v);
      if (!gpsOk && mounted) {
        unawaited(_persistNavPickupFlag(v.id, false));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _navegacionIniciada = false);
        });
        _actionBusy = false;
        return;
      }

      final tieneCoords = _coordsValid(v.latCliente, v.lonCliente);

      /// Si el sheet se cierra sin elegir app (gesto, barrier, etc.), no dejar
      /// `_navegacionIniciada` en true: desbloquea de nuevo «Navegar» y abordo coherente.
      var eligioAppExterna = false;

      if (mounted) {
        setState(() => _viajeSheetOcultoPorModalNav = true);
        try {
          await showNavegacionWazeMapsSheet(
            context,
            title: 'Abrir navegación',
            addressLine: 'Punto de recogida: ${v.origen}',
            tieneCoords: tieneCoords,
            gpsCoordinatesLine: tieneCoords
                ? 'GPS: ${NavegacionExternaLauncher.fmtCoord(v.latCliente)}, ${NavegacionExternaLauncher.fmtCoord(v.lonCliente)}'
                : null,
            showSinGpsBanner: !tieneCoords,
            footerHint: corpPickup
                ? (paradasCorp > 0
                    ? 'Waze → recogida en la empresa. '
                        'Maps → ruta completa: empresa + $paradasCorp parada(s) en orden.'
                    : 'Waze → recogida en la empresa. Maps → empresa y destino.')
                : 'Elige Waze o Maps; al llegar, vuelve a RAI para marcar abordo y el código.',
            onWaze: () {
              eligioAppExterna = true;
              if (corpPickup) {
                unawaited(
                    CorporativoTaxistaService.abrirWazeDesdeViaje(corpData));
              } else if (tieneCoords) {
                unawaited(NavegacionExternaLauncher.abrirWazeDestino(
                    v.latCliente, v.lonCliente));
              } else {
                unawaited(
                    NavegacionExternaLauncher.abrirWazeBusqueda(v.origen));
              }
            },
            onMaps: () {
              eligioAppExterna = true;
              if (corpPickup) {
                unawaited(
                    CorporativoTaxistaService.abrirMapsDesdeViaje(corpData));
              } else if (tieneCoords) {
                unawaited(NavegacionExternaLauncher.abrirGoogleMapsDestino(
                    v.latCliente, v.lonCliente));
              } else {
                unawaited(NavegacionExternaLauncher.abrirGoogleMapsDireccion(
                    v.origen));
              }
            },
            onCancel: () {
              unawaited(_persistNavPickupFlag(v.id, false));
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _navegacionIniciada = false);
              });
            },
          );
        } finally {
          if (mounted) {
            setState(() => _viajeSheetOcultoPorModalNav = false);
          }
        }
      }

      if (mounted && eligioAppExterna) {
        unawaited(_persistNavPickupFlag(v.id, true));
        setState(() => _navegacionIniciada = true);
      }

      if (mounted && !eligioAppExterna) {
        unawaited(_persistNavPickupFlag(v.id, false));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _navegacionIniciada = false);
        });
      }

      if (mounted && eligioAppExterna) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.navigation, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Navegación hacia el cliente lista. Al llegar, en RAI: «Cliente a bordo» y luego el código.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            );
          }
        });
      }
    } catch (e) {
      logDbg('Error iniciando navegación: $e');
      unawaited(_persistNavPickupFlag(v.id, false));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _navegacionIniciada = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al iniciar navegación: ${errorAuthEs(e)}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      });
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _marcarClienteAbordo(Viaje v) async {
    if (_actionBusy) return;
    _actionBusy = true;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        throw Exception('Usuario no autenticado');
      }

      final estadoN = EstadosViaje.normalizar(v.estado);
      final bool yaEnAboard = estadoN == EstadosViaje.aBordo ||
          estadoN == EstadosViaje.enCurso;
      if (!yaEnAboard) {
        await ViajesRepo.marcarClienteAbordo(viajeId: v.id, uidTaxista: uid);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Text('✅ Cliente marcado como a bordo'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      });

      final snapshot =
          await FirebaseFirestore.instance.collection('viajes').doc(v.id).get();
      unawaited(_persistNavPickupFlag(v.id, false));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && snapshot.exists) {
          final viajeActualizado = Viaje.fromMap(v.id, snapshot.data()!);
          final bool corpPin =
              CorporativoPasajerosChoferCard.esViajeCorporativo(v);
          if (corpPin) {
            unawaited(_limpiarCorpDeViajeEnCursoAlEntrar());
            return;
          }
          setState(() {
            _cachedViaje = viajeActualizado;
            _navegacionIniciada = false;
            _clienteCerca = false;
            if (corpPin && !viajeActualizado.codigoVerificado) {
              _corpPinUiActivo = true;
              _corpPinSheetExpandido = false;
            }
          });
          if (corpPin && !viajeActualizado.codigoVerificado) {
            _expandirSheetParaPinCorp();
            unawaited(_corpGpsCheckpoint(viajeActualizado, 'abordo'));
          }
        }
      });
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error: ${errorAuthEs(e)}'),
                backgroundColor: Colors.red),
          );
        }
      });
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _salirTrasLiberacionCorpCodigo({String? mensaje}) async {
    _corpCodigoTimeoutTicker?.cancel();
    _stopGps();
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    if (mensaje != null && mensaje.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(mensaje), duration: const Duration(seconds: 6)),
      );
    }
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const TaxistaShell()),
      (route) => false,
    );
  }

  Future<void> _syncCorpCodigoLive(String viajeId) async {
    if (viajeId.isEmpty) return;
    try {
      final vs = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get();
      if (!mounted || !vs.exists) return;
      final d = vs.data() ?? <String, dynamic>{};
      if (!CorporativoPasajerosChoferCard.esViajeCorporativo(
          Viaje.fromMap(viajeId, d))) {
        return;
      }
      if (CorporativoTaxistaService.corpSinPinVerificacionChofer(
        d,
        uidTaxista: FirebaseAuth.instance.currentUser?.uid,
      )) {
        return;
      }
      _iniciarTickerCorpCodigoDesdeViaje(d);
      final est = EstadosViaje.normalizar((d['estado'] ?? '').toString());
      final bool abordo = d['clienteAbordo'] == true;
      if (d['codigoVerificado'] != true &&
          abordo &&
          (est == EstadosViaje.enOrigenEsperandoCodigo ||
              est == EstadosViaje.pendienteCodigo ||
              EstadosViaje.esAbordo(est))) {
        if (mounted) {
          setState(() => _corpPinUiActivo = true);
        }
        _expandirSheetParaPinCorp();
      } else if (!abordo && mounted && _corpPinUiActivo) {
        setState(() => _corpPinUiActivo = false);
      }
      final intentos = d['intentosCodigo'];
      if (intentos is num && mounted) {
        setState(() => _corpIntentosFallidos = intentos.toInt().clamp(0, 3));
      }
      if (est == EstadosViaje.codigoBloqueado) {
        await _salirTrasLiberacionCorpCodigo(
          mensaje:
              'Viaje bloqueado por intentos fallidos. El encargado fue notificado.',
        );
      } else if (est == EstadosViaje.canceladoPorTiempo) {
        await _salirTrasLiberacionCorpCodigo(
          mensaje: 'Viaje cancelado: tiempo de espera del código agotado.',
        );
      }
    } catch (_) {
      /* no bloquear UI */
    }
  }

  Future<void> _solicitarCodigoCorpEncargado(Viaje v) async {
    if (_actionBusy) return;
    final confirmar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.black,
            title: const Text('No tengo código',
                style: TextStyle(color: Colors.white)),
            content: const Text(
              'Se avisará al encargado por chat y notificación. '
              'Podrás seguir disponible para otros viajes mientras te envían el código.',
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Solicitar código'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmar || !mounted) return;
    _actionBusy = true;
    try {
      await CorporativoFaseAService.taxistaSolicitarCodigo(v.id);
      await _salirTrasLiberacionCorpCodigo(
        mensaje: 'Solicitud enviada al encargado. Revisá Mis rutas corporativas cuando te envíen el código.',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorAuthEs(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      _actionBusy = false;
    }
  }

  void _iniciarTickerCorpCodigoDesdeViaje(Map<String, dynamic> data) {
    final v = _cachedViaje;
    if (v == null || !_esViajeCorporativo(v)) return;
    if (data['codigoVerificado'] == true) {
      _corpCodigoTimeoutTicker?.cancel();
      return;
    }
    DateTime? llegada;
    final raw = data['tiempoLlegadaOrigen'];
    if (raw is Timestamp) llegada = raw.toDate();
    DateTime? fechaHora;
    final fh = data['fechaHora'];
    if (fh is Timestamp) {
      fechaHora = fh.toDate();
    } else if (_cachedViaje != null) {
      fechaHora = _cachedViaje!.fechaHora;
    }

    final limite = CorporativoEsperaCodigoConstants.limiteEsperaCodigo(
      tiempoLlegadaOrigen: llegada,
      fechaHoraRecogida: fechaHora,
    );
    if (limite == null) return;
    void tick() {
      if (!mounted) return;
      final rest = limite.difference(DateTime.now());
      if (rest.isNegative) {
        _corpCodigoTimeoutTicker?.cancel();
        final est = EstadosViaje.normalizar((data['estado'] ?? '').toString());
        if (est == EstadosViaje.canceladoPorTiempo) {
          unawaited(_salirTrasLiberacionCorpCodigo(
            mensaje: 'Viaje cancelado: tiempo de espera del código agotado.',
          ));
        }
        return;
      }
      setState(() => _corpTiempoRestanteCodigo = rest);
    }

    tick();
    _corpCodigoTimeoutTicker?.cancel();
    _corpCodigoTimeoutTicker =
        Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  String _formatoTiempoRestante(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _verificarCodigo(String viajeId, String codigoCorrecto) async {
    if (_actionBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final esperado = _digitsOnlyCode(codigoCorrecto);
    final ingresado = _digitsOnlyCode(_codigoCtrl.text);
    final corp = _cachedViaje != null &&
        CorporativoPasajerosChoferCard.esViajeCorporativo(_cachedViaje!);
    if (!corp && esperado.length != 6) {
      _tripFlowSnack(
        'Este viaje no tiene código de 6 dígitos en el sistema. '
        'Pide al cliente que abra su viaje y confirme el PIN; si sigue igual, contacta soporte.',
      );
      return;
    }
    if (ingresado.length != 6) {
      _tripFlowSnack(
        corp
            ? 'Ingresa el código del período (mismo toda la quincena). '
                'Pídeselo al encargado de la empresa.'
            : 'Ingresa los 6 dígitos que te dicta el cliente.',
        backgroundColor: Colors.redAccent,
      );
      return;
    }

    if (!corp) {
      if (ingresado != esperado) {
        _tripFlowSnack(
          'Código incorrecto. Vuelve a pedírselo al cliente.',
          backgroundColor: Colors.redAccent,
        );
        return;
      }
    }

    _actionBusy = true;
    _codigoCtrl.clear();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _actionBusy = false;
      return;
    }

    try {
      try {
        await ViajesRepo.iniciarViaje(
          viajeId: viajeId,
          uidTaxista: uid,
          pinVerificacion: ingresado,
        );
      } catch (eInicio) {
        if (corp && eInicio is FirebaseFunctionsException) {
          final details = eInicio.details;
          Map<String, dynamic>? detMap;
          if (details is Map) {
            detMap = Map<String, dynamic>.from(details);
          }
          final bloqueado = detMap?['codigoBloqueado'] == true;
          final restantes = detMap?['intentosRestantes'];
          if (restantes is num) {
            setState(() {
              _corpIntentosFallidos = (3 - restantes.toInt()).clamp(0, 3);
            });
          } else {
            setState(() => _corpIntentosFallidos = 3);
          }
          final msg = (eInicio.message ?? '').trim().isNotEmpty
              ? eInicio.message!.trim()
              : errorAuthEs(eInicio);
          if (bloqueado) {
            await _salirTrasLiberacionCorpCodigo(mensaje: msg);
            return;
          }
          _tripFlowSnack(msg, backgroundColor: Colors.redAccent);
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorAuthEs(eInicio)),
                backgroundColor: Colors.redAccent,
                duration: const Duration(seconds: 6),
              ),
            );
          }
        });
        return;
      }

      if (!mounted) {
        return;
      }

      final viajeSnap = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get();

      if (!mounted) {
        _actionBusy = false;
        return;
      }

      final data = viajeSnap.data();
      if (data != null) {
        final viajeActualizado = Viaje.fromMap(viajeId, data);
        _aplicarProgresoMultiparadaDesdeViaje(viajeActualizado);
        if (mounted) {
          _corpPinFocusNode.unfocus();
          FocusManager.instance.primaryFocus?.unfocus();
          setState(() {
            _cachedViaje = viajeActualizado;
            _corpPinUiActivo = false;
            _corpPinSheetExpandido = false;
          });
          _restablecerSheetTrasPinCorp();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _scheduleDrawRoute();
            if (corp) {
              unawaited(_corpGpsOnEnCurso(viajeActualizado));
            }
          });
        }

        if (corp) {
          _tripFlowSnack(
            'Código correcto. Abriendo navegación a la primera parada…',
            backgroundColor: Colors.green,
          );
          if (mounted) {
            await _corpAbrirNavegacionDestinoActual(viajeActualizado);
          }
          if (mounted) _restablecerSheetTrasPinCorp();
        } else if (_esMultiparada(viajeActualizado)) {
          _tripFlowSnack(
            'Código correcto. Tocá cada parada abajo → Waze → ✓.',
            backgroundColor: Colors.green,
          );
          if (mounted) {
            _expandirViajeSheetTrasMapa();
            _restablecerSheetTrasPinCorp();
          }
        } else {
          if (_permitePruebaSinRecorrido(viajeActualizado)) {
            _tripFlowSnack(
              'Código correcto. Abrí «Iniciar ruta» o Maps/Waze al destino '
              '(en prueba podés finalizar sin recorrer).',
              backgroundColor: Colors.green,
            );
          } else {
            _tripFlowSnack(
              'Código correcto. Tocá «Iniciar ruta al destino» o abrí Maps/Waze.',
              backgroundColor: Colors.green,
            );
          }
          if (mounted) _restablecerSheetTrasPinCorp();
        }
      }
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error al iniciar: $e'),
                backgroundColor: Colors.red),
          );
        }
      });
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _finalizarViaje(
    Viaje v, {
    bool trasConfirmarUltimaParadaMultiparada = false,
  }) async {
    if (_actionBusy) {
      if (trasConfirmarUltimaParadaMultiparada) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(
            _finalizarViaje(
              v,
              trasConfirmarUltimaParadaMultiparada: true,
            ),
          );
        });
      }
      return;
    }
    if (trasConfirmarUltimaParadaMultiparada) {
      _multiparadaAutoFacturaViajeId = v.id;
    }
    _actionBusy = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      print('[FINALIZAR_VIAJE] _finalizarViaje abort: sin uid');
      _actionBusy = false;
      return;
    }

    print('[FINALIZAR] _finalizarViaje start viajeId=${v.id} uid=$uid');
    final messenger = ScaffoldMessenger.of(context);

    var viajeOperativo = v;
    if (_esViajeCorporativo(v) &&
        v.codigoVerificado &&
        _esMultiparada(v) &&
        !_multiparadaRutaCompleta(v) &&
        _permitePruebaSinRecorrido(v)) {
      viajeOperativo = await _completarParadasCorporativoPendientes(v);
      if (mounted) {
        setState(() => _cachedViaje = viajeOperativo);
      }
    }

    if (!_puedeFinalizarViajeMultiparada(viajeOperativo)) {
      final int total = _legsNavegacionMultiparada(viajeOperativo).length;
      final int hechos =
          viajeOperativo.multiparadaLegCompletadas.clamp(0, total);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Viaje multiparada: confirmá las $total paradas/destinos antes de finalizar '
              '($hechos/$total registrados).',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      if (trasConfirmarUltimaParadaMultiparada) {
        _liberarGuardAutoFacturaMultiparada(viajeOperativo.id);
      }
      _actionBusy = false;
      return;
    }

    if (_esViajeCorporativo(viajeOperativo) &&
        !_permitePruebaSinRecorrido(viajeOperativo) &&
        !_esMultiparada(viajeOperativo) &&
        !_navegacionDestinoIniciada) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Abrí Waze o Maps al destino antes de finalizar el viaje.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
      _actionBusy = false;
      return;
    }

    // Callable acepta `en_curso` o `a_bordo` (PIN verificado sin transición).
    var estadoParaFinalizar = EstadosViaje.normalizar(viajeOperativo.estado);
    if (!EstadosViaje.taxistaPuedeInvocarFinalizar(estadoParaFinalizar)) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('viajes')
            .doc(viajeOperativo.id)
            .get();
        final data = snap.data() ?? const <String, dynamic>{};
        final String estadoRemoto =
            EstadosViaje.normalizar((data['estado'] ?? '').toString());
        if (!EstadosViaje.taxistaPuedeInvocarFinalizar(estadoRemoto)) {
          if (_esViajeCorporativo(viajeOperativo) &&
              viajeOperativo.codigoVerificado &&
              estadoRemoto == EstadosViaje.aBordo) {
            await ViajesRepo.iniciarViaje(
              viajeId: viajeOperativo.id,
              uidTaxista: uid,
            );
            estadoParaFinalizar = EstadosViaje.enCurso;
          } else {
          print(
              '[FINALIZAR_ERROR] estado remoto no finalizable: $estadoRemoto viajeId=${viajeOperativo.id}');
          if (mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Para finalizar, primero tené el cliente a bordo con código verificado '
                  'e iniciá la ruta al destino (o esperá a que la app actualice el estado).',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          _actionBusy = false;
          return;
          }
        } else {
          estadoParaFinalizar = estadoRemoto;
        }
      } catch (_) {
        print('[FINALIZAR_ERROR] error validando estado remoto viajeId=${viajeOperativo.id}');
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo validar el estado del viaje. Intenta nuevamente.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        _actionBusy = false;
        return;
      }
    }

    if (_permitePruebaSinRecorrido(viajeOperativo)) {
      print(
        '[FLYGO_SIM_CASA] finalizar sin GPS/diálogo/medición viaje=${viajeOperativo.id} '
        'tipo=${viajeOperativo.tipoServicio} corp=${_esViajeCorporativo(viajeOperativo)}',
      );
    } else if (trasConfirmarUltimaParadaMultiparada &&
        _esMultiparada(viajeOperativo) &&
        _multiparadaRutaCompleta(viajeOperativo)) {
      // El chofer acaba de confirmar el destino final con ✓: factura/comisión al instante.
      await _asegurarGps(viajeOperativo.id, allowPermissionDialog: false);
      if (mounted) {
        _tripFlowSnack(
          'Destino final confirmado. Generando factura y comisión…',
          backgroundColor: Colors.greenAccent,
        );
      }
    } else {
      // Intento de GPS en vivo sin abrir diálogo de permisos (permiso ya concedido).
      await _asegurarGps(viajeOperativo.id, allowPermissionDialog: false);

      // Diálogo informativo; no bloqueamos por distancia.
      final ({double lat, double lon})? pinDestino =
          _coordsDestinoParaFinalizar(viajeOperativo);
      double? distMinM;
      if (pinDestino != null) {
        distMinM = await _menorDistanciaMetrosAlDestinoParaFinalizar(
          viajeOperativo,
          pinDestino,
          pingStreamLatLon: _taxistaPosCola.value,
        );
      }

      if (!mounted) {
        _actionBusy = false;
        return;
      }

      final ok = await _dialogoConfirmarFinalizarViaje(
            context,
            hayPinDestino: pinDestino != null,
            distanciaMetrosMin: distMinM,
          ) ??
          false;

      if (!ok) {
        print('[FINALIZAR_VIAJE] usuario canceló diálogo');
        _actionBusy = false;
        return;
      }
    }

    try {
      // Evita que TaxistaShell quite ViajeEnCurso antes de factura/post-viaje.
      ActiveTripService.mantenerOverlayViajeEnShell(const Duration(minutes: 3));

      if (_esViajeCorporativo(viajeOperativo)) {
        await _corpGpsCheckpoint(viajeOperativo, 'fin');
      }

      print('[FINALIZAR] invocando ViajesRepo.completarViajePorTaxista');
      try {
        try {
          final snapPre = await FirebaseFirestore.instance
              .collection('viajes')
              .doc(v.id)
              .get();
          final dPre = snapPre.data() ?? const <String, dynamic>{};
          final stPre = EstadosViaje.normalizar(
              (dPre['estado'] ?? '').toString());
          final compPre = dPre['completado'] == true;
          print(
            '[FINALIZAR_ERROR] pre-callable viajeId=${v.id} '
            'estadoFirestore=$stPre completado=$compPre '
            'codigoVerificado=${dPre['codigoVerificado'] == true}',
          );
        } catch (e, st) {
          print(
              '[FINALIZAR_ERROR] pre-callable lectura Firestore falló viajeId=${v.id}: $e $st');
        }

        final outcome = await ViajesRepo.completarViajePorTaxista(viajeOperativo.id);
        if (outcome == CompletarViajeTaxistaOutcome.alreadyCompleted &&
            mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Viaje ya finalizado'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } on FirebaseFunctionsException catch (e, st) {
        print(
            '[FINALIZAR_ERROR] FirebaseFunctionsException viajeId=${viajeOperativo.id} '
            '${e.code} ${e.message} $st');
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'No se pudo finalizar el viaje: ${e.message ?? e.code}',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        ActiveTripService.cancelarMantenimientoOverlayViaje();
        if (trasConfirmarUltimaParadaMultiparada) {
          _liberarGuardAutoFacturaMultiparada(viajeOperativo.id);
        }
        _actionBusy = false;
        return;
      } catch (e, st) {
        print('[FINALIZAR_ERROR] completarViaje viajeId=${viajeOperativo.id} $e $st');
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('No se pudo finalizar el viaje: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        ActiveTripService.cancelarMantenimientoOverlayViaje();
        if (trasConfirmarUltimaParadaMultiparada) {
          _liberarGuardAutoFacturaMultiparada(viajeOperativo.id);
        }
        _actionBusy = false;
        return;
      }

      print('[FINALIZAR] callable OK → factura (comisión/prepago ya en CF)');

      // Comisión + descuento prepago + asiento + bloqueo operativo los hace
      // completarViajePorTaxista (Admin SDK). NO reintentar PagoData en cliente:
      // billetera/movimientos_prepago están bloqueados por reglas → permission-denied.
      try {
        final doc = await FirebaseFirestore.instance
            .collection('viajes')
            .doc(viajeOperativo.id)
            .get();
        final data = doc.data() ?? {};
        final asentado = data['pagoRegistrado'] == true ||
            _pagoYaAsentadoPorServidor(data);
        if (!asentado) {
          print(
            '[FINALIZAR] aviso: viaje completado sin marca de pago en doc '
            '(CF debió asentar; no se usa PagoData legacy)',
          );
          if (mounted) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Viaje finalizado. La comisión se asienta en servidor; '
                  'si el saldo no baja, contacta soporte.',
                ),
                backgroundColor: Colors.orangeAccent,
                duration: Duration(seconds: 5),
              ),
            );
          }
        } else {
          print('[FINALIZAR] pago/comisión asentados por servidor OK');
        }
      } catch (e, st) {
        await ErrorReporting.reportError(
          e,
          stack: st,
          context: '_finalizarViaje: verificar asiento post-CF',
        );
      }

      _stopGps();

      final Map<String, dynamic>? semillaViaje =
          await FirebaseFirestore.instance
              .collection('viajes')
              .doc(v.id)
              .get()
              .then((DocumentSnapshot<Map<String, dynamic>> s) => s.data());

      print('[FINALIZAR] abriendo factura + post-viaje taxista viajeId=${viajeOperativo.id}');
      await PostViajeTaxistaNav.abrirFacturaYFlujo(
        context: mounted ? context : null,
        viajeId: viajeOperativo.id,
        uidTaxista: uid,
        viajeDataSemilla: semillaViaje,
      );
    } catch (e, st) {
      print('[FINALIZAR] _finalizarViaje catch outer $e $st');
      ActiveTripService.cancelarMantenimientoOverlayViaje();
      if (trasConfirmarUltimaParadaMultiparada) {
        _liberarGuardAutoFacturaMultiparada(v.id);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          messenger
              .showSnackBar(SnackBar(content: Text('❌ ${errorAuthEs(e)}')));
        }
      });
    } finally {
      _actionBusy = false;
    }
  }

  Future<void> _cancelarPorTaxista(Viaje v) async {
    if (_actionBusy) return;
    _actionBusy = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _actionBusy = false;
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    final String estado = EstadosViaje.normalizar(v.estado);
    if (!EstadosViaje.taxistaPuedeCancelarViajeDesdeApp(estado)) {
      _actionBusy = false;
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(EstadosViaje.mensajeNoCancelarViajeTrasAbordarApp),
          ),
        );
      }
      return;
    }

    final confirmar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.black,
            title: const Text('Cancelar viaje',
                style: TextStyle(color: Colors.white)),
            content: const Text(
              'Solo puedes cancelar antes de que el cliente esté a bordo o el viaje esté en ruta. '
              'Si cancelas ahora, el viaje se cancela y el cliente sale de viaje en curso.\n\n'
              'Las cancelaciones frecuentes o sin causa pueden revisarse. '
              '¿Confirmas que deseas cancelar en este punto del servicio?',
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:
                    const Text('No', style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sí, cancelar'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmar) {
      _actionBusy = false;
      return;
    }

    try {
      await ViajesRepo.cancelarPorTaxista(
        viajeId: v.id,
        uidTaxista: uid,
      );
      _stopGps();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                '🚨 Viaje cancelado y limpiado. Ya estás disponible.',
              ),
            ),
          );

          navigator.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const TaxistaShell()),
            (route) => false,
          );
        }
      });
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          String msg = errorAuthEs(e);
          if (e is FirebaseFunctionsException) {
            final m = (e.message ?? '').trim();
            if (m.isNotEmpty) msg = m;
            if (e.code == 'permission-denied') {
              msg = m.isNotEmpty
                  ? m
                  : 'No se pudo cancelar: permiso denegado.';
            } else if (e.code == 'failed-precondition') {
              msg = m.isNotEmpty
                  ? m
                  : 'No se puede cancelar en este estado del viaje.';
            }
          }
          messenger.showSnackBar(SnackBar(content: Text('❌ $msg')));
        }
      });
    } finally {
      _actionBusy = false;
    }
  }

  // ===== Ver información del cliente =====
  Future<void> _verInfoCliente({required String uidCliente}) async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uidCliente)
                  .snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: Colors.greenAccent));
                }

                final u = snap.data?.data() ?? {};
                final nombre = (u['nombre'] ?? '—').toString().trim();
                final telefono = (u['telefono'] ?? '—').toString().trim();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                        child: Container(
                            width: 46,
                            height: 5,
                            decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(3)))),
                    const SizedBox(height: 16),
                    const Text('Información del Cliente',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person,
                                  color: Colors.greenAccent, size: 24),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Nombre',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12)),
                                    Text(nombre,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 18)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.phone,
                                  color: Colors.greenAccent, size: 24),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Teléfono',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12)),
                                    Text(telefono,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 18)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Cerrar'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ===== Contactar encargado / cliente =====
  Future<void> _contactarCliente({
    required String uidCliente,
    required String viajeId,
    Viaje? viaje,
  }) async {
    if (!mounted) return;
    final bool corp = viaje != null
        ? CorporativoPasajerosChoferCard.esViajeCorporativo(viaje)
        : (_cachedViaje != null &&
            CorporativoPasajerosChoferCard.esViajeCorporativo(_cachedViaje!));
    final ColorScheme sheetScheme = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        final ColorScheme cs = Theme.of(sheetCtx).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.40,
          maxChildSize: 0.95,
          builder: (ctx, controller) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(sheetCtx).viewPadding.bottom + 16),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('usuarios')
                    .doc(uidCliente)
                    .snapshots(),
                builder: (ctx2, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: CircularProgressIndicator(color: cs.primary),
                      ),
                    );
                  }

                  final u = snap.data?.data() ?? {};
                  final nombre = (u['nombre'] ?? '—').toString().trim();

                  String telClienteLimpio() =>
                      _cleanPhone(telefonoCrudoDesdeMapa(u));

                  return ListView(
                    controller: controller,
                    children: [
                      Center(
                        child: Container(
                          width: 46,
                          height: 5,
                          decoration: BoxDecoration(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        corp ? 'Contactar encargado' : 'Contactar cliente',
                        style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        corp
                            ? (nombre.isEmpty
                                ? 'Encargado de la empresa'
                                : nombre)
                            : (nombre.isEmpty ? 'Cliente' : nombre),
                        style:
                            TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
                      ),
                      if (viaje != null &&
                          _chatViajeHabilitadoParaTaxista(
                            viaje,
                            EstadosViaje.normalizar(viaje.estado),
                          ) &&
                          FirebaseAuth.instance.currentUser?.uid != null) ...[
                        const SizedBox(height: 12),
                        ViajeChatMensajesEnVivo(
                          viajeId: viajeId,
                          miUid: FirebaseAuth.instance.currentUser!.uid,
                          otroUid: uidCliente,
                          otroNombre: corp
                              ? (nombre.isEmpty ? 'Encargado' : nombre)
                              : (nombre.isEmpty ? 'Cliente' : nombre),
                          esCorporativo: corp,
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () async {
                          final String tel = telClienteLimpio();
                          if (tel.isEmpty) {
                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Número del cliente no disponible aún. Usa el chat o espera unos segundos.',
                                ),
                              ),
                            );
                            return;
                          }
                          unawaited(
                            ViajeComunicacionRepo.notificarIntentoComunicacion(
                              viajeId: viajeId,
                              tipo: 'llamada',
                            ),
                          );
                          await telefonoLaunchUri(telefonoUriLlamada(tel));
                        },
                        icon: Icon(Icons.call, color: cs.onPrimary),
                        label: const Text('Llamar'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final String tel = telClienteLimpio();
                          if (tel.isEmpty) {
                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Número del cliente no disponible aún. Usa el chat o espera unos segundos.',
                                ),
                              ),
                            );
                            return;
                          }
                          unawaited(
                            ViajeComunicacionRepo.notificarIntentoComunicacion(
                              viajeId: viajeId,
                              tipo: 'whatsapp',
                            ),
                          );
                          const String waMsg = 'Hola, soy tu taxista de RAI.';
                          if (await telefonoLaunchUri(
                            telefonoUriWhatsAppApp(tel, waMsg),
                          )) {
                            return;
                          }
                          await telefonoLaunchUri(
                            telefonoUriWhatsAppWeb(tel, waMsg),
                          );
                        },
                        icon:
                            Icon(Icons.chat_bubble_outline, color: cs.primary),
                        label: const Text('WhatsApp'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          Future.microtask(() {
                            if (!mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  otroUid: uidCliente,
                                  otroNombre:
                                      nombre.isEmpty ? 'Cliente' : nombre,
                                  viajeId: viajeId,
                                ),
                              ),
                            );
                          });
                        },
                        icon: Icon(Icons.chat_outlined, color: cs.primary),
                        label: const Text('Chat en la app'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          side: BorderSide(color: cs.outline),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        child:
                            Text('Cerrar', style: TextStyle(color: cs.primary)),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _selectorNavegacionDestino(
    double lat,
    double lon, {
    String titulo = 'Abrir navegación',
    String? addressLine,
    String? footerHint,
    Viaje? viajeParaPersistirDestino,
  }) async {
    if (!mounted) return false;
    if (_selectorNavegacionAbierto) return false;
    _selectorNavegacionAbierto = true;
    var eligioAppExterna = false;
    try {
      if (mounted) setState(() => _viajeSheetOcultoPorModalNav = true);
      try {
        await showNavegacionWazeMapsSheet(
          context,
          title: titulo,
          addressLine: addressLine,
          tieneCoords: true,
          gpsCoordinatesLine:
              'GPS: ${NavegacionExternaLauncher.fmtCoord(lat)}, ${NavegacionExternaLauncher.fmtCoord(lon)}',
          footerHint: footerHint ??
              'Elige Waze o Google Maps. Las coordenadas son el pin exacto del viaje.',
          onWaze: () {
            eligioAppExterna = true;
            unawaited(NavegacionExternaLauncher.abrirWazeDestino(lat, lon));
          },
          onMaps: () {
            eligioAppExterna = true;
            unawaited(
                NavegacionExternaLauncher.abrirGoogleMapsDestino(lat, lon));
          },
        );
      } finally {
        if (mounted) {
          setState(() => _viajeSheetOcultoPorModalNav = false);
        }
      }
    } finally {
      _selectorNavegacionAbierto = false;
    }

    final Viaje? vNav = viajeParaPersistirDestino ?? _cachedViaje;
    if (eligioAppExterna && vNav != null) {
      _marcarNavegacionDestinoLista(vNav);
    }
    return eligioAppExterna;
  }

  String _s(Object? x) => x?.toString() ?? '';

  double? _extraNumero(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw == null) return null;
    return double.tryParse(raw.toString().trim());
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );

  Widget _servicioBadge(Viaje v) {
    Color color;
    IconData icon;
    String label;

    switch (v.tipoServicio) {
      case 'motor':
        color = Colors.orange;
        icon = Icons.two_wheeler;
        label = '🛵 MOTOR';
        break;
      case 'turismo':
        color = Colors.purple;
        icon = Icons.beach_access;
        label = '🏝️ TURISMO';
        break;
      default:
        color = Colors.greenAccent;
        icon = Icons.directions_car;
        label = '🚗 NORMAL';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildWaypoints(Viaje v, {required bool enRuta}) {
    if (v.waypoints == null || v.waypoints!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📍 Paradas intermedias:',
            style: TextStyle(
                color: Colors.orangeAccent, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...v.waypoints!.asMap().entries.map((entry) {
            final index = entry.key + 1;
            final dynamic rawWp = entry.value;
            if (rawWp is! Map) return const SizedBox.shrink();
            final Map<String, dynamic> waypoint =
                Map<String, dynamic>.from(rawWp);
            final label = waypoint['label']?.toString() ?? 'Parada $index';
            final lat = _waypointLat(waypoint);
            final lon = _waypointLon(waypoint);
            final navOk =
                enRuta && lat != null && lon != null && _coordsValid(lat, lon);
            final wLat = lat;
            final wLon = lon;
            return Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.flag_circle,
                      size: 16, color: Colors.orangeAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$index. $label',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  if (navOk &&
                      wLat != null &&
                      wLon != null &&
                      !_esMultiparada(v))
                    IconButton(
                      tooltip: 'Navegar a esta parada',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: () => _selectorNavegacionDestino(wLat, wLon),
                      icon: const Icon(Icons.navigation,
                          size: 20, color: Colors.greenAccent),
                    ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildExtras(Viaje v) {
    if (v.extras == null || v.extras!.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Widget> chips = [];
    final dynamic rawPasajeros = v.extras!['pasajeros'];
    if (rawPasajeros != null) {
      final int? pasajeros = rawPasajeros is num
          ? rawPasajeros.round()
          : int.tryParse(rawPasajeros.toString());
      if (pasajeros != null && pasajeros > 0) {
        chips.add(_chip(
            '👥 $pasajeros pasajero${pasajeros != 1 ? 's' : ''}'));
      }
    }
    final double? peaje = _extraNumero(v.extras!['peaje']);
    if (peaje != null && peaje > 0) {
      chips.add(_chip('💰 Peaje: ${FormatosMoneda.rd(peaje)}'));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        children: chips,
      ),
    );
  }

  Widget _tarjetaVehiculoVisibleAlCliente(Viaje v) {
    final taxistaId = (v.uidTaxista).toString().trim();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: taxistaId.isEmpty
          ? const Stream.empty()
          : FirebaseFirestore.instance
              .collection('usuarios')
              .doc(taxistaId)
              .snapshots(),
      builder: (context, snap) {
        final tx = (snap.hasData && snap.data!.exists)
            ? (snap.data!.data() ?? const {})
            : const {};

        final tipo = _s(v.tipoVehiculo).trim().isNotEmpty
            ? _s(v.tipoVehiculo).trim()
            : _s(tx['tipoVehiculo']).trim();
        final marca = _s((v as dynamic).marca).trim().isNotEmpty
            ? _s((v as dynamic).marca).trim()
            : _s(tx['marca']).trim().isNotEmpty
                ? _s(tx['marca']).trim()
                : _s(tx['vehiculoMarca']).trim();
        final modelo = _s((v as dynamic).modelo).trim().isNotEmpty
            ? _s((v as dynamic).modelo).trim()
            : _s(tx['modelo']).trim().isNotEmpty
                ? _s(tx['modelo']).trim()
                : _s(tx['vehiculoModelo']).trim();
        final color = _s((v as dynamic).color).trim().isNotEmpty
            ? _s((v as dynamic).color).trim()
            : _s(tx['color']).trim().isNotEmpty
                ? _s(tx['color']).trim()
                : _s(tx['vehiculoColor']).trim();
        final placa = _s((v as dynamic).placa).trim().isNotEmpty
            ? _s((v as dynamic).placa).trim()
            : _s(tx['placa']).trim();

        final linea = [
          if (tipo.isNotEmpty) tipo,
          if (marca.isNotEmpty) marca,
          if (modelo.isNotEmpty) modelo,
        ].join(' · ');

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tu vehículo (visible al cliente)',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(linea.isEmpty ? '—' : linea,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Wrap(children: [
                if (color.isNotEmpty) _chip('Color: $color'),
                if (placa.isNotEmpty) _chip('Placa: $placa'),
              ]),
            ],
          ),
        );
      },
    );
  }

  String _labelEstado(String e, {Viaje? viaje}) {
    final s = EstadosViaje.normalizar(e);
    if (s == EstadosViaje.pendiente) return 'Pendiente';
    if (s == EstadosViaje.aceptado) return 'Aceptado';
    if (s == EstadosViaje.enCaminoPickup) return 'Ir a buscar cliente';
    if (s == EstadosViaje.aBordo) return 'Cliente a bordo';
    if (s == EstadosViaje.enOrigenEsperandoCodigo) {
      if (viaje != null &&
          (_corpClienteAbordoConfirmado(viaje) || _corpPinUiActivo)) {
        return 'En empresa — pedir PIN';
      }
      return 'Ir a la empresa';
    }
    if (s == EstadosViaje.pendienteCodigo) return 'Esperando PIN';
    if (s == EstadosViaje.enCurso) return 'En curso';
    if (s == EstadosViaje.completado) return 'Completado';
    if (s == EstadosViaje.cancelado) return 'Cancelado';
    return e;
  }

  int _etapaActualViaje(String estadoBase) {
    if (EstadosViaje.esCompletado(estadoBase)) return 4;
    if (EstadosViaje.esEnCurso(estadoBase)) return 3;
    if (EstadosViaje.esAbordo(estadoBase)) return 2;
    if (EstadosViaje.esEnCaminoPickup(estadoBase) ||
        EstadosViaje.esAceptado(estadoBase)) {
      return 1;
    }
    return 0;
  }

  Widget _estadoProfesionalCard({
    required IconData icon,
    required Color color,
    required String titulo,
    required String detalle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progresoOperativoViaje(String estadoBase) {
    try {
      final int etapa = _etapaActualViaje(estadoBase);
      const labels = <String>[
        'Aceptado',
        'Pickup',
        'A bordo',
        'En ruta',
        'Finalizado',
      ];
      final double progress =
          ((etapa + 1) / labels.length).clamp(0.0, 1.0).toDouble();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Progreso del viaje',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              backgroundColor: Colors.white12,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List<Widget>.generate(labels.length, (i) {
              final bool done = i <= etapa;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: done
                      ? Colors.greenAccent.withValues(alpha: 0.18)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: done
                        ? Colors.greenAccent.withValues(alpha: 0.6)
                        : Colors.white24,
                  ),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    color: done ? Colors.greenAccent : Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }),
          ),
        ],
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  static String _formatDurationHMS(Duration d) {
    if (d.isNegative) return '00:00';
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildDuracionEnRuta(Viaje v, String estadoBase) {
    try {
      if (!EstadosViaje.esEnCurso(estadoBase)) return const SizedBox.shrink();
      final DateTime? start = v.inicioRutaDesde;
      if (start == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: StreamBuilder<DateTime>(
          stream: _duracionEnRutaTicker,
          builder: (BuildContext context, AsyncSnapshot<DateTime> snap) {
            if (snap.hasError) return const SizedBox.shrink();
            try {
              final Duration elapsed = DateTime.now().difference(start);
              return Row(
                children: [
                  const Icon(Icons.schedule, color: Colors.blueAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tiempo en ruta: ${_formatDurationHMS(elapsed)}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                  ),
                ],
              );
            } catch (_) {
              return const SizedBox.shrink();
            }
          },
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildDetallesViajePanel(Viaje v, String estadoBase) {
    try {
      final fecha = _safeFechaViaje(v.fechaHora);
      final total = _safeMoneyViaje(v.precio);
      final bool corp =
          CorporativoPasajerosChoferCard.esViajeCorporativo(v);

      final Widget contenido = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!corp)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '🧭 ${v.origen} → ${v.destino}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: _servicioBadge(v)),
              ],
            ),
          if (!corp) const SizedBox(height: 8),
          Text(
            '🕓 Fecha: $fecha',
            style: const TextStyle(fontSize: 16, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            '💰 Total: $total',
            style: const TextStyle(fontSize: 18, color: Colors.greenAccent),
          ),
          _DesgloseComisionNeto(
            precio: v.precio,
            esCorporativo: corp,
          ),
          const SizedBox(height: 8),
          Text(
            '📍 Estado: ${_labelEstado(estadoBase)}',
            style: const TextStyle(fontSize: 16, color: Colors.white70),
          ),
          const SizedBox(height: 10),
          _progresoOperativoViaje(estadoBase),
          _buildDuracionEnRuta(v, estadoBase),
          if (!corp)
            _buildWaypoints(
              v,
              enRuta: EstadosViaje.esEnCurso(estadoBase),
            ),
          _buildExtras(v),
        ],
      );

      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: contenido,
      );
    } catch (e, st) {
      unawaited(ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: detalles_panel',
      ));
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🧭 ${v.origen} → ${v.destino}',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '📍 Estado: ${_labelEstado(estadoBase)}',
              style: const TextStyle(fontSize: 15, color: Colors.white70),
            ),
          ],
        ),
      );
    }
  }

  void _escucharCancelacionRemota(String viajeId) {
    _cancelSub?.cancel();
    _cancelListenerIniciadoEn = DateTime.now();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final messenger = ScaffoldMessenger.of(context);

    _cancelSub = FirebaseFirestore.instance
        .collection('viajes')
        .doc(viajeId)
        .snapshots()
        .listen((ds) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        _diag('remote snapshot id=$viajeId exists=${ds.exists}');

        if (!ds.exists) {
          if (_procesandoRemocion) return;
          _procesandoRemocion = true;
          final bool ausenciaConfirmada = await _confirmarAusenciaReal(
            viajeId: viajeId,
            uidTaxista: uid,
          );
          _diag('absence check id=$viajeId confirmed=$ausenciaConfirmada');
          _procesandoRemocion = false;
          if (!ausenciaConfirmada) return;
          _stopGps();
          messenger.showSnackBar(
              const SnackBar(content: Text('El viaje ya no está disponible.')));
          await NavigationService.irAlInicioTaxista(context: context);
          return;
        }

        final d = ds.data();
        if (d == null) return;

        final est = (d['estado'] ?? '').toString();
        final estN = EstadosViaje.normalizar(est);
        final taxistaId = (d['taxistaId'] ?? d['uidTaxista'] ?? '').toString();
        final bool teRemovieron =
            uid.isNotEmpty && (taxistaId.isEmpty || taxistaId != uid);
        _diag(
            'state id=$viajeId estado=$estN taxistaDoc=$taxistaId me=$uid teRemovieron=$teRemovieron');

        if (estN == EstadosViaje.cancelado || teRemovieron) {
          // Tras aceptar, el primer snapshot puede llegar sin taxista asignado aún.
          final DateTime? desde = _cancelListenerIniciadoEn;
          if (teRemovieron &&
              estN != EstadosViaje.cancelado &&
              desde != null &&
              DateTime.now().difference(desde) <
                  const Duration(seconds: 5)) {
            return;
          }
          // Evita flicker por estados transitorios/reconciliaciones rápidas.
          if (_procesandoRemocion) return;
          _procesandoRemocion = true;
          final String? motivoConfirmado = await _confirmarRemocionReal(
            viajeId: viajeId,
            uidTaxista: uid,
            snapshotActual: d,
          );
          _diag('removal check id=$viajeId result=$motivoConfirmado');
          _procesandoRemocion = false;
          if (motivoConfirmado == null) return;

          _stopGps();
          if (uid.isNotEmpty) {
            try {
              await FirebaseFirestore.instance
                  .collection('usuarios')
                  .doc(uid)
                  .set({
                'viajeActivoId': '',
                'updatedAt': FieldValue.serverTimestamp(),
                'actualizadoEn': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            } catch (e, st) {
              await ErrorReporting.reportError(
                e,
                stack: st,
                context:
                    'viaje_en_curso_taxista: reset viajeActivoId (removido)',
              );
            }
          }
          final bool esRemocion = motivoConfirmado == 'removido' ||
              (motivoConfirmado != 'cancelado' && teRemovieron);
          messenger.showSnackBar(
            SnackBar(
              content: Text(esRemocion
                  ? 'Fuiste removido del viaje.'
                  : 'El cliente canceló el viaje.'),
            ),
          );
          await NavigationService.irAlInicioTaxista(context: context);
        }
        // Posición del viaje: ya la cubre StreamBuilder + stream deduplicado; evitar setState duplicado aquí.
      });
    }, onError: (e, st) {
      ErrorReporting.reportError(
        e,
        stack: st,
        context: 'viaje_en_curso_taxista: stream listener onError',
      );
    });
  }

  Future<String?> _confirmarRemocionReal({
    required String viajeId,
    required String uidTaxista,
    required Map<String, dynamic> snapshotActual,
  }) async {
    final String estadoNow =
        EstadosViaje.normalizar((snapshotActual['estado'] ?? '').toString());
    final String taxistaNow =
        (snapshotActual['taxistaId'] ?? snapshotActual['uidTaxista'] ?? '')
            .toString();

    if (estadoNow == EstadosViaje.cancelado) {
      _diag('confirmRemocion fast-cancel id=$viajeId');
      return 'cancelado';
    }
    if (uidTaxista.isEmpty) return null;

    // Si aún me pertenece, claramente no está removido.
    if (taxistaNow == uidTaxista) return null;

    try {
      // Pequeño debounce para permitir reconciliaciones rápidas del backend.
      await Future.delayed(const Duration(milliseconds: 700));
      final doc = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get();
      if (!doc.exists) {
        _diag('confirmRemocion doc-missing id=$viajeId');
        return 'removido';
      }
      final data = doc.data() ?? const <String, dynamic>{};
      final String estado =
          EstadosViaje.normalizar((data['estado'] ?? '').toString());
      final String taxista =
          (data['taxistaId'] ?? data['uidTaxista'] ?? '').toString();

      if (estado == EstadosViaje.cancelado) {
        _diag('confirmRemocion server-cancel id=$viajeId');
        return 'cancelado';
      }
      // Solo confirmamos remoción cuando el viaje sigue sin pertenecerme.
      if (taxista.isEmpty || taxista != uidTaxista) {
        _diag(
            'confirmRemocion server-removed id=$viajeId taxista=$taxista me=$uidTaxista');
        return 'removido';
      }
      return null;
    } catch (_) {
      // Si falla verificación remota, no mostramos mensaje agresivo por seguridad UX.
      return null;
    }
  }

  Future<bool> _confirmarAusenciaReal({
    required String viajeId,
    required String uidTaxista,
  }) async {
    try {
      await Future.delayed(const Duration(milliseconds: 700));
      final doc = await FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .get();
      if (!doc.exists) return true;
      final data = doc.data() ?? const <String, dynamic>{};
      final String estado =
          EstadosViaje.normalizar((data['estado'] ?? '').toString());
      final String taxista =
          (data['taxistaId'] ?? data['uidTaxista'] ?? '').toString();
      if (estado == EstadosViaje.cancelado) return true;
      return taxista.isEmpty ||
          (uidTaxista.isNotEmpty && taxista != uidTaxista);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: RaiViajeEnCursoUi.scaffoldBg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: RaiViajeEnCursoUi.scaffoldBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: _flygoSimCasa
            ? GestureDetector(
                onDoubleTap: () {
                  final v = _cachedViaje;
                  if (v == null || !mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '[SIM CASA] Doble tap en título → finalizar (mismo que el botón)',
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  unawaited(_finalizarViaje(v));
                },
                child: const Text(
                  'Mi viaje en curso',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : const Text(
                'Mi viaje en curso',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
        actions: [
          ViajesCercanosTaxistaAppBarAction(
            controller: _viajesCercanosCtl,
            escuchaActiva: _viajesCercanosEscucha,
            referenciaOrdenCola: _colaReferenciaOrden,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: StreamBuilder<Viaje?>(
              stream: _viajeEnCursoStream ?? const Stream<Viaje?>.empty(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    _cachedViaje == null) {
                  _scheduleSyncEsperaCargaViaje(true);
                  return _buildCargandoViajeOError();
                }

                Viaje? v = snap.hasData ? snap.data : null;
                if (v != null && _esCorpInformativoExcluido(v)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) unawaited(_limpiarCorpDeViajeEnCursoAlEntrar());
                  });
                  v = null;
                }
                if (v == null &&
                    (snap.connectionState == ConnectionState.waiting ||
                        ActiveTripService.debeBloquearShellSinViajeTaxista ||
                        ActiveTripService.debeMantenerOverlayViajeEnShell ||
                        _cachedViaje != null)) {
                  final Viaje? cache = _cachedViaje;
                  if (cache != null && !_esCorpInformativoExcluido(cache)) {
                    v = cache;
                  }
                  if (snap.hasData &&
                      snap.data == null &&
                      _cachedViaje != null &&
                      v == null) {
                    _programarConfirmacionViajeNull();
                  }
                }

                if (snap.hasError) {
                  if (v != null) {
                    final fecha = _safeFechaViaje(v.fechaHora);
                    final total = _safeMoneyViaje(v.precio);
                    final estadoBase = EstadosViaje.normalizar(
                      v.estado.isNotEmpty
                          ? v.estado
                          : (v.completado
                              ? EstadosViaje.completado
                              : (v.aceptado
                                  ? EstadosViaje.aceptado
                                  : EstadosViaje.pendiente)),
                    );
                    return Column(
                      children: [
                        Expanded(
                          flex: RaiViajeEnCursoUi.mapFlex,
                          child: RepaintBoundary(
                            child: _mapaOPlaceholder(
                              mapa: const MapaTiempoReal(
                                key: ValueKey<String>('mapa-cache-viaje'),
                                esTaxista: true,
                                esCliente: false,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: RaiViajeEnCursoUi.panelFlex,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('🧭 ${v.origen} → ${v.destino}',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Text('🕓 Fecha: $fecha',
                                    style: const TextStyle(
                                        fontSize: 16, color: Colors.white70)),
                                const SizedBox(height: 8),
                                Text('💰 Total: $total',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        color: Colors.greenAccent)),
                                // Desglose informativo (solo lectura, no
                                // modifica el cálculo): comisión RAI y neto.
                                _DesgloseComisionNeto(
              precio: v.precio,
              esCorporativo:
                  CorporativoPasajerosChoferCard.esViajeCorporativo(v),
            ),
                                const SizedBox(height: 8),
                                Text('📍 Estado: ${_labelEstado(estadoBase)}',
                                    style: const TextStyle(
                                        fontSize: 16, color: Colors.white70)),
                                const SizedBox(height: 12),
                                const Text(
                                  'Reconectando viaje en tiempo real...',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                  }
                  _scheduleSyncEsperaCargaViaje(true);
                  return _buildCargandoViajeOError();
                }

                if (v == null) {
                  _cancelarDebounceViajeNull();
                  _navPickupPrefsLoadedForId = null;
                  _distanciaMetrosAlDestino = null;
                  _stopGps();
                  if (ActiveTripService.debeBloquearShellSinViajeTaxista ||
                      ActiveTripService.debeMantenerOverlayViajeEnShell) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) unawaited(_salirSiSoloCorpInformativo());
                    });
                    _scheduleSyncEsperaCargaViaje(true);
                    return _buildCargandoViajeOError();
                  }
                  _cachedViaje = null;
                  _scheduleSyncEsperaCargaViaje(false);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ActiveTripService.cancelarMantenimientoOverlayViaje();
                    ActiveTripService.cancelarBloqueoShellTaxista();
                    ActiveTripService.notificarRebuildShell();
                  });
                  return Column(
                    children: [
                      Expanded(
                        flex: RaiViajeEnCursoUi.mapFlex,
                        child: RepaintBoundary(
                          child: _mapaOPlaceholder(
                            mapa: const MapaTiempoReal(
                              key: ValueKey<String>('mapa-sin-viaje'),
                              esTaxista: true,
                              esCliente: false,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: RaiViajeEnCursoUi.panelFlex,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                const Icon(
                                  Icons.taxi_alert,
                                  color: Colors.greenAccent,
                                  size: 60,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No tienes viaje en curso',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Puedes buscar viajes disponibles\nen el botón verde',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    ActiveTripService
                                        .cancelarMantenimientoOverlayViaje();
                                    Navigator.of(context, rootNavigator: true)
                                        .pushAndRemoveUntil(
                                      MaterialPageRoute<void>(
                                          builder: (_) => const TaxistaShell()),
                                      (route) => false,
                                    );
                                  },
                                  icon: const Icon(Icons.search),
                                  label: const Text('Buscar viajes'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.greenAccent,
                                    foregroundColor: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                }

                _cancelarDebounceViajeNull();
                _scheduleSyncEsperaCargaViaje(false);

                if (_esCorpInformativoExcluido(v)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) unawaited(_limpiarCorpDeViajeEnCursoAlEntrar());
                  });
                  _scheduleSyncEsperaCargaViaje(false);
                  return _buildCargandoViajeOError();
                }

                final viaje = v;

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final bool escucharPendientes = (() {
                    final String est = EstadosViaje.normalizar(
                      viaje.estado.isNotEmpty
                          ? viaje.estado
                          : (viaje.completado
                              ? EstadosViaje.completado
                              : (viaje.aceptado
                                  ? EstadosViaje.aceptado
                                  : EstadosViaje.pendiente)),
                    );
                    return EstadosViaje.esActivo(est);
                  })();
                  if (_viajesCercanosEscucha.value != escucharPendientes) {
                    _viajesCercanosEscucha.value = escucharPendientes;
                    if (!escucharPendientes) {
                      _viajesCercanosCtl.resetListeningUi();
                    }
                  }
                  _sincronizarReferenciaOrdenCola(viaje);
                });

                // Actualizar cache
                if (_cachedViaje?.id != viaje.id) {
                  _navPickupPrefsLoadedForId = null;
                  _navDestinoPrefsLoadedForId = null;
                  _navegacionIniciada = false;
                  _navegacionDestinoIniciada = false;
                  _distanciaMetrosAlDestino = null;
                  _distanciaDestinoNotifier.value = null;
                  _viajesCercanosCtl.resetSugerenciaEncadenar();
                  _viajesCercanosCtl.setEncoladoId(null);
                  _viajesCercanosCtl.resetListeningUi();
                  _codigoCtrl.clear();
                  _clienteCerca = false;
                  _multiLegCompletadas = 0;
                  _multiNavViajeId = null;
                  _multiparadaAutoFacturaViajeId = null;
                  _corpPinUiActivo = false;
                  _corpPinSheetExpandido = false;
                  final Viaje? prevCache = _cachedViaje;
                  _cachedViaje = viaje;
                  _notificarCambioPasajerosCorpSiCorresponde(prevCache, viaje);
                  _aplicarProgresoMultiparadaDesdeViaje(viaje);
                  _programarAutoFacturaMultiparadaSiCorresponde(viaje);
                  _asegurarChatCorporativo(viaje);
                  _escucharCancelacionRemota(viaje.id);
                  unawaited(_syncCorpCodigoLive(viaje.id));
                  unawaited(_notificarEncadenadoSiCorresponde(viaje.id));

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _asegurarGps(viaje.id).then((_) {
                      if (mounted) {
                        _scheduleDrawRoute();
                      }
                    });
                  });
                } else {
                  final Viaje? prevCache = _cachedViaje;
                  final String prevSig = prevCache != null
                      ? _firmaRutaMapaTaxista(prevCache)
                      : '';
                  _cachedViaje = viaje;
                  _notificarCambioPasajerosCorpSiCorresponde(prevCache, viaje);
                  _aplicarProgresoMultiparadaDesdeViaje(viaje);
                  _programarAutoFacturaMultiparadaSiCorresponde(viaje);
                  _asegurarChatCorporativo(viaje);
                  unawaited(_syncCorpCodigoLive(viaje.id));
                  final String newSig = _firmaRutaMapaTaxista(viaje);
                  if (prevSig != newSig && mounted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _scheduleDrawRoute();
                    });
                  }
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    unawaited(_loadNavPickupPrefs(viaje));
                    unawaited(_loadNavDestinoPrefs(viaje));
                  }
                  _recalcDistanciaDestino();
                  _sincronizarReferenciaOrdenCola(viaje);
                });

                final estadoBase = _estadoBaseViaje(viaje);

                if (estadoBase == EstadosViaje.cancelado) {
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    unawaited(_persistNavPickupFlag(viaje.id, false));
                    _stopGps();
                    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                    if (uid.isNotEmpty) {
                      try {
                        await FirebaseFirestore.instance
                            .collection('usuarios')
                            .doc(uid)
                            .set({
                          'viajeActivoId': '',
                          'updatedAt': FieldValue.serverTimestamp(),
                          'actualizadoEn': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                      } catch (e, st) {
                        await ErrorReporting.reportError(
                          e,
                          stack: st,
                          context:
                              'viaje_en_curso_taxista: set viajeActivoId (cancelado)',
                        );
                      }
                    }
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('El cliente canceló el viaje.'),
                        duration: Duration(seconds: 4),
                      ),
                    );
                    await NavigationService.irAlInicioTaxista(context: context);
                  });
                  return const SizedBox.shrink();
                }

                // Pins origen/destino siempre (aunque la ruta Directions aún no llegó).
                final LatLng? puntoOrigen =
                    _coordsValid(viaje.latCliente, viaje.lonCliente)
                        ? LatLng(viaje.latCliente, viaje.lonCliente)
                        : null;

                final LatLng? puntoDestino =
                    _coordsValid(viaje.latDestino, viaje.lonDestino)
                        ? LatLng(viaje.latDestino, viaje.lonDestino)
                        : null;

                final bool esCorpMapa =
                    CorporativoPasajerosChoferCard.esViajeCorporativo(viaje);
                if (esCorpMapa) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) unawaited(_limpiarCorpDeViajeEnCursoAlEntrar());
                  });
                  return const SizedBox.shrink();
                }
                final bool mostrarPinCorp =
                    _corpDebeMostrarPanelPin(viaje, estadoBase);
                if (_viajeSheetAseguradoParaId != viaje.id) {
                  _viajeSheetAseguradoParaId = viaje.id;
                  _asegurarSheetExpandido(forzar: true);
                } else if (mostrarPinCorp && !_corpPinSheetExpandido) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _expandirSheetParaPinCorp();
                  });
                }
                if (viaje.codigoVerificado && _corpPinUiActivo) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _corpPinUiActivo = false;
                        _corpPinSheetExpandido = false;
                      });
                    }
                  });
                }
                final Set<Marker> pinsViaje = _corpMapMarkers.isNotEmpty
                    ? _corpMapMarkers
                    : (esCorpMapa
                        ? _buildCorpParadaMarkersSync(viaje)
                        : _buildTripPointMarkers(viaje));
                final String? orientacionMapa = esCorpMapa
                    ? null
                    : _mensajeOrientacionFlujo(viaje, estadoBase);

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: _mapaOPlaceholder(
                          mapa: MapaTiempoReal(
                          key: ValueKey<String>('mapa-${viaje.id}'),
                          origen: puntoOrigen,
                          origenNombre: viaje.origen,
                          destino: puntoDestino,
                          destinoNombre: viaje.destino,
                          mostrarOrigen: false,
                          mostrarDestino: false,
                          esTaxista: true,
                          esCliente: false,
                          mostrarTaxista: false,
                          ubicacionTaxista:
                              _coordsValid(viaje.latTaxista, viaje.lonTaxista)
                                  ? LatLng(viaje.latTaxista, viaje.lonTaxista)
                                  : null,
                          overlayPolylines: _polylines,
                          overlayMarkers: pinsViaje,
                          onUserInteractWithMap: _colapsarViajeSheetPorMapa,
                          onUserMapGestureEnd: _expandirViajeSheetTrasMapa,
                          suprimirBannerUbicacionLocal: true,
                        ),
                        ),
                      ),
                    ),
                    if (orientacionMapa != null || _mostrarAlertaUbicacionEnViaje)
                      Positioned(
                        top: MediaQuery.paddingOf(context).top + 8,
                        left: 12,
                        right: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (orientacionMapa != null)
                              ViajeFlujoOrientacionBanner(
                                mensaje: orientacionMapa,
                              ),
                            if (orientacionMapa != null &&
                                _mostrarAlertaUbicacionEnViaje)
                              const SizedBox(height: 8),
                            if (_mostrarAlertaUbicacionEnViaje)
                              _buildAlertaUbicacionViaje(mapFloating: true),
                          ],
                        ),
                      ),
                    if (!_viajeSheetOcultoPorModalNav)
                      _buildViajeDraggableSheet(
                        context: context,
                        viaje: viaje,
                        estadoBase: estadoBase,
                        esCorpMapa: esCorpMapa,
                        mostrarPinCorp: mostrarPinCorp,
                        uid: FirebaseAuth.instance.currentUser?.uid,
                      ),
                  ],
                );
              },
            ),
          ),
          ViajesCercanosTaxistaLayer(
            controller: _viajesCercanosCtl,
            escuchaActiva: _viajesCercanosEscucha,
            referenciaOrdenCola: _colaReferenciaOrden,
          ),
          ViajesCercanosTaxistaEncadenarSugerencia(
            controller: _viajesCercanosCtl,
            escuchaActiva: _viajesCercanosEscucha,
            referenciaOrdenCola: _colaReferenciaOrden,
            distanciaAlDestinoMetros: _distanciaDestinoNotifier,
          ),
        ],
      ),
    );
  }

  String? _mensajeOrientacionFlujo(Viaje v, String estadoBase) =>
      viajeFlujoOrientacionMensajeTaxista(
        estadoBase: estadoBase,
        navegacionPickupIniciada: _navegacionIniciada,
        navegacionDestinoIniciada: _navegacionDestinoIniciada,
        codigoVerificado: v.codigoVerificado,
        esMultiparada: _esMultiparada(v),
        multiparadaRutaCompleta: _multiparadaRutaCompleta(v),
        esCorporativo: CorporativoPasajerosChoferCard.esViajeCorporativo(v),
      );

  Future<void> _notificarEncadenadoSiCorresponde(String viajeId) async {
    if (!mounted || _ultimoSnackEncadenadoViajeId == viajeId) return;
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance.collection('viajes').doc(viajeId).get();
      if (!snap.exists || !mounted) return;
      final Map<String, dynamic> d = snap.data() ?? <String, dynamic>{};
      if (d['promovidoDesdeCola'] != true) return;
      _ultimoSnackEncadenadoViajeId = viajeId;
      final String metodo = (d['metodoPago'] ?? '').toString().trim();
      final String pago = metodo.isNotEmpty
          ? MetodoPagoViaje.etiquetaDocumento(metodo)
          : 'forma de pago';
      _tripFlowSnack(
        'Siguiente recogida conectada · Revisá $pago y pedí el PIN al abordar.',
        backgroundColor: const Color(0xFFFFB020),
      );
      if (_viajeSheetCtrl.isAttached) {
        unawaited(
          _viajeSheetCtrl.animateTo(
            _kViajeSheetPin,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    } catch (_) {}
  }

  void _notificarCambioPasajerosCorpSiCorresponde(Viaje? prev, Viaje next) {
    if (!mounted || prev == null) return;
    if (!CorporativoPasajerosChoferCard.esViajeCorporativo(next)) return;
    final String firmaPrev = _firmaPasajerosCorpTaxista(prev);
    final String firmaNext = _firmaPasajerosCorpTaxista(next);
    if (firmaPrev == firmaNext) return;
    final int prevN =
        CorporativoPasajerosChoferCard.pasajerosDesdeViaje(prev).length;
    final int nextN =
        CorporativoPasajerosChoferCard.pasajerosDesdeViaje(next).length;
    final String msg = nextN > prevN
        ? 'Ruta actualizada en tiempo real: ahora $nextN pasajero(s).'
        : nextN < prevN
            ? 'Ruta actualizada: quedan $nextN pasajero(s) activo(s).'
            : 'Paradas de la ruta actualizadas.';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tripFlowSnack(msg, backgroundColor: Colors.lightBlueAccent);
      _scheduleDrawRoute();
      _recalcDistanciaDestino();
    });
  }

  // ==================== BARRA DE ACCIONES ====================

  Widget _actionBar(Viaje v, String estadoBase) {
    estadoBase = _estadoBaseViaje(v);
    final bool corp = CorporativoPasajerosChoferCard.esViajeCorporativo(v);
    final bool compactoPickup = _esPickupClienteSheetCompacto(v, estadoBase);
    final String? orientacion = corp || compactoPickup
        ? null
        : _mensajeOrientacionFlujo(v, estadoBase);
    final List<Widget> buttons = _getActionButtons(v, estadoBase);
    if (orientacion == null && buttons.isEmpty) {
      return const SizedBox.shrink();
    }
    final Widget contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (orientacion != null) ...<Widget>[
          ViajeFlujoOrientacionBanner(mensaje: orientacion),
          const SizedBox(height: 12),
        ],
        ...buttons,
      ],
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RaiViajeEnCursoUi.actionPanelBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: RaiDsColors.border),
      ),
      child: corp
          ? contenido
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (Widget? currentChild,
                      List<Widget> previousChildren) =>
                  currentChild ?? const SizedBox.shrink(),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: KeyedSubtree(
                key: ValueKey<String>(
                  '$estadoBase|${_navegacionIniciada ? 1 : 0}|${_navegacionDestinoIniciada ? 1 : 0}|${_clienteCerca ? 1 : 0}|${v.codigoVerificado ? 1 : 0}|${orientacion ?? ''}',
                ),
                child: contenido,
              ),
            ),
    );
  }

  Widget _buildCorporativoPinIngresoPanel(Viaje v) {
    final uidCli = _uidClienteDe(v);
    return Container(
      key: const ValueKey<String>('corp_pin_ingreso_panel'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF5EEAD4).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pin_rounded, color: Color(0xFF5EEAD4), size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Paso 3 — Código con los pasajeros',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Pedí el PIN de 6 dígitos del período a los empleados o al encargado. '
            'Tenés hasta ${CorporativoEsperaCodigoConstants.timeoutMinutos} min '
            'desde la hora de recogida.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: Text(
                  'Intentos: ${_corpIntentosFallidos.clamp(0, 3)}/3',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _corpIntentosFallidos >= 2
                        ? Colors.redAccent
                        : Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Tiempo: ${_formatoTiempoRestante(_corpTiempoRestanteCodigo)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codigoCtrl,
            focusNode: _corpPinFocusNode,
            autofocus: false,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              letterSpacing: 8,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            onSubmitted: (_) =>
                _verificarCodigo(v.id, v.codigoVerificacion ?? ''),
            decoration: InputDecoration(
              hintText: '000000',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 32,
                letterSpacing: 8,
              ),
              filled: true,
              fillColor: Colors.grey[900],
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: Color(0xFF5EEAD4)),
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: Color(0xFF5EEAD4)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: Color(0xFF5EEAD4), width: 2),
              ),
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 14),
          _btnPrimario(
            icon: const Icon(Icons.verified, size: 24),
            label: const Text(
              'VERIFICAR E INICIAR RUTA',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            onPressed: _actionBusy
                ? null
                : () => _verificarCodigo(v.id, v.codigoVerificacion ?? ''),
            backgroundColor: Colors.orange,
          ),
          const SizedBox(height: 10),
          _btnSecundario(
            icon: const Icon(Icons.help_outline, size: 20),
            label: const Text('No tengo código'),
            onPressed:
                _actionBusy ? null : () => _solicitarCodigoCorpEncargado(v),
          ),
          if (uidCli.isNotEmpty) ...[
            const SizedBox(height: 8),
            _btnSecundario(
              icon: const Icon(Icons.chat, size: 20),
              label: Text(_labelContactar(v)),
              onPressed: () => _contactarCliente(
                uidCliente: uidCli,
                viajeId: v.id,
                viaje: v,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _onNavegacionExternaDesdeCardCorp(Viaje v) {
    if (!mounted) return;
    final estadoBase = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado
              ? EstadosViaje.completado
              : (v.aceptado
                  ? EstadosViaje.aceptado
                  : EstadosViaje.pendiente)),
    );
    if (_corpMostrarNavPickup(v, estadoBase)) {
      unawaited(_persistNavPickupFlag(v.id, true));
      setState(() => _navegacionIniciada = true);
      return;
    }
    if (_corpMostrarNavDestino(v, estadoBase)) {
      _marcarNavegacionDestinoLista(v);
    }
  }

  Future<void> _corpIniciarRutaAlDestino(Viaje v) async {
    if (_actionBusy || _selectorNavegacionAbierto) return;
    _actionBusy = true;
    try {
      await _corpAsegurarViajeEnCurso(v);
      if (!mounted) return;
      final operativo = await _corpRefrescarViajeDesdeFirestore(v.id) ?? v;
      final abierto = await _corpAbrirNavegacionDestinoActual(operativo);
      if (!mounted) return;
      if (!abierto) {
        _tripFlowSnack(
          'Ruta iniciada. Tocá Maps/Waze arriba o «Navegar a parada».',
          backgroundColor: Colors.green.shade800,
        );
      } else if (_permitePruebaSinRecorrido(operativo)) {
        _tripFlowSnack(
          'Ruta iniciada. En modo prueba podés finalizar sin recorrer km.',
          backgroundColor: Colors.green.shade800,
        );
      }
      _expandirViajeSheetTrasMapa();
    } finally {
      if (mounted) _actionBusy = false;
    }
  }

  List<Widget> _botonesCorpTrasCodigo(
    Viaje v,
    String estadoBase,
    String uidCli,
  ) {
    final bool multi = _esMultiparada(v);
    final bool multiCompleta = multi && _multiparadaRutaCompleta(v);
    final bool rutaIniciada = _navegacionDestinoIniciada ||
        EstadosViaje.esEnCurso(estadoBase) ||
        (multi && _multiLegCompletadas > 0);

    return [
      _estadoProfesionalCard(
        icon: multiCompleta
            ? Icons.flag_rounded
            : Icons.task_alt_rounded,
        color: multiCompleta ? Colors.lightBlueAccent : Colors.greenAccent,
        titulo: multiCompleta
            ? 'Paso actual: todas las paradas hechas'
            : rutaIniciada && multi
                ? 'Paso actual: ruta en curso'
                : 'Paso actual: código verificado',
        detalle: multiCompleta
            ? 'Finalizá el viaje para cerrar la ruta corporativa.'
            : rutaIniciada && multi
                ? 'Confirmá cada parada o navegá con Maps/Waze.'
                : multi
                    ? 'Siguiente: iniciar ruta y dejar pasajeros uno a uno.'
                    : 'Siguiente: abrir navegación al destino y conducir.',
      ),
      const SizedBox(height: 12),
      Text(
        multiCompleta ? 'Ruta multiparada completa' : 'Código verificado',
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      Text(
        multiCompleta
            ? 'Todas las paradas quedaron confirmadas. Tocá «Finalizar viaje».'
            : rutaIniciada && multi
                ? 'Seguí las paradas abajo: Waze/Maps y confirmá con ✓.'
                : multi
                    ? 'Tocá una parada abajo, abrí Waze o Maps y confirmá con ✓.'
                    : 'El código quedó verificado. Abrí Maps o Waze arriba o tocá «Iniciar ruta».',
        style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.35),
      ),
      const SizedBox(height: 16),
      if (!multiCompleta && !rutaIniciada)
        _btnPrimario(
          icon: const Icon(Icons.play_arrow, size: 24),
          label: const Text('Iniciar ruta al destino',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          onPressed: () => unawaited(_corpIniciarRutaAlDestino(v)),
        ),
      if (multi) ...[
        if (!multiCompleta && !rutaIniciada) const SizedBox(height: 12),
        ..._bloqueNavegacionMultiparada(
          v,
          habilitado: _multiparadaNavegacionInteractiva(v, estadoBase),
        ),
      ],
      if (multiCompleta ||
          (!multi && _corpMostrarBotonFinalizar(v, estadoBase))) ...[
        const SizedBox(height: 12),
        if (multiCompleta)
          Text(
            'Todas las paradas confirmadas. Ya podés cerrar el viaje.',
            style: TextStyle(
              color: Colors.greenAccent.withValues(alpha: 0.95),
              fontSize: 12.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Text(
            'Si ya estás en destino, podés finalizar cuando corresponda.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        const SizedBox(height: 12),
        _btnFinalizarViaje(
          onPressed: _puedePulsarFinalizarViaje(v)
              ? () => _finalizarViaje(v)
              : null,
          label: _labelFinalizarViaje(v),
        ),
      ] else if (multi) ...[
        const SizedBox(height: 8),
        Text(
          'Tras «Iniciar ruta», tocá cada parada → Waze → ✓.',
          style: TextStyle(
            color: Colors.orangeAccent.withValues(alpha: 0.95),
            fontSize: 12.5,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ];
  }

  List<Widget> _getActionButtonsPickupCompact(Viaje v, String uidCli) {
    return <Widget>[
      if (!_navegacionIniciada)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _iniciarNavegacionPickup(v),
            icon: const Icon(Icons.navigation, size: 24),
            label: const Text(
              'Navegar hacia el cliente',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        )
      else
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _marcarClienteAbordo(v),
            icon: const Icon(Icons.person_add, size: 24),
            label: const Text(
              'Cliente a bordo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      if (_permitePruebaSinRecorrido(v)) ...<Widget>[
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _actionBusy
                ? null
                : () async {
                    unawaited(_persistNavPickupFlag(v.id, true));
                    if (!_navegacionIniciada) {
                      setState(() => _navegacionIniciada = true);
                      _tripFlowSnack(
                        'Punto marcado. Siguiente: «Cliente a bordo».',
                        backgroundColor: Colors.teal.shade800,
                      );
                    } else {
                      await _marcarClienteAbordo(v);
                    }
                  },
            icon: const Icon(Icons.check_circle_outline_rounded, size: 22),
            label: Text(
              _navegacionIniciada
                  ? 'Llegué — mostrar código (prueba)'
                  : 'Llegué al punto (prueba en casa)',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.tealAccent,
              side: BorderSide(color: Colors.tealAccent.withValues(alpha: 0.55)),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _cancelarPorTaxista(v),
          icon: const Icon(Icons.cancel_outlined, size: 20),
          label: const Text('Cancelar viaje', style: TextStyle(fontSize: 15)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
            foregroundColor: Colors.redAccent,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _getActionButtons(Viaje v, String estadoBase) {
    estadoBase = _estadoBaseViaje(v);
    final uidCli = _uidClienteDe(v);

    // Corporativo fijo → pantalla informativa (Mis rutas), no mezclar con turismo/pool.
    if (_esViajeCorporativo(v)) {
      return [
        _estadoProfesionalCard(
          icon: Icons.alt_route,
          color: const Color(0xFF5EEAD4),
          titulo: 'Ruta corporativa',
          detalle:
              'No va en «Viaje en curso». Entrá por Mi trabajo → '
              'Rutas corporativas.',
        ),
        const SizedBox(height: 12),
        _btnPrimario(
          icon: const Icon(Icons.home_rounded, size: 24),
          label: const Text(
            'Volver a Mi trabajo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          onPressed: _actionBusy
              ? null
              : () {
                  unawaited(_limpiarCorpDeViajeEnCursoAlEntrar());
                  unawaited(NavigationService.irAlInicioTaxista(context: context));
                },
        ),
      ];
    }

    if (EstadosViaje.esAceptado(estadoBase) ||
        EstadosViaje.esEnCaminoPickup(estadoBase) ||
        _corpEnFasePickup(v, estadoBase)) {
      final bool corp = CorporativoPasajerosChoferCard.esViajeCorporativo(v);
      if (!corp && _esPickupClienteSheetCompacto(v, estadoBase)) {
        return _getActionButtonsPickupCompact(v, uidCli);
      }
      return [
        if (!corp) ...[
          _estadoProfesionalCard(
            icon: Icons.directions_car_filled_rounded,
            color: Colors.lightBlueAccent,
            titulo: 'Paso actual: ir al punto de recogida',
            detalle: _navegacionIniciada
                ? 'Siguiente acción: confirmar "Cliente a bordo" y el código.'
                : 'Primero abre Waze/Maps con «Navegar hacia el cliente».',
          ),
          const SizedBox(height: 12),
          Text(
            'Paso 1: ve al cliente · Paso 2: confirma abordo · Paso 3: código que te dicta · Paso 4: navegas al destino',
            style: const TextStyle(
                color: Colors.white60, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📍 Punto de recogida del cliente',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  v.origen,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (uidCli.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ClientePerfilConductorChip(
                      uidCliente: uidCli,
                    ),
                  ),
                ],
                if (_clienteCerca) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.green, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Estás cerca del punto de recogida.',
                            style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ] else if (_clienteCerca) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.location_on, color: Colors.greenAccent, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cerca de la empresa',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (corp) ...[
          if (_corpSinPin(v)) ...[
            Text(
              'Esta ruta usa la pantalla de destinos (sin código de verificación).',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _actionBusy
                    ? null
                    : () {
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid == null) return;
                        unawaited(
                          NavigationService.abrirViajeCorporativoTaxista(
                            uidTaxista: uid,
                            viajeId: v.id,
                          ),
                        );
                      },
                icon: const Icon(Icons.map_rounded, size: 24),
                label: const Text(
                  'Abrir ruta y destinos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ] else ...[
          if (!_navegacionIniciada) ...[
            Text(
              'Paso 1: abrí Maps o Waze arriba para ir a la empresa.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_navegacionIniciada && !_actionBusy)
                  ? () => _marcarClienteAbordo(v)
                  : null,
              icon: const Icon(Icons.person_add, size: 24),
              label: const Text(
                'Cliente a bordo (paso 2)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade800,
                disabledForegroundColor: Colors.white38,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          if (!_navegacionIniciada) ...[
            const SizedBox(height: 8),
            Text(
              'Este botón se activa al volver de Maps o Waze.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
          if (_permitePruebaSinRecorrido(v)) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _actionBusy
                    ? null
                    : () async {
                        unawaited(_persistNavPickupFlag(v.id, true));
                        await _marcarClienteAbordo(v);
                      },
                icon: const Icon(Icons.check_circle_outline_rounded, size: 22),
                label: const Text('Llegué — mostrar código (prueba)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.tealAccent,
                  side: BorderSide(
                      color: Colors.tealAccent.withValues(alpha: 0.55)),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
          ],
        ] else if (!_navegacionIniciada) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _iniciarNavegacionPickup(v),
              icon: const Icon(Icons.navigation, size: 24),
              label: const Text(
                'Navegar hacia el cliente',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          if (_permitePruebaSinRecorrido(v)) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _actionBusy
                    ? null
                    : () async {
                        unawaited(_persistNavPickupFlag(v.id, true));
                        setState(() => _navegacionIniciada = true);
                        _tripFlowSnack(
                          'Punto marcado. Siguiente: «Cliente a bordo (paso 2)».',
                          backgroundColor: Colors.teal.shade800,
                        );
                      },
                icon: const Icon(Icons.check_circle_outline_rounded, size: 22),
                label: const Text('Llegué al punto (prueba en casa)'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.tealAccent,
                  side: BorderSide(
                      color: Colors.tealAccent.withValues(alpha: 0.55)),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _marcarClienteAbordo(v),
              icon: const Icon(Icons.person_add, size: 24),
              label: const Text(
                'Cliente a bordo (paso 2)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
        if (!corp) ...[
          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: uidCli.isEmpty
                      ? null
                      : () => _verInfoCliente(uidCliente: uidCli),
                  icon: const Icon(Icons.person, size: 18),
                  label: Text(_labelVerOtro(v)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: uidCli.isEmpty
                      ? null
                      : () =>
                          _contactarCliente(
                              uidCliente: uidCli, viajeId: v.id, viaje: v),
                  icon: const Icon(Icons.chat, size: 18),
                  label: Text(_labelContactar(v)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ] else
          const SizedBox(height: 8),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _corpEnFasePickup(v, estadoBase) ? () => _cancelarPorTaxista(v) : null,
            icon: const Icon(Icons.cancel_outlined, size: 20),
            label: const Text('Cancelar viaje', style: TextStyle(fontSize: 15)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ];
    }

    if (EstadosViaje.esAbordo(estadoBase) ||
        (CorporativoPasajerosChoferCard.esViajeCorporativo(v) &&
            !_corpRutaOperativa(v) &&
            _corpClienteAbordoConfirmado(v) &&
            (estadoBase == EstadosViaje.enOrigenEsperandoCodigo ||
                estadoBase == EstadosViaje.pendienteCodigo ||
                EstadosViaje.esEnCurso(estadoBase)))) {
      final bool corpPin = CorporativoPasajerosChoferCard.esViajeCorporativo(v);
      if (corpPin && _corpSinPin(v)) {
        return [
          _estadoProfesionalCard(
            icon: Icons.route_rounded,
            color: const Color(0xFF5EEAD4),
            titulo: 'Ruta corporativa',
            detalle:
                'Sin código de verificación: usá la pantalla de destinos.',
          ),
          const SizedBox(height: 12),
          _btnPrimario(
            icon: const Icon(Icons.map_rounded, size: 24),
            label: const Text(
              'Abrir ruta y destinos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            onPressed: _actionBusy
                ? null
                : () {
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid == null) return;
                    unawaited(
                      NavigationService.abrirViajeCorporativoTaxista(
                        uidTaxista: uid,
                        viajeId: v.id,
                      ),
                    );
                  },
          ),
        ];
      }
      if (!corpPin && !_codigoEsperadoValido(v.codigoVerificacion)) {
        return [
          _estadoProfesionalCard(
            icon: Icons.warning_amber_rounded,
            color: Colors.orangeAccent,
            titulo: 'Paso actual: validar código de inicio',
            detalle:
                'No hay PIN válido en el viaje; contacta soporte antes de continuar.',
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.55)),
            ),
            child: const Text(
              'Este viaje no tiene un código de verificación válido en el sistema. '
              'Contacta soporte o cancela para que el cliente pueda solicitar un viaje nuevo.',
              style: TextStyle(color: Colors.white70, height: 1.35),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _btnSecundario(
                icon: const Icon(Icons.person, size: 20),
                label: Text(_labelVerOtro(v)),
                onPressed: uidCli.isEmpty
                    ? null
                    : () => _verInfoCliente(uidCliente: uidCli),
                enFila: true,
              ),
              const SizedBox(width: 12),
              _btnSecundario(
                icon: const Icon(Icons.chat, size: 20),
                label: Text(_labelContactar(v)),
                onPressed: uidCli.isEmpty
                    ? null
                    : () =>
                        _contactarCliente(
                            uidCliente: uidCli, viajeId: v.id, viaje: v),
                enFila: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 12),
          const Text(
            'Cancelación bloqueada: el cliente ya está a bordo.',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
          ),
        ];
      }

      if (v.codigoVerificado) {
        return [
          _estadoProfesionalCard(
            icon: Icons.task_alt_rounded,
            color: Colors.greenAccent,
            titulo: 'Paso actual: código verificado',
            detalle: corpPin
                ? 'Siguiente: iniciar ruta y dejar pasajeros uno a uno.'
                : 'Siguiente acción esperada: abrir navegación al destino y conducir.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Código verificado',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            corpPin
                ? 'El código del período quedó verificado. Continúa para pasar a «en ruta» y dejar pasajeros en orden.'
                : 'El código ya quedó verificado. Continúa para pasar a «en ruta» y abrir navegación al destino.',
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 16),
            _btnPrimario(
              icon: const Icon(Icons.play_arrow, size: 24),
              label: const Text('Iniciar ruta al destino',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              onPressed: () => unawaited(_corpIniciarRutaAlDestino(v)),
            ),
          if (_multiparadaPanelVisible(v, estadoBase)) ...[
            const SizedBox(height: 12),
            ..._bloqueNavegacionMultiparada(
              v,
              habilitado: _multiparadaNavegacionInteractiva(v, estadoBase),
            ),
          ],
          if (!corpPin) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _btnSecundario(
                  icon: const Icon(Icons.person, size: 20),
                  label: Text(_labelVerOtro(v)),
                  onPressed: uidCli.isEmpty
                      ? null
                      : () => _verInfoCliente(uidCliente: uidCli),
                  enFila: true,
                ),
                const SizedBox(width: 12),
                _btnSecundario(
                  icon: const Icon(Icons.chat, size: 20),
                  label: Text(_labelContactar(v)),
                  onPressed: uidCli.isEmpty
                      ? null
                      : () =>
                          _contactarCliente(
                              uidCliente: uidCli, viajeId: v.id, viaje: v),
                  enFila: true,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 12),
          if (!_esMultiparada(v)) ...[
            Text(
              'Si ya estás en destino o el sistema no pasó a «en ruta», podés finalizar '
              'igual: se usa la misma facturación que con «FINALIZAR» en viaje en curso '
              '(motor, turismo o programado).',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            if (!corpPin)
              _ConfirmarTransferenciaTaxistaButton(
                viajeId: v.id,
                metodoPagoFallback: v.metodoPago,
              ),
            if (!corpPin)
              TarjetaPagoEstadoTaxistaBanner(
                viajeId: v.id,
                metodoPagoFallback: v.metodoPago,
              ),
            if (!corpPin)
              EfectivoPagoTaxistaBanner(
                viajeId: v.id,
                metodoPagoFallback: v.metodoPago,
                montoFallback: v.precio,
              ),
            if (!corpPin)
              TaxistaRegistrarImpagoButton(
                viajeId: v.id,
                metodoPagoFallback: v.metodoPago,
              ),
            if (_permitePruebaSinRecorrido(v)) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _hintPruebaSinRecorrido(v, trasIniciarRuta: true),
                  style: TextStyle(
                    color: Colors.deepOrangeAccent.withValues(alpha: 0.95),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            _btnFinalizarViaje(
              onPressed: _puedePulsarFinalizarViaje(v)
                  ? () => _finalizarViaje(v)
                  : null,
              label: _labelFinalizarViaje(v),
            ),
          ] else if (corpPin) ...[
            Text(
              'Tras «Iniciar ruta», tocá cada parada → Waze → ✓.',
              style: TextStyle(
                color: Colors.orangeAccent.withValues(alpha: 0.95),
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
            Text(
              'Ruta multiparada: tocá cada parada abajo → Waze → ✓.',
              style: TextStyle(
                color: Colors.orangeAccent.withValues(alpha: 0.95),
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 12),
          const Text(
            'Cancelación bloqueada: el cliente ya está a bordo.',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
          ),
        ];
      }

      return [
        _estadoProfesionalCard(
          icon: Icons.pin_rounded,
          color: Colors.amberAccent,
          titulo: corpPin
              ? 'Paso actual: código con los pasajeros'
              : 'Paso actual: solicitar PIN al cliente',
          detalle: corpPin
              ? 'Pídeselo a los empleados o al encargado en el punto. '
                  'No aparece en tu pantalla (anti-fraude).'
              : 'Siguiente acción esperada: validar el código para iniciar la ruta.',
        ),
        const SizedBox(height: 12),
        Text(
          corpPin ? 'Paso 3 — Código con los pasajeros' : 'Paso 3 — Código con el cliente',
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          corpPin
              ? 'Los empleados te dictan el PIN de 6 dígitos del período. '
                  'Tenés hasta ${CorporativoEsperaCodigoConstants.timeoutMinutos} min '
                  'desde la hora de recogida (si llegaste antes, el reloj cuenta desde esa hora). '
                  'Si hoy no laboran (feriado), no te lo dan y la ruta no cuenta.'
              : 'El mismo PIN de 6 dígitos que el cliente ve en su pantalla. '
                  'Al verificarlo, el viaje pasa a ruta y se puede abrir navegación al destino.',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 16),
        if (corpPin) ...[
          Row(
            children: [
              Flexible(
                child: Text(
                  'Intentos: ${_corpIntentosFallidos.clamp(0, 3)}/3',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _corpIntentosFallidos >= 2
                        ? Colors.redAccent
                        : Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Tiempo: ${_formatoTiempoRestante(_corpTiempoRestanteCodigo)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              TextField(
                controller: _codigoCtrl,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                onSubmitted: (_) =>
                    _verificarCodigo(v.id, v.codigoVerificacion ?? ''),
                decoration: InputDecoration(
                  hintText: '000000',
                  hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 32,
                      letterSpacing: 8),
                  filled: true,
                  fillColor: Colors.grey[900],
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide.none,
                  ),
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),
              _btnPrimario(
                icon: const Icon(Icons.verified, size: 24),
                label: const Text('VERIFICAR E INICIAR RUTA',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                onPressed: _actionBusy
                    ? null
                    : () => _verificarCodigo(v.id, v.codigoVerificacion ?? ''),
                backgroundColor: Colors.orange,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _btnSecundario(
              icon: const Icon(Icons.person, size: 20),
              label: Text(_labelVerOtro(v)),
              onPressed: uidCli.isEmpty
                  ? null
                  : () => _verInfoCliente(uidCliente: uidCli),
              enFila: true,
            ),
            const SizedBox(width: 12),
            _btnSecundario(
              icon: const Icon(Icons.chat, size: 20),
              label: Text(_labelContactar(v)),
              onPressed: uidCli.isEmpty
                  ? null
                  : () => _contactarCliente(
                      uidCliente: uidCli, viajeId: v.id, viaje: v),
              enFila: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
        const SizedBox(height: 12),
        if (corpPin) ...[
          _btnSecundario(
            icon: const Icon(Icons.help_outline, size: 20),
            label: const Text('No tengo código'),
            onPressed: _actionBusy ? null : () => _solicitarCodigoCorpEncargado(v),
          ),
          const SizedBox(height: 8),
          _btnSecundario(
            icon: const Icon(Icons.chat, size: 20),
            label: Text(_labelContactar(v)),
            onPressed: uidCli.isEmpty
                ? null
                : () => _contactarCliente(
                    uidCliente: uidCli, viajeId: v.id, viaje: v),
          ),
        ] else
          _btnPeligro(
            icon: const Icon(Icons.cancel_outlined, size: 20),
            label: const Text('Salir a disponibilidad',
                style: TextStyle(fontSize: 15)),
            onPressed: () => _cancelarPorTaxista(v),
          ),
      ];
    }

    if (EstadosViaje.esEnCurso(estadoBase)) {
      final pendiente = _proximoLegMultiparadaPendiente(v);
      final bool corpEnRuta = CorporativoPasajerosChoferCard.esViajeCorporativo(v);
      final String destinoUi = _esMultiparada(v) && pendiente != null
          ? pendiente.label
          : v.destino;
      final int totalMulti = _legsNavegacionMultiparada(v).length;
      final int hechosMulti = _esMultiparada(v)
          ? multiparadaLegsVisitadosDesdeViaje(v, totalLegs: totalMulti).length
          : 0;
      return [
        if (!corpEnRuta)
          _estadoProfesionalCard(
            icon: Icons.route_rounded,
            color: Colors.lightBlueAccent,
            titulo: _esMultiparada(v)
                ? 'Paso actual: ruta multiparada'
                : 'Paso actual: en ruta al destino',
            detalle: _esMultiparada(v)
                ? 'Tocá la parada → Waze o Maps → confirmá con ✓ ($hechosMulti/$totalMulti).'
                : 'Siguiente acción esperada: al llegar, confirmar y finalizar el viaje.',
          ),
        if (!corpEnRuta) const SizedBox(height: 12),
        Text(
          corpEnRuta && _esMultiparada(v)
              ? 'Siguiente parada pendiente'
              : (_esMultiparada(v)
                  ? 'Siguiente parada pendiente'
                  : 'En camino al destino'),
          style: const TextStyle(
              color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          destinoUi,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        if (!corpEnRuta) ...[
          const SizedBox(height: 8),
          Text(
            _coordsLegMultiActual(v) == null
                ? 'No hay coordenadas de destino en el viaje: podés finalizar igual para emitir la factura.'
                : _distanciaMetrosAlDestino == null
                    ? 'Distancia al destino: sin señal GPS en este momento (podés finalizar igual).'
                    : 'Distancia al pin actual: ${_textoDistanciaAlPin(_distanciaMetrosAlDestino!)} '
                        '(referencia; podés finalizar cuando corresponda).',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_esMultiparada(v))
          ..._bloqueNavegacionMultiparada(
            v,
            habilitado: _multiparadaNavegacionInteractiva(v, estadoBase),
          ),
        if (!_esMultiparada(v) || _multiparadaRutaCompleta(v)) ...[
          if (!_navegacionDestinoIniciada &&
              (!_esViajeCorporativo(v) || !_esMultiparada(v))) ...[
            _btnPrimario(
              icon: const Icon(Icons.navigation, size: 24),
              label: const Text('Navegar al destino',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              onPressed: () async {
                final okGps = await _gpsListoParaAbrirNavegacionExterna(v);
                if (!okGps) return;
                await _selectorNavegacionDestino(
                  v.latDestino,
                  v.lonDestino,
                  viajeParaPersistirDestino: v,
                );
              },
            ),
            if (_permitePruebaSinRecorrido(v)) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _marcarNavegacionDestinoLista(v);
                    _expandirViajeSheetTrasMapa();
                    _tripFlowSnack(
                      'Listo. Siguiente paso: «Finalizar viaje».',
                      backgroundColor: const Color(0xFF2E7D32),
                    );
                  },
                  icon: const Icon(Icons.skip_next_rounded, size: 22),
                  label: const Text('Continuar sin mapa (prueba en casa)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.tealAccent,
                    side: BorderSide(
                        color: Colors.tealAccent.withValues(alpha: 0.55)),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ],
        if (!corpEnRuta) ...[
          Row(
            children: [
              _btnSecundario(
                icon: const Icon(Icons.person, size: 20),
                label: Text(_labelVerOtro(v)),
                onPressed: uidCli.isEmpty
                    ? null
                    : () => _verInfoCliente(uidCliente: uidCli),
                enFila: true,
              ),
              const SizedBox(width: 12),
              _btnSecundario(
                icon: const Icon(Icons.chat, size: 20),
                label: Text(_labelContactar(v)),
                onPressed: uidCli.isEmpty
                    ? null
                    : () => _contactarCliente(
                        uidCliente: uidCli, viajeId: v.id, viaje: v),
                enFila: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
        const SizedBox(height: 12),
        // Botón opcional para que el taxista confirme la transferencia él mismo
        // (sin esperar al admin). Solo visible si el método es transferencia y
        // el cliente ya subió el comprobante. No reemplaza al admin: la
        // validación admin sigue funcionando como respaldo.
        if (!CorporativoPasajerosChoferCard.esViajeCorporativo(v))
          _ConfirmarTransferenciaTaxistaButton(
            viajeId: v.id,
            metodoPagoFallback: v.metodoPago,
          ),
        if (!CorporativoPasajerosChoferCard.esViajeCorporativo(v))
          TarjetaPagoEstadoTaxistaBanner(
            viajeId: v.id,
            metodoPagoFallback: v.metodoPago,
          ),
        if (!CorporativoPasajerosChoferCard.esViajeCorporativo(v))
          EfectivoPagoTaxistaBanner(
            viajeId: v.id,
            metodoPagoFallback: v.metodoPago,
            montoFallback: v.precio,
          ),
        if (!CorporativoPasajerosChoferCard.esViajeCorporativo(v))
          TaxistaRegistrarImpagoButton(
            viajeId: v.id,
            metodoPagoFallback: v.metodoPago,
          ),
        if (_permitePruebaSinRecorrido(v) && !_navegacionDestinoIniciada) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _hintPruebaSinRecorrido(v, trasIniciarRuta: false),
              style: TextStyle(
                color: Colors.deepOrangeAccent.withValues(alpha: 0.95),
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
        ],
        if (_esMultiparada(v) && !_multiparadaRutaCompleta(v)) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.45)),
            ),
            child: Text(
              _esViajeCorporativo(v)
                  ? 'Tocá cada parada abajo → Waze → ✓. '
                      'Finalizar se activa al completar todas '
                      '(${_multiLegCompletadas.clamp(0, _legsNavegacionMultiparada(v).length)}/'
                      '${_legsNavegacionMultiparada(v).length}).'
                  : 'Multiparada: faltan destinos por confirmar '
                      '(${_multiLegCompletadas.clamp(0, _legsNavegacionMultiparada(v).length)}/'
                      '${_legsNavegacionMultiparada(v).length}). '
                      'Tocá la parada → Waze → ✓.',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_mostrarBotonFinalizarViaje(v, estadoBase: estadoBase)) ...[
          _btnFinalizarViaje(
            onPressed: _puedePulsarFinalizarViaje(v)
                ? () => _finalizarViaje(v)
                : null,
            label: _labelFinalizarViaje(v),
          ),
        ],
      ];
    }

    return [
      _estadoProfesionalCard(
        icon: Icons.sync_problem_rounded,
        color: Colors.orangeAccent,
        titulo: 'Sincronizando viaje…',
        detalle:
            'El viaje está asignado pero el estado aún se actualiza. '
            'Tocá «Reintentar» arriba o esperá unos segundos.',
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => unawaited(_sembrarViajeActivoDesdeServidor()),
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar carga'),
        ),
      ),
    ];
  }

  // ==================== ESTILOS DE BOTONES ====================

  String _labelFinalizarViaje(Viaje v) {
    if (_esViajeCorporativo(v)) return 'Finalizar ruta corporativa';
    return 'Finalizar viaje';
  }

  Widget _btnFinalizarViaje({
    required VoidCallback? onPressed,
    String label = 'Finalizar viaje',
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.flag_rounded, size: 26),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.15,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade700,
          disabledForegroundColor: Colors.white54,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _btnPrimario({
    required Widget icon,
    required Widget label,
    required VoidCallback? onPressed,
    Color? backgroundColor,
  }) {
    return RaiViajeEnCursoUi.overflowSafeIconButton(
      onPressed: onPressed,
      icon: icon,
      label: label,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? Colors.greenAccent,
        foregroundColor: Colors.black,
        minimumSize: const Size(double.infinity, 56),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    );
  }

  Widget _btnSecundario({
    required Widget icon,
    required Widget label,
    required VoidCallback? onPressed,
    bool enFila = false,
  }) {
    final Widget boton = RaiViajeEnCursoUi.overflowSafeOutlinedIconButton(
      onPressed: onPressed,
      icon: icon,
      label: label,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        foregroundColor: Colors.white,
        minimumSize: Size(enFila ? 1 : double.infinity, 48),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    if (enFila) return Expanded(child: boton);
    return SizedBox(width: double.infinity, child: boton);
  }

  Widget _btnPeligro({
    required Widget icon,
    required Widget label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: RaiViajeEnCursoUi.overflowSafeOutlinedIconButton(
        onPressed: onPressed,
        icon: icon,
        label: label,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
          foregroundColor: Colors.redAccent,
          minimumSize: const Size(double.infinity, 48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

}

/// Botón "Confirmar pago recibido" que aparece SOLO cuando:
///   * el método de pago del viaje es transferencia,
///   * el cliente ya subió el comprobante (`comprobanteTransferenciaUrl`),
///   * la transferencia aún no fue confirmada (`transferenciaConfirmada != true`).
///
/// El botón llama a la callable [ViajesRepo.confirmarTransferenciaPorTaxista]
/// (Cloud Function `confirmarTransferenciaTaxistaSeguro`). El admin sigue
/// pudiendo validar como respaldo; este botón es el "atajo" del taxista.
class _ConfirmarTransferenciaTaxistaButton extends StatefulWidget {
  const _ConfirmarTransferenciaTaxistaButton({
    required this.viajeId,
    required this.metodoPagoFallback,
  });

  final String viajeId;
  final String metodoPagoFallback;

  @override
  State<_ConfirmarTransferenciaTaxistaButton> createState() =>
      _ConfirmarTransferenciaTaxistaButtonState();
}

class _ConfirmarTransferenciaTaxistaButtonState
    extends State<_ConfirmarTransferenciaTaxistaButton> {
  bool _enviando = false;

  Future<void> _confirmar() async {
    if (_enviando) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _enviando = true);
    try {
      await ViajesRepo.confirmarTransferenciaPorTaxista(
          viajeId: widget.viajeId);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Pago confirmado.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo confirmar el pago: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('viajes')
          .doc(widget.viajeId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }
        final data = snap.data!.data() ?? const <String, dynamic>{};
        final String metodo = (data['metodoPago']?.toString().isNotEmpty == true
                ? data['metodoPago'].toString()
                : widget.metodoPagoFallback)
            .toString();
        if (!MetodoPagoViaje.esTransferencia(metodo)) {
          return const SizedBox.shrink();
        }
        if (CorporativoTaxistaService.esViajeCorporativoDoc(data)) {
          return const SizedBox.shrink();
        }
        final String comprobante =
            (data['comprobanteTransferenciaUrl'] ?? '').toString().trim();
        if (comprobante.isEmpty) return const SizedBox.shrink();
        if (data['transferenciaConfirmada'] == true) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade400),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified, color: Colors.greenAccent, size: 18),
                  SizedBox(width: 8),
                  Text('Pago confirmado',
                      style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _enviando ? null : _confirmar,
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_enviando
                  ? 'Confirmando...'
                  : 'Confirmar pago recibido'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Línea informativa que muestra al taxista la comisión RAI y el neto a
/// recibir sobre el total del viaje.
///
/// IMPORTANTE: este widget es de SOLO LECTURA. No persiste ni recalcula
/// nada en Firestore: simplemente reformatea localmente lo que ya calculan
/// `PlataformaEconomia` (cliente) y la Cloud Function `finalizarViajeSeguro`
/// (backend). Si en el futuro se cambia el % nominal en
/// [PlataformaEconomia.comisionViajePorcentaje] (sincronizado desde `config/comision`), la etiqueta se actualiza sola.
class _DesgloseComisionNeto extends StatelessWidget {
  const _DesgloseComisionNeto({
    required this.precio,
    this.esCorporativo = false,
  });

  final double precio;
  final bool esCorporativo;

  @override
  Widget build(BuildContext context) {
    if (!precio.isFinite || precio <= 0) return const SizedBox.shrink();

    try {
      final double pct = PlataformaEconomia.comisionViajePorcentaje;
      final String pctLabel = (pct - pct.round()).abs() < 1e-9
          ? pct.round().toString()
          : pct.toStringAsFixed(1);
      final double comision = PlataformaEconomia.comisionRdDesdeTotal(precio);
      final double neto = PlataformaEconomia.gananciaTaxistaRdDesdeTotal(precio);

      final String comisionTxt = FormatosMoneda.rd(comision);
      final String netoTxt = FormatosMoneda.rd(neto);

      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (esCorporativo) ...[
              const Text(
                '🏢 Ruta corporativa — tarifa acordada con la empresa',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF5EEAD4),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              '📊 Comisión RAI ($pctLabel%): $comisionTxt',
              style: const TextStyle(
                fontSize: 13.5,
                color: Colors.white60,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '💵 Neto a recibir: $netoTxt',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (esCorporativo) ...[
              const SizedBox(height: 4),
              const Text(
                'Pago vía RAI al liquidar el período.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.white54,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}
