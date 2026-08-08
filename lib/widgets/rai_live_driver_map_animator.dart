import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/drivers_location_nearby_config.dart';
import 'package:flygo_nuevo/utils/viaje_pool_taxista_gate.dart';
import 'package:flygo_nuevo/widgets/rai_map_vehicle_icons.dart';

/// Conductor en mapa en vivo (desde `drivers_location` o viaje).
class RaiLiveDriverPoint {
  const RaiLiveDriverPoint({
    required this.uid,
    required this.position,
    this.heading,
    this.online = true,
    this.viajeId,
    this.clienteId,
  });

  final String uid;
  final LatLng position;
  final double? heading;
  final bool online;
  final String? viajeId;
  final String? clienteId;

  bool esAsignadoA(String? clienteUid) {
    if (clienteUid == null || clienteUid.isEmpty) return false;
    if (clienteId != null && clienteId == clienteUid) return true;
    return false;
  }

  /// Conductor con viaje activo (demanda en curso — mapa rojo).
  bool get enViaje => viajeId != null && viajeId!.trim().isNotEmpty;
}

/// Interpola posiciones entre pings de Firestore para movimiento fluido.
class RaiLiveDriverMapAnimator {
  RaiLiveDriverMapAnimator({required TickerProvider vsync}) : _vsync = vsync;

  final TickerProvider _vsync;
  final Map<String, LatLng> _display = <String, LatLng>{};
  final Map<String, LatLng> _target = <String, LatLng>{};
  final Map<String, double> _bearing = <String, double>{};
  final Map<String, LatLng> _prevForBearing = <String, LatLng>{};

  Ticker? _ticker;
  VoidCallback? onFrame;

  Map<String, LatLng> get displayPositions =>
      Map<String, LatLng>.unmodifiable(_display);

  double bearingFor(String uid, {double fallback = 0}) =>
      _bearing[uid] ?? fallback;

  void syncTargets(Iterable<RaiLiveDriverPoint> drivers) {
    final Set<String> activos = <String>{};
    for (final RaiLiveDriverPoint d in drivers) {
      activos.add(d.uid);
      _target[d.uid] = d.position;
      _display.putIfAbsent(d.uid, () => d.position);

      final LatLng? prev = _prevForBearing[d.uid];
      final double? fromGps = d.heading;
      final double? fromMove = RaiMapVehicleIcons.bearingEntre(prev, d.position);
      if (fromGps != null && fromGps.isFinite && fromGps >= 0) {
        _bearing[d.uid] = fromGps;
      } else if (fromMove != null) {
        _bearing[d.uid] = fromMove;
      }
      _prevForBearing[d.uid] = d.position;
    }

    final List<String> stale =
        _target.keys.where((String k) => !activos.contains(k)).toList();
    for (final String k in stale) {
      _target.remove(k);
      _display.remove(k);
      _bearing.remove(k);
      _prevForBearing.remove(k);
    }

    _ensureTicker();
  }

  void _ensureTicker() {
    if (_ticker != null) return;
    _ticker = _vsync.createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    if (_target.isEmpty) return;
    bool cambio = false;
    for (final MapEntry<String, LatLng> e in _target.entries) {
      final LatLng actual = _display[e.key] ?? e.value;
      final LatLng objetivo = e.value;
      final double km = DistanciaService.calcularDistancia(
        actual.latitude,
        actual.longitude,
        objetivo.latitude,
        objetivo.longitude,
      );
      if (km < 0.00003) {
        if (actual != objetivo) {
          _display[e.key] = objetivo;
          cambio = true;
        }
        continue;
      }
      final double t = math.min(0.38, km * 18);
      _display[e.key] = LatLng(
        actual.latitude + (objetivo.latitude - actual.latitude) * t,
        actual.longitude + (objetivo.longitude - actual.longitude) * t,
      );
      cambio = true;
    }
    if (cambio) onFrame?.call();
  }

  void dispose() {
    _ticker?.dispose();
    _ticker = null;
  }
}

