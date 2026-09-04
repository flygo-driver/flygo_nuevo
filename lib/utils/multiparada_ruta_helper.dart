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

  /// 🔥 MEJORA: ahora NO elimina waypoints duplicados ni cercanos,
  /// solo descarta coordenadas inválidas (null, NaN, 0,0).
  static List<Map<String, dynamic>> sanitizarWaypoints(
    List<Map<String, dynamic>> raw,
  ) {
    final List<Map<String, dynamic>> parsed = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> w in raw) {
      final double? lat = coordLat(w);
      final double? lon = coordLon(w);
      // Solo descartar si lat o lon son nulos, no finitos, o exactamente 0,0
      if (lat == null || lon == null) continue;
      if (!lat.isFinite || !lon.isFinite) continue;
      if (lat == 0 && lon == 0) continue;
      // 🔥 Ya no verificamos duplicados ni cercanía; el usuario decide
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

  /// Paradas intermedias (sin origen ni destino) para mapa, Waze y Google Maps.
  static List<({double lat, double lon, String label})>
      paradasIntermediasParaNavegacion({
    required Map<String, dynamic> viajeData,
    List<Map<String, dynamic>>? waypointsModel,
  }) {
    final List<({double lat, double lon, String label})> desdeRuta =
        _paradasDesdeRutaPuntos(viajeData);
    final List<({double lat, double lon, String label})> desdeWaypoints =
        _paradasDesdeWaypoints(viajeData, waypointsModel);
    final List<({double lat, double lon, String label})> fusionadas =
        _fusionarParadasNavegacion(desdeRuta, desdeWaypoints);
    if (fusionadas.isNotEmpty) return fusionadas;
    return _paradasDesdeSegmentos(viajeData);
  }

  static List<({double lat, double lon, String label})> _paradasDesdeWaypoints(
    Map<String, dynamic> viajeData,
    List<Map<String, dynamic>>? waypointsModel,
  ) {
    final List<({double lat, double lon, String label})> out =
        <({double lat, double lon, String label})>[];
    final List<Map<String, dynamic>> wps =
        waypointsModel != null && waypointsModel.isNotEmpty
            ? sanitizarWaypoints(waypointsModel)
            : waypointsDesdeDoc(viajeData);
    for (final Map<String, dynamic> m in wps) {
      final double? lat = coordLat(m);
      final double? lon = coordLon(m);
      if (lat == null || lon == null || !coordsValidas(lat, lon)) continue;
      final String label = normalizarLabel(
        (m['label'] ?? '').toString(),
        'Parada ${out.length + 1}',
      );
      out.add((lat: lat, lon: lon, label: label));
    }
    return out;
  }

  static List<({double lat, double lon, String label})> _paradasDesdeRutaPuntos(
    Map<String, dynamic> viajeData,
  ) {
    final List<({double lat, double lon, String label})> out =
        <({double lat, double lon, String label})>[];
    final dynamic rp = _rutaPuntosDesdeViajeData(viajeData);
    if (rp is! List) return out;
    for (final dynamic item in rp) {
      if (item is! Map) continue;
      final Map<String, dynamic> m = Map<String, dynamic>.from(item);
      final String rol = (m['rol'] ?? '').toString().toLowerCase();
      if (rol == 'origen' || rol == 'destino' || rol == 'destino_final') {
        continue;
      }
      final double? lat = coordLat(m);
      final double? lon = coordLon(m);
      if (lat == null || lon == null || !coordsValidas(lat, lon)) continue;
      final String label = normalizarLabel(
        (m['label'] ?? 'Parada').toString(),
        'Parada ${out.length + 1}',
      );
      out.add((lat: lat, lon: lon, label: label));
    }
    return out;
  }

  static List<({double lat, double lon, String label})> _paradasDesdeSegmentos(
    Map<String, dynamic> viajeData,
  ) {
    final List<({double lat, double lon, String label})> out =
        <({double lat, double lon, String label})>[];
    final dynamic raw = viajeData['segmentos'];
    final dynamic ex = viajeData['extras'];
    final List<dynamic> segs = raw is List
        ? raw
        : (ex is Map && ex['segmentos'] is List)
            ? ex['segmentos'] as List
            : <dynamic>[];
    if (segs.length < 2) return out;
    for (int i = 0; i < segs.length - 1; i++) {
      final dynamic item = segs[i];
      if (item is! Map) continue;
      final Map<String, dynamic> m = Map<String, dynamic>.from(item);
      final double? lat = _coordField(m, 'latDestino');
      final double? lon = _coordField(m, 'lonDestino');
      if (lat == null || lon == null || !coordsValidas(lat, lon)) continue;
      final String label = normalizarLabel(
        (m['destino'] ?? m['label'] ?? 'Parada ${out.length + 1}').toString(),
        'Parada ${out.length + 1}',
      );
      out.add((lat: lat, lon: lon, label: label));
    }
    return out;
  }

  /// Por índice: prioriza [rutaPuntos] y rellena huecos con [waypoints].
  static List<({double lat, double lon, String label})> _fusionarParadasNavegacion(
    List<({double lat, double lon, String label})> desdeRuta,
    List<({double lat, double lon, String label})> desdeWaypoints,
  ) {
    final int n = desdeRuta.length > desdeWaypoints.length
        ? desdeRuta.length
        : desdeWaypoints.length;
    if (n == 0) return <({double lat, double lon, String label})>[];
    final List<({double lat, double lon, String label})> out =
        <({double lat, double lon, String label})>[];
    for (int i = 0; i < n; i++) {
      final ({double lat, double lon, String label})? r =
          i < desdeRuta.length ? desdeRuta[i] : null;
      final ({double lat, double lon, String label})? w =
          i < desdeWaypoints.length ? desdeWaypoints[i] : null;
      if (r != null && coordsValidas(r.lat, r.lon)) {
        out.add(r);
      } else if (w != null && coordsValidas(w.lat, w.lon)) {
        out.add(w);
      }
    }
    return out;
  }

  /// Origen / pickup con fallback a `latOrigen`/`lonOrigen` y `rutaPuntos`.
  static ({double lat, double lon, String label})? origenParaNavegacion({
    required Map<String, dynamic> viajeData,
    required double latClienteModelo,
    required double lonClienteModelo,
    String labelOrigen = '',
  }) {
    if (coordsValidas(latClienteModelo, lonClienteModelo)) {
      return (
        lat: latClienteModelo,
        lon: lonClienteModelo,
        label: normalizarLabel(labelOrigen, 'Origen'),
      );
    }
    final double? latOri = _coordField(viajeData, 'latOrigen');
    final double? lonOri = _coordField(viajeData, 'lonOrigen');
    if (latOri != null &&
        lonOri != null &&
        coordsValidas(latOri, lonOri)) {
      return (
        lat: latOri,
        lon: lonOri,
        label: normalizarLabel(labelOrigen, 'Origen'),
      );
    }
    final dynamic rp = _rutaPuntosDesdeViajeData(viajeData);
    if (rp is List) {
      for (final dynamic item in rp) {
        if (item is! Map) continue;
        final Map<String, dynamic> m = Map<String, dynamic>.from(item);
        final String rol = (m['rol'] ?? '').toString().toLowerCase();
        if (rol != 'origen') continue;
        final double? lat = coordLat(m);
        final double? lon = coordLon(m);
        if (lat == null || lon == null || !coordsValidas(lat, lon)) continue;
        final String lbl = (m['label'] ?? labelOrigen).toString().trim();
        return (
          lat: lat,
          lon: lon,
          label: normalizarLabel(lbl, 'Origen'),
        );
      }
    }
    final dynamic geo = viajeData['origenGeoPoint'];
    if (geo != null) {
      try {
        final dynamic lat = (geo as dynamic).latitude;
        final dynamic lon = (geo as dynamic).longitude;
        if (lat is num && lon is num) {
          final double la = lat.toDouble();
          final double lo = lon.toDouble();
          if (coordsValidas(la, lo)) {
            return (
              lat: la,
              lon: lo,
              label: normalizarLabel(labelOrigen, 'Origen'),
            );
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Destino final con fallback a `rutaPuntos` si `latDestino`/`lonDestino` vienen en 0.
  static ({double lat, double lon, String label, bool esFinal})?
      destinoFinalLegParaNavegacion({
    required Map<String, dynamic> viajeData,
    required double latDestinoModelo,
    required double lonDestinoModelo,
    String labelDestino = '',
  }) {
    if (coordsValidas(latDestinoModelo, lonDestinoModelo)) {
      return (
        lat: latDestinoModelo,
        lon: lonDestinoModelo,
        label: normalizarLabel(labelDestino, 'Destino final'),
        esFinal: true,
      );
    }
    final dynamic rp = _rutaPuntosDesdeViajeData(viajeData);
    if (rp is! List) return null;
    for (final dynamic item in rp.reversed) {
      if (item is! Map) continue;
      final Map<String, dynamic> m = Map<String, dynamic>.from(item);
      final String rol = (m['rol'] ?? '').toString().toLowerCase();
      if (rol != 'destino' && rol != 'destino_final') continue;
      final double? lat = coordLat(m);
      final double? lon = coordLon(m);
      if (lat == null || lon == null || !coordsValidas(lat, lon)) continue;
      final String lbl = (m['label'] ?? labelDestino).toString().trim();
      return (
        lat: lat,
        lon: lon,
        label: normalizarLabel(lbl, 'Destino final'),
        esFinal: true,
      );
    }
    final dynamic geoDest = viajeData['destinoGeoPoint'];
    if (geoDest != null) {
      try {
        final dynamic lat = (geoDest as dynamic).latitude;
        final dynamic lon = (geoDest as dynamic).longitude;
        if (lat is num && lon is num) {
          final double la = lat.toDouble();
          final double lo = lon.toDouble();
          if (coordsValidas(la, lo)) {
            return (
              lat: la,
              lon: lo,
              label: normalizarLabel(labelDestino, 'Destino final'),
              esFinal: true,
            );
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Orden de navegación multiparada: paradas → destino final.
  static List<({double lat, double lon, String label, bool esFinal})>
      legsNavegacionMultiparada({
    required Map<String, dynamic> viajeData,
    List<Map<String, dynamic>>? waypointsModel,
    required double latDestinoModelo,
    required double lonDestinoModelo,
    String labelDestino = '',
  }) {
    final List<({double lat, double lon, String label, bool esFinal})> out =
        <({double lat, double lon, String label, bool esFinal})>[];
    for (final ({double lat, double lon, String label}) p
        in paradasIntermediasParaNavegacion(
      viajeData: viajeData,
      waypointsModel: waypointsModel,
    )) {
      out.add((lat: p.lat, lon: p.lon, label: p.label, esFinal: false));
    }
    final ({double lat, double lon, String label, bool esFinal})? dest =
        destinoFinalLegParaNavegacion(
      viajeData: viajeData,
      latDestinoModelo: latDestinoModelo,
      lonDestinoModelo: lonDestinoModelo,
      labelDestino: labelDestino,
    );
    if (dest != null) out.add(dest);
    return out;
  }

  static dynamic _rutaPuntosDesdeViajeData(Map<String, dynamic> viajeData) {
    final dynamic directo = viajeData['rutaPuntos'];
    if (directo is List) return directo;
    final dynamic ex = viajeData['extras'];
    if (ex is Map) return ex['rutaPuntos'];
    return null;
  }

  static double? _coordField(Map<String, dynamic> data, String key) {
    final dynamic x = data[key];
    if (x is num && x.isFinite) return x.toDouble();
    final double? d = double.tryParse('$x');
    if (d != null && d.isFinite) return d;
    return null;
  }

  /// Documento mínimo para resolver paradas desde un [Viaje] en pantalla.
  static Map<String, dynamic> viajeDocDesdeModelo({
    List<Map<String, dynamic>>? waypoints,
    Map<String, dynamic>? extras,
    double latDestino = 0,
    double lonDestino = 0,
    String destino = '',
    double latCliente = 0,
    double lonCliente = 0,
    List<dynamic>? rutaPuntos,
    List<dynamic>? segmentos,
  }) {
    final Map<String, dynamic> ex =
        extras != null ? Map<String, dynamic>.from(extras) : <String, dynamic>{};
    final List<dynamic>? rp =
        rutaPuntos ?? (ex['rutaPuntos'] is List ? ex['rutaPuntos'] as List : null);
    final List<dynamic>? seg =
        segmentos ?? (ex['segmentos'] is List ? ex['segmentos'] as List : null);
    return <String, dynamic>{
      if (waypoints != null) 'waypoints': waypoints,
      'extras': ex,
      if (rp != null) 'rutaPuntos': rp,
      if (seg != null) 'segmentos': seg,
      'latCliente': latCliente,
      'lonCliente': lonCliente,
      'latDestino': latDestino,
      'lonDestino': lonDestino,
      'destino': destino,
    };
  }
}