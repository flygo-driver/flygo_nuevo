import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flygo_nuevo/utils/navegacion_salida_app.dart';
import 'package:flygo_nuevo/servicios/navigation_service.dart';
import 'package:flygo_nuevo/shell/cliente_shell.dart';
import 'package:flygo_nuevo/widgets/rai_app_bar.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/modelo/chofer_turismo.dart';
import 'package:flygo_nuevo/navegacion/post_viaje_cliente_nav.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/choferes_turismo_repo.dart';
import 'package:flygo_nuevo/servicios/asignacion_turismo_repo.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';
import 'package:flygo_nuevo/legal/terms_data.dart';
import 'package:flygo_nuevo/utils/telefono_viaje.dart';
import 'package:flygo_nuevo/widgets/turismo_mensaje_operaciones_panel.dart';
import 'package:url_launcher/url_launcher.dart';

/// Contacto para asignación turismo (sin chofer disponible / urgencia ADM).
const String _kTurismoSoporteEmail = kTermsContactEmail;
const String _kTurismoSoporteTelDigitos = '18094201481';
const String _kTurismoSoporteTelVisible = '809-420-1481';

class EsperaAsignacionTurismo extends StatefulWidget {
  final String viajeId;
  const EsperaAsignacionTurismo({super.key, required this.viajeId});

  @override
  State<EsperaAsignacionTurismo> createState() =>
      _EsperaAsignacionTurismoState();
}