/// Parsea documentos `drivers_location` con filtro de frescura y disponibilidad.
List<RaiLiveDriverPoint> raiLiveDriversDesdeDocs(
  Iterable<DocumentSnapshot<Map<String, dynamic>>> docs, {
  Duration maxAge = DriversLocationNearbyConfig.maxAgeConductoresDisponibles,
  LatLng? centroKm,
  double? radioKm,
  String? uidCliente,
  /// Si se indica (p. ej. `motor`), solo conductores del mismo pool que el viaje.
  String? tipoServicioViaje,
}) {
  final DateTime ahora = DateTime.now();
  final DateTime limiteDisponibles = ahora.subtract(maxAge);
  final DateTime limiteAsignado = ahora.subtract(
    DriversLocationNearbyConfig.maxAgeConductorAsignado,
  );
  final List<RaiLiveDriverPoint> out = <RaiLiveDriverPoint>[];
  for (final DocumentSnapshot<Map<String, dynamic>> d in docs) {
    final Map<String, dynamic>? data = d.data();
    if (data == null) continue;
    if (!_conductorVisibleEnMapaCliente(data, uidCliente)) continue;
    if (!_conductorCoincideTipoViaje(data, uidCliente, tipoServicioViaje)) {
      continue;
    }

    final dynamic rawLoc = data['location'];
    if (rawLoc is! GeoPoint) continue;
    final double lat = rawLoc.latitude;
    final double lon = rawLoc.longitude;
    if (!lat.isFinite || !lon.isFinite) continue;

    final bool asignadoAlCliente = _conductorAsignadoAlCliente(data, uidCliente);
    final dynamic rawUp = data['updatedAt'];
    DateTime? updated;
    if (rawUp is Timestamp) updated = rawUp.toDate();
    final DateTime limite =
        asignadoAlCliente ? limiteAsignado : limiteDisponibles;
    if (updated != null && updated.isBefore(limite)) continue;

    if (centroKm != null && radioKm != null) {
      final double km = DistanciaService.calcularDistancia(
        centroKm.latitude,
        centroKm.longitude,
        lat,
        lon,
      );
      if (km > radioKm) continue;
    }

    final double? heading = (data['heading'] is num)
        ? (data['heading'] as num).toDouble()
        : null;

    out.add(
      RaiLiveDriverPoint(
        uid: d.id,
        position: LatLng(lat, lon),
        heading: heading,
        online: data['online'] != false,
        viajeId: data['viajeId']?.toString(),
        clienteId: data['clienteId']?.toString(),
      ),
    );
  }
  return out;
}

bool _conductorAsignadoAlCliente(
  Map<String, dynamic> data,
  String? uidCliente,
) {
  if (uidCliente == null || uidCliente.isEmpty) return false;
  final String cid = (data['clienteId'] ?? '').toString().trim();
  return cid.isNotEmpty && cid == uidCliente;
}

bool _conductorVisibleEnMapaCliente(
  Map<String, dynamic> data,
  String? uidCliente,
) {
  if (data['tracking'] != true) return false;

  if (_conductorAsignadoAlCliente(data, uidCliente)) return true;

  final String viajeId = (data['viajeId'] ?? '').toString().trim();
  if (viajeId.isNotEmpty) return false;

  return data['disponible'] == true && data['online'] == true;
}

/// Misma regla que el pool taxista: motor ↔ motor; taxi ↔ no motor.
bool _conductorCoincideTipoViaje(
  Map<String, dynamic> data,
  String? uidCliente,
  String? tipoServicioViaje,
) {
  if (tipoServicioViaje == null || tipoServicioViaje.trim().isEmpty) {
    return true;
  }
  if (_conductorAsignadoAlCliente(data, uidCliente)) return true;

  final String poolModoViaje =
      tipoServicioViaje.trim().toLowerCase() == TaxistaPoolModoConductor.motor
          ? TaxistaPoolModoConductor.motor
          : TaxistaPoolModoConductor.vehiculo;
  return ViajePoolTaxistaGate.viajeCoincideModoConductor(
    <String, dynamic>{'tipoServicio': _tipoServicioConductorEnMapa(data)},
    poolModoViaje,
  );
}

String _tipoServicioConductorEnMapa(Map<String, dynamic> data) {
  final String raw = (data['tipoServicio'] ?? '').toString().trim().toLowerCase();
  if (raw == TaxistaPoolModoConductor.motor) {
    return TaxistaPoolModoConductor.motor;
  }
  return 'normal';
}
