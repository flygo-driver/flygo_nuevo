import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:flygo_nuevo/utils/rai_region_operativa.dart';

/// Estilo y utilidades compartidas para mapas RAI (cliente + taxista).
abstract final class RaiMapPresentation {
  RaiMapPresentation._();

  static const double maxZoomTrip = 16.5;
  static const double followZoomDriver = 17.0;
  static const double followZoomBooking = 15.5;

  static const Color routeCore = Color(0xFF0A0A0A);
  static const Color routeGlow = Color(0x66000000);
  static const Color routeNeon = Color(0xFF00E676);

  static LatLngBounds boundsFromPoints(Iterable<LatLng> points) {
    final List<LatLng> pts = points.toList(growable: false);
    if (pts.isEmpty) {
      const LatLng c = RaiRegionOperativa.centroNacional;
      return LatLngBounds(
        southwest: LatLng(c.latitude - 0.04, c.longitude - 0.04),
        northeast: LatLng(c.latitude + 0.04, c.longitude + 0.04),
      );
    }
    double minLat = pts.first.latitude;
    double maxLat = pts.first.latitude;
    double minLng = pts.first.longitude;
    double maxLng = pts.first.longitude;
    for (final LatLng p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  static Future<void> fitBounds(
    GoogleMapController controller,
    LatLngBounds bounds, {
    double padding = 100,
    double maxZoom = maxZoomTrip,
  }) async {
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, padding),
      );
      final double z = await controller.getZoomLevel();
      if (z > maxZoom) {
        await controller.animateCamera(CameraUpdate.zoomTo(maxZoom));
      }
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 160));
      try {
        await controller.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, padding),
        );
      } catch (_) {}
    }
  }

  /// Ruta con halo + núcleo (estilo app moderna).
  static void applyRoutePolylines(
    Set<Polyline> target, {
    required String id,
    required List<LatLng> points,
    bool wideRibbon = false,
    Color? coreColor,
  }) {
    target.removeWhere(
      (Polyline p) =>
          p.polylineId.value == id || p.polylineId.value == '${id}_glow',
    );
    if (points.length < 2) return;

    if (wideRibbon) {
      target.add(
        Polyline(
          polylineId: PolylineId('${id}_glow'),
          points: points,
          width: 22,
          color: routeGlow,
          geodesic: true,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
      target.add(
        Polyline(
          polylineId: PolylineId(id),
          points: points,
          width: 16,
          color: routeCore,
          geodesic: true,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
      return;
    }

    target.add(
      Polyline(
        polylineId: PolylineId('${id}_glow'),
        points: points,
        width: 10,
        color: routeNeon.withValues(alpha: 0.28),
        geodesic: true,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    );
    target.add(
      Polyline(
        polylineId: PolylineId(id),
        points: points,
        width: 6,
        color: coreColor ?? routeNeon,
        geodesic: true,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    );
  }

  /// Halos suaves en origen (azul) y destino (verde RAI).
  static void syncHalos({
    required Set<Circle> circles,
    LatLng? origen,
    LatLng? destino,
    String origenId = 'halo_origen',
    String destinoId = 'halo_destino',
  }) {
    circles.removeWhere(
      (Circle c) =>
          c.circleId.value == origenId || c.circleId.value == destinoId,
    );
    if (origen != null) {
      circles.add(
        Circle(
          circleId: CircleId(origenId),
          center: origen,
          radius: 52,
          fillColor: const Color(0x4400B0FF),
          strokeColor: const Color(0xFF00B0FF),
          strokeWidth: 2,
          zIndex: 1,
        ),
      );
    }
    if (destino != null) {
      circles.add(
        Circle(
          circleId: CircleId(destinoId),
          center: destino,
          radius: 52,
          fillColor: const Color(0x4400E676),
          strokeColor: const Color(0xFF00E676),
          strokeWidth: 2,
          zIndex: 1,
        ),
      );
    }
  }
}
