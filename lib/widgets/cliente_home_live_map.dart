import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:flygo_nuevo/design_system/rai_ds_colors.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/drivers_location_nearby_repo.dart';
import 'package:flygo_nuevo/utils/rai_map_presentation.dart';
import 'package:flygo_nuevo/utils/rai_region_operativa.dart';
import 'package:flygo_nuevo/widgets/rai_live_driver_map_animator.dart';
import 'package:flygo_nuevo/widgets/rai_map_vehicle_icons.dart';

class _CamaraPlan {
  const _CamaraPlan({
    this.target,
    this.zoom,
    this.bounds,
    this.padding = 56,
    this.maxZoom = RaiMapPresentation.maxZoomTrip,
  });

  final LatLng? target;
  final double? zoom;
  final LatLngBounds? bounds;
  final double padding;
  final double maxZoom;

  bool get usaBounds => bounds != null;
}

/// Mapa en vivo del inicio cliente: conductores reales con app + GPS activos.
class ClienteHomeLiveMap extends StatefulWidget {
  const ClienteHomeLiveMap({
    super.key,
    required this.accentGreen,
    required this.isDark,
  });

  final Color accentGreen;
  final bool isDark;

  @override
  State<ClienteHomeLiveMap> createState() => _ClienteHomeLiveMapState();
}

