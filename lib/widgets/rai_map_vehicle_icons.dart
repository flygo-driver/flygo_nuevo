import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static BitmapDescriptor? _taxiClienteAsignado;
  static Future<void>? _loading;

  static BitmapDescriptor? get taxista => _taxista;
  static BitmapDescriptor? get taxiCliente => _taxiCliente;
  static BitmapDescriptor? get taxiClienteAsignado => _taxiClienteAsignado;
  static bool get listo =>
      _taxista != null && _taxiCliente != null && _taxiClienteAsignado != null;

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
      _tintedAssetIcon(assetTaxiCliente, const Color(0xFFE53935)),
    ]);
    _taxista = results[0];
    _taxiCliente = results[1];
    _taxiClienteAsignado = results[2];
  }

  static Future<BitmapDescriptor> _tintedAssetIcon(
    String assetPath,
    Color tint,
  ) async {
    final ByteData data = await rootBundle.load(assetPath);
    final ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: 144,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Paint paint = Paint()
      ..colorFilter = ColorFilter.mode(tint, BlendMode.srcIn);
    canvas.drawImage(image, Offset.zero, paint);
    final ui.Image tinted = await recorder
        .endRecording()
        .toImage(image.width, image.height);
    final ByteData? bytes =
        await tinted.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
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

  /// Vista cliente: rojo solo en fase recogida (viene hacia ti). En ruta al destino = taxi normal.
  static BitmapDescriptor? iconoVistaCliente({
    required bool esMiConductor,
    required bool faseRecogida,
  }) {
    if (esMiConductor && faseRecogida) {
      return taxiClienteAsignado ?? taxiCliente;
    }
    return taxiCliente;
  }

  static bool faseRecogidaDesdeEstado(String? estadoBase) {
    if (estadoBase == null || estadoBase.trim().isEmpty) return false;
    final String e = estadoBase.trim().toLowerCase();
    return e == 'aceptado' ||
        e == 'en_camino_pickup' ||
        e == 'encaminopickup';
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
    bool asignado = false,
  }) {
    final asset = vistaCliente ? assetTaxiCliente : assetTaxista;
    final rot = vistaCliente
        ? rotationTaxiCliente(bearing)
        : rotationTaxista(bearing);
    Widget img = Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
    if (asignado && vistaCliente) {
      img = ColorFiltered(
        colorFilter: const ColorFilter.mode(Color(0xFFE53935), BlendMode.srcIn),
        child: img,
      );
    }
    return Transform.rotate(
      angle: rot * math.pi / 180,
      child: img,
    );
  }
}
