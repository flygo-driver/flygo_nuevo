import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:flygo_nuevo/widgets/rai_map_vehicle_icons.dart';

/// Interpola posiciones de marcadores entre pings GPS para movimiento fluido.
class RaiLiveMarkerAnimator {
  RaiLiveMarkerAnimator({
    required TickerProvider vsync,
    required void Function() onTick,
    this.duration = const Duration(milliseconds: 900),
  }) : _onTick = onTick {
    _ticker = vsync.createTicker(_onFrame);
  }

  final Duration duration;
  final void Function() _onTick;

  late final Ticker _ticker;
  final Map<String, _AnimEntry> _entries = <String, _AnimEntry>{};

  void dispose() {
    _ticker.dispose();
    _entries.clear();
  }

  void clear() {
    _entries.clear();
    if (_ticker.isActive) _ticker.stop();
  }

  /// Actualiza destinos; inicia animación si hay cambio relevante.
  void syncTargets(
    Map<String, LatLng> targets, {
    Map<String, double?> headings = const <String, double?>{},
  }) {
    final Set<String> alive = targets.keys.toSet();
    _entries.removeWhere((String k, _) => !alive.contains(k));

    bool needsTick = false;
    for (final MapEntry<String, LatLng> e in targets.entries) {
      final String id = e.key;
      final LatLng target = e.value;
      final double? heading = headings[id];
      final _AnimEntry? prev = _entries[id];

      if (prev == null) {
        _entries[id] = _AnimEntry(
          from: target,
          to: target,
          fromBearing: heading,
          toBearing: heading,
          startedAt: DateTime.now(),
          settled: true,
        );
        continue;
      }

      if (_sameLatLng(prev.to, target, epsMeters: 2.5) &&
          (heading == null || _sameBearing(prev.toBearing, heading))) {
        continue;
      }

      final LatLng from = prev.settled ? prev.to : prev.lerpAt(_progress(prev));
      final double? fromBearing = prev.settled
          ? prev.toBearing
          : _lerpBearing(prev.fromBearing, prev.toBearing, _progress(prev));

      _entries[id] = _AnimEntry(
        from: from,
        to: target,
        fromBearing: fromBearing,
        toBearing: heading ?? fromBearing,
        startedAt: DateTime.now(),
        settled: false,
      );
      needsTick = true;
    }

    if (needsTick && !_ticker.isActive) {
      _ticker.start();
    }
  }

  LatLng position(String id, LatLng fallback) {
    final _AnimEntry? e = _entries[id];
    if (e == null) return fallback;
    if (e.settled) return e.to;
    return e.lerpAt(_progress(e));
  }

  double bearing(String id, {double fallback = 0}) {
    final _AnimEntry? e = _entries[id];
    if (e == null) return fallback;
    if (e.settled) {
      return e.toBearing ?? fallback;
    }
    return _lerpBearing(
          e.fromBearing,
          e.toBearing,
          _progress(e),
        ) ??
        fallback;
  }

  void _onFrame(Duration _) {
    bool animating = false;
    final DateTime now = DateTime.now();
    for (final _AnimEntry e in _entries.values) {
      if (e.settled) continue;
      if (now.difference(e.startedAt) >= duration) {
        e.settled = true;
      } else {
        animating = true;
      }
    }
    _onTick();
    if (!animating) _ticker.stop();
  }

  double _progress(_AnimEntry e) {
    final double t =
        DateTime.now().difference(e.startedAt).inMilliseconds / duration.inMilliseconds;
    return Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
  }

  static bool _sameLatLng(LatLng a, LatLng b, {double epsMeters = 3}) {
    final double dLat = (a.latitude - b.latitude).abs();
    final double dLng = (a.longitude - b.longitude).abs();
    return dLat < epsMeters / 111000 && dLng < epsMeters / 111000;
  }

  static bool _sameBearing(double? a, double? b) {
    if (a == null || b == null) return a == b;
    return (a - b).abs() < 4;
  }

  static double? _lerpBearing(double? a, double? b, double t) {
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;
    double diff = b - a;
    while (diff > 180) {
      diff -= 360;
    }
    while (diff < -180) {
      diff += 360;
    }
    return RaiMapVehicleIcons.rotationTaxiCliente(a + diff * t);
  }
}

class _AnimEntry {
  _AnimEntry({
    required this.from,
    required this.to,
    required this.fromBearing,
    required this.toBearing,
    required this.startedAt,
    required this.settled,
  });

  final LatLng from;
  final LatLng to;
  final double? fromBearing;
  final double? toBearing;
  final DateTime startedAt;
  bool settled;

  LatLng lerpAt(double t) {
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }
}
