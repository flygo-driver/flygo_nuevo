import 'dart:math' as math;

/// Geohash para consultas por zona en Firestore (`drivers_location`).
abstract final class RaiGeohash {
  RaiGeohash._();

  static const String _alphabet = '0123456789bcdefghjkmnpqrstuvwxyz';

  /// Codifica lat/lon a geohash (precisión 1–12).
  static String encode(
    double latitude,
    double longitude, {
    int precision = 7,
  }) {
    final int p = precision.clamp(1, 12);
    final List<double> latInterval = <double>[-90.0, 90.0];
    final List<double> lonInterval = <double>[-180.0, 180.0];
    final StringBuffer hash = StringBuffer();
    var isEven = true;
    var bit = 0;
    var ch = 0;

    while (hash.length < p) {
      if (isEven) {
        final double mid = (lonInterval[0] + lonInterval[1]) / 2;
        if (longitude > mid) {
          ch |= 1 << (4 - bit);
          lonInterval[0] = mid;
        } else {
          lonInterval[1] = mid;
        }
      } else {
        final double mid = (latInterval[0] + latInterval[1]) / 2;
        if (latitude > mid) {
          ch |= 1 << (4 - bit);
          latInterval[0] = mid;
        } else {
          latInterval[1] = mid;
        }
      }
      isEven = !isEven;
      if (bit < 4) {
        bit++;
      } else {
        hash.write(_alphabet[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return hash.toString();
  }

  /// Prefijos de celda para consultar conductores en un radio (centro + vecinos).
  static List<String> prefixesForRadius(
    double latitude,
    double longitude,
    double radiusKm,
  ) {
    final int precision = _precisionForRadiusKm(radiusKm);
    final String center = encode(latitude, longitude, precision: precision);
    final _GeoCell cell = _decode(center);
    final double latStep = cell.latErr * 2;
    final double lonStep = cell.lonErr * 2;
    final Set<String> out = <String>{center};

    for (final int dLat in <int>[-1, 0, 1]) {
      for (final int dLon in <int>[-1, 0, 1]) {
        if (dLat == 0 && dLon == 0) continue;
        out.add(
          encode(
            cell.lat + dLat * latStep,
            cell.lon + dLon * lonStep,
            precision: precision,
          ),
        );
      }
    }
    return out.toList(growable: false);
  }

  static int _precisionForRadiusKm(double radiusKm) {
    if (radiusKm <= 2) return 6;
    if (radiusKm <= 8) return 5;
    if (radiusKm <= 28) return 4;
    return 3;
  }

  static _GeoCell _decode(String hash) {
    final List<double> latInterval = <double>[-90.0, 90.0];
    final List<double> lonInterval = <double>[-180.0, 180.0];
    var isEven = true;

    for (int i = 0; i < hash.length; i++) {
      final int cd = _alphabet.indexOf(hash[i]);
      if (cd < 0) continue;
      for (int mask = 16; mask > 0; mask >>= 1) {
        if (isEven) {
          final double mid = (lonInterval[0] + lonInterval[1]) / 2;
          if ((cd & mask) != 0) {
            lonInterval[0] = mid;
          } else {
            lonInterval[1] = mid;
          }
        } else {
          final double mid = (latInterval[0] + latInterval[1]) / 2;
          if ((cd & mask) != 0) {
            latInterval[0] = mid;
          } else {
            latInterval[1] = mid;
          }
        }
        isEven = !isEven;
      }
    }

    final double lat = (latInterval[0] + latInterval[1]) / 2;
    final double lon = (lonInterval[0] + lonInterval[1]) / 2;
    return _GeoCell(
      lat: lat,
      lon: lon,
      latErr: (latInterval[1] - latInterval[0]) / 2,
      lonErr: (lonInterval[1] - lonInterval[0]) / 2,
    );
  }

  /// Límite superior de rango Firestore para prefijo geohash.
  static String upperBound(String prefix) => '$prefix\uf8ff';

  /// ¿Movió el centro lo suficiente para cambiar celdas de consulta?
  static bool debeRecalcularConsulta({
    required double prevLat,
    required double prevLon,
    required double newLat,
    required double newLon,
    required double radiusKm,
  }) {
    final int precision = _precisionForRadiusKm(radiusKm);
    final String a = encode(prevLat, prevLon, precision: precision);
    final String b = encode(newLat, newLon, precision: precision);
    if (a != b) return true;
    final double km = _haversineKm(prevLat, prevLon, newLat, newLon);
    return km > math.max(1.2, radiusKm * 0.12);
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double r = 6371.0;
    final double dLat = (lat2 - lat1) * math.pi / 180;
    final double dLon = (lon2 - lon1) * math.pi / 180;
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

class _GeoCell {
  const _GeoCell({
    required this.lat,
    required this.lon,
    required this.latErr,
    required this.lonErr,
  });

  final double lat;
  final double lon;
  final double latErr;
  final double lonErr;
}
