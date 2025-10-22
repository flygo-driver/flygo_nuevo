// lib/pantallas/cliente/viaje_en_curso_cliente.dart
// Modo ESTRICTO: solo muestra el viaje cuyo id está en usuarios/{uid}.viajeActivoId.
// Cancelar: DELETE<=60s o UPDATE a cancelado → SIEMPRE limpia usuarios/{uid}.viajeActivoId.
// Programados: al crear un viaje programado, setea viajeActivoId para que aparezca aquí.
// Extras: sirena/háptica al aceptar/ir en camino, ETA + countdown, llamada, WhatsApp, chat, navegación.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/formatos_moneda.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/widgets/cliente_drawer.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/viajes_repo.dart';
import 'package:flygo_nuevo/pantallas/chat/chat_screen.dart';

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

String _s(Object? x) => x?.toString() ?? '';

// Haversine (fallback ETA cuando DirectionsService no trae distancia/tiempo)
double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLon = (lon2 - lon1) * math.pi / 180.0;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}

class ViajeEnCursoCliente extends StatefulWidget {
  const ViajeEnCursoCliente({super.key});
  @override
  State<ViajeEnCursoCliente> createState() => _ViajeEnCursoClienteState();
}

class _ViajeEnCursoClienteState extends State<ViajeEnCursoCliente> {
  GoogleMapController? _map;
  bool _myLoc = false;

  final Map<PolylineId, Polyline> _polylines = {};
  Timer? _routeDebounce;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pagoSub;

  String _lastRouteKey = '';
  String _lastBoundsKey = '';

  // Watch puntual del doc activo (para ETA/sirena)
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _viajeDocSub;
  Timer? _etaDebounce;
  double? _etaMin; // minutos hasta pickup
  double? _distKm; // distancia hasta pickup
  DateTime? _etaTarget; // ahora + etaMin
  String _lastNotifiedState = '';

  @override
  void initState() {
    super.initState();
    _enableMyLocation();
    _listenPagoFinal();
  }

  @override
  void dispose() {
    _map?.dispose();
    _pagoSub?.cancel();
    _routeDebounce?.cancel();
    _disposeDocWatch();
    super.dispose();
  }

