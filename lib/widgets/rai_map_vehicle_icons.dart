import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Iconos de vehículo para mapas (taxista en GPS + conductor visto por cliente).
abstract final class RaiMapVehicleIcons {
  static const String assetTaxista = 'assets/map/vehiculo_taxista.png';
  static const String assetTaxiCliente = 'assets/map/vehiculo_taxi_cliente.png';

  /// Imagen negra: frente apunta al norte.
  static const double _offsetTaxista = 0;

  /// Imagen amarilla: frente apunta al este → compensar −90°.
  static const double _offsetTaxiCliente = -90;

  static BitmapDescriptor? _taxista;
  static BitmapDescriptor? _taxiCliente;
  static Future<void>? _loading;

  static BitmapDescriptor? get taxista => _taxista;
  static BitmapDescriptor? get taxiCliente => _taxiCliente;
  static bool get listo => _taxista != null && _taxiCliente != null;

  static Future<void> ensureLoaded() {
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    const config = ImageConfiguration(
      size: Size(72, 72),
      devicePixelRatio: 2.5,
    );
    final results = await Future.wait([
      BitmapDescriptor.asset(config, assetTaxista),
      BitmapDescriptor.asset(config, assetTaxiCliente),
    ]);
    _taxista = results[0];
    _taxiCliente = results[1];
  }

  static double rotationTaxista(double bearing) =>
      _normalize(bearing + _offsetTaxista);

  static double rotationTaxiCliente(double bearing) =>
      _normalize(bearing + _offsetTaxiCliente);

  /// Bearing entre dos pings GPS (mín. 4 m para evitar jitter parado).
  static double? bearingEntre(LatLng? anterior, LatLng actual,
      {double minMetros = 4}) {
    if (anterior == null) return null;
    final d = Geolocator.distanceBetween(
      anterior.latitude,
      anterior.longitude,
      actual.latitude,
      actual.longitude,
    );
    if (d < minMetros) return null;
    return Geolocator.bearingBetween(
      anterior.latitude,
      anterior.longitude,
      actual.latitude,
      actual.longitude,
    );
  }

  static double resolverBearing({
    required LatLng actual,
    LatLng? anterior,
    double? headingGps,
    double fallback = 0,
  }) {
    if (headingGps != null && headingGps.isFinite && headingGps >= 0) {
      return headingGps;
    }
    return bearingEntre(anterior, actual) ?? fallback;
  }

  static double _normalize(double deg) {
    var d = deg % 360;
    if (d < 0) d += 360;
    return d;
  }

  /// Widget para flutter_map (web): rota el PNG según bearing.
  static Widget imagenTaxista({
    required double bearing,
    double size = 52,
    bool vistaCliente = false,
  }) {
    final asset = vistaCliente ? assetTaxiCliente : assetTaxista;
    final rot = vistaCliente
        ? rotationTaxiCliente(bearing)
        : rotationTaxista(bearing);
    return Transform.rotate(
      angle: rot * math.pi / 180,
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