class _EsperaAsignacionTurismoState extends State<EsperaAsignacionTurismo>
    with SingleTickerProviderStateMixin {
  static const double _kEsperaSheetMin = 0.24;
  static const double _kEsperaSheetInitial = 0.42;

  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  GoogleMapController? _map;
  final Set<Polyline> _polylines = {};
  String? _rutaViajeIdCargada;
  String _ultimaFirmaBounds = '';
  StreamSubscription<List<ChoferTurismo>>? _choferesSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _choferAsignadoSub;
  List<ChoferTurismo> _choferesRed = <ChoferTurismo>[];
  String _choferesStreamSig = '';
  String _choferAsignadoStreamUid = '';
  LatLng? _ubicacionChoferAsignado;
  Timer? _reintentoAutoAsignacionTimer;
  Timer? _navegarViajeActivoTimer;
  bool _reintentoAutoEnCurso = false;
  bool _navegacionViajeActivoProgramada = false;
  bool _postCompletadoEnCurso = false;
  String _ultimoTaxistaAsignadoNotificado = '';

  List<ChoferTurismo> get _choferesDisponiblesEnMapa => _choferesRed
      .where((ChoferTurismo c) => c.disponible && c.ultimaUbicacion != null)
      .toList();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _reintentoAutoAsignacionTimer?.cancel();
    _navegarViajeActivoTimer?.cancel();
    _stopChoferAsignadoStream(notificarUi: false);
    _stopChoferesStream(notificarUi: false);
    _controller.dispose();
    _map?.dispose();
    super.dispose();
  }

  void _stopChoferAsignadoStream({bool notificarUi = true}) {
    _choferAsignadoSub?.cancel();
    _choferAsignadoSub = null;
    _choferAsignadoStreamUid = '';
    if (_ubicacionChoferAsignado == null) return;
    _ubicacionChoferAsignado = null;
    if (notificarUi && mounted) setState(() {});
  }

  void _ensureChoferAsignadoUbicacionStream(String uidChofer) {
    if (uidChofer.isEmpty) {
      _stopChoferAsignadoStream();
      return;
    }
    if (_choferAsignadoStreamUid == uidChofer && _choferAsignadoSub != null) {
      return;
    }
    _choferAsignadoStreamUid = uidChofer;
    _choferAsignadoSub?.cancel();
    _choferAsignadoSub = FirebaseFirestore.instance
        .collection('choferes_turismo')
        .doc(uidChofer)
        .snapshots()
        .listen(
      (DocumentSnapshot<Map<String, dynamic>> snap) {
        if (!snap.exists) return;
        final Map<String, dynamic> d = snap.data() ?? <String, dynamic>{};
        final GeoPoint? u = d['ultimaUbicacion'] as GeoPoint?;
        LatLng? nueva;
        if (u != null && _coordOk(u.latitude, u.longitude)) {
          nueva = LatLng(u.latitude, u.longitude);
        } else {
          final Map<String, dynamic>? ubic =
              d['ubicacion'] as Map<String, dynamic>?;
          final double? lat = _numCoord(ubic?['lat']);
          final double? lon = _numCoord(ubic?['lon']);
          if (_coordOk(lat, lon)) nueva = LatLng(lat!, lon!);
        }
        if (nueva == null) return;
        if (!mounted) return;
        if (_ubicacionChoferAsignado?.latitude == nueva.latitude &&
            _ubicacionChoferAsignado?.longitude == nueva.longitude) {
          return;
        }
        setState(() => _ubicacionChoferAsignado = nueva);
        final Map<String, dynamic>? viaje = _ultimoDataViaje;
        if (viaje != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_ajustarCamara(viaje));
          });
        }
      },
      onError: (_) {},
    );
  }

  Map<String, dynamic>? _ultimoDataViaje;

  void _ensureReintentoAutoAsignacion(Map<String, dynamic> data) {
    final String taxistaId =
        (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString();
    if (taxistaId.isNotEmpty) {
      _reintentoAutoAsignacionTimer?.cancel();
      _reintentoAutoAsignacionTimer = null;
      return;
    }
    if (!AsignacionTurismoRepo.estadoPermiteAutoAsignacionTurismo(data)) return;
    if (_reintentoAutoAsignacionTimer != null) return;

    unawaited(_intentarAsignacionAutomaticaSilenciosa());

    _reintentoAutoAsignacionTimer = Timer.periodic(
      const Duration(seconds: 35),
      (_) => unawaited(_intentarAsignacionAutomaticaSilenciosa()),
    );
  }

  Future<void> _intentarAsignacionAutomaticaSilenciosa() async {
    if (_reintentoAutoEnCurso || !mounted) return;
    _reintentoAutoEnCurso = true;
    try {
      final bool esAhora = _ultimoDataViaje?['esAhora'] == true;
      await AsignacionTurismoRepo.publicarViajeEnPoolTurismo(
        viajeId: widget.viajeId,
        omitirVentanaPublicacion: esAhora,
      );
    } catch (_) {
      // Firestore stream reflejará pool turístico o ventana programada.
    } finally {
      _reintentoAutoEnCurso = false;
    }
  }

  void _notificarAsignacionChofer(BuildContext context, Map<String, dynamic> data) {
    final String taxistaId =
        (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString();
    if (taxistaId.isEmpty || taxistaId == _ultimoTaxistaAsignadoNotificado) {
      return;
    }
    _ultimoTaxistaAsignadoNotificado = taxistaId;
    final String nombre =
        (data['nombreTaxista'] ?? '').toString().trim();
    final String titulo = nombre.isNotEmpty
        ? '¡Chofer asignado: $nombre!'
        : '¡Chofer asignado a tu viaje!';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(titulo),
        backgroundColor: Colors.green.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  bool _viajeOperativoParaMapa(Map<String, dynamic> data) {
    if (data['completado'] == true) return false;
    final String st =
        EstadosViaje.normalizar((data['estado'] ?? '').toString());
    return !EstadosViaje.esTerminal(st);
  }

  void _programarNavegacionViajeActivo(BuildContext context) {
    if (_navegacionViajeActivoProgramada) return;
    _navegacionViajeActivoProgramada = true;
    _navegarViajeActivoTimer?.cancel();
    final NavigatorState? navRoot =
        Navigator.of(context, rootNavigator: true);
    _navegarViajeActivoTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      unawaited(
        NavigationService.irAViajeEnCursoClienteTrasAsignacionTaxista(
          preNav: navRoot,
        ),
      );
    });
  }

  void _procesarActualizacionViaje(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    _ultimoDataViaje = data;
    final String taxistaId =
        (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString();

    if (taxistaId.isNotEmpty &&
        AsignacionTurismoRepo.viajeTurismoChoferConfirmado(data)) {
      _ensureChoferAsignadoUbicacionStream(taxistaId);
      _notificarAsignacionChofer(context, data);
      if (_viajeOperativoParaMapa(data)) {
        _programarNavegacionViajeActivo(context);
      }
    } else {
      _stopChoferAsignadoStream();
      _navegacionViajeActivoProgramada = false;
      _navegarViajeActivoTimer?.cancel();
      _ultimoTaxistaAsignadoNotificado = '';
      _ensureReintentoAutoAsignacion(data);
    }

    _syncMapaConViaje(data);
  }

  String? _tipoVehiculoFiltro(Map<String, dynamic> data) {
    final String t = (data['subtipoTurismo'] ?? '').toString().toLowerCase();
    if (t == 'busqueda' || t.isEmpty) return null;
    const validos = <String>{'carro', 'jeepeta', 'minivan', 'bus'};
    return validos.contains(t) ? t : null;
  }

  int get _choferesConUbicacionEnMapa => _choferesDisponiblesEnMapa.length;

  String _firmaChoferesMapa() {
    return _choferesRed
        .map((ChoferTurismo c) {
          final GeoPoint? u = c.ultimaUbicacion;
          if (u == null) return '${c.uid}:na';
          return '${c.uid}:${u.latitude.toStringAsFixed(4)},${u.longitude.toStringAsFixed(4)}';
        })
        .join(';');
  }

  void _stopChoferesStream({bool notificarUi = true}) {
    _choferesSub?.cancel();
    _choferesSub = null;
    _choferesStreamSig = '';
    if (_choferesRed.isEmpty) return;
    _choferesRed = <ChoferTurismo>[];
    if (notificarUi && mounted) setState(() {});
  }

  void _ensureChoferesStream(Map<String, dynamic> data) {
    final String taxistaId =
        (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString();
    if (taxistaId.isNotEmpty) {
      _stopChoferesStream();
      return;
    }

    final LatLng? pickup = _pickupLatLng(data);
    final String? tipo = _tipoVehiculoFiltro(data);
    final String sig =
        '${pickup?.latitude},${pickup?.longitude}|${tipo ?? 'todos'}';
    if (_choferesStreamSig == sig && _choferesSub != null) return;
    _choferesStreamSig = sig;
    _choferesSub?.cancel();

    _choferesSub = ChoferesTurismoRepo.streamChoferesRedAprobados(
      tipoVehiculo: tipo,
      lat: pickup?.latitude,
      lon: pickup?.longitude,
      radioKm: 60,
    ).listen(
      (List<ChoferTurismo> lista) {
        if (!mounted) return;
        setState(() => _choferesRed = lista);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_ajustarCamara(data));
        });
      },
      onError: (_) {},
    );
  }

  double? _numCoord(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }

  bool _coordOk(double? lat, double? lon) {
    if (lat == null || lon == null) return false;
    if (!lat.isFinite || !lon.isFinite) return false;
    if (lat == 0 && lon == 0) return false;
    return lat.abs() <= 90 && lon.abs() <= 180;
  }

  LatLng? _pickupLatLng(Map<String, dynamic> data) {
    final double? lat = _numCoord(data['latCliente'] ?? data['latOrigen']);
    final double? lon = _numCoord(data['lonCliente'] ?? data['lonOrigen']);
    if (!_coordOk(lat, lon)) return null;
    return LatLng(lat!, lon!);
  }

  LatLng? _destinoLatLng(Map<String, dynamic> data) {
    final double? lat = _numCoord(data['latDestino']);
    final double? lon = _numCoord(data['lonDestino']);
    if (!_coordOk(lat, lon)) return null;
    return LatLng(lat!, lon!);
  }

  LatLng? _taxistaLatLng(Map<String, dynamic> data) {
    final double? lat =
        _numCoord(data['latTaxista'] ?? data['driverLat']);
    final double? lon =
        _numCoord(data['lonTaxista'] ?? data['driverLon']);
    if (_coordOk(lat, lon)) return LatLng(lat!, lon!);
    return _ubicacionChoferAsignado;
  }

  bool _viajeTieneChoferAsignado(Map<String, dynamic> data) {
    return AsignacionTurismoRepo.viajeTurismoChoferConfirmado(data);
  }

  int _choferesCompatiblesConViaje(Map<String, dynamic> data) {
    return AsignacionTurismoRepo.contarChoferesCompatiblesEnRed(
      data,
      _choferesRed,
    );
  }

  Set<Marker> _markersFor(Map<String, dynamic> data) {
    final Set<Marker> markers = <Marker>{};
    final LatLng? pickup = _pickupLatLng(data);
    final LatLng? destino = _destinoLatLng(data);
    final LatLng? taxista = _taxistaLatLng(data);
    final String origenTxt = (data['origen'] ?? 'Recogida').toString();
    final String destinoTxt = (data['destino'] ?? 'Destino').toString();

    if (pickup != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(title: 'Recogida: $origenTxt'),
        ),
      );
    }
    if (destino != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destino'),
          position: destino,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueViolet,
          ),
          infoWindow: InfoWindow(title: 'Destino: $destinoTxt'),
        ),
      );
    }
    if (taxista != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('chofer'),
          position: taxista,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Chofer asignado'),
          zIndexInt: 3,
        ),
      );
    } else {
      final String? tipoFiltro = _tipoVehiculoFiltro(data);
      for (final ChoferTurismo chofer in _choferesDisponiblesEnMapa) {
        final GeoPoint? u = chofer.ultimaUbicacion;
        if (u == null) continue;
        if (!_coordOk(u.latitude, u.longitude)) continue;
        final String vehiculo = chofer.vehiculos.isNotEmpty
            ? chofer.vehiculos.first.tipo
            : 'turismo';
        if (tipoFiltro != null &&
            !chofer.vehiculos.any((v) => v.tipo == tipoFiltro)) {
          continue;
        }
        final double hue =
            (35 + (chofer.uid.hashCode % 115).abs()).toDouble().clamp(15.0, 330.0);
        markers.add(
          Marker(
            markerId: MarkerId('turismo_disp_${chofer.uid}'),
            position: LatLng(u.latitude, u.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(hue),
            infoWindow: InfoWindow(
              title: chofer.nombre.isNotEmpty ? chofer.nombre : 'Chofer turismo',
              snippet: 'Disponible · $vehiculo · esperando asignación',
            ),
            zIndexInt: 2,
          ),
        );
      }
    }
    return markers;
  }

  Future<void> _cargarRutaPreview(Map<String, dynamic> data) async {
    if (_rutaViajeIdCargada == widget.viajeId && _polylines.isNotEmpty) return;
    final LatLng? pickup = _pickupLatLng(data);
    final LatLng? destino = _destinoLatLng(data);
    if (pickup == null || destino == null) return;

    try {
      final dir = await DirectionsService.drivingDistanceKm(
        originLat: pickup.latitude,
        originLon: pickup.longitude,
        destLat: destino.latitude,
        destLon: destino.longitude,
        withTraffic: true,
        region: 'do',
      );
      final List<LatLng> pts = dir?.path ?? <LatLng>[];
      if (!mounted) return;
      setState(() {
        _rutaViajeIdCargada = widget.viajeId;
        _polylines
          ..clear()
          ..add(
            Polyline(
              polylineId: const PolylineId('ruta_turismo_espera'),
              points: pts.isNotEmpty
                  ? pts
                  : <LatLng>[pickup, destino],
              width: 5,
              color: const Color(0xFFBA68C8),
              geodesic: true,
            ),
          );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rutaViajeIdCargada = widget.viajeId;
        _polylines
          ..clear()
          ..add(
            Polyline(
              polylineId: const PolylineId('ruta_turismo_espera'),
              points: <LatLng>[pickup, destino],
              width: 4,
              color: const Color(0xFFBA68C8),
              geodesic: true,
            ),
          );
      });
    }
  }

  Future<void> _ajustarCamara(Map<String, dynamic> data) async {
    final GoogleMapController? map = _map;
    if (map == null) return;

    final List<LatLng> puntos = <LatLng>[];
    final LatLng? pickup = _pickupLatLng(data);
    final LatLng? destino = _destinoLatLng(data);
    final LatLng? taxista = _taxistaLatLng(data);
    if (pickup != null) puntos.add(pickup);
    if (destino != null) puntos.add(destino);
    if (taxista != null) {
      puntos.add(taxista);
    } else {
      for (final ChoferTurismo chofer in _choferesDisponiblesEnMapa) {
        final GeoPoint? u = chofer.ultimaUbicacion;
        if (u != null && _coordOk(u.latitude, u.longitude)) {
          puntos.add(LatLng(u.latitude, u.longitude));
        }
      }
    }

    if (puntos.isEmpty) {
      await map.animateCamera(
        CameraUpdate.newCameraPosition(
          const CameraPosition(
            target: LatLng(18.4861, -69.9312),
            zoom: 12,
          ),
        ),
      );
      return;
    }
    if (puntos.length == 1) {
      await map.animateCamera(
        CameraUpdate.newLatLngZoom(puntos.first, 14),
      );
      return;
    }

    double minLat = puntos.first.latitude;
    double maxLat = puntos.first.latitude;
    double minLon = puntos.first.longitude;
    double maxLon = puntos.first.longitude;
    for (final LatLng p in puntos) {
      minLat = minLat < p.latitude ? minLat : p.latitude;
      maxLat = maxLat > p.latitude ? maxLat : p.latitude;
      minLon = minLon < p.longitude ? minLon : p.longitude;
      maxLon = maxLon > p.longitude ? maxLon : p.longitude;
    }
    final LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat, minLon),
      northeast: LatLng(maxLat, maxLon),
    );
    try {
      await map.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 56),
      );
    } catch (_) {
      await map.animateCamera(
        CameraUpdate.newLatLngZoom(puntos.first, 13),
      );
    }
  }

  void _syncMapaConViaje(Map<String, dynamic> data) {
    _ensureChoferesStream(data);

    final String firma =
        '${_pickupLatLng(data)}|${_destinoLatLng(data)}|${_taxistaLatLng(data)}|$_firmaChoferesMapa()';
    if (firma != _ultimaFirmaBounds) {
      _ultimaFirmaBounds = firma;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_ajustarCamara(data));
      });
    }
    if (_rutaViajeIdCargada != widget.viajeId) {
      unawaited(_cargarRutaPreview(data));
    }
  }

  Future<void> _launchUri(BuildContext context, Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace.')),
      );
    }
  }

  Future<void> _contactarWhatsAppAsignacion(BuildContext context) async {
    final String ref = widget.viajeId.length > 8
        ? widget.viajeId.substring(0, 8)
        : widget.viajeId;
    final String msg =
        'Hola RAI, solicito asignación de chofer para mi viaje turístico #$ref.';
    final Uri waApp = telefonoUriWhatsAppApp(_kTurismoSoporteTelDigitos, msg);
    final Uri waWeb = telefonoUriWhatsAppWeb(_kTurismoSoporteTelDigitos, msg);
    if (await canLaunchUrl(waApp)) {
      if (!context.mounted) return;
      await _launchUri(context, waApp);
      return;
    }
    if (!context.mounted) return;
    await _launchUri(context, waWeb);
  }

  Future<void> _contactarCorreoAsignacion(BuildContext context) async {
    final String ref = widget.viajeId.length > 8
        ? widget.viajeId.substring(0, 8)
        : widget.viajeId;
    final Uri mail = Uri.parse(
      'mailto:$_kTurismoSoporteEmail?subject=${Uri.encodeComponent('Asignación turismo #$ref')}'
      '&body=${Uri.encodeComponent('Hola, necesito asignar un chofer a mi viaje turístico #$ref.\n\nGracias.')}',
    );
    if (!context.mounted) return;
    await _launchUri(context, mail);
  }

  Future<void> _llamarSoporteAsignacion(BuildContext context) async {
    if (!context.mounted) return;
    await _launchUri(
      context,
      telefonoUriLlamada(_kTurismoSoporteTelDigitos),
    );
  }

  Widget _badgeEstadoChofer(ChoferTurismo c) {
    final bool enMapa = c.disponible && c.ultimaUbicacion != null;
    final String label;
    final Color bg;
    final Color fg;
    if (enMapa) {
      label = 'EN VIVO';
      bg = Colors.greenAccent.withValues(alpha: 0.22);
      fg = Colors.greenAccent;
    } else if (c.disponible) {
      label = 'DISPONIBLE';
      bg = Colors.amber.withValues(alpha: 0.2);
      fg = Colors.amberAccent;
    } else {
      label = 'OCUPADO';
      bg = Colors.orange.withValues(alpha: 0.18);
      fg = Colors.orangeAccent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _filaChoferRed(ChoferTurismo c) {
    final String veh = c.vehiculos.isNotEmpty
        ? _getTipoVehiculoLabel(c.vehiculos.first.tipo)
        : 'Turismo';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            c.disponible ? Icons.local_taxi : Icons.local_taxi_outlined,
            size: 20,
            color: c.disponible ? Colors.greenAccent : Colors.white38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.nombre.isNotEmpty ? c.nombre : 'Chofer turístico',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  veh,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _badgeEstadoChofer(c),
        ],
      ),
    );
  }

  Widget _buildChoferAsignadoHero(Map<String, dynamic> data) {
    final String nombre =
        (data['nombreTaxista'] ?? '').toString().trim();
    final String placa = (data['placa'] ?? '').toString().trim();
    final String telefono =
        (data['telefonoTaxista'] ?? data['telefono'] ?? '').toString().trim();
    final bool enMapa = _taxistaLatLng(data) != null;
    final bool auto = data['asignacionAutomatica'] == true;
    final String subtitulo = auto
        ? 'Asignación automática · conectando seguimiento en vivo'
        : 'Asignado por administración · en tiempo real';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.greenAccent.withValues(alpha: 0.22),
            Colors.green.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.greenAccent.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.greenAccent, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  nombre.isNotEmpty ? nombre : 'Tu chofer turístico',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'ASIGNADO',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitulo,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12,
            ),
          ),
          if (placa.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Placa: $placa',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
          if (telefono.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Tel: $telefono',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                enMapa ? Icons.gps_fixed : Icons.gps_not_fixed,
                size: 16,
                color: enMapa ? Colors.greenAccent : Colors.amberAccent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  enMapa
                      ? 'Ubicación del chofer en el mapa · en vivo'
                      : 'Esperando ubicación del chofer en el mapa…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (_navegacionViajeActivoProgramada) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              color: Colors.greenAccent,
              backgroundColor: Colors.white12,
              minHeight: 4,
            ),
            const SizedBox(height: 6),
            const Text(
              'Abriendo viaje en curso…',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChoferAsignadoAViajeCard(Map<String, dynamic> data) {
    final String nombre =
        (data['nombreTaxista'] ?? '').toString().trim();
    final String placa = (data['placa'] ?? '').toString().trim();
    if (nombre.isEmpty && placa.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified, color: Colors.greenAccent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chofer asignado a tu viaje',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                if (nombre.isNotEmpty)
                  Text(
                    nombre,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (placa.isNotEmpty)
                  Text(
                    'Placa: $placa',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChoferesDisponiblesPanel(Map<String, dynamic> data) {
    final String taxistaId =
        (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString();
    final int enMapa = _choferesConUbicacionEnMapa;
    final int total = _choferesRed.length;
    final int compatibles = _choferesCompatiblesConViaje(data);
    final int disponibles =
        _choferesRed.where((ChoferTurismo c) => c.disponible).length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups, color: Colors.amberAccent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Red de choferes turísticos',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              if (total > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$total',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            taxistaId.isNotEmpty
                ? 'Tu chofer ya fue asignado. Los demás conductores siguen en la red en vivo.'
                : compatibles > 0
                    ? '$compatibles chofer${compatibles == 1 ? '' : 'es'} con ${AsignacionTurismoRepo.etiquetaVehiculoRequeridoDesdeViaje(data)} en línea'
                    : enMapa > 0
                    ? '$enMapa en el mapa · $disponibles disponible${disponibles == 1 ? '' : 's'} · actualización en vivo'
                    : total > 0
                        ? '$total chofer${total == 1 ? '' : 'es'} en la red; ubicación en camino al mapa'
                        : 'Aún no hay choferes en la red. Usa soporte abajo para pedir asignación.',
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
          ),
          if (taxistaId.isNotEmpty) _buildChoferAsignadoAViajeCard(data),
          if (_choferesRed.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(color: Colors.white12, height: 16),
            const Text(
              'Lista en vivo',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _choferesRed.length,
                separatorBuilder: (_, __) =>
                    Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                itemBuilder: (_, int i) => _filaChoferRed(_choferesRed[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSoporteAsignacionesPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '¿Sin chofer con tu vehículo? Escribe a operaciones',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Operaciones RAI recibe tu mensaje al instante en el panel admin (push y correo).',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TurismoMensajeOperacionesPanel(viajeId: widget.viajeId),
          const SizedBox(height: 12),
          _soporteTile(
            icon: Icons.chat,
            color: const Color(0xFF25D366),
            label: 'WhatsApp',
            value: _kTurismoSoporteTelVisible,
            onTap: () => _contactarWhatsAppAsignacion(context),
          ),
          const SizedBox(height: 8),
          _soporteTile(
            icon: Icons.email_outlined,
            color: Colors.lightBlueAccent,
            label: 'Correo',
            value: _kTurismoSoporteEmail,
            onTap: () => _contactarCorreoAsignacion(context),
          ),
          const SizedBox(height: 8),
          _soporteTile(
            icon: Icons.phone_in_talk,
            color: Colors.greenAccent,
            label: 'Teléfono',
            value: _kTurismoSoporteTelVisible,
            onTap: () => _llamarSoporteAsignacion(context),
          ),
        ],
      ),
    );
  }

  Widget _soporteTile({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new, color: Colors.white.withValues(alpha: 0.45), size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipEstadoMapa(Map<String, dynamic> data) {
    final String taxistaId =
        (data['uidTaxista'] ?? data['taxistaId'] ?? '').toString();
    final bool choferEnMapa = _taxistaLatLng(data) != null;
    final int enMapa = _choferesConUbicacionEnMapa;
    final int total = _choferesRed.length;
    final String texto = choferEnMapa
        ? 'Tu chofer en el mapa · seguimiento en vivo'
        : taxistaId.isNotEmpty &&
                AsignacionTurismoRepo.viajeTurismoChoferConfirmado(data)
            ? 'Chofer confirmado · ubicación en camino'
            : taxistaId.isNotEmpty
                ? 'Esperando confirmación del chofer…'
            : enMapa > 0
                ? '$enMapa chofer${enMapa == 1 ? '' : 'es'} turístico${enMapa == 1 ? '' : 's'} en el mapa · en vivo'
                : total > 0
                    ? '$total chofer${total == 1 ? '' : 'es'} en línea · ubicación en camino'
                    : 'Ruta en vivo · esperando choferes turísticos disponibles';

    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              choferEnMapa
                  ? Icons.local_taxi
                  : (enMapa > 0 ? Icons.groups : Icons.map_outlined),
              color: choferEnMapa
                  ? Colors.greenAccent
                  : (enMapa > 0 ? Colors.amberAccent : Colors.purpleAccent),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTipoVehiculoLabel(String tipo) {
    switch (tipo) {
      case 'carro':
        return '🚗 Carro Turismo';
      case 'jeepeta':
        return '🚙 Jeepeta Turismo';
      case 'minivan':
        return '🚐 Minivan Turismo';
      case 'bus':
        return '🚌 Bus Turismo';
      default:
        return tipo;
    }
  }

  String _formatFecha(Timestamp? timestamp) {
    if (timestamp == null) return '—';
    final fecha = timestamp.toDate();
    return DateFormat('dd/MM/yyyy - HH:mm', 'es').format(fecha);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.viajeId.trim().isEmpty) {
      return FlygoSalidaSegura(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: const RaiAppBar(
            title: '🏝️ Turismo RAI',
            backWhenCanPop: true,
          ),
          body: _buildErrorState(
            'No se recibió el identificador del viaje. Vuelve a solicitar turismo desde el inicio.',
          ),
        ),
      );
    }

    return FlygoSalidaSegura(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: const RaiAppBar(
          title: '🏝️ Turismo RAI',
          backWhenCanPop: true,
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('viajes')
            .doc(widget.viajeId)
            .snapshots(),
        builder: (BuildContext context,
            AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _buildLoadingState();
          }

          final Map<String, dynamic> data =
              snapshot.data!.data() as Map<String, dynamic>;
          final String estado = (data['estado'] ?? '').toString();
          if (EstadosViaje.esCancelado(estado)) {
            return _buildErrorState(
              'Este viaje turístico fue cancelado. Puedes solicitar uno nuevo cuando quieras.',
            );
          }

          if (EstadosViaje.esCompletado(estado)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_navegarPostViajeCompletado());
            });
            return _buildCompletadoState(navegandoPostViaje: _postCompletadoEnCurso);
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _procesarActualizacionViaje(context, data);
          });

          return _buildWaitingScreen(data);
        },
      ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A1B3D), Colors.black],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.purple),
            SizedBox(height: 24),
            Text(
              'Preparando tu experiencia turística...',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF330000), Colors.black],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 64),
              const SizedBox(height: 16),
              const Text(
                '¡Ups! Algo salió mal',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navegarPostViajeCompletado() async {
    if (_postCompletadoEnCurso || !mounted) return;
    _postCompletadoEnCurso = true;
    if (mounted) setState(() {});

    ActiveTripService.cancelarMantenimientoOverlayViaje();

    if (!mounted) return;

    await PostViajeClienteNav.abrirFacturaYFlujo(
      context: context,
      viajeId: widget.viajeId,
    );
  }

  Widget _buildCompletadoState({bool navegandoPostViaje = false}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B3D2A), Colors.black],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.greenAccent, size: 64),
              const SizedBox(height: 16),
              Text(
                navegandoPostViaje ? 'Abriendo recibo…' : 'Viaje finalizado',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              if (navegandoPostViaje) ...[
                const SizedBox(height: 20),
                const CircularProgressIndicator(color: Colors.greenAccent),
              ] else ...[
              const SizedBox(height: 8),
              const Text(
                'Este viaje turístico ya se completó. Gracias por confiar en RAI.',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  unawaited(
                    NavigationService.irAlInicioCliente(
                      context: context,
                      viajeId: widget.viajeId,
                      forzarLimpiarViajeActivo: true,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Volver al inicio'),
              ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _metodoPagoLabel(String raw) {
    if (raw.trim().isEmpty) return '—';
    if (MetodoPagoViaje.esEfectivo(raw)) return 'Efectivo';
    if (MetodoPagoViaje.esTransferencia(raw)) {
      return 'Transferencia bancaria';
    }
    if (MetodoPagoViaje.esTarjeta(raw)) return 'Tarjeta';
    return raw.trim();
  }

  String? _pasajerosDesdeExtras(Map<String, dynamic> data) {
    final dynamic ex = data['extras'];
    if (ex is! Map) return null;
    final Map map = ex;
    final dynamic p =
        map['pasajeros'] ?? map['numPasajeros'] ?? map['pasajeros_count'];
    if (p == null) return null;
    final String t = p.toString().trim();
    return t.isEmpty ? null : t;
  }

  Widget _buildWaitingScreen(Map<String, dynamic> data) {
    final bool choferAsignado = _viajeTieneChoferAsignado(data);
    final int compatibles = _choferesCompatiblesConViaje(data);
    final bool sinChoferesEnRed = !choferAsignado &&
        (compatibles == 0 || _choferesRed.isEmpty);

    final destino = data['destino'] ?? 'Destino no especificado';
    final origen = data['origen'] ?? 'Origen no especificado';
    final fechaHora = data['fechaHora'] as Timestamp?;
    final precio = (data['precio'] ?? 0).toDouble();
    final tipoVehiculo =
        _getTipoVehiculoLabel(data['subtipoTurismo'] ?? 'carro');
    final distancia = (data['distanciaKm'] ?? 0).toDouble();
    final String estadoRaw = (data['estado'] ?? '').toString();
    final String? pasajeros = _pasajerosDesdeExtras(data);
    final String metodoPago =
        _metodoPagoLabel((data['metodoPago'] ?? '').toString());
    final LatLng? pickup = _pickupLatLng(data);
    final CameraPosition camaraInicial = CameraPosition(
      target: pickup ?? const LatLng(18.4861, -69.9312),
      zoom: pickup != null ? 13 : 11,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: camaraInicial,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            mapToolbarEnabled: false,
            markers: _markersFor(data),
            polylines: _polylines,
            onMapCreated: (GoogleMapController c) {
              _map = c;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) unawaited(_ajustarCamara(data));
              });
            },
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 12,
          right: 12,
          child: _chipEstadoMapa(data),
        ),
        Positioned(
          right: 12,
          bottom: MediaQuery.sizeOf(context).height * _kEsperaSheetInitial + 8,
          child: FloatingActionButton.small(
            heroTag: 'turismo_espera_centrar',
            backgroundColor: Colors.black.withValues(alpha: 0.78),
            foregroundColor: Colors.purpleAccent,
            onPressed: () => unawaited(_ajustarCamara(data)),
            child: const Icon(Icons.my_location),
          ),
        ),
        DraggableScrollableSheet(
          minChildSize: _kEsperaSheetMin,
          maxChildSize: 0.92,
          initialChildSize: _kEsperaSheetInitial,
          snap: true,
          snapSizes: const <double>[
            _kEsperaSheetMin,
            _kEsperaSheetInitial,
            0.58,
            0.92,
          ],
          builder: (sheetCtx, scrollController) {
            final bottomInset = MediaQuery.viewPaddingOf(sheetCtx).bottom;
            return DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF2A1B3D),
                    Color(0xFF1A0F2A),
                    Colors.black,
                  ],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 18,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottomInset),
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Text(
                    'Desliza hacia arriba para ver detalles',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 72,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (BuildContext context, Widget? child) {
                            return Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.purple.withValues(
                                    alpha: _pulseAnimation.value * 0.3),
                              ),
                            );
                          },
                        ),
                        const Icon(
                          Icons.beach_access,
                          color: Colors.purple,
                          size: 40,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (choferAsignado) ...[
                    _buildChoferAsignadoHero(data),
                    const SizedBox(height: 16),
                  ] else ...[
                    Center(
                      child: Text(
                        AsignacionTurismoRepo.tituloEsperaTurismoCliente(data),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        AsignacionTurismoRepo.subtituloEsperaTurismoCliente(
                          data,
                          choferesCompatibles: compatibles,
                          choferesEnLinea: _choferesRed.length,
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          height: 1.35,
                        ),
                      ),
                    ),
                    if (AsignacionTurismoRepo.viajeEnPoolTurismoPublico(data)) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.tealAccent
                                    .withValues(alpha: 0.55)),
                          ),
                          child: const Text(
                            'Visible para choferes turismo en la app',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ] else if (estadoRaw.toLowerCase() == 'pendiente_admin') ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.purpleAccent
                                    .withValues(alpha: 0.5)),
                          ),
                          child: const Text(
                            'Actualización en tiempo real',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.purple.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _controller,
                          builder: (BuildContext context, Widget? child) {
                            return LinearProgressIndicator(
                              value: _controller.value * 0.5,
                              backgroundColor: Colors.white10,
                              color: Colors.purple,
                              minHeight: 8,
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                choferAsignado
                                    ? 'Chofer confirmado · abriendo viaje…'
                                    : AsignacionTurismoRepo
                                            .viajeEnPoolTurismoPublico(data)
                                        ? 'En pool turístico · esperando que un chofer acepte…'
                                        : 'Publicando tu viaje en pool turístico…',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                            Text(
                              choferAsignado ? '✓' : '⏳ 2-5 min',
                              style: TextStyle(
                                color: choferAsignado
                                    ? Colors.greenAccent
                                    : Colors.purple.shade200,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!choferAsignado) ...[
                    const SizedBox(height: 12),
                    _buildChoferesDisponiblesPanel(data),
                  ],
                  if (sinChoferesEnRed || !choferAsignado) ...[
                    const SizedBox(height: 12),
                    _buildSoporteAsignacionesPanel(context),
                  ],
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.purple),
                              ),
                              child: Text(
                                '#${widget.viajeId.substring(0, 8)}',
                                style: const TextStyle(
                                  color: Colors.purple,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _infoRow(Icons.flag, 'Origen', origen),
                        const SizedBox(height: 8),
                        _infoRow(Icons.flag, 'Destino', destino,
                            color: Colors.greenAccent),
                        const SizedBox(height: 12),
                        if (fechaHora != null) ...[
                          _infoRow(Icons.calendar_today, 'Fecha',
                              _formatFecha(fechaHora)),
                          const SizedBox(height: 8),
                        ],
                        _infoRow(
                            Icons.directions_car, 'Vehículo', tipoVehiculo),
                        if (pasajeros != null) ...[
                          const SizedBox(height: 8),
                          _infoRow(
                              Icons.people_outline, 'Pasajeros', pasajeros),
                        ],
                        const SizedBox(height: 8),
                        _infoRow(Icons.payments_outlined, 'Método de pago',
                            metodoPago),
                        if (distancia > 0) ...[
                          const SizedBox(height: 8),
                          _infoRow(Icons.straighten, 'Distancia',
                              FormatosMoneda.km(distancia)),
                        ],
                        const Divider(color: Colors.white24, height: 24),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Total',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                FormatosMoneda.rd(precio),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        unawaited(
                          NavigationService.irAlInicioCliente(context: context),
                        );
                      },
                      icon: const Icon(Icons.home_rounded, size: 20),
                      label: const Text('Volver al inicio'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white38),
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _showCancelDialog(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'CANCELAR VIAJE',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value,
      {Color color = Colors.white70}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showCancelDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final onSurface = cs.onSurface;
        final muted = onSurface.withValues(alpha: 0.72);
        return AlertDialog(
          backgroundColor: cs.surface,
          title: Text(
            'Cancelar viaje',
            style: TextStyle(color: onSurface),
          ),
          content: Text(
            '¿Estás seguro que deseas cancelar este viaje turístico?',
            style: TextStyle(color: muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(foregroundColor: cs.primary),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Sí, cancelar'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para cancelar.')),
      );
      return;
    }

    try {
      await ViajesRepo.cancelarPorCliente(
        viajeId: widget.viajeId,
        uidCliente: user.uid,
        motivo: 'Cancelado desde espera turismo',
      );
      if (!mounted) return;
      await NavigationService.clearAndGo(const ClienteShellWithDeepLink());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cancelar: $e')),
      );
    }
  }
}
