// lib/pantallas/cliente/viaje_en_curso_cliente.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
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
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/telefono_viaje.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/utils/navegacion_salida_app.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/error_auth_es.dart';
import 'package:flygo_nuevo/pantallas/chat/chat_screen.dart';
import 'package:flygo_nuevo/pantallas/cliente/post_viaje_cliente_flow.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/widgets/cliente_viaje_live_conductores.dart';
import 'package:flygo_nuevo/widgets/navegacion_waze_maps_sheet.dart';

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

String _s(Object? x) => x?.toString() ?? '';

double _taxistaHueByEstado(String estado) {
  final String e = EstadosViaje.normalizar(estado);
  if (e == EstadosViaje.aceptado || e == EstadosViaje.enCaminoPickup) {
    // En camino al cliente: color distinto y visible
    return BitmapDescriptor.hueCyan;
  }
  if (e == EstadosViaje.aBordo || e == EstadosViaje.enCurso) {
    // Viaje en curso
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
  String r6(Object? n) {
    if (n is num && n.isFinite) return n.toStringAsFixed(6);
    return 'x';
  }

  final String est = EstadosViaje.normalizar((d['estado'] ?? '').toString());
  final Object? dLat = d['driverLat'] ?? d['latTaxista'];
  final Object? dLon = d['driverLon'] ?? d['lonTaxista'];
  final String tid = (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString();
  final bool codigoOk = d['codigoVerificado'] == true;
  final bool completado = d['completado'] == true;
  final int wp = (d['waypoints'] is List) ? (d['waypoints'] as List).length : 0;
  final String codPin = (d['codigoVerificacion'] ?? d['codigo_verificacion'] ?? '')
      .toString();

  // Mayor precisión en coords para mapa en vivo (taxista / cliente).
  return '${ds.id}|$est|${r6(dLat)}|${r6(dLon)}|${r6(d['latCliente'])}|${r6(d['lonCliente'])}|'
      '${r6(d['latDestino'])}|${r6(d['lonDestino'])}|$tid|$codigoOk|$completado|'
      '${d['metodoPago']}|${d['precio']}|$wp|$codPin';
}

class ViajeEnCursoCliente extends StatefulWidget {
  const ViajeEnCursoCliente({super.key});
  @override
  State<ViajeEnCursoCliente> createState() => _ViajeEnCursoClienteState();
}

class _ViajeEnCursoClienteState extends State<ViajeEnCursoCliente>
    with TickerProviderStateMixin {
  /// Altura mínima del sheet (tap en mapa / pickup) — mapa casi a pantalla completa.
  static const double _kSheetMinPickupNav = 0.11;

  /// Apertura por defecto a media pantalla.
  static const double _kSheetInitialMitad = 0.5;

  GoogleMapController? _map;
  bool _myLoc = false;

  final Map<PolylineId, Polyline> _polylines = {};
  Timer? _routeDebounce;

  String _lastRouteKey = '';
  String _lastBoundsKey = '';

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _viajeDocSub;
  String _lastNotifiedState = '';

  /// Publica la posición del cliente en el documento del viaje (Firestore en vivo).
  StreamSubscription<Position>? _clienteViajePosSub;
  String? _clienteViajePosViajeId;

  /// Seguimiento automático de cámara al taxista (el usuario puede soltar con gesto en el mapa).
  bool _seguirTaxistaCamara = true;
  DateTime? _ultimoSeguimientoTaxistaMs;
  double? _ultimoSeguimientoTaxLat;
  double? _ultimoSeguimientoTaxLon;

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  /// Cámara movida por código (no colapsar/expandir tarjeta como si fuera gesto del usuario).
  int _programmaticCameraDepth = 0;
  Timer? _mapGestureEndDebounce;

  /// Evita animar el colapso del sheet más de una vez por viaje (espera conductor o viene al pickup).
  String? _sheetCollapsedPickupForViajeId;

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

  /// Último viaje activo visto (para pantalla de cierre cuando `viajeActivoId` ya se limpió en servidor).
  String _lastNonEmptyViajeActivoId = '';
  DocumentSnapshot<Map<String, dynamic>>? _viajeCierreDocSnap;
  String? _viajeCierreFetchKey;

  /// Evita abrir dos veces el flujo post-viaje para el mismo id.
  String? _navPostViajeParaId;
  bool _abriendoFlujoPostViaje = false;

  // 🚀 NUEVO: Conductores disponibles
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _driversSub;
  List<DocumentSnapshot<Map<String, dynamic>>> _driversList = [];
  String _lastDriversPoolSig = '';
  Map<String, String?> _driverFotoPorUid = <String, String?>{};
  Timer? _fotosDebounce;
  late final AnimationController _radarCtrl;
  late final AnimationController _progresoBrilloCtrl;

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _progresoBrilloCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _enableMyLocation();
    _lastNotifiedState = '';
  }

  @override
  void dispose() {
    _map?.dispose();
    _routeDebounce?.cancel();
    _disposeDocWatch();
    _stopClienteUbicacionEnViaje();
    _sheetController.dispose();
    _mensajeCercaniaTimer?.cancel();
    _driversSub?.cancel();
    _fotosDebounce?.cancel();
    _radarCtrl.dispose();
    _progresoBrilloCtrl.dispose();
    _pickupEtaDebounce?.cancel();
    _mapGestureEndDebounce?.cancel();
    super.dispose();
  }

  void _stopClienteUbicacionEnViaje() {
    _clienteViajePosSub?.cancel();
    _clienteViajePosSub = null;
    _clienteViajePosViajeId = null;
  }

  Future<void> _ensureClienteUbicacionEnViaje(String viajeId) async {
    if (_clienteViajePosViajeId == viajeId && _clienteViajePosSub != null) {
      return;
    }

    await _clienteViajePosSub?.cancel();
    _clienteViajePosViajeId = viajeId;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return;
    }

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

    final ref = FirebaseFirestore.instance.collection('viajes').doc(viajeId);
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
  }

  void _maybeAnimarCamaraAlTaxista(Viaje v, String estadoBase) {
    if (!_seguirTaxistaCamara) return;
    if (!_isValidCoord(v.latTaxista, v.lonTaxista)) return;
    if (v.uidTaxista.isEmpty) return;
    // Pickup + trayecto al destino: el pasajero puede seguir al conductor en el mapa.
    if (!(estadoBase == EstadosViaje.aceptado ||
        estadoBase == EstadosViaje.enCaminoPickup ||
        estadoBase == EstadosViaje.enCurso)) {
      return;
    }

    final DateTime now = DateTime.now();
    if (_ultimoSeguimientoTaxistaMs != null &&
        now.difference(_ultimoSeguimientoTaxistaMs!) <
            const Duration(milliseconds: 850)) {
      return;
    }

    if (_ultimoSeguimientoTaxLat != null && _ultimoSeguimientoTaxLon != null) {
      final double dKm = _haversineKm(
        _ultimoSeguimientoTaxLat!,
        _ultimoSeguimientoTaxLon!,
        v.latTaxista,
        v.lonTaxista,
      );
      if (dKm < 0.004) {
        return;
      }
    }

    _ultimoSeguimientoTaxistaMs = now;
    _ultimoSeguimientoTaxLat = v.latTaxista;
    _ultimoSeguimientoTaxLon = v.lonTaxista;

    final GoogleMapController? c = _map;
    if (c == null) return;
    _programmaticCameraDepth++;
    c
        .animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(v.latTaxista, v.lonTaxista), 16),
    )
        .then((_) {}, onError: (_) {
      if (_programmaticCameraDepth > 0) _programmaticCameraDepth--;
    });
  }

  /// Mientras interactúas con el mapa: tarjeta al mínimo; al soltar (cámara idle) vuelve a la mitad.
  void _colapsarSheetPorTapMapa() {
    if (!_sheetController.isAttached) return;
    _sheetController.animateTo(
      _kSheetMinPickupNav,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _expandirSheetTrasMapaInteract() {
    if (!_sheetController.isAttached) return;
    _sheetController.animateTo(
      _kSheetInitialMitad,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _maybeColapsarSheetPickupNav(Viaje v, String estadoBase) {
    if (_sheetCollapsedPickupForViajeId == v.id) return;
    final bool esperandoPool = !v.esTurismo &&
        v.uidTaxista.isEmpty &&
        (estadoBase == EstadosViaje.pendiente ||
            estadoBase == EstadosViaje.pendientePago);
    final bool turismoSinConductor = v.esTurismo && v.uidTaxista.isEmpty;
    final bool fasePickup = v.uidTaxista.isNotEmpty &&
        (estadoBase == EstadosViaje.aceptado ||
            estadoBase == EstadosViaje.enCaminoPickup) &&
        _isValidCoord(v.latTaxista, v.lonTaxista);
    if (!esperandoPool && !turismoSinConductor && !fasePickup) return;
    if (!_sheetController.isAttached) return;
    _sheetCollapsedPickupForViajeId = v.id;
    _sheetController.animateTo(
      _kSheetMinPickupNav,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
    if (fasePickup && !_seguirTaxistaCamara) {
      setState(() => _seguirTaxistaCamara = true);
    }
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
  }

  // 🚀 NUEVO: Iniciar escucha de conductores disponibles
  void _startListeningDrivers() {
    if (_driversSub != null) return;

    _driversSub = FirebaseFirestore.instance
        .collection('drivers_location')
        .where('online', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      final String sig =
          snapshot.docs.map((DocumentSnapshot<Map<String, dynamic>> doc) {
        final Map<String, dynamic>? data = doc.data();
        final GeoPoint? gp = data?['location'] as GeoPoint?;
        if (gp == null) return doc.id;
        return '${doc.id}:${gp.latitude.toStringAsFixed(4)},${gp.longitude.toStringAsFixed(4)}';
      }).join('|');
      if (sig == _lastDriversPoolSig) return;
      _lastDriversPoolSig = sig;
      if (mounted) {
        setState(() {
          _driversList = snapshot.docs;
        });
        _schedulePrefetchDriverFotos();
      }
    }, onError: (error) {
      debugPrint('Error cargando conductores: $error');
    });
  }

  // 🚀 NUEVO: Detener escucha de conductores
  void _stopListeningDrivers() {
    _fotosDebounce?.cancel();
    _fotosDebounce = null;
    _driversSub?.cancel();
    _driversSub = null;
    _lastDriversPoolSig = '';
    if (mounted) {
      setState(() {
        _driversList = [];
        _driverFotoPorUid = <String, String?>{};
      });
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

  int get _driversCount => _driversList.length;

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
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    final bool denied = (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever);
    setState(() => _myLoc = !denied);
  }

  // Navegación externa
  String _fmtCoord(double v) => v.toStringAsFixed(6);

  Future<bool> _tryLaunch(Uri uri, {bool preferExternalApp = true}) async {
    try {
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

  Future<void> _openGoogleMapsTo(double lat, double lon,
      {String? label}) async {
    final String la = _fmtCoord(lat), lo = _fmtCoord(lon);
    final String qLabel = (label == null || label.trim().isEmpty)
        ? '$la,$lo'
        : Uri.encodeComponent('$la,$lo($label)');
    final Uri navIntent = Uri(
      scheme: 'google.navigation',
      queryParameters: {'q': '$la,$lo', 'mode': 'd'},
    );
    final Uri geoIntent = Uri.parse('geo:$la,$lo?q=$qLabel');
    final Uri web = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$la,$lo&travelmode=driving');

    if (await _tryLaunch(navIntent)) return;
    if (await _tryLaunch(geoIntent)) return;
    await _tryLaunch(web, preferExternalApp: false);
  }

  Future<void> _openWazeTo(double lat, double lon) async {
    final String la = _fmtCoord(lat), lo = _fmtCoord(lon);
    final Uri deep = Uri.parse('waze://?ll=$la,$lo&navigate=yes');
    final Uri web = Uri.parse('https://waze.com/ul?ll=$la,$lo&navigate=yes');
    if (await _tryLaunch(deep)) return;
    if (await _tryLaunch(web, preferExternalApp: false)) return;
    await _openGoogleMapsTo(lat, lon);
  }

  /// Abre Google Maps en el punto del conductor (vista / marcador), sin forzar ruta en la app RAI.
  Future<void> _openGoogleMapsVerUbicacionConductor(
      double lat, double lon) async {
    final String la = _fmtCoord(lat), lo = _fmtCoord(lon);
    final Uri geoIntent = Uri.parse('geo:$la,$lo');
    final Uri mapsSearch = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$la,$lo',
    );
    if (await _tryLaunch(geoIntent)) return;
    await _tryLaunch(mapsSearch, preferExternalApp: false);
  }

  Future<void> abrirNavegacionAlDestino(Viaje v) async {
    if (!_isValidCoord(v.latDestino, v.lonDestino)) return;
    if (!mounted) return;
    await showNavegacionWazeMapsSheet(
      context,
      title: 'Navegar al destino',
      addressLine: v.destino.trim().isNotEmpty ? 'Destino: ${v.destino}' : null,
      tieneCoords: true,
      gpsCoordinatesLine:
          'GPS: ${_fmtCoord(v.latDestino)}, ${_fmtCoord(v.lonDestino)}',
      footerHint: 'Elige Waze o Google Maps.',
      onWaze: () => unawaited(_openWazeTo(v.latDestino, v.lonDestino)),
      onMaps: () => unawaited(
        _openGoogleMapsTo(v.latDestino, v.lonDestino, label: v.destino),
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
          content: Text('Esperando ubicación GPS del conductor en tiempo real.'),
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

  bool _mostrarRutaHaciaDestinoCliente(Viaje v) {
    final estado = _normEstadoViaje(v);
    return estado == EstadosViaje.enCurso ||
        (estado == EstadosViaje.aBordo && v.codigoVerificado);
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

    final Map<PolylineId, Polyline> beforePolys =
        Map<PolylineId, Polyline>.from(_polylines);
    _polylines.clear();

    if ((estado == EstadosViaje.aceptado ||
            estado == EstadosViaje.enCaminoPickup) &&
        _isValidCoord(v.latTaxista, v.lonTaxista) &&
        _isValidCoord(v.latCliente, v.lonCliente)) {
      await _drawRoute(
        _latLng(v.latTaxista, v.lonTaxista),
        _latLng(v.latCliente, v.lonCliente),
        id: 'pickup',
        color: const Color(0xFF00E5FF),
        width: 7,
      );
    }

    if (_mostrarRutaHaciaDestinoCliente(v) &&
        _isValidCoord(v.latCliente, v.lonCliente) &&
        _isValidCoord(v.latDestino, v.lonDestino)) {
      final List<({double lat, double lon})>? vias = _coordsWaypointsValidos(v);
      await _drawRoute(
        _latLng(v.latCliente, v.lonCliente),
        _latLng(v.latDestino, v.lonDestino),
        id: 'ruta',
        viaIntermediate: vias,
      );
    }

    if (!mounted) return;
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
        final List<LatLng> wpts = <LatLng>[];
        final List<Map<String, dynamic>>? raw = v.waypoints;
        if (raw != null && _mostrarRutaHaciaDestinoCliente(v)) {
          for (final Map<String, dynamic> m in raw) {
            final double? la = _coordDoubleMap(m['lat']);
            final double? lo = _coordDoubleMap(m['lon'] ?? m['lng']);
            if (la != null &&
                lo != null &&
                _isValidCoord(la, lo)) {
              wpts.add(LatLng(la, lo));
            }
          }
        }
        return wpts;
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
    final double edgePad = fasePickupCam ? 88.0 : 60.0;

    try {
      _programmaticCameraDepth++;
      await mapRef.animateCamera(CameraUpdate.newLatLngBounds(bounds, edgePad));
    } catch (_) {
      if (_programmaticCameraDepth > 0) _programmaticCameraDepth--;
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      final GoogleMapController? mapRef2 = _map;
      if (mapRef2 != null) {
        try {
          _programmaticCameraDepth++;
          await mapRef2
              .animateCamera(CameraUpdate.newLatLngBounds(bounds, edgePad));
        } catch (_) {
          if (_programmaticCameraDepth > 0) _programmaticCameraDepth--;
        }
      }
    }
  }

  /// Para rutas con paradas: firma estable para redibujar si cambian coords en Firestore.
  String _firmaWaypointsViaje(Viaje v) {
    final List<Map<String, dynamic>>? w = v.waypoints;
    if (w == null || w.isEmpty) return '';
    final StringBuffer b = StringBuffer();
    for (final Map<String, dynamic> m in w) {
      final double? la = _coordDoubleMap(m['lat']);
      final double? lo = _coordDoubleMap(m['lon'] ?? m['lng']);
      if (la != null &&
          lo != null &&
          la.isFinite &&
          lo.isFinite &&
          _isValidCoord(la, lo)) {
        b.write('${la.toStringAsFixed(5)},${lo.toStringAsFixed(5)};');
      }
    }
    return b.toString();
  }

  double? _coordDoubleMap(dynamic x) {
    if (x is num) return x.toDouble();
    if (x is String) return double.tryParse(x);
    return null;
  }

  List<({double lat, double lon})>? _coordsWaypointsValidos(Viaje v) {
    final List<Map<String, dynamic>>? raw = v.waypoints;
    if (raw == null || raw.isEmpty) return null;
    final List<({double lat, double lon})> out =
        <({double lat, double lon})>[];
    for (final Map<String, dynamic> m in raw) {
      final double? la = _coordDoubleMap(m['lat']);
      final double? lo = _coordDoubleMap(m['lon'] ?? m['lng']);
      if (la == null || lo == null) continue;
      if (!_isValidCoord(la, lo)) continue;
      out.add((lat: la, lon: lo));
    }
    return out.isEmpty ? null : out;
  }

  Future<void> _drawRoute(
    LatLng a,
    LatLng b, {
    required String id,
    Color color = const Color(0xFF49F18B),
    int width = 6,
    List<({double lat, double lon})>? viaIntermediate,
  }) async {
    try {
      final dynamic dir = await DirectionsService.drivingDistanceKm(
        originLat: a.latitude,
        originLon: a.longitude,
        destLat: b.latitude,
        destLon: b.longitude,
        waypoints:
            (viaIntermediate != null && viaIntermediate.isNotEmpty)
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

      final PolylineId polyId = PolylineId(id);
      _polylines[polyId] = Polyline(
        polylineId: polyId,
        width: width,
        points: pts.isNotEmpty ? pts : [a, b],
        geodesic: true,
        color: color,
      );
    } catch (_) {
      _polylines[PolylineId(id)] = Polyline(
        polylineId: PolylineId(id),
        width: width.clamp(4, 12),
        points: [a, b],
        geodesic: true,
        color: color,
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
  }

  Widget _bodySinViajeActivo({required String mensaje}) {
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
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => intentarSalirAlGate(context),
                icon: const Icon(Icons.home_rounded, size: 20),
                label: const Text('Volver al inicio'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirFlujoPostViaje(
      {required String viajeId, required String uid}) async {
    try {
      await _limpiarActivoDelUsuario(uid);
    } catch (_) {}
    if (!mounted) return;
    setState(_limpiarCacheCierreViaje);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PostViajeClienteFlow(viajeId: viajeId),
      ),
    );
  }

  void _programarFlujoPostViaje(
      {required String viajeId, required String uid}) {
    if (_abriendoFlujoPostViaje) return;
    if (_navPostViajeParaId == viajeId) return;
    _navPostViajeParaId = viajeId;
    _abriendoFlujoPostViaje = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;
        await _abrirFlujoPostViaje(viajeId: viajeId, uid: uid);
      } finally {
        _abriendoFlujoPostViaje = false;
      }
    });
  }

  /// Transferencia: mostrar cuenta del taxista en cuanto hay conductor y el viaje no terminó (antes solo a bordo / en ruta).
  bool _mostrarDatosTransferenciaCliente(Viaje v, String estadoBase) {
    if (!MetodoPagoViaje.esTransferencia(v.metodoPago)) return false;
    if (v.uidTaxista.isEmpty) return false;
    if (EstadosViaje.esTerminal(estadoBase)) return false;
    return true;
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
      motivoCtrl.dispose();
    }

    if (motivo == null || motivo.isEmpty) {
      return;
    }

    if (mounted) setState(() => _cancelandoViajeCliente = true);

    try {
      await _runWithBlocking(() async {
        final int segundos = await _segundosRestantesBorradoDesdeServidor(v.id);
        bool deleted = false;

        if (segundos > 0) {
          try {
            final ds = await FirebaseFirestore.instance
                .collection('viajes')
                .doc(v.id)
                .get();
            final d = ds.data() ?? const <String, dynamic>{};
            final String estado =
                EstadosViaje.normalizar((d['estado'] ?? '').toString());
            final String uidTx =
                (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString();
            final bool puedeBorrarRapido = uidTx.isEmpty &&
                (estado == EstadosViaje.pendiente ||
                    estado == EstadosViaje.pendientePago ||
                    estado == 'pendiente_admin');
            if (puedeBorrarRapido) {
              await FirebaseFirestore.instance
                  .collection('viajes')
                  .doc(v.id)
                  .delete();
              deleted = true;
            }
          } catch (_) {}
        }

        if (!deleted) {
          await ViajesRepo.cancelarPorCliente(
            viajeId: v.id,
            uidCliente: uid,
            motivo: motivo,
          );
        }

        await _limpiarActivoDelUsuario(uid);
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' &&
          await _viajeQuedoCanceladoEnServidor(v.id)) {
        if (!mounted) return;
        setState(() => _cancelandoViajeCliente = false);
        Navigator.of(context).pushNamedAndRemoveUntil(
            kRutaGateAuth, (r) => false);
        return;
      }
      if (!mounted) return;
      final String detalle = errorAuthEs(e);
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
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(e.message ?? 'La cancelación tardó demasiado.')),
        );
      if (mounted) setState(() => _cancelandoViajeCliente = false);
      return;
    } catch (e) {
      final String lower = e.toString().toLowerCase();
      if ((lower.contains('permission-denied') ||
              lower.contains('permission_denied')) &&
          await _viajeQuedoCanceladoEnServidor(v.id)) {
        if (!mounted) return;
        setState(() => _cancelandoViajeCliente = false);
        Navigator.of(context).pushNamedAndRemoveUntil(
            kRutaGateAuth, (r) => false);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('No se pudo cancelar el viaje: $e')),
        );
      if (mounted) setState(() => _cancelandoViajeCliente = false);
      return;
    }

    if (!mounted) return;
    setState(() => _cancelandoViajeCliente = false);
    Navigator.of(context).pushNamedAndRemoveUntil(kRutaGateAuth, (r) => false);
  }

  // Watch viaje doc
  void _disposeDocWatch() {
    _viajeDocSub?.cancel();
    _viajeDocSub = null;
  }

  void _watchViajeDoc(String viajeId) {
    if (_viajeDocSub != null && _lastRouteKey.startsWith('$viajeId|')) return;

    _disposeDocWatch();

    _viajeDocSub = FirebaseFirestore.instance
        .collection('viajes')
        .doc(viajeId)
        .snapshots()
        .distinct()
        .listen((DocumentSnapshot<Map<String, dynamic>> ds) async {
      if (!ds.exists) return;
      final Map<String, dynamic> d = ds.data() ?? {};
      final String estado = (d['estado'] ?? '').toString();
      final String estN = EstadosViaje.normalizar(estado);

      final bool tieneTaxista =
          (d['uidTaxista'] ?? d['taxistaId'] ?? '').toString().isNotEmpty;
      final bool esEstadoValido = (estN == EstadosViaje.aceptado ||
          estN == EstadosViaje.enCaminoPickup);
      final bool esCambioEstado = _lastNotifiedState != estN;
      final bool noEsPendiente =
          estN != EstadosViaje.pendiente && estN != EstadosViaje.cancelado;

      if (esEstadoValido && esCambioEstado && tieneTaxista && noEsPendiente) {
        _lastNotifiedState = estN;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tu taxista va en camino 🚕'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }, onError: (Object _) {});
  }

  // Widget de paradas
  Widget _buildParadasWidget(Viaje v) {
    if (v.waypoints == null || v.waypoints!.isEmpty) {
      return const SizedBox.shrink();
    }

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
              Text(
                '📍 Ruta con paradas:',
                style: TextStyle(
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
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
          ...v.waypoints!.asMap().entries.map((entry) {
            final int index = entry.key + 1;
            final Map<String, dynamic> waypoint = entry.value;
            final String label =
                waypoint['label']?.toString() ?? 'Parada $index';
            return Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4, top: 2),
              child: Row(
                children: [
                  const Icon(Icons.flag_circle, size: 14, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Parada $index: $label',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
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
                const Icon(Icons.flag_circle, size: 14, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Destino: ${v.destino}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
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
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ORIGEN',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(v.origen,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.greenAccent),
                ),
                child: Text(
                  _labelEstado(estadoBase),
                  style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
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

  Widget _buildDriverCard(Viaje v) {
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
                          color: Colors.greenAccent.withValues(alpha: 0.28)),
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
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              otroUid: v.uidTaxista,
                              otroNombre: nombre,
                              viajeId: v.id,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
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
                    onPressed: () => unawaited(_openGoogleMapsVerUbicacionConductor(
                          v.latTaxista,
                          v.lonTaxista,
                        )),
                    icon: Icon(Icons.map_outlined, color: cs.onSurfaceVariant),
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
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
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

  // Datos bancarios (recibe el monto)
  Widget _buildDatosBancarios(
      Viaje v, String taxistaId, double monto, Map<String, dynamic> viajeData) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .doc(taxistaId)
          .snapshots()
          .distinct(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }
        final data = snap.data!.data() ?? {};
        final banco = data['banco'] ?? '';
        final cuenta = data['numeroCuenta'] ?? '';
        final titular =
            (data['titularCuenta'] ?? data['titular'] ?? '').toString();

        if (banco.isEmpty || cuenta.isEmpty || titular.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange),
            ),
            child: const Text(
              'El taxista no ha completado sus datos bancarios (banco, cuenta y titular). Contacta con él para acordar el pago.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          );
        }

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
              const Text('DATOS PARA TRANSFERENCIA',
                  style: TextStyle(
                      color: Colors.greenAccent, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('Monto a pagar: ${_safeMoney(monto)}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Banco: $banco',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Cuenta: $cuenta',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Titular: $titular',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              const Text('Realiza el pago directamente al taxista.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 12),
              Builder(
                builder: (_) {
                  final String estadoTransfer =
                      (viajeData['estado'] ?? '').toString();
                  final String comprobante =
                      (viajeData['comprobanteTransferenciaUrl'] ?? '')
                          .toString();
                  final String motivoRechazo =
                      (viajeData['motivoRechazoTransferencia'] ?? '')
                          .toString()
                          .trim();
                  final bool confirmada =
                      viajeData['transferenciaConfirmada'] == true;
                  if (confirmada) {
                    return const Text(
                      'Transferencia validada por Administracion.',
                      style: TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.w700),
                    );
                  }
                  if (estadoTransfer == 'pendiente_confirmacion') {
                    return const Text(
                      'Comprobante enviado. Pendiente de validacion.',
                      style: TextStyle(
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.w700),
                    );
                  }
                  if (estadoTransfer == 'transferencia_rechazada') {
                    return Column(
                      children: [
                        Text(
                          motivoRechazo.isEmpty
                              ? 'Transferencia rechazada por administración. Revisa el comprobante y vuelve a enviarlo.'
                              : 'Transferencia rechazada: $motivoRechazo',
                          style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w700),
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
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? u = FirebaseAuth.instance.currentUser;

    return FlygoSalidaSegura(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: RaiAppBar(
          title: 'Mi viaje en curso',
          backWhenCanPop: true,
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
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return _cargaLinealOscura();
                }
                if (userSnap.hasError ||
                    !userSnap.hasData ||
                    !userSnap.data!.exists) {
                  return _bodySinViajeActivo(
                      mensaje: 'No tienes viaje activo.');
                }

                final Map<String, dynamic> userData =
                    userSnap.data!.data() ?? {};
                final String activoId =
                    (userData['viajeActivoId'] ?? '').toString();

                if (activoId.isEmpty) {
                  _disposeDocWatch();
                  _stopClienteUbicacionEnViaje();
                  final String lost = _lastNonEmptyViajeActivoId;

                  if (lost.isNotEmpty) {
                    DocumentSnapshot<Map<String, dynamic>>? docSnap =
                        _viajeCierreDocSnap;
                    if (docSnap == null || docSnap.id != lost) {
                      final String fetchKey = '${u.uid}|$lost';
                      if (_viajeCierreFetchKey != fetchKey) {
                        _viajeCierreFetchKey = fetchKey;
                        WidgetsBinding.instance.addPostFrameCallback((_) async {
                          try {
                            final DocumentSnapshot<Map<String, dynamic>> d =
                                await FirebaseFirestore.instance
                                    .collection('viajes')
                                    .doc(lost)
                                    .get();
                            if (!mounted) return;
                            setState(() => _viajeCierreDocSnap = d);
                          } catch (_) {
                            if (mounted) {
                              setState(() => _viajeCierreFetchKey = null);
                            }
                          }
                        });
                      }
                      docSnap = _viajeCierreDocSnap;
                    }

                    if (docSnap != null &&
                        docSnap.exists &&
                        docSnap.id == lost) {
                      final Map<String, dynamic> d =
                          docSnap.data() ?? <String, dynamic>{};
                      final String st = EstadosViaje.normalizar(
                          (d['estado'] ?? '').toString());
                      final bool done = (d['completado'] == true) ||
                          st == EstadosViaje.completado;
                      final bool canc = st == EstadosViaje.cancelado ||
                          st == EstadosViaje.rechazado;
                      if (done || canc) {
                        _programarFlujoPostViaje(
                            viajeId: docSnap.id, uid: u.uid);
                        return _cargaLinealOscura();
                      }
                    }

                    if (docSnap == null ||
                        !docSnap.exists ||
                        docSnap.id != lost) {
                      return _cargaLinealOscura();
                    }
                  }

                  return _bodySinViajeActivo(
                    mensaje: 'No tienes viaje activo en este momento.',
                  );
                }

                if (_viajeCierreDocSnap != null &&
                    _viajeCierreDocSnap!.id != activoId) {
                  _viajeCierreDocSnap = null;
                  _viajeCierreFetchKey = null;
                }
                if (_lastNonEmptyViajeActivoId.isNotEmpty &&
                    _lastNonEmptyViajeActivoId != activoId) {
                  _navPostViajeParaId = null;
                }
                _lastNonEmptyViajeActivoId = activoId;

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('viajes')
                      .doc(activoId)
                      .snapshots()
                      .distinct((DocumentSnapshot<Map<String, dynamic>> a,
                              DocumentSnapshot<Map<String, dynamic>> b) =>
                          _viajeDocMapUiSig(a) == _viajeDocMapUiSig(b)),
                  builder: (context, vSnap) {
                    if (vSnap.connectionState == ConnectionState.waiting) {
                      return _cargaLinealOscura();
                    }

                    if (vSnap.hasError ||
                        !vSnap.hasData ||
                        !vSnap.data!.exists) {
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        await _limpiarActivoDelUsuario(u.uid);
                      });
                      return _bodySinViajeActivo(
                        mensaje:
                            'No tienes viaje activo en este momento.',
                      );
                    }

                    final Map<String, dynamic> data = vSnap.data!.data() ?? {};
                    final Viaje v = Viaje.fromMap(
                      vSnap.data!.id,
                      Map<String, dynamic>.from(data),
                    );

                    final String uidClienteViaje =
                        ViajesRepo.uidClienteDesdeDocViaje(data);
                    if (uidClienteViaje.isNotEmpty &&
                        uidClienteViaje != u.uid) {
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        await _limpiarActivoDelUsuario(u.uid);
                      });
                      return _bodySinViajeActivo(
                        mensaje:
                            'No tienes viaje activo en este momento.',
                      );
                    }

                    _watchViajeDoc(v.id);

                    final String estadoBase = EstadosViaje.normalizar(
                      v.estado.isNotEmpty
                          ? v.estado
                          : (v.completado
                              ? EstadosViaje.completado
                              : (v.aceptado
                                  ? EstadosViaje.aceptado
                                  : EstadosViaje.pendiente)),
                    );

                    if (EstadosViaje.esTerminal(estadoBase)) {
                      _stopClienteUbicacionEnViaje();
                      _programarFlujoPostViaje(viajeId: v.id, uid: u.uid);
                      return _cargaLinealOscura();
                    }

                    // Ubicación del cliente en Firestore en tiempo real durante el viaje activo.
                    _ensureClienteUbicacionEnViaje(v.id);

                    // Pool de conductores: solo viajes normales/motor en espera (turismo va por ADM)
                    final bool esperandoTaxista = !v.esTurismo &&
                        v.uidTaxista.isEmpty &&
                        (estadoBase == EstadosViaje.pendiente ||
                            estadoBase == EstadosViaje.pendientePago);

                    // Iniciar o detener escucha de conductores según corresponda
                    if (esperandoTaxista && _driversSub == null) {
                      _startListeningDrivers();
                    } else if (!esperandoTaxista && _driversSub != null) {
                      _stopListeningDrivers();
                    }

                    final Set<Marker> markers = <Marker>{
                      if (_mostrarRutaHaciaDestinoCliente(v) &&
                          _isValidCoord(v.latDestino, v.lonDestino))
                        Marker(
                          markerId: const MarkerId('destino'),
                          position: _latLng(v.latDestino, v.lonDestino),
                          infoWindow:
                              InfoWindow(title: 'Destino: ${v.destino}'),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueGreen),
                        ),
                      if (_isValidCoord(v.latCliente, v.lonCliente))
                        Marker(
                          markerId: const MarkerId('pickup'),
                          position: _latLng(v.latCliente, v.lonCliente),
                          infoWindow: InfoWindow(
                              title: 'Punto de recogida: ${v.origen}'),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueAzure),
                        ),
                      // Si tenemos taxista, mostrar su marcador
                      if (v.uidTaxista.isNotEmpty &&
                          _isValidCoord(v.latTaxista, v.lonTaxista))
                        Marker(
                          markerId: const MarkerId('taxista'),
                          position: _latLng(v.latTaxista, v.lonTaxista),
                          infoWindow: const InfoWindow(title: 'Taxista'),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            _taxistaHueByEstado(estadoBase),
                          ),
                        ),
                    };
                    final Set<Circle> circles = <Circle>{};

                    // Conductores en pool: orden por cercanía al pickup + marcadores con tono distinto
                    final List<DocumentSnapshot<Map<String, dynamic>>>
                        driversSortedMapa = esperandoTaxista &&
                                _isValidCoord(v.latCliente, v.lonCliente)
                            ? conductoresOrdenadosPorPickup(
                                _driversList,
                                pickupLat: v.latCliente,
                                pickupLon: v.lonCliente,
                              )
                            : List<DocumentSnapshot<Map<String, dynamic>>>.from(
                                _driversList);

                    if (esperandoTaxista) {
                      for (final DocumentSnapshot<Map<String, dynamic>> doc
                          in driversSortedMapa) {
                        final Map<String, dynamic>? docData = doc.data();
                        final GeoPoint? location =
                            docData?['location'] as GeoPoint?;
                        if (location != null &&
                            _isValidCoord(
                                location.latitude, location.longitude)) {
                          final double hue =
                              35 + (doc.id.hashCode % 115).abs().toDouble();
                          markers.add(
                            Marker(
                              markerId: MarkerId('pool_${doc.id}'),
                              position:
                                  LatLng(location.latitude, location.longitude),
                              icon: BitmapDescriptor.defaultMarkerWithHue(
                                  hue.clamp(15.0, 330.0)),
                              infoWindow:
                                  const InfoWindow(title: 'Conductor en línea'),
                            ),
                          );
                        }
                      }
                    }

                    // Banner / pulso / FABs: conductor yendo al pickup o en viaje al destino.
                    final bool pulsoTaxistaEnMapa = v.uidTaxista.isNotEmpty &&
                        _isValidCoord(v.latTaxista, v.lonTaxista) &&
                        (estadoBase == EstadosViaje.aceptado ||
                            estadoBase == EstadosViaje.enCaminoPickup ||
                            estadoBase == EstadosViaje.enCurso);
                    if (pulsoTaxistaEnMapa) {
                      final LatLng txPos = _latLng(v.latTaxista, v.lonTaxista);
                      circles.add(
                        Circle(
                          circleId: const CircleId('taxista_pulse_inner'),
                          center: txPos,
                          radius: 120,
                          fillColor: Colors.greenAccent.withValues(alpha: 0.18),
                          strokeColor:
                              Colors.greenAccent.withValues(alpha: 0.55),
                          strokeWidth: 2,
                        ),
                      );
                      circles.add(
                        Circle(
                          circleId: const CircleId('taxista_pulse_outer'),
                          center: txPos,
                          radius: 220,
                          fillColor:
                              Colors.lightBlueAccent.withValues(alpha: 0.08),
                          strokeColor:
                              Colors.lightBlueAccent.withValues(alpha: 0.35),
                          strokeWidth: 1,
                        ),
                      );
                    }

                    final LatLng initialTarget =
                        _isValidCoord(v.latCliente, v.lonCliente)
                            ? _latLng(v.latCliente, v.lonCliente)
                            : (_isValidCoord(v.latDestino, v.lonDestino)
                                ? _latLng(v.latDestino, v.lonDestino)
                                : const LatLng(18.4861, -69.9312));

                    final String routeKey =
                        '${v.id}|${EstadosViaje.normalizar(v.estado)}|'
                        '${v.latCliente},${v.lonCliente}|'
                        '${v.latDestino},${v.lonDestino}|'
                        '${v.latTaxista},${v.lonTaxista}|'
                        '${_firmaWaypointsViaje(v)}';
                    if (routeKey != _lastRouteKey) {
                      _lastRouteKey = routeKey;
                      _scheduleDrawRoute(v);
                    }

                    final String boundsKey =
                        '${v.id}|${v.latCliente},${v.lonCliente}|'
                        '${v.latDestino},${v.lonDestino}|'
                        '${v.latTaxista},${v.lonTaxista}|'
                        '${_firmaWaypointsViaje(v)}';
                    if (_map != null && boundsKey != _lastBoundsKey) {
                      _lastBoundsKey = boundsKey;
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _fitBoundsFor(v));
                    }

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _maybeColapsarSheetPickupNav(v, estadoBase);
                      _maybeAnimarCamaraAlTaxista(v, estadoBase);
                      _schedulePickupEtaRefresh(v, estadoBase);
                    });

                    final bool cancelarHabilitado =
                        EstadosViaje.clientePuedeCancelarViajeDesdeApp(
                            estadoBase);
                    final String codigoVerificacion =
                        v.codigoVerificacion ?? '';
                    final bool codigoVerificado = v.codigoVerificado;

                    // ===== DETECCIÓN DE CERCANÍA (nunca setState durante build) =====
                    if (_isValidCoord(v.latTaxista, v.lonTaxista) &&
                        _isValidCoord(v.latCliente, v.lonCliente)) {
                      final double distanciaTaxista =
                          DistanciaService.calcularDistancia(
                        v.latTaxista,
                        v.lonTaxista,
                        v.latCliente,
                        v.lonCliente,
                      );
                      final bool cerca = distanciaTaxista < 0.2; // 200 metros
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
                                setState(() => _mostrarMensajeCercania = false);
                              }
                            });
                          } else if (!cerca && _mostrarMensajeCercania) {
                            setState(() => _mostrarMensajeCercania = false);
                            _mensajeCercaniaTimer?.cancel();
                          }
                        });
                      }
                    }

                    return Stack(
                      children: [
                        RepaintBoundary(
                          child: GoogleMap(
                            key: ValueKey<String>('gmap-${v.id}'),
                            initialCameraPosition:
                                CameraPosition(target: initialTarget, zoom: 14),
                            onMapCreated: (GoogleMapController c) {
                              _map = c;
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) async {
                                final GoogleMapController? mapRef = _map;
                                if (!mounted || mapRef == null) return;
                                try {
                                  _programmaticCameraDepth++;
                                  await mapRef.animateCamera(
                                      CameraUpdate.newLatLngZoom(
                                          initialTarget, 14));
                                } catch (_) {
                                  if (_programmaticCameraDepth > 0) {
                                    _programmaticCameraDepth--;
                                  }
                                }
                                final String bk =
                                    '${v.id}|${v.latCliente},${v.lonCliente}|'
                                    '${v.latDestino},${v.lonDestino}|'
                                    '${v.latTaxista},${v.lonTaxista}';
                                if (_lastBoundsKey != bk) {
                                  _lastBoundsKey = bk;
                                  await _fitBoundsFor(v);
                                }
                              });
                            },
                            onCameraMoveStarted: () {
                              _mapGestureEndDebounce?.cancel();
                              if (_programmaticCameraDepth == 0) {
                                _colapsarSheetPorTapMapa();
                              }
                              if (_seguirTaxistaCamara) {
                                setState(() => _seguirTaxistaCamara = false);
                              }
                            },
                            onCameraIdle: () {
                              if (_programmaticCameraDepth > 0) {
                                _programmaticCameraDepth--;
                                return;
                              }
                              _mapGestureEndDebounce?.cancel();
                              // Motor: no reexpandir la tarjeta al parar la cámara; el usuario
                              // baja el panel a mano para ver el mapa y no debe "subir sola".
                              if (!v.esMotor) {
                                _expandirSheetTrasMapaInteract();
                              }
                            },
                            onTap: (_) {
                              if (_programmaticCameraDepth > 0) return;
                              _colapsarSheetPorTapMapa();
                              _mapGestureEndDebounce?.cancel();
                              if (!v.esMotor) {
                                _mapGestureEndDebounce = Timer(
                                  const Duration(milliseconds: 420),
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
                            polylines: Set<Polyline>.of(_polylines.values),
                            compassEnabled: true,
                            mapToolbarEnabled: false,
                          ),
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
                                color: Colors.black.withValues(alpha: 0.88),
                                elevation: 6,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
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
                                                duration: const Duration(
                                                    milliseconds: 280),
                                                switchInCurve:
                                                    Curves.easeOutCubic,
                                                switchOutCurve:
                                                    Curves.easeInCubic,
                                                transitionBuilder:
                                                    (child, animation) {
                                                  return FadeTransition(
                                                    opacity: animation,
                                                    child: SlideTransition(
                                                      position: Tween<Offset>(
                                                        begin: const Offset(
                                                            0, 0.08),
                                                        end: Offset.zero,
                                                      ).animate(animation),
                                                      child: child,
                                                    ),
                                                  );
                                                },
                                                child: Text(
                                                  estadoBase ==
                                                          EstadosViaje.enCurso
                                                      ? 'Viaje en marcha · conductor en tiempo real'
                                                      : (_pickupEtaTitulo ??
                                                          'Tu conductor va hacia tu punto de recogida'),
                                                  key: ValueKey<String>(
                                                    estadoBase ==
                                                            EstadosViaje.enCurso
                                                        ? 'en-curso-title'
                                                        : (_pickupEtaTitulo ??
                                                            'pickup-title-default'),
                                                  ),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 15,
                                                    height: 1.25,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              _pickupEtaMinimizado
                                                  ? Icons.expand_more_rounded
                                                  : Icons.expand_less_rounded,
                                              color: Colors.white70,
                                            ),
                                          ],
                                        ),
                                        if (!_pickupEtaMinimizado &&
                                            (estadoBase ==
                                                    EstadosViaje.enCurso ||
                                                _pickupEtaDetalle != null ||
                                                _pickupEtaTitulo == null))
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                AnimatedSwitcher(
                                                  duration: const Duration(
                                                      milliseconds: 260),
                                                  switchInCurve:
                                                      Curves.easeOutCubic,
                                                  switchOutCurve:
                                                      Curves.easeInCubic,
                                                  transitionBuilder:
                                                      (child, animation) {
                                                    return FadeTransition(
                                                      opacity: animation,
                                                      child: child,
                                                    );
                                                  },
                                                  child: Text(
                                                    estadoBase ==
                                                            EstadosViaje.enCurso
                                                        ? 'Seguí la ubicación del conductor en el mapa; '
                                                            'tocá «Seguir conductor» si soltaste el seguimiento.'
                                                        : (_pickupEtaDetalle ??
                                                            'Mapa en vivo: podés seguir el desplazamiento y '
                                                                'subir o bajar la tarjeta inferior arrastrando.'),
                                                    key: ValueKey<String>(
                                                      estadoBase ==
                                                              EstadosViaje
                                                                  .enCurso
                                                          ? 'en-curso-detail'
                                                          : (_pickupEtaDetalle ??
                                                              'pickup-detail-default'),
                                                    ),
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 13,
                                                      height: 1.35,
                                                    ),
                                                  ),
                                                ),
                                                if (_isValidCoord(
                                                    v.latTaxista, v.lonTaxista))
                                                  Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: TextButton.icon(
                                                      onPressed: () => unawaited(
                                                        _openGoogleMapsVerUbicacionConductor(
                                                          v.latTaxista,
                                                          v.lonTaxista,
                                                        ),
                                                      ),
                                                      style:
                                                          TextButton.styleFrom(
                                                        foregroundColor:
                                                            const Color(
                                                                0xFF49F18B),
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 0,
                                                                vertical: 6),
                                                        tapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                      icon: const Icon(
                                                          Icons.map_rounded,
                                                          size: 18),
                                                      label: const Text(
                                                        'Navegar con mapa',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
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
                        if (_isValidCoord(v.latTaxista, v.lonTaxista))
                          Positioned(
                            top: pulsoTaxistaEnMapa ? 108 : 16,
                            right: 16,
                            child: FloatingActionButton.extended(
                              onPressed: () => _centrarEnTaxista(v),
                              icon: const Icon(Icons.my_location,
                                  color: Colors.white),
                              label: const Text('Seguir conductor',
                                  style: TextStyle(color: Colors.white)),
                              backgroundColor: Colors.black87,
                              heroTag: null,
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
                                final double pulso = 0.55 + (0.45 * math.sin(t * 2 * math.pi)).abs();
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D2B1A).withValues(
                                      alpha: 0.78 + (0.18 * pulso),
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.greenAccent.withValues(
                                        alpha: 0.55 + (0.4 * pulso),
                                      ),
                                      width: 1.1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.greenAccent.withValues(
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
                                        Icons.fiber_manual_record_rounded,
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
                        if (_isValidCoord(v.latTaxista, v.lonTaxista))
                          Positioned(
                            top: pulsoTaxistaEnMapa ? 164 : 72,
                            right: 16,
                            child: FloatingActionButton.extended(
                              onPressed: () => _centrarClienteYTaxista(v),
                              icon: const Icon(Icons.center_focus_strong,
                                  color: Colors.white),
                              label: const Text('Centrar ambos',
                                  style: TextStyle(color: Colors.white)),
                              backgroundColor: Colors.black54,
                              heroTag: null,
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
                        DraggableScrollableSheet(
                          controller: _sheetController,
                          initialChildSize: _kSheetInitialMitad,
                          minChildSize: _kSheetMinPickupNav,
                          maxChildSize: 0.9,
                          // En motor: arrastre continuo; en otros servicios se mantienen anclajes.
                          snap: !v.esMotor,
                          snapSizes: v.esMotor
                              ? null
                              : const [
                                  _kSheetMinPickupNav,
                                  0.35,
                                  _kSheetInitialMitad,
                                  0.9,
                                ],
                          builder: (context, scrollController) {
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(24)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 20,
                                    offset: const Offset(0, -5),
                                  ),
                                ],
                              ),
                              child: ListView(
                                controller: scrollController,
                                // Con poco contenido, sin esto el panel a veces no reacciona al
                                // arrastre vertical (comportamiento de DraggableScrollableSheet).
                                physics: v.esMotor
                                    ? const AlwaysScrollableScrollPhysics(
                                        parent: ClampingScrollPhysics(),
                                      )
                                    : null,
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  20 +
                                      MediaQuery.of(context).viewPadding.bottom +
                                      76,
                                ),
                                children: [
                                  Center(
                                    child: Container(
                                      width: 40,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: Colors.white24,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Mensaje de viaje programado
                                  if (estadoBase == EstadosViaje.pendiente &&
                                      v.uidTaxista.isEmpty)
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      margin: const EdgeInsets.only(bottom: 16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E1A0F),
                                        borderRadius: BorderRadius.circular(16),
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
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  if (esperandoTaxista)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 14),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF0F2818),
                                            Color(0xFF0A1A12)
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.greenAccent
                                              .withValues(alpha: 0.45),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.greenAccent
                                                .withValues(alpha: 0.12),
                                            blurRadius: 18,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Row(
                                            children: [
                                              Icon(Icons.radar,
                                                  color: Colors.greenAccent,
                                                  size: 22),
                                              SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  'Buscando conductor cercano',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _driversCount > 0
                                                ? 'Hay actividad en tu zona en este momento.'
                                                : 'Notificando a conductores en la zona…',
                                            style: const TextStyle(
                                                color: Colors.white60,
                                                fontSize: 13),
                                          ),
                                          if (_driversCount > 0) ...[
                                            const SizedBox(height: 14),
                                            ClienteConductoresCercaStrip(
                                              docsOrdenados: _isValidCoord(
                                                      v.latCliente,
                                                      v.lonCliente)
                                                  ? conductoresOrdenadosPorPickup(
                                                      _driversList,
                                                      pickupLat: v.latCliente,
                                                      pickupLon: v.lonCliente,
                                                    )
                                                  : List<
                                                      DocumentSnapshot<
                                                          Map<String,
                                                              dynamic>>>.from(
                                                      _driversList,
                                                    ),
                                              fotoPorUid: _driverFotoPorUid,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),

                                  if (v.uidTaxista.isNotEmpty &&
                                      _isValidCoord(v.latTaxista, v.lonTaxista))
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 16),
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
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color:
                                              Colors.greenAccent.withValues(alpha: 0.45),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _lineaEtaPickupCliente(v, estadoBase),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              height: 1.3,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
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
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: ElevatedButton.icon(
                                                  onPressed: () => _centrarEnTaxista(v),
                                                  icon: const Icon(Icons.my_location),
                                                  label: const Text('Ver en tiempo real'),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.greenAccent,
                                                    foregroundColor: Colors.black,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                  // Código de verificación y estado post-abordo
                                  if (v.uidTaxista.isNotEmpty &&
                                      !codigoVerificado &&
                                      estadoBase == EstadosViaje.aBordo &&
                                      codigoVerificacion.isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF2A1338),
                                            Color(0xFF1B0F2E),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                            color: Colors.purpleAccent,
                                            width: 1.6),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          const Row(
                                            children: [
                                              Icon(Icons.verified_user_rounded,
                                                  color: Colors.purpleAccent),
                                              SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Confirma tu abordo',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            'Comparte este código con tu conductor para iniciar el viaje.',
                                            style: TextStyle(
                                                color: Colors.white70,
                                                height: 1.3),
                                          ),
                                          const SizedBox(height: 14),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 14, horizontal: 20),
                                            decoration: BoxDecoration(
                                              color: Colors.black
                                                  .withValues(alpha: 0.45),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: Colors.purpleAccent),
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    codigoVerificacion,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 30,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      letterSpacing: 8,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton.icon(
                                              onPressed: () {
                                                Clipboard.setData(
                                                  ClipboardData(
                                                    text: codigoVerificacion,
                                                  ),
                                                );
                                                if (!mounted) return;
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                        'Código copiado.'),
                                                  ),
                                                );
                                              },
                                              icon: const Icon(Icons.copy_rounded,
                                                  size: 18),
                                              label: const Text(
                                                'Copiar código',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  if (v.uidTaxista.isNotEmpty &&
                                      !codigoVerificado &&
                                      estadoBase == EstadosViaje.aBordo &&
                                      codigoVerificacion.isEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.orange
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: Colors.orange
                                                .withValues(alpha: 0.5)),
                                      ),
                                      child: const Text(
                                        'Estás a bordo, pero este viaje no muestra un código de verificación en la app. '
                                        'Si el conductor lo necesita, contacta soporte.',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            height: 1.35),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  if (v.uidTaxista.isNotEmpty &&
                                      codigoVerificado &&
                                      (estadoBase == EstadosViaje.aBordo ||
                                          estadoBase == EstadosViaje.enCurso))
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.greenAccent.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.greenAccent
                                              .withValues(alpha: 0.55),
                                        ),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.check_circle_rounded,
                                              color: Colors.greenAccent),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Código validado. Tu viaje está en marcha, sigue el avance del conductor en tiempo real.',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.28),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  if (v.esTurismo)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.deepPurple
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: Colors.purpleAccent
                                                .withValues(alpha: 0.45)),
                                      ),
                                      child: const Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.travel_explore,
                                              color: Colors.purpleAccent,
                                              size: 26),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              'Viaje turístico: asignación y seguimiento coordinados por administración. '
                                              'Cronómetro, código y comisiones siguen el mismo flujo que un viaje normal.',
                                              style: TextStyle(
                                                  color: Colors.white70,
                                                  height: 1.35,
                                                  fontSize: 13),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  // Transferencia: desde que hay conductor hasta el fin (no en estados terminales).
                                  if (_mostrarDatosTransferenciaCliente(
                                      v, estadoBase)) ...[
                                    if (EstadosViaje.esAceptado(estadoBase) &&
                                        !EstadosViaje.esAbordo(estadoBase) &&
                                        !EstadosViaje.esEnCurso(estadoBase))
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
                                            'Puedes transferir al conductor ya: cuando vaya en camino o a bordo, '
                                            'el monto sigue siendo el mismo. Conserva tu comprobante.',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    _buildDatosBancarios(
                                        v, v.uidTaxista, v.precio, data),
                                    const SizedBox(height: 16),
                                  ],

                                  // Conductor primero: placa, llamada, WhatsApp y mapa visibles antes del detalle del viaje.
                                  if (v.uidTaxista.isNotEmpty) ...[
                                    _buildDriverCard(v),
                                    const SizedBox(height: 16),
                                  ],

                                  // Tarjeta de información del viaje
                                  _buildTripInfoCard(v, estadoBase),

                                  // Paradas intermedias
                                  if (v.waypoints != null &&
                                      v.waypoints!.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    _buildParadasWidget(v),
                                  ],

                                  const SizedBox(height: 20),

                                  // ========== BOTONES ORGANIZADOS PROFESIONALMENTE ==========

                                  // BOTÓN PRINCIPAL: Navegar al destino (solo en curso)
                                  if (estadoBase == EstadosViaje.enCurso &&
                                      _isValidCoord(v.latDestino, v.lonDestino))
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () =>
                                              abrirNavegacionAlDestino(v),
                                          icon: const Icon(Icons.navigation,
                                              color: Colors.black, size: 24),
                                          label: const Text(
                                            'NAVEGAR AL DESTINO',
                                            style: TextStyle(
                                                color: Colors.black,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.greenAccent,
                                            foregroundColor: Colors.black,
                                            minimumSize:
                                                const Size(double.infinity, 56),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16)),
                                            elevation: 0,
                                          ),
                                        ),
                                      ),
                                    ),

                                  // BOTÓN DE CANCELAR VIAJE (solo si es cancelable)
                                  if (cancelarHabilitado)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          onPressed: _cancelandoViajeCliente
                                              ? null
                                              : () => _deleteOrCancelEstricto(v),
                                          icon: const Icon(
                                            Icons.cancel_outlined,
                                            size: 20,
                                          ),
                                          label: Text(
                                            _cancelandoViajeCliente
                                                ? 'Cancelando...'
                                                : 'Cancelar viaje',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.redAccent,
                                            side: const BorderSide(
                                              color: Colors.redAccent,
                                              width: 1.4,
                                            ),
                                            minimumSize:
                                                const Size(double.infinity, 52),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 18,
                                              vertical: 14,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                        if (pulsoTaxistaEnMapa)
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: MediaQuery.sizeOf(context).height *
                                (_kSheetMinPickupNav + 0.02),
                            child: Material(
                              elevation: 8,
                              borderRadius: BorderRadius.circular(14),
                              color: Colors.black.withValues(alpha: 0.88),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    const Icon(Icons.local_taxi,
                                        color: Colors.greenAccent, size: 22),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _lineaEtaPickupCliente(v, estadoBase),
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