class _ClienteHomeLiveMapState extends State<ClienteHomeLiveMap>
    with TickerProviderStateMixin {
  static const LatLng _fallbackCenter = RaiRegionOperativa.centroNacional;
  static const double _kRadioKmConductores = 30;
  static const int _kMaxConductoresCamara = 6;
  static const Duration _kAutoResumeCamara = Duration(seconds: 10);

  GoogleMapController? _map;
  DriversLocationNearbySession? _nearbySession;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _viajeSub;
  StreamSubscription<Position>? _gpsSub;
  Timer? _cameraDebounce;
  Timer? _autoResumeTimer;

  late final RaiLiveDriverMapAnimator _driverAnim;
  late final AnimationController _pulseCtrl;

  LatLng _center = _fallbackCenter;
  List<DocumentSnapshot<Map<String, dynamic>>> _rawDrivers =
      const <DocumentSnapshot<Map<String, dynamic>>>[];
  List<RaiLiveDriverPoint> _conductores = const <RaiLiveDriverPoint>[];
  int _conductoresCerca = 0;
  double? _kmConductorMasCercano;
  String? _miTaxistaAsignadoUid;
  String? _estadoViajeActivo;

  bool _ubicacionLista = false;
  bool _usuarioMovioCamara = false;
  bool _conductoresConsultados = false;
  String _zonaEtiqueta = RaiRegionOperativa.etiqueta(RaiRegionOperativa.otros);
  int _programmaticCameraDepth = 0;
  int _cameraAnimSeq = 0;
  LatLng? _ultimoTargetCamara;
  double? _ultimoZoomCamara;

  @override
  void initState() {
    super.initState();
    _driverAnim = RaiLiveDriverMapAnimator(vsync: this)
      ..onFrame = () {
        if (mounted) setState(() {});
      };
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    unawaited(RaiMapVehicleIcons.ensureLoaded());
    unawaited(_iniciarUbicacionEnVivo());
    _escucharConductores();
    _escucharViajeAsignado();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _driverAnim.dispose();
    _cameraDebounce?.cancel();
    _autoResumeTimer?.cancel();
    _nearbySession?.dispose();
    _userSub?.cancel();
    _viajeSub?.cancel();
    _gpsSub?.cancel();
    _map?.dispose();
    super.dispose();
  }

  double _mapHeight(BuildContext context) {
    final double h = MediaQuery.sizeOf(context).height;
    return (h * 0.42).clamp(300.0, 420.0);
  }

  void _escucharViajeAsignado() {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _userSub?.cancel();
    _userSub = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .snapshots()
        .listen((DocumentSnapshot<Map<String, dynamic>> snap) {
      final String viajeId =
          (snap.data()?['viajeActivoId'] ?? '').toString().trim();
      _viajeSub?.cancel();
      _viajeSub = null;
      if (viajeId.isEmpty) {
        if ((_miTaxistaAsignadoUid != null || _estadoViajeActivo != null) &&
            mounted) {
          setState(() {
            _miTaxistaAsignadoUid = null;
            _estadoViajeActivo = null;
          });
        }
        return;
      }
      _viajeSub = FirebaseFirestore.instance
          .collection('viajes')
          .doc(viajeId)
          .snapshots()
          .listen((DocumentSnapshot<Map<String, dynamic>> v) {
        final Map<String, dynamic>? vd = v.data();
        final String tid = (vd?['uidTaxista'] ??
                vd?['taxistaId'] ??
                '')
            .toString()
            .trim();
        final String est = (vd?['estado'] ?? '').toString().trim();
        if (!mounted) return;
        final String? next = tid.isEmpty ? null : tid;
        if (next != _miTaxistaAsignadoUid || est != _estadoViajeActivo) {
          setState(() {
            _miTaxistaAsignadoUid = next;
            _estadoViajeActivo = est.isEmpty ? null : est;
          });
          _nearbySession?.update(
            center: _center,
            uidAsignado: next,
            uidCliente: FirebaseAuth.instance.currentUser?.uid,
          );
          if (next != null) _programarAjusteCamara(inmediato: true);
        }
      });
    });
  }

  Future<void> _iniciarUbicacionEnVivo() async {
    try {
      final bool serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      final Position? last = await Geolocator.getLastKnownPosition();
      if (last != null && _coordsOk(last.latitude, last.longitude)) {
        _aplicarUbicacionUsuario(last.latitude, last.longitude, forzarCamara: true);
      }

      _gpsSub?.cancel();
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 12,
        ),
      ).listen((Position pos) {
        if (!_coordsOk(pos.latitude, pos.longitude)) return;
        _aplicarUbicacionUsuario(pos.latitude, pos.longitude);
      });
    } catch (_) {}
  }

  void _aplicarUbicacionUsuario(
    double lat,
    double lon, {
    bool forzarCamara = false,
  }) {
    final bool primeraVez = !_ubicacionLista;
    final double movimientoKm = _ubicacionLista
        ? DistanciaService.calcularDistancia(
            _center.latitude,
            _center.longitude,
            lat,
            lon,
          )
        : double.infinity;

    if (!primeraVez && !forzarCamara && movimientoKm < 0.012) return;

    if (!mounted) return;
    setState(() {
      _center = LatLng(lat, lon);
      _ubicacionLista = true;
      _zonaEtiqueta = RaiRegionOperativa.etiqueta(
        RaiRegionOperativa.resolver(lat, lon),
      );
    });
    _recalcularConductores();
    _nearbySession?.update(center: LatLng(lat, lon));
    _programarAjusteCamara(inmediato: primeraVez || forzarCamara);
  }

  void _recalcularConductores() {
    if (_rawDrivers.isEmpty) return;
    final String? uidCliente = FirebaseAuth.instance.currentUser?.uid;
    _aplicarConductores(
      DriversLocationNearbyUpdate(
        conductores: raiLiveDriversDesdeDocs(
          _rawDrivers,
          centroKm: _ubicacionLista ? _center : null,
          radioKm: _ubicacionLista ? _kRadioKmConductores : null,
          uidCliente: uidCliente,
        ),
        docs: _rawDrivers,
        region: RaiRegionOperativa.resolver(_center.latitude, _center.longitude),
      ),
    );
  }

  void _aplicarConductores(DriversLocationNearbyUpdate update) {
    final String? miUid = FirebaseAuth.instance.currentUser?.uid;
    _driverAnim.syncTargets(update.conductores);

    String? asignado = _miTaxistaAsignadoUid;
    if (asignado == null || asignado.isEmpty) {
      for (final RaiLiveDriverPoint d in update.conductores) {
        if (d.esAsignadoA(miUid)) {
          asignado = d.uid;
          break;
        }
      }
    }

    final double? kmCercano = update.conductores.isEmpty
        ? null
        : DistanciaService.calcularDistancia(
            _center.latitude,
            _center.longitude,
            update.conductores.first.position.latitude,
            update.conductores.first.position.longitude,
          );

    setState(() {
      _rawDrivers = update.docs;
      _conductores = update.conductores;
      _conductoresCerca = update.conductores.length;
      _kmConductorMasCercano = kmCercano;
      _conductoresConsultados = true;
      _zonaEtiqueta = RaiRegionOperativa.etiqueta(update.region);
      if (asignado != null && asignado.isNotEmpty) {
        _miTaxistaAsignadoUid = asignado;
      }
    });
    _programarAjusteCamara();
  }

  void _escucharConductores() {
    _nearbySession?.dispose();
    final String? uidCliente = FirebaseAuth.instance.currentUser?.uid;
    _nearbySession = DriversLocationNearbyRepo.createSession(
      initialCenter: _center,
      uidAsignado: _miTaxistaAsignadoUid,
      uidCliente: uidCliente,
      radiusKm: _kRadioKmConductores,
      maxResultados: 60,
      onUpdate: (DriversLocationNearbyUpdate update) {
        if (!mounted) return;
        _aplicarConductores(update);
      },
    );
  }

  bool _coordsOk(double lat, double lon) =>
      lat.isFinite && lon.isFinite && lat.abs() <= 90 && lon.abs() <= 180;

  void _programarAjusteCamara({bool inmediato = false}) {
    if (_usuarioMovioCamara) return;
    _cameraDebounce?.cancel();
    final Duration delay =
        inmediato ? Duration.zero : const Duration(milliseconds: 480);
    _cameraDebounce = Timer(delay, () {
      if (!mounted) return;
      unawaited(_ajustarCamaraInteligente());
    });
  }

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  List<RaiLiveDriverPoint> get _focoCamara {
    if (_miTaxistaAsignadoUid != null && _miTaxistaAsignadoUid!.isNotEmpty) {
      for (final RaiLiveDriverPoint d in _conductores) {
        if (d.uid == _miTaxistaAsignadoUid) {
          return <RaiLiveDriverPoint>[d];
        }
      }
    }
    return _conductores.take(_kMaxConductoresCamara).toList(growable: false);
  }

  _CamaraPlan _planificarCamara() {
    final List<RaiLiveDriverPoint> foco = _focoCamara;

    if (foco.isEmpty) {
      return _CamaraPlan(
        target: _center,
        zoom: _ubicacionLista ? 14.4 : 12.3,
      );
    }

    final RaiLiveDriverPoint nearest = foco.first;
    final double kmCercano = DistanciaService.calcularDistancia(
      _center.latitude,
      _center.longitude,
      nearest.position.latitude,
      nearest.position.longitude,
    );

    final bool esAsignado =
        _miTaxistaAsignadoUid != null && nearest.uid == _miTaxistaAsignadoUid;

    if (_ubicacionLista && (esAsignado || kmCercano <= 1.2)) {
      final double bias = esAsignado ? 0.54 : 0.48;
      return _CamaraPlan(
        target: _lerpLatLng(_center, nearest.position, bias),
        zoom: esAsignado
            ? (17.0 - kmCercano * 0.35).clamp(15.5, 17.2)
            : (16.4 - kmCercano * 0.65).clamp(15.0, 16.4),
      );
    }

    final List<LatLng> pts = <LatLng>[
      if (_ubicacionLista) _center,
      ...foco.map((d) => d.position),
    ];
    return _CamaraPlan(
      bounds: RaiMapPresentation.boundsFromPoints(pts),
      padding: 52,
      maxZoom: kmCercano <= 2 ? 15.8 : 14.2,
    );
  }

  bool _cambioCamaraSignificativo(_CamaraPlan plan) {
    if (plan.usaBounds) {
      _ultimoTargetCamara = null;
      _ultimoZoomCamara = null;
      return true;
    }
    final LatLng? prev = _ultimoTargetCamara;
    final double? prevZ = _ultimoZoomCamara;
    if (prev == null || prevZ == null || plan.target == null || plan.zoom == null) {
      return true;
    }
    final double movKm = DistanciaService.calcularDistancia(
      prev.latitude,
      prev.longitude,
      plan.target!.latitude,
      plan.target!.longitude,
    );
    return movKm > 0.035 || (plan.zoom! - prevZ).abs() > 0.35;
  }

  Future<void> _conCamaraProgramatica(Future<void> Function() accion) async {
    _programmaticCameraDepth++;
    try {
      await accion();
    } finally {
      _programmaticCameraDepth =
          (_programmaticCameraDepth - 1).clamp(0, 999);
    }
  }

  Future<void> _ajustarCamaraInteligente() async {
    final GoogleMapController? c = _map;
    if (c == null || _usuarioMovioCamara) return;

    final _CamaraPlan plan = _planificarCamara();
    if (!_cambioCamaraSignificativo(plan)) return;

    final int runId = ++_cameraAnimSeq;

    await _conCamaraProgramatica(() async {
      if (plan.usaBounds && plan.bounds != null) {
        if (runId != _cameraAnimSeq) return;
        await RaiMapPresentation.fitBounds(
          c,
          plan.bounds!,
          padding: plan.padding,
          maxZoom: plan.maxZoom,
        );
        return;
      }

      if (plan.target == null || plan.zoom == null) return;
      if (runId != _cameraAnimSeq) return;
      await c.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: plan.target!, zoom: plan.zoom!),
        ),
      );
      _ultimoTargetCamara = plan.target;
      _ultimoZoomCamara = plan.zoom;
    });
  }

  void _onCameraIdle() {
    if (!_usuarioMovioCamara) return;
    _autoResumeTimer?.cancel();
    _autoResumeTimer = Timer(_kAutoResumeCamara, () {
      if (!mounted || !_usuarioMovioCamara) return;
      setState(() => _usuarioMovioCamara = false);
      _programarAjusteCamara(inmediato: true);
    });
  }

  void _onUserGesture() {
    if (_programmaticCameraDepth > 0) return;
    _autoResumeTimer?.cancel();
    if (!_usuarioMovioCamara) {
      setState(() => _usuarioMovioCamara = true);
    }
  }

  int _etaMinutosAprox(double km) => math.max(1, (km / 0.38).round());

  Set<Marker> _buildMarkers() {
    final Set<Marker> out = <Marker>{};
    final String? miUid = FirebaseAuth.instance.currentUser?.uid;

    if (_ubicacionLista) {
      out.add(
        Marker(
          markerId: const MarkerId('cliente_home'),
          position: _center,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          zIndexInt: 3,
        ),
      );
    }

    for (final RaiLiveDriverPoint d in _conductores) {
      final LatLng pos =
          _driverAnim.displayPositions[d.uid] ?? d.position;
      final bool esAsignado =
          d.uid == _miTaxistaAsignadoUid || d.esAsignadoA(miUid);
      final bool faseRecogida = esAsignado &&
          RaiMapVehicleIcons.faseRecogidaDesdeEstado(_estadoViajeActivo);
      final bool enViaje = d.enViaje;
      final double bearing = RaiMapVehicleIcons.resolverBearing(
        actual: pos,
        headingGps: d.heading,
        fallback: _driverAnim.bearingFor(d.uid),
      );

      final BitmapDescriptor? iconoVeh =
          RaiMapVehicleIcons.iconoVistaCliente(
        esMiConductor: esAsignado,
        faseRecogida: faseRecogida,
      );
      final BitmapDescriptor icon = iconoVeh ??
          (enViaje
              ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange)
              : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen));

      final bool usaIconoVehiculo = iconoVeh != null;

      out.add(
        Marker(
          markerId: MarkerId('drv_${d.uid}'),
          position: pos,
          icon: icon,
          anchor: usaIconoVehiculo
              ? const Offset(0.5, 0.5)
              : const Offset(0.5, 1.0),
          rotation: usaIconoVehiculo
              ? RaiMapVehicleIcons.rotationTaxiCliente(bearing)
              : 0,
          flat: usaIconoVehiculo,
          zIndexInt: faseRecogida ? 6 : (d.online ? 2 : 1),
          infoWindow: InfoWindow(
            title: esAsignado
                ? (faseRecogida ? 'Tu conductor viene' : 'Tu conductor')
                : (enViaje ? 'Ocupado' : 'Disponible'),
            snippet: enViaje && !esAsignado ? 'En servicio en la zona' : null,
          ),
        ),
      );
    }
    return out;
  }

  Set<Circle> _buildCircles() {
    if (!_ubicacionLista) return const <Circle>{};
    final Set<Circle> out = <Circle>{
      Circle(
        circleId: const CircleId('cliente_pulse'),
        center: _center,
        radius: 420,
        fillColor: widget.accentGreen.withValues(alpha: 0.07),
        strokeColor: widget.accentGreen.withValues(alpha: 0.35),
        strokeWidth: 2,
      ),
    };

    if (_miTaxistaAsignadoUid != null) {
      RaiLiveDriverPoint? asignado;
      for (final RaiLiveDriverPoint d in _conductores) {
        if (d.uid == _miTaxistaAsignadoUid) {
          asignado = d;
          break;
        }
      }
      if (asignado != null) {
        final LatLng pos =
            _driverAnim.displayPositions[asignado.uid] ?? asignado.position;
        out.add(
          Circle(
            circleId: const CircleId('assigned_driver_pulse'),
            center: pos,
            radius: 200,
            fillColor: const Color(0x44E53935),
            strokeColor: const Color(0xFFE53935),
            strokeWidth: 2,
          ),
        );
      }
    } else if (_conductores.isNotEmpty) {
      final RaiLiveDriverPoint nearest = _conductores.first;
      final LatLng pos =
          _driverAnim.displayPositions[nearest.uid] ?? nearest.position;
      out.add(
        Circle(
          circleId: const CircleId('nearest_driver_pulse'),
          center: pos,
          radius: math.max(160, 340 - ( _kmConductorMasCercano ?? 1) * 45),
          fillColor: widget.accentGreen.withValues(alpha: 0.06),
          strokeColor: widget.accentGreen.withValues(alpha: 0.32),
          strokeWidth: 2,
        ),
      );
    }
    return out;
  }

  String _leyendaInferior() {
    if (_miTaxistaAsignadoUid != null && _miTaxistaAsignadoUid!.isNotEmpty) {
      RaiLiveDriverPoint? asignado;
      for (final RaiLiveDriverPoint d in _conductores) {
        if (d.uid == _miTaxistaAsignadoUid) {
          asignado = d;
          break;
        }
      }
      if (asignado != null) {
        final double km = DistanciaService.calcularDistancia(
          _center.latitude,
          _center.longitude,
          asignado.position.latitude,
          asignado.position.longitude,
        );
        final String dist = km < 1
            ? '${(km * 1000).round()} m'
            : '${km.toStringAsFixed(1)} km';
        return 'Tu conductor en vivo · a $dist (~${_etaMinutosAprox(km)} min)';
      }
      return 'Tu conductor aceptó · ubicándolo en el mapa…';
    }
    if (!_ubicacionLista) {
      return 'Red RAI en tiempo real · activa ubicación para ver conductores en tu zona';
    }
    if (_kmConductorMasCercano == null) {
      if (!_conductoresConsultados) {
        return 'Buscando conductores en $_zonaEtiqueta…';
      }
      return 'Red activa en $_zonaEtiqueta · pedí tu viaje y te conectamos con un conductor';
    }
    final double km = _kmConductorMasCercano!;
    final String dist = km < 1
        ? '${(km * 1000).round()} m'
        : '${km.toStringAsFixed(1)} km';
    final int eta = _etaMinutosAprox(km);
    if (_conductoresCerca == 1) {
      return '1 conductor en vivo a $dist · ~$eta min';
    }
    return '$_conductoresCerca conductores en vivo · el más próximo a $dist (~$eta min)';
  }

  String? _leyendaColores() {
    if (_conductoresCerca == 0 || _miTaxistaAsignadoUid != null) return null;
    return 'Verde = disponible · Rojo = en viaje';
  }

  @override
  Widget build(BuildContext context) {
    final double mapHeight = _mapHeight(context);
    final Color border = widget.isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    final Color chipBg = widget.isDark
        ? Colors.black.withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.92);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: widget.isDark ? 0.35 : 0.10),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: SizedBox(
          height: mapHeight,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _center,
                  zoom: 13.6,
                ),
                onMapCreated: (GoogleMapController c) {
                  _map = c;
                  _programarAjusteCamara(inmediato: true);
                },
                onCameraMoveStarted: _onUserGesture,
                onCameraIdle: _onCameraIdle,
                onTap: (_) => _onUserGesture(),
                markers: _buildMarkers(),
                circles: _buildCircles(),
                myLocationEnabled: _ubicacionLista,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                liteModeEnabled: false,
                trafficEnabled: true,
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 56,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: widget.isDark ? 0.58 : 0.24),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: _LiveChip(
                  pulse: _pulseCtrl,
                  accent: widget.accentGreen,
                  background: chipBg,
                  tieneAsignado: _miTaxistaAsignadoUid != null,
                ),
              ),
              Positioned(
                right: 10,
                top: 10,
                child: _ConductoresChip(
                  count: _conductoresCerca,
                  kmCercano: _kmConductorMasCercano,
                  background: chipBg,
                  accent: widget.accentGreen,
                  isDark: widget.isDark,
                  tieneAsignado: _miTaxistaAsignadoUid != null,
                  consultado: _conductoresConsultados,
                ),
              ),
              if (_ubicacionLista &&
                  _conductoresCerca == 0 &&
                  _miTaxistaAsignadoUid == null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: _ZonaSinConductoresCard(
                        zona: _zonaEtiqueta,
                        consultado: _conductoresConsultados,
                        background: chipBg,
                        accent: widget.accentGreen,
                        isDark: widget.isDark,
                      ),
                    ),
                  ),
                ),
              if (_usuarioMovioCamara)
                Positioned(
                  right: 10,
                  bottom: 52,
                  child: Material(
                    color: chipBg,
                    elevation: 2,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () {
                        _autoResumeTimer?.cancel();
                        setState(() => _usuarioMovioCamara = false);
                        _ultimoTargetCamara = null;
                        _ultimoZoomCamara = null;
                        _programarAjusteCamara(inmediato: true);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.my_location_rounded,
                              size: 15,
                              color: widget.accentGreen,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _miTaxistaAsignadoUid != null
                                  ? 'Seguir conductor'
                                  : 'Seguir cercanos',
                              style: TextStyle(
                                color: widget.isDark
                                    ? Colors.white
                                    : Colors.black87,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: widget.isDark ? 0.74 : 0.48),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    _leyendaInferior(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.94),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
              if (_leyendaColores() != null)
                Positioned(
                  left: 10,
                  bottom: 44,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: Text(
                        _leyendaColores()!,
                        style: TextStyle(
                          color: widget.isDark ? Colors.white70 : Colors.black87,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZonaSinConductoresCard extends StatelessWidget {
  const _ZonaSinConductoresCard({
    required this.zona,
    required this.consultado,
    required this.background,
    required this.accent,
    required this.isDark,
  });

  final String zona;
  final bool consultado;
  final Color background;
  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final String titulo = consultado
        ? 'Aún no hay conductores visibles en $zona'
        : 'Buscando conductores en $zona…';
    final String subtitulo = consultado
        ? 'La red RAI está activa. Puedes pedir tu viaje y te conectamos con el más cercano.'
        : 'Conectando con la red en tiempo real…';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accent.withValues(alpha: 0.28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.travel_explore_rounded,
                color: accent,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: (isDark ? Colors.white : Colors.black87)
                      .withValues(alpha: 0.72),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  const _LiveChip({
    required this.pulse,
    required this.accent,
    required this.background,
    required this.tieneAsignado,
  });

  final Animation<double> pulse;
  final Color accent;
  final Color background;
  final bool tieneAsignado;

  @override
  Widget build(BuildContext context) {
    final Color liveColor = tieneAsignado ? const Color(0xFFE53935) : accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: liveColor.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: pulse,
              builder: (context, _) {
                final double t = pulse.value;
                return Container(
                  width: 8 + (t * 3),
                  height: 8 + (t * 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: liveColor,
                    boxShadow: [
                      BoxShadow(
                        color: liveColor.withValues(alpha: 0.35 + t * 0.25),
                        blurRadius: 6 + t * 4,
                        spreadRadius: t * 1.5,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(width: 7),
            Text(
              tieneAsignado ? 'TU TAXI' : 'EN VIVO',
              style: TextStyle(
                color: liveColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConductoresChip extends StatelessWidget {
  const _ConductoresChip({
    required this.count,
    required this.kmCercano,
    required this.background,
    required this.accent,
    required this.isDark,
    required this.tieneAsignado,
    required this.consultado,
  });

  final int count;
  final double? kmCercano;
  final Color background;
  final Color accent;
  final bool isDark;
  final bool tieneAsignado;
  final bool consultado;

  @override
  Widget build(BuildContext context) {
    final String label;
    if (tieneAsignado) {
      label = kmCercano != null && kmCercano! < 1
          ? 'En camino · ${(kmCercano! * 1000).round()} m'
          : 'Tu conductor en camino';
    } else if (count == 0) {
      label = consultado ? 'En tu zona' : 'Buscando en tu zona';
    } else if (kmCercano != null && kmCercano! < 1) {
      label = '$count en vivo · ${(kmCercano! * 1000).round()} m';
    } else if (kmCercano != null) {
      label = '$count en vivo · ${kmCercano!.toStringAsFixed(1)} km';
    } else {
      label = count == 1 ? '1 conductor en vivo' : '$count conductores en vivo';
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_taxi_rounded,
              size: 14,
              color: tieneAsignado
                  ? const Color(0xFFE53935)
                  : (count > 0
                      ? accent
                      : RaiDsColors.neon.withValues(alpha: 0.7)),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
