import 'package:geolocator/geolocator.dart';

/// Normalización y validación de origen / paradas / destino (multiparada).
abstract final class MultiparadaRutaHelper {
  MultiparadaRutaHelper._();

  static const double metrosMinEntrePuntos = 40;

  /// Rutas corporativas (recogida empresa → bajadas): umbral más bajo que taxi.
  static const double metrosMinEntrePuntosCorporativo = 20;

  static double round6(double v) => double.parse(v.toStringAsFixed(6));

  static String normalizarLabel(String raw, String fallback) {
    final String s = raw.trim();
    return s.isEmpty ? fallback : s;
  }

  static bool coordsValidas(double lat, double lon) =>
      lat.isFinite &&
      lon.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lon >= -180 &&
      lon <= 180 &&
      !(lat.abs() < 1e-6 && lon.abs() < 1e-6);

  static bool coordsCercanas(
    double lat1,
    double lon1,
    double lat2,
    double lon2, {
    double metros = metrosMinEntrePuntos,
  }) {
    if (!coordsValidas(lat1, lon1) || !coordsValidas(lat2, lon2)) {
      return false;
    }
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) < metros;
  }

  static double? coordLat(Map<String, dynamic> w) {
    for (final String k in <String>['lat', 'latitude', 'latitud']) {
      final dynamic x = w[k];
      if (x is num && x.isFinite) return x.toDouble();
      final double? d = double.tryParse('$x');
      if (d != null && d.isFinite) return d;
    }
    return null;
  }

  static double? coordLon(Map<String, dynamic> w) {
    for (final String k in <String>['lon', 'lng', 'longitude', 'longitud']) {
      final dynamic x = w[k];
      if (x is num && x.isFinite) return x.toDouble();
      final double? d = double.tryParse('$x');
      if (d != null && d.isFinite) return d;
    }
    return null;
  }

  /// Waypoints intermedios ordenados y con etiquetas/coords normalizadas.
  static List<Map<String, dynamic>> waypointsDesdeDoc(
    Map<String, dynamic> data,
  ) {
    final dynamic raw = data['waypoints'];
    if (raw is! List) return <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> parsed = <Map<String, dynamic>>[];
    for (final dynamic w in raw) {
      if (w is Map) parsed.add(Map<String, dynamic>.from(w));
    }
    return sanitizarWaypoints(parsed);
  }

  static bool esViajeMultiparada(Map<String, dynamic> data) {
    final String cat =
        (data['categoria'] ?? '').toString().trim().toLowerCase();
    if (cat == 'multi') return true;
    if (waypointsDesdeDoc(data).isNotEmpty) return true;
    final dynamic legs = data['multiparadaLegsTotal'];
    if (legs is num && legs.toInt() > 1) return true;
    final dynamic rp = data['extras'] is Map
        ? (data['extras'] as Map)['rutaPuntos']
        : null;
    if (rp is List) {
      for (final dynamic item in rp) {
        if (item is Map &&
            (item['rol'] ?? '').toString().toLowerCase() == 'parada') {
          return true;
        }
      }
    }
    return false;
  }

  /// Ordena por `orden`, redondea coords y renumera 1…n.
  static List<Map<String, dynamic>> sanitizarWaypoints(
    List<Map<String, dynamic>> raw,
  ) {
    final List<Map<String, dynamic>> parsed = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> w in raw) {
      final double? lat = coordLat(w);
      final double? lon = coordLon(w);
      if (lat == null || lon == null || !coordsValidas(lat, lon)) continue;
      final int orden = (w['orden'] is num) ? (w['orden'] as num).toInt() : 0;
      parsed.add(<String, dynamic>{
        'lat': round6(lat),
        'lon': round6(lon),
        'label': normalizarLabel(
          (w['label'] ?? '').toString(),
          'Parada ${parsed.length + 1}',
        ),
        if (orden > 0) 'orden': orden,
        if (w['pasajeroId'] != null) 'pasajeroId': w['pasajeroId'],
      });
    }
    if (parsed.isEmpty) return parsed;
    parsed.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final int oa = (a['orden'] as int?) ?? 0;
      final int ob = (b['orden'] as int?) ?? 0;
      if (oa != ob) return oa.compareTo(ob);
      return 0;
    });
    for (int i = 0; i < parsed.length; i++) {
      parsed[i]['orden'] = i + 1;
      final String lbl = (parsed[i]['label'] ?? '').toString();
      if (lbl.trim().isEmpty) {
        parsed[i]['label'] = 'Parada ${i + 1}';
      }
    }
    return parsed;
  }

  /// `null` si la ruta es válida; mensaje para el usuario si no.
  static String? validarSecuenciaRuta({
    required double latOrigen,
    required double lonOrigen,
    required String labelOrigen,
    required double latDestino,
    required double lonDestino,
    required String labelDestino,
    required List<({double lat, double lon, String label})> paradas,
    double metrosMinimos = metrosMinEntrePuntos,
    String? mensajeOrigenDestinoCercanos,
    String? mensajeOrigenDestinoCoinciden,
  }) {
    if (!coordsValidas(latOrigen, lonOrigen) ||
        !coordsValidas(latDestino, lonDestino)) {
      return 'Origen o destino sin ubicación válida en el mapa.';
    }
    if (coordsCercanas(
      latOrigen,
      lonOrigen,
      latDestino,
      lonDestino,
      metros: metrosMinimos,
    )) {
      return mensajeOrigenDestinoCercanos ??
          'El destino está demasiado cerca del origen. Elegí puntos distintos.';
    }
    final List<({double lat, double lon, String label})> secuencia =
        <({double lat, double lon, String label})>[
      (lat: latOrigen, lon: lonOrigen, label: labelOrigen),
      ...paradas,
      (lat: latDestino, lon: lonDestino, label: labelDestino),
    ];
    for (int i = 0; i < secuencia.length; i++) {
      for (int j = i + 1; j < secuencia.length; j++) {
        if (coordsCercanas(
          secuencia[i].lat,
          secuencia[i].lon,
          secuencia[j].lat,
          secuencia[j].lon,
          metros: metrosMinimos,
        )) {
          if (i == 0 && j == secuencia.length - 1) {
            return mensajeOrigenDestinoCoinciden ??
                'El destino coincide con el origen. Revisá la ruta.';
          }
          return 'Hay dos paradas en el mismo lugar (${secuencia[i].label} y '
              '${secuencia[j].label}). Ajustá origen, paradas o destino.';
        }
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> construirRutaPuntos({
    required double latOrigen,
    required double lonOrigen,
    required String labelOrigen,
    required double latDestino,
    required double lonDestino,
    required String labelDestino,
    required List<Map<String, dynamic>> waypoints,
  }) {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[
      <String, dynamic>{
        'lat': round6(latOrigen),
        'lon': round6(lonOrigen),
        'label': normalizarLabel(labelOrigen, 'Origen'),
        'rol': 'origen',
      },
    ];
    for (final Map<String, dynamic> w in waypoints) {
      final orden = w['orden'];
      out.add(<String, dynamic>{
        'lat': w['lat'],
        'lon': w['lon'],
        'label': normalizarLabel((w['label'] ?? '').toString(), 'Parada'),
        'rol': 'parada',
        if (orden is num) 'orden': orden.toInt(),
      });
    }
    out.add(<String, dynamic>{
      'lat': round6(latDestino),
      'lon': round6(lonDestino),
      'label': normalizarLabel(labelDestino, 'Destino'),
      'rol': 'destino',
    });
    return out;
  }

  /// Alinea textos y coords de segmentos con la ruta visible al guardar.
  static List<Map<String, dynamic>> alinearSegmentosConPuntos({
    required List<Map<String, dynamic>> segmentos,
    required List<({String label, double lat, double lon})> puntosOrdenados,
  }) {
    if (segmentos.isEmpty || puntosOrdenados.length < 2) return segmentos;
    if (segmentos.length != puntosOrdenados.length - 1) return segmentos;
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (int i = 0; i < segmentos.length; i++) {
      final Map<String, dynamic> seg =
          Map<String, dynamic>.from(segmentos[i]);
      final ({String label, double lat, double lon}) desde = puntosOrdenados[i];
      final ({String label, double lat, double lon}) hasta =
          puntosOrdenados[i + 1];
      seg['tramo'] = i + 1;
      seg['origen'] = desde.label;
      seg['destino'] = hasta.label;
      seg['latOrigen'] = round6(desde.lat);
      seg['lonOrigen'] = round6(desde.lon);
      seg['latDestino'] = round6(hasta.lat);
      seg['lonDestino'] = round6(hasta.lon);
      out.add(seg);
    }
    return out;
  }
}