  Future<void> _enableMyLocation() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    final denied = (p == LocationPermission.denied || p == LocationPermission.deniedForever);
    setState(() => _myLoc = !denied);
  }

  // ==== Pago modal al finalizar (opcional) ====
  void _listenPagoFinal() {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    final q = FirebaseFirestore.instance
        .collection('viajes')
        .where('uidCliente', isEqualTo: u.uid)
        .where('completado', isEqualTo: true)
        .orderBy('finalizadoEn', descending: true)
        .limit(1);

    String? ultimoId;
    _pagoSub = q.snapshots().listen((snap) {
      if (snap.docs.isEmpty) return;
      final d = snap.docs.first.data();
      final id = snap.docs.first.id;
      if (ultimoId == id) return;
      ultimoId = id;

      final finTs = d['finalizadoEn'];
      if (finTs is! Timestamp) return;
      final esRec = DateTime.now().difference(finTs.toDate()).inMinutes <= 10;
      if (!esRec) return;

      final double total = (d['precioFinal'] is num)
          ? (d['precioFinal'] as num).toDouble()
          : ((d['precio'] is num) ? (d['precio'] as num).toDouble() : 0.0);

      if (!mounted) return;
      _showPagoModal(context, total);
    });
  }

  void _showPagoModal(BuildContext ctx, double total) {
    if (!mounted) return;
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFAAAAAA).withAlpha(100),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Viaje finalizado',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text('Total a pagar', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 6),
            Text(
              _safeMoney(total),
              style: const TextStyle(color: Colors.greenAccent, fontSize: 40, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text('Gracias por viajar con FlyGo', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(bctx).maybePop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Entendido'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ==== Navegación externa (mejorada) ====
  String _fmtCoord(double v) => v.toStringAsFixed(6);

  Future<bool> _tryLaunch(Uri uri, {bool preferExternalApp = true}) async {
    try {
      final ok1 = await launchUrl(uri, mode: preferExternalApp ? LaunchMode.externalApplication : LaunchMode.platformDefault);
      if (ok1) return true;
      final ok2 = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (ok2) return true;
      if (uri.scheme.startsWith('http')) {
        final ok3 = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok3) return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _openGoogleMapsTo(double lat, double lon, {String? label}) async {
    final la = _fmtCoord(lat), lo = _fmtCoord(lon);
    final qLabel = (label == null || label.trim().isEmpty)
        ? '$la,$lo'
        : Uri.encodeComponent('$la,$lo($label)');
    final navIntent = Uri(scheme: 'google.navigation', queryParameters: {'q': '$la,$lo', 'mode': 'd'});
    final geoIntent = Uri.parse('geo:$la,$lo?q=$qLabel');
    final web = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$la,$lo&travelmode=driving');
    if (await _tryLaunch(navIntent)) return;
    if (await _tryLaunch(geoIntent)) return;
    await _tryLaunch(web, preferExternalApp: false);
  }

  Future<void> _openWazeTo(double lat, double lon) async {
    final la = _fmtCoord(lat), lo = _fmtCoord(lon);
    final deep = Uri.parse('waze://?ll=$la,$lo&navigate=yes');
    final web  = Uri.parse('https://waze.com/ul?ll=$la,$lo&navigate=yes');
    if (await _tryLaunch(deep)) return;
    if (await _tryLaunch(web, preferExternalApp: false)) return;
    await _openGoogleMapsTo(lat, lon);
  }

  Future<void> abrirNavegacionAlPickup(Viaje v) async {
    if (!_isValidCoord(v.latCliente, v.lonCliente)) return;
    await _openWazeTo(v.latCliente, v.lonCliente);
  }

  Future<void> abrirNavegacionAlDestino(Viaje v) async {
    if (!_isValidCoord(v.latDestino, v.lonDestino)) return;
    await _openWazeTo(v.latDestino, v.lonDestino);
  }

  // ==== Rutas / mapa ====
  void _scheduleDrawRoute(Viaje v) {
    _routeDebounce?.cancel();
    _routeDebounce = Timer(const Duration(milliseconds: 350), () => _drawRoutesForState(v));
  }

  Future<void> _drawRoutesForState(Viaje v) async {
    if (!mounted) return;
    final estado = EstadosViaje.normalizar(
      v.estado.isNotEmpty
          ? v.estado
          : (v.completado ? EstadosViaje.completado : (v.aceptado ? EstadosViaje.enCurso : EstadosViaje.pendiente)),
    );

    _polylines.clear();

    // Ruta taxista -> cliente
    if ((estado == EstadosViaje.aceptado || estado == EstadosViaje.enCaminoPickup) &&
        _isValidCoord(v.latTaxista, v.lonTaxista) &&
        _isValidCoord(v.latCliente, v.lonCliente)) {
      await _drawRoute(_latLng(v.latTaxista, v.lonTaxista), _latLng(v.latCliente, v.lonCliente), id: 'pickup');
    }
    // Ruta cliente -> destino
    if ((estado == EstadosViaje.aBordo || estado == EstadosViaje.enCurso) &&
        _isValidCoord(v.latCliente, v.lonCliente) &&
        _isValidCoord(v.latDestino, v.lonDestino)) {
      await _drawRoute(_latLng(v.latCliente, v.lonCliente), _latLng(v.latDestino, v.lonDestino), id: 'ruta');
    }

    if (mounted) setState(() {});
  }

  Future<void> _fitBoundsFor(Viaje v) async {
    final mapRef = _map;
    if (mapRef == null) return;
    final pts = <LatLng>[
      if (_isValidCoord(v.latCliente, v.lonCliente)) _latLng(v.latCliente, v.lonCliente),
      if (_isValidCoord(v.latDestino, v.lonDestino)) _latLng(v.latDestino, v.lonDestino),
      if (_isValidCoord(v.latTaxista, v.lonTaxista)) _latLng(v.latTaxista, v.lonTaxista),
    ];
    if (pts.isEmpty) return;

    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = p.latitude  < minLat ? p.latitude  : minLat;
      maxLat = p.latitude  > maxLat ? p.latitude  : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    final bounds = LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
    try {
      await mapRef.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      final mapRef2 = _map;
      if (mapRef2 != null) {
        try { await mapRef2.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60)); } catch (_) {}
      }
    }
  }

  Future<void> _drawRoute(LatLng a, LatLng b, {required String id}) async {
    try {
      final dynamic dir = await DirectionsService.drivingDistanceKm(
        originLat: a.latitude,
        originLon: a.longitude,
        destLat: b.latitude,
        destLon: b.longitude,
        withTraffic: true,
        region: 'do',
      );

      // Intentamos leer path de varias formas
      List<LatLng> pts = const <LatLng>[];
      try {
        if (dir?.path is List<LatLng>) {
          pts = dir.path as List<LatLng>;
        } else if (dir?.polylinePoints is List) {
          final raw = dir.polylinePoints as List;
          final parsed = <LatLng>[];
          for (final e in raw) {
            try {
              if (e is Map) {
                final la = e['lat'] as num;
                final lo = (e['lng'] ?? e['lon']) as num;
                parsed.add(LatLng(la.toDouble(), lo.toDouble()));
              } else {
                final ed = e as dynamic;
                final la = (ed.lat as num);
                final num loNum = (ed.lng is num) ? ed.lng as num : ed.lon as num;
                parsed.add(LatLng(la.toDouble(), loNum.toDouble()));
              }
            } catch (_) {}
          }
          pts = parsed;
        }
      } catch (_) {}

      final polyId = PolylineId(id);
      if (pts.isEmpty && _polylines.containsKey(polyId)) return;
      _polylines[polyId] = Polyline(
        polylineId: polyId, width: 6, points: pts.isNotEmpty ? pts : [a, b],
        geodesic: true, color: const Color(0xFF49F18B),
      );
    } catch (_) {
      _polylines[PolylineId(id)] = Polyline(
        polylineId: PolylineId(id), width: 5, points: [a, b],
        geodesic: true, color: const Color(0xFF49F18B),
      );
    }
  }

  // ==== Cancelación estricta (y limpieza del usuario) ====
  Future<int> _segundosRestantesBorradoDesdeServidor(String viajeId) async {
    try {
      final ds = await FirebaseFirestore.instance.collection('viajes').doc(viajeId).get();
      if (!ds.exists) return 0;
      final d = ds.data() ?? {};
      Timestamp? baseTs;

      final creadoEn = d['creadoEn'];
      final createdAt = d['createdAt'];
      final fechaCreacion = d['fechaCreacion'];
      final aceptadoEn = d['aceptadoEn'];

      if (creadoEn is Timestamp)      { baseTs = creadoEn; }
      else if (createdAt is Timestamp){ baseTs = createdAt; }
      else if (fechaCreacion is Timestamp) { baseTs = fechaCreacion; }
      else if (aceptadoEn is Timestamp)    { baseTs = aceptadoEn; }

      if (baseTs == null) return 0;
      final limite = baseTs.toDate().add(const Duration(seconds: 60));
      final rest = limite.difference(DateTime.now()).inSeconds;
      return rest > 0 ? rest : 0;
    } catch (_) { return 0; }
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

  Future<void> _deleteOrCancelEstricto(Viaje v) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    await _runWithBlocking(() async {
      final segundos = await _segundosRestantesBorradoDesdeServidor(v.id);
      var deleted = false;
      if (segundos > 0) {
        try {
          await FirebaseFirestore.instance.collection('viajes').doc(v.id).delete();
          deleted = true;
        } catch (_) {}
      }
      if (!deleted) {
        await ViajesRepo.cancelarPorCliente(
          viajeId: v.id, uidCliente: uid, motivo: 'cancelado_por_cliente',
        );
      }
      await _limpiarActivoDelUsuario(uid);
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('🚫 Viaje cancelado')));
  }

  // ==== Watch del viaje activo (para sirena/ETA) ====
  void _disposeDocWatch() {
    _viajeDocSub?.cancel(); _viajeDocSub = null;
    _etaDebounce?.cancel(); _etaDebounce = null;
  }

  void _watchViajeDoc(String viajeId) {
    _disposeDocWatch();
    _viajeDocSub = FirebaseFirestore.instance
        .collection('viajes').doc(viajeId).snapshots().listen((ds) async {
      if (!ds.exists) return;
      final d = ds.data() ?? {};
      final estado = (d['estado'] ?? '').toString();
      final estN = EstadosViaje.normalizar(estado);

      // Sirena/háptica al pasar a aceptado / en camino (solo una vez por estado)
      if ((estN == EstadosViaje.aceptado || estN == EstadosViaje.enCaminoPickup) && _lastNotifiedState != estN) {
        _lastNotifiedState = estN;
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.heavyImpact();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tu taxista va en camino 🚕')));
        }
      }

      // ETA hacia pickup (driver -> cliente)
      final driverLat = d['driverLat'] ?? d['latTaxista'];
      final driverLon = d['driverLon'] ?? d['lonTaxista'];
      final cliLat = (d['latCliente'] ?? 0);
      final cliLon = (d['lonCliente'] ?? 0);

      _etaDebounce?.cancel();
      _etaDebounce = Timer(const Duration(seconds: 12), () async {
        if (driverLat is num && driverLon is num && cliLat is num && cliLon is num &&
            _isValidCoord(driverLat.toDouble(), driverLon.toDouble()) &&
            _isValidCoord(cliLat.toDouble(), cliLon.toDouble())) {
          try {
            final dynamic dir = await DirectionsService.drivingDistanceKm(
              originLat: driverLat.toDouble(),
              originLon: driverLon.toDouble(),
              destLat: cliLat.toDouble(),
              destLon: cliLon.toDouble(),
              withTraffic: true,
              region: 'do',
            );

            // Lee distancia/tiempo con múltiples claves
            double? km;
            double? min;
            try {
              final dk = (dir?.distanceKm ??
                  dir?.km ??
                  (dir is Map ? (dir['distanceKm'] ?? dir['km'] ?? dir['distance']) : null) ??
                  dir?.distance);
              if (dk is num) km = dk.toDouble();
            } catch (_) {}
            try {
              final dm = (dir?.durationMinutes ??
                  dir?.minutes ??
                  (dir is Map ? (dir['durationMinutes'] ?? dir['minutes'] ?? dir['duration']) : null) ??
                  dir?.duration);
              if (dm is num) min = dm.toDouble();
            } catch (_) {}

            // Fallbacks → valores no nulos
            final double kmVal = (km != null && km > 0)
                ? km
                : _haversineKm(driverLat.toDouble(), driverLon.toDouble(), cliLat.toDouble(), cliLon.toDouble());

            final double minVal = (min != null && min > 0)
                ? min
                : (kmVal / 25.0) * 60.0; // ~25 km/h

            if (mounted) {
              setState(() {
                _distKm = kmVal > 0 ? kmVal : null;
                _etaMin = minVal > 0 ? minVal : null;
                _etaTarget = (_etaMin != null) ? DateTime.now().add(Duration(minutes: _etaMin!.round())) : null;
              });
            }

            // Umbral adicional (sirena)
            final bool nearByTime = minVal <= 3;
            final bool nearByDist = kmVal <= 0.5;
            if (nearByTime || nearByDist) {
              SystemSound.play(SystemSoundType.alert);
              HapticFeedback.mediumImpact();
            }
          } catch (_) {}
        }
      });
    }, onError: (_) {});
  }

  // ====== Chips helper ======
  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  // ====== Bloque Conductor + Vehículo (INFO COMPLETA) ======
  Widget _bloqueConductorYVehiculo(Viaje v) {
    if (v.uidTaxista.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🚕 Conductor: —', style: TextStyle(color: Colors.white70, fontSize: 16)),
          Text('🚗 Vehículo: —', style: TextStyle(color: Colors.white70, fontSize: 16)),
          SizedBox(height: 6),
          Text('📞 Teléfono: —', style: TextStyle(color: Colors.white70, fontSize: 16)),
        ],
      );
    }

    final taxistaRef = FirebaseFirestore.instance.collection('usuarios').doc(v.uidTaxista);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: taxistaRef.snapshots(),
      builder: (context, snap) {
        final tx = (snap.hasData && snap.data!.exists) ? (snap.data!.data() ?? const {}) : const {};

        // Nombre
        final nombre = v.nombreTaxista.isNotEmpty
            ? v.nombreTaxista
            : (tx['nombre'] ?? tx['displayName'] ?? '').toString();

        // Teléfono visible
        final telFromViaje = v.telefonoTaxista.isNotEmpty ? v.telefonoTaxista : v.telefono;
        final tel = telFromViaje.trim().isNotEmpty ? telFromViaje : (tx['telefono'] ?? '').toString();
        String clean(String raw) {
          final only = raw.replaceAll(RegExp(r'\D+'), '');
          if (only.isEmpty) return '';
          if (only.startsWith('1')) return only;
          if (only.length == 10) return '1$only';
          return only;
        }
        final telClean = clean(tel);
        final telVisible = telClean.isNotEmpty ? '+$telClean' : '—';

        // Vehículo (con múltiples alias)
        final tipo   = _s(v.tipoVehiculo).trim().isNotEmpty ? _s(v.tipoVehiculo).trim() : _s(tx['tipoVehiculo']).trim();
        final marca  = _s((v as dynamic).marca).trim().isNotEmpty ? _s((v as dynamic).marca).trim()
                       : _s(tx['marca']).trim().isNotEmpty ? _s(tx['marca']).trim() : _s(tx['vehiculoMarca']).trim();
        final modelo = _s((v as dynamic).modelo).trim().isNotEmpty ? _s((v as dynamic).modelo).trim()
                       : _s(tx['modelo']).trim().isNotEmpty ? _s(tx['modelo']).trim() : _s(tx['vehiculoModelo']).trim();
        final color  = _s((v as dynamic).color).trim().isNotEmpty ? _s((v as dynamic).color).trim()
                       : _s(tx['color']).trim().isNotEmpty ? _s(tx['color']).trim() : _s(tx['vehiculoColor']).trim();
        final placa  = _s((v as dynamic).placa).trim().isNotEmpty ? _s((v as dynamic).placa).trim()
                       : _s(tx['placa']).trim();

        final vehiculoLinea = [
          if (tipo.isNotEmpty) tipo,
          if (marca.isNotEmpty) marca,
          if (modelo.isNotEmpty) modelo,
        ].join(' · ');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🚕 Conductor: ${nombre.isEmpty ? "—" : nombre}', style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 4),
            Text('🚗 Vehículo: ${vehiculoLinea.isEmpty ? "—" : vehiculoLinea}', style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            Wrap(children: [
              if (placa.isNotEmpty) _chip('Placa: $placa'),
              if (color.isNotEmpty) _chip('Color: $color'),
            ]),
            const SizedBox(height: 6),
            Text('📞 Teléfono: $telVisible', style: const TextStyle(color: Colors.white70, fontSize: 16)),
          ],
        );
      },
    );
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;

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
        title: const Text('Mi viaje en curso', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: (u == null)
          ? const Center(child: Text('Inicia sesión para ver tu viaje.', style: TextStyle(color: Colors.white70)))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('usuarios').doc(u.uid).snapshots(),
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
                }
                if (userSnap.hasError || !userSnap.hasData || !userSnap.data!.exists) {
                  return const Center(child: Text('No tienes viaje activo.', style: TextStyle(color: Colors.white70)));
                }

                final userData = userSnap.data!.data() ?? {};
                final activoId = (userData['viajeActivoId'] ?? '').toString();
                if (activoId.isEmpty) {
                  _disposeDocWatch();
                  return const Center(child: Text('No tienes viaje activo en este momento.', style: TextStyle(color: Colors.white70)));
                }

                // Stream del documento ACTIVO (único)
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('viajes').doc(activoId).snapshots(),
                  builder: (context, vSnap) {
                    if (vSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
                    }
                    if (vSnap.hasError || !vSnap.hasData || !vSnap.data!.exists) {
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        await _limpiarActivoDelUsuario(u.uid);
                      });
                      return const Center(child: Text('No tienes viaje activo en este momento.', style: TextStyle(color: Colors.white70)));
                    }

                    final data = vSnap.data!.data() ?? {};
                    final v = Viaje.fromMap(vSnap.data!.id, Map<String, dynamic>.from(data));

                    _watchViajeDoc(v.id);

                    final estadoBase = EstadosViaje.normalizar(
                      v.estado.isNotEmpty
                          ? v.estado
                          : (v.completado ? EstadosViaje.completado : (v.aceptado ? EstadosViaje.enCurso : EstadosViaje.pendiente)),
                    );

                    if (EstadosViaje.esTerminal(estadoBase)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        await _limpiarActivoDelUsuario(u.uid);
                      });
                      return const Center(child: Text('No tienes viaje activo en este momento.', style: TextStyle(color: Colors.white70)));
                    }

                    final vaEnCamino = EstadosViaje.esEnCaminoPickup(estadoBase) || estadoBase == EstadosViaje.aceptado;
                    final esProgramadoSinAsignar = (estadoBase == EstadosViaje.pendiente) && (v.uidTaxista.isEmpty);

                    final markers = <Marker>{
                      if (_isValidCoord(v.latDestino, v.lonDestino))
                        Marker(
                          markerId: const MarkerId('destino'),
                          position: _latLng(v.latDestino, v.lonDestino),
                          infoWindow: InfoWindow(title: 'Destino: ${v.destino}'),
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                        ),
                      if (_isValidCoord(v.latCliente, v.lonCliente))
                        Marker(
                          markerId: const MarkerId('pickup'),
                          position: _latLng(v.latCliente, v.lonCliente),
                          infoWindow: InfoWindow(title: 'Punto de recogida: ${v.origen}'),
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                        ),
                      if (_isValidCoord(v.latTaxista, v.lonTaxista))
                        Marker(
                          markerId: const MarkerId('taxista'),
                          position: _latLng(v.latTaxista, v.lonTaxista),
                          infoWindow: const InfoWindow(title: 'Taxista'),
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                        ),
                    };

                    final initialTarget = _isValidCoord(v.latCliente, v.lonCliente)
                        ? _latLng(v.latCliente, v.lonCliente)
                        : (_isValidCoord(v.latDestino, v.lonDestino)
                            ? _latLng(v.latDestino, v.lonDestino)
                            : const LatLng(18.4861, -69.9312)); // SDQ

                    final routeKey = '${v.id}|${EstadosViaje.normalizar(v.estado)}|'
                        '${v.latCliente},${v.lonCliente}|${v.latDestino},${v.lonDestino}|${v.latTaxista},${v.lonTaxista}';
                    if (routeKey != _lastRouteKey) {
                      _lastRouteKey = routeKey;
                      _scheduleDrawRoute(v);
                    }

                    final boundsKey =
                        '${v.id}|${v.latCliente},${v.lonCliente}|${v.latDestino},${v.lonDestino}|${v.latTaxista},${v.lonTaxista}';
                    if (_map != null && boundsKey != _lastBoundsKey) {
                      _lastBoundsKey = boundsKey;
                      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBoundsFor(v));
                    }

                    final fechaTxt = _safeFecha(v.fechaHora);
                    final totalTxt = _safeMoney(v.precio);
                    final cancelarHabilitado = !EstadosViaje.esTerminal(estadoBase);

                    return Column(
                      children: [
                        Expanded(
                          flex: 3,
                          child: GoogleMap(
                            initialCameraPosition: CameraPosition(target: initialTarget, zoom: 14),
                            onMapCreated: (c) {
                              _map = c;
                              WidgetsBinding.instance.addPostFrameCallback((_) async {
                                final mapRef = _map;
                                if (!mounted || mapRef == null) return;
                                try { await mapRef.animateCamera(CameraUpdate.newLatLngZoom(initialTarget, 14)); } catch (_) {}
                                final bk =
                                    '${v.id}|${v.latCliente},${v.lonCliente}|${v.latDestino},${v.lonDestino}|${v.latTaxista},${v.lonTaxista}';
                                if (_lastBoundsKey != bk) {
                                  _lastBoundsKey = bk;
                                  await _fitBoundsFor(v);
                                }
                              });
                            },
                            myLocationEnabled: _myLoc,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: true,
                            markers: markers,
                            polylines: Set<Polyline>.of(_polylines.values),
                            compassEnabled: true,
                            mapToolbarEnabled: false,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: ListView(
                              children: [
                                if (esProgramadoSinAsignar)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E1A0F),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.orangeAccent.withAlpha(120)),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.schedule, color: Colors.orangeAccent),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Tu viaje está programado. Te avisaremos cuando un taxista lo acepte.',
                                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                        ),
                                      ],
                                    ),
                                  ),

                                if (vaEnCamino) ...[
                                  const SizedBox(height: 10),
                                  _bannerEnCamino(etaMin: _etaMin, distKm: _distKm, etaTarget: _etaTarget),
                                ],

                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[900],
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('🧭 ${v.origen} → ${v.destino}',
                                          style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 8),
                                      Text('🕓 ${v.completado ? "Realizado" : "Fecha"}: $fechaTxt',
                                          style: const TextStyle(fontSize: 16, color: Colors.white70)),
                                      const SizedBox(height: 8),
                                      Text('💰 Total: $totalTxt', style: const TextStyle(color: Colors.greenAccent, fontSize: 18)),
                                      const SizedBox(height: 8),
                                      Text('📍 Estado: ${_labelEstado(estadoBase)}',
                                          style: const TextStyle(fontSize: 16, color: Colors.white70)),
                                      const SizedBox(height: 8),

                                      // Datos del conductor + vehículo (INFO COMPLETA)
                                      _bloqueConductorYVehiculo(v),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // ====== ACCIONES ORDENADAS ======
                                _btnVerTaxista(v), // abre hoja con llamar/whatsapp/chat y muestra vehículo/placa/color
                                const SizedBox(height: 10),
                                _btnVerRuta(v),     // mantiene navegación
                                const SizedBox(height: 12),

                                // ===== Cancelación estricta (y limpieza) =====
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: cancelarHabilitado ? () async => _deleteOrCancelEstricto(v) : null,
                                    icon: const Icon(Icons.cancel_outlined),
                                    label: const Text('Cancelar viaje'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                      minimumSize: const Size(double.infinity, 52),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }

  /// Banner “va en camino” con ETA y countdown grande
  Widget _bannerEnCamino({double? etaMin, double? distKm, DateTime? etaTarget}) {
    final em = (etaMin ?? 0).toDouble();
    final dk = (distKm ?? 0).toDouble();
    final showEta = em > 0;
    final showKm = dk > 0;

    final line = [
      if (showEta) 'Llega aprox. en ${em.toStringAsFixed(0)} min',
      if (showKm) '${dk.toStringAsFixed(1)} km',
    ].join(' • ');

    final t = etaTarget;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1A12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent.withAlpha(96)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.directions_car, color: Colors.greenAccent),
              SizedBox(width: 10),
              Expanded(
                child: Text('Tu taxista va en camino',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (line.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(line, style: const TextStyle(color: Colors.white70)),
          ],
          if (t != null) ...[
            const SizedBox(height: 6),
            _CountdownGrande(target: t),
          ],
        ],
      ),
    );
  }

  /// Bloqueo modal sin pasar BuildContext por awaits
  Future<void> _runWithBlocking(Future<void> Function() task) async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator(color: Colors.greenAccent)),
      ),
    );
    try {
      await task();
    } finally {
      if (mounted) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) {
          nav.pop();
        }
      }
    }
  }

  String _labelEstado(String e) {
    final s = EstadosViaje.normalizar(e);
    if (s == EstadosViaje.pendiente) return 'Pendiente';
    if (s == EstadosViaje.aceptado) return 'Aceptado';
    if (s == EstadosViaje.enCaminoPickup) return 'Conductor en camino';
    if (s == EstadosViaje.aBordo) return 'A bordo';
    if (s == EstadosViaje.enCurso) return 'En curso';
    if (s == EstadosViaje.completado) return 'Completado';
    if (s == EstadosViaje.cancelado) return 'Cancelado';
    return e;
  }

  // ===== Botón: Ver taxista (abre hoja con acciones) =====
  Widget _btnVerTaxista(Viaje v) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.person_outline, color: Colors.green),
        label: const Text('Ver taxista'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          minimumSize: const Size(double.infinity, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () => _abrirHojaAccionesTaxista(v),
      ),
    );
  }

  // ===== Botón: Ver ruta al destino (mantener) =====
  Widget _btnVerRuta(Viaje v) {
    final tieneDestino = _isValidCoord(v.latDestino, v.lonDestino);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: !tieneDestino ? null : () async {
          if (!mounted) return;
          await showModalBottomSheet(
            context: context,
            backgroundColor: Colors.black,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            builder: (_) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(runSpacing: 12, children: [
                  Center(child: Container(width: 44, height: 5,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)))),
                  const SizedBox(height: 8),
                  const Text('Abrir navegación', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => abrirNavegacionAlDestino(v),
                    icon: const Icon(Icons.directions_car, color: Colors.green),
                    label: const Text('Waze'),
                    style: _styleBase(),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openGoogleMapsTo(v.latDestino, v.lonDestino, label: v.destino),
                    icon: const Icon(Icons.map, color: Colors.green),
                    label: const Text('Google Maps'),
                    style: _styleBase(),
                  ),
                ]),
              ),
            ),
          );
        },
        icon: const Icon(Icons.route, color: Colors.green),
        label: const Text('Ver ruta al destino'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          minimumSize: const Size(double.infinity, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // ===== Hoja de acciones del taxista (con datos visibles) =====
  Future<void> _abrirHojaAccionesTaxista(Viaje v) async {
    if (!mounted) return;

    // Datos mínimos para acciones y visualización
    final telFromViaje = v.telefonoTaxista.isNotEmpty ? v.telefonoTaxista : v.telefono;
    final tel = telFromViaje.trim().isNotEmpty ? telFromViaje : '';
    String normalize(String raw) {
      final only = raw.replaceAll(RegExp(r'\D+'), '');
      if (only.isEmpty) return '';
      if (only.startsWith('1')) return only; // +1 RD
      if (only.length == 10) return '1$only';
      return only;
    }
    final telClean = normalize(tel);
    final tieneTel = telClean.isNotEmpty;
    final taxistaId = v.uidTaxista;
    final nombre = v.nombreTaxista.isEmpty ? 'Taxista' : v.nombreTaxista;

    // También mostramos detalles del vehículo aquí
    // Cargar perfil en el sheet con un StreamBuilder anidado para datos vivos
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) {
        final taxistaRef = FirebaseFirestore.instance.collection('usuarios').doc(v.uidTaxista);
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: taxistaRef.snapshots(),
          builder: (ctx, snap) {
            final tx = (snap.hasData && snap.data!.exists) ? (snap.data!.data() ?? const {}) : const {};

            final tipo   = _s(v.tipoVehiculo).trim().isNotEmpty ? _s(v.tipoVehiculo).trim() : _s(tx['tipoVehiculo']).trim();
            final marca  = _s((v as dynamic).marca).trim().isNotEmpty ? _s((v as dynamic).marca).trim()
                           : _s(tx['marca']).trim().isNotEmpty ? _s(tx['marca']).trim() : _s(tx['vehiculoMarca']).trim();
            final modelo = _s((v as dynamic).modelo).trim().isNotEmpty ? _s((v as dynamic).modelo).trim()
                           : _s(tx['modelo']).trim().isNotEmpty ? _s(tx['modelo']).trim() : _s(tx['vehiculoModelo']).trim();
            final color  = _s((v as dynamic).color).trim().isNotEmpty ? _s((v as dynamic).color).trim()
                           : _s(tx['color']).trim().isNotEmpty ? _s(tx['color']).trim() : _s(tx['vehiculoColor']).trim();
            final placa  = _s((v as dynamic).placa).trim().isNotEmpty ? _s((v as dynamic).placa).trim()
                           : _s(tx['placa']).trim();

            final vehiculoLinea = [
              if (tipo.isNotEmpty) tipo,
              if (marca.isNotEmpty) marca,
              if (modelo.isNotEmpty) modelo,
            ].join(' · ');

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16, right: 16, top: 16,
                  bottom: MediaQuery.of(sheetCtx).viewPadding.bottom + 16,
                ),
                child: Wrap(runSpacing: 12, children: [
                  Center(child: Container(width: 46, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)))),
                  const SizedBox(height: 6),
                  const Text('Tu taxista', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(nombre, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),

                  // Detalles del vehículo en la hoja
                  if (vehiculoLinea.isNotEmpty)
                    Text('Vehículo: $vehiculoLinea', style: const TextStyle(color: Colors.white70)),
                  Row(
                    children: [
                      if (placa.isNotEmpty) Expanded(child: Text('Placa: $placa', style: const TextStyle(color: Colors.white54))),
                      if (color.isNotEmpty) Expanded(child: Text('Color: $color', style: const TextStyle(color: Colors.white54))),
                    ],
                  ),
                  if (telClean.isNotEmpty)
                    Text('Teléfono: +$telClean', style: const TextStyle(color: Colors.white54)),

                  const SizedBox(height: 4),
                  ElevatedButton.icon(
                    onPressed: !tieneTel ? null : () async {
                      final uri = Uri(scheme: 'tel', path: '+$telClean');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.platformDefault);
                      }
                    },
                    icon: const Icon(Icons.call, color: Colors.green),
                    label: const Text('Llamar'),
                    style: _styleBase(),
                  ),
                  ElevatedButton.icon(
                    onPressed: !tieneTel ? null : () async {
                      final msg = Uri.encodeComponent('Hola, soy tu cliente de FlyGo.');
                      final waApp = Uri.parse('whatsapp://send?phone=%2B$telClean&text=$msg');
                      if (await canLaunchUrl(waApp)) {
                        await launchUrl(waApp);
                      } else {
                        final waWeb = Uri.parse('https://wa.me/$telClean?text=$msg');
                        await launchUrl(waWeb, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.chat_bubble_outline, color: Colors.green),
                    label: const Text('WhatsApp'),
                    style: _styleBase(),
                  ),
                  ElevatedButton.icon(
                    onPressed: taxistaId.isEmpty ? null : () {
                      Navigator.of(sheetCtx).pop();
                      if (!mounted) return;
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChatScreen(otroUid: taxistaId, otroNombre: nombre, viajeId: v.id),
                      ));
                    },
                    icon: const Icon(Icons.chat, color: Colors.green),
                    label: const Text('Chat (app)'),
                    style: _styleBase(),
                  ),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  ButtonStyle _styleBase() => ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        minimumSize: const Size(double.infinity, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
}

/* ============== Countdown grande ============== */
class _CountdownGrande extends StatelessWidget {
  final DateTime target;
  const _CountdownGrande({required this.target});

  String _fmt(Duration d) {
    if (d.inSeconds <= 0) return 'AHORA';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: Stream<DateTime>.periodic(const Duration(seconds: 5), (_) => DateTime.now()),
      initialData: DateTime.now(),
      builder: (context, snap) {
        final now = snap.data!;
        final txt = _fmt(target.difference(now));
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Center(
            child: Text(
              txt,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.greenAccent),
            ),
          ),
        );
      },
    );
  }
}

