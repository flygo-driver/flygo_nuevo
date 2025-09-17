// lib/servicios/lugares_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:geocoding/geocoding.dart' as geocoding;

/// API key (Web) para Places Autocomplete/Details.
/// Si la dejas vacía, tendrás modo offline con POIs locales + geocoding fallback.
const String kGooglePlacesApiKey = '';

class PrediccionLugar {
  final String placeId;
  final String primary;
  final String? secondary;
  const PrediccionLugar({
    required this.placeId,
    required this.primary,
    this.secondary,
  });
}

class DetalleLugar {
  final String placeId;
  final String name; // “Hotel El Embajador”, “Calle X #12”, “BlueMall”
  final String? address; // “Piantini, Santo Domingo, DN, República Dominicana”
  final double lat;
  final double lon;

  const DetalleLugar({
    required this.placeId,
    required this.name,
    required this.lat,
    required this.lon,
    this.address,
  });

  String get displayLabel {
    final a = (address ?? '').trim();
    final n = name.trim();
    if (a.isEmpty) return n;
    if (a.toLowerCase().contains(n.toLowerCase())) return a;
    return '$n, $a';
  }
}

/// ---------------- POIs locales (RD) con aliases ----------------

class _LocalPOI {
  final String id; // código único interno
  final String name; // nombre visible
  final String address; // zona/ciudad
  final double lat;
  final double lon;
  final List<String> aliases; // abreviaturas, apodos, siglas
  const _LocalPOI(
    this.id,
    this.name,
    this.address,
    this.lat,
    this.lon, [
    this.aliases = const [],
  ]);
}

// Aeropuertos (con aliases que activan "ae", "aero", "aeropuerto", etc.)
const List<_LocalPOI> _AIRPORTS_DO = [
  _LocalPOI(
    'SDQ',
    'Aeropuerto Internacional Las Américas (SDQ)',
    'Boca Chica, Santo Domingo',
    18.4297,
    -69.6689,
    [
      'ae',
      'aer',
      'aero',
      'aerop',
      'aeropuerto',
      'las americas',
      'las américas',
      'sdq',
    ],
  ),
  _LocalPOI(
    'PUJ',
    'Aeropuerto Internacional de Punta Cana (PUJ)',
    'Punta Cana, La Altagracia',
    18.5674,
    -68.3634,
    [
      'ae',
      'aer',
      'aero',
      'aerop',
      'aeropuerto',
      'punta',
      'aeropuerto punta',
      'puj',
    ],
  ),
  _LocalPOI(
    'STI',
    'Aeropuerto Internacional del Cibao (STI)',
    'Santiago de los Caballeros',
    19.4061,
    -70.6047,
    ['ae', 'aer', 'aero', 'aerop', 'aeropuerto', 'cibao', 'sti'],
  ),
  _LocalPOI(
    'POP',
    'Aeropuerto Internacional Gregorio Luperón (POP)',
    'Puerto Plata',
    19.7579,
    -70.5697,
    ['ae', 'aer', 'aero', 'aerop', 'aeropuerto', 'puerto plata', 'pop'],
  ),
  _LocalPOI(
    'JBQ',
    'Aeropuerto Internacional La Isabela (JBQ)',
    'Santo Domingo (Higüero)',
    18.5725,
    -69.9856,
    [
      'ae',
      'aer',
      'aero',
      'aerop',
      'aeropuerto',
      'higuero',
      'la isabela',
      'jbq',
    ],
  ),
  _LocalPOI(
    'LRM',
    'Aeropuerto Internacional La Romana (LRM)',
    'La Romana',
    18.4510,
    -68.9117,
    ['ae', 'aer', 'aero', 'aerop', 'aeropuerto', 'la romana aeropuerto', 'lrm'],
  ),
  _LocalPOI(
    'AZS',
    'Aeropuerto Internacional El Catey (AZS)',
    'Samaná',
    19.2690,
    -69.7370,
    [
      'ae',
      'aer',
      'aero',
      'aerop',
      'aeropuerto',
      'catey',
      'samana aeropuerto',
      'azs',
    ],
  ),
];

// Hoteles/POIs/malls/zonas (muestra representativa, puedes añadir más)
const List<_LocalPOI> _POIS_DO = [
  // Hoteles SD
  _LocalPOI(
    'HTL_EMB',
    'Hotel El Embajador',
    'Piantini, Santo Domingo',
    18.4641,
    -69.9428,
    ['emb', 'embajador', 'hotel emb'],
  ),
  _LocalPOI(
    'HTL_JAR',
    'Renaissance Jaragua Hotel',
    'Malecón, Santo Domingo',
    18.4636,
    -69.8957,
    ['jar', 'jaragua'],
  ),
  _LocalPOI(
    'HTL_JWM',
    'JW Marriott Santo Domingo',
    'BlueMall, Piantini',
    18.4727,
    -69.9407,
    ['jw', 'jw marriott', 'marriot', 'marr'],
  ),
  // Hoteles PC
  _LocalPOI(
    'HTL_BBV',
    'Barceló Bávaro Palace',
    'Bávaro, Punta Cana',
    18.6576,
    -68.4015,
    ['barcelo', 'bavaro', 'bbv'],
  ),
  _LocalPOI(
    'HTL_HRH',
    'Hard Rock Hotel & Casino Punta Cana',
    'Macao, Punta Cana',
    18.7282,
    -68.4687,
    ['hard', 'hard rock', 'hrh'],
  ),

  // Malls
  _LocalPOI(
    'MALL_BM',
    'BlueMall Santo Domingo',
    'Piantini, Santo Domingo',
    18.4724,
    -69.9402,
    ['blue', 'bluemall'],
  ),
  _LocalPOI(
    'MALL_AG',
    'Ágora Mall',
    'Serrallés, Santo Domingo',
    18.4878,
    -69.9365,
    ['ago', 'agora'],
  ),
  _LocalPOI(
    'MALL_SA',
    'Sambil Santo Domingo',
    'Los Jardines, Santo Domingo',
    18.4870,
    -69.9218,
    ['sam', 'sambil'],
  ),
  _LocalPOI(
    'MALL_BMPC',
    'BlueMall Punta Cana',
    'Punta Cana',
    18.5670,
    -68.4033,
    ['blue', 'bluemall'],
  ),

  // Zonas/landmarks
  _LocalPOI('ZN_COL', 'Zona Colonial', 'Santo Domingo', 18.4764, -69.8833, [
    'zona',
    'colonial',
    'zona col',
  ]),
  _LocalPOI(
    'MLC_SD',
    'Malecón de Santo Domingo',
    'Santo Domingo',
    18.4605,
    -69.9048,
    ['male', 'malecon'],
  ),

  // Universidades/hospitales
  _LocalPOI(
    'UNI_UASD',
    'UASD - Universidad Autónoma de Santo Domingo',
    'Gazcue, Santo Domingo',
    18.4632,
    -69.9110,
    ['uasd', 'universidad uasd'],
  ),
  _LocalPOI(
    'HSP_CED',
    'Centro de Diagnóstico CEDIMAT',
    'Paseo de la Salud, SD',
    18.4707,
    -69.9537,
    ['ced', 'cedimat'],
  ),
];

// Lista completa unificada (aeropuertos + otros)
final List<_LocalPOI> _ALL_LOCAL = [..._AIRPORTS_DO, ..._POIS_DO];

String _norm(String s) {
  var x = s.toLowerCase();
  x = x
      .replaceAll(RegExp('[áàä]'), 'a')
      .replaceAll(RegExp('[éèë]'), 'e')
      .replaceAll(RegExp('[íìï]'), 'i')
      .replaceAll(RegExp('[óòö]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u')
      .replaceAll('ñ', 'n');
  return x;
}

/// Para evitar records (Dart 3), usamos clase simple.
class _ScoredPOI {
  final _LocalPOI poi;
  final int score;
  const _ScoredPOI(this.poi, this.score);
}

List<PrediccionLugar> _filterLocalPOIs(String q) {
  final nq = _norm(q.trim());
  if (nq.isEmpty) return const [];

  final scored = <_ScoredPOI>[];

  int scoreFor(_LocalPOI p) {
    final name = _norm(p.name);
    final addr = _norm(p.address);
    final aliases = p.aliases.map(_norm).toList();

    // Scoring simple: prefijo > contiene > alias
    if (name.startsWith(nq) ||
        addr.startsWith(nq) ||
        p.id.toLowerCase().startsWith(nq)) {
      return 3;
    }
    if (name.contains(nq) ||
        addr.contains(nq) ||
        p.id.toLowerCase().contains(nq)) {
      return 2;
    }
    if (aliases.any((a) => a.startsWith(nq))) return 2;
    if (aliases.any((a) => a.contains(nq))) return 1;
    return 0;
  }

  for (final p in _ALL_LOCAL) {
    final s = scoreFor(p);
    if (s > 0) scored.add(_ScoredPOI(p, s));
  }

  scored.sort((a, b) => b.score.compareTo(a.score));

  return scored
      .map(
        (e) => PrediccionLugar(
          placeId: 'local:poi:${e.poi.id}',
          primary: e.poi.name,
          secondary: e.poi.address,
        ),
      )
      .toList(growable: false);
}

/// Chips rápidas para UI (top lugares)
List<PrediccionLugar> _quickChips() {
  final base = <_LocalPOI>[
    // aeropuertos + malls + zonas + 1–2 hoteles
    ..._AIRPORTS_DO.take(4),
    _POIS_DO.firstWhere((p) => p.id == 'MALL_BM', orElse: () => _POIS_DO.first),
    _POIS_DO.firstWhere((p) => p.id == 'MALL_AG', orElse: () => _POIS_DO.first),
    _POIS_DO.firstWhere((p) => p.id == 'ZN_COL', orElse: () => _POIS_DO.first),
    _POIS_DO.firstWhere((p) => p.id == 'HTL_EMB', orElse: () => _POIS_DO.first),
  ];
  return base
      .map(
        (p) => PrediccionLugar(
          placeId: 'local:poi:${p.id}',
          primary: p.name,
          secondary: p.address,
        ),
      )
      .toList(growable: false);
}

/// ---------- Tipo auxiliar para formateo RD (TOP-LEVEL, no dentro de la clase) ----------
class _FormattedRD {
  final String titulo;
  final String? resto;
  const _FormattedRD(this.titulo, this.resto);
}

/// --------------------------------------------------------------------------

class LugaresService {
  LugaresService._();
  static final LugaresService instance = LugaresService._();
  bool get _placesEnabled => kGooglePlacesApiKey.trim().isNotEmpty;

  // Exponer chips rápidas
  static List<PrediccionLugar> get sugerenciasRapidasDO => _quickChips();

  Future<List<PrediccionLugar>> autocompletar(
    String query, {
    String? country, // 'DO'
    double? biasLat,
    double? biasLon,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    // 1) Local smart matching (aeropuertos + hoteles + malls + zonas)
    final locals = _filterLocalPOIs(q);

    // Sin API key: locals + eco para geocoding
    if (!_placesEnabled) {
      final merged = <PrediccionLugar>[
        ...locals,
        PrediccionLugar(placeId: q, primary: q, secondary: country),
      ];
      final seen = <String>{};
      return merged
          .where((p) {
            final k = p.primary.toLowerCase();
            if (seen.contains(k)) return false;
            seen.add(k);
            return true;
          })
          .toList(growable: false);
    }

    // 2) Google Places Autocomplete
    try {
      final params = <String, String>{
        'input': q,
        'key': kGooglePlacesApiKey,
        'language': 'es',
        // 'types': 'establishment', // si quieres priorizar negocios
      };
      if (country != null && country.trim().isNotEmpty) {
        params['components'] = 'country:${country.trim()}';
      }
      if (biasLat != null && biasLon != null) {
        params['location'] =
            '${biasLat.toStringAsFixed(6)},${biasLon.toStringAsFixed(6)}';
        params['radius'] = '50000';
      }

      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        params,
      );
      final json = await _getJson(uri);
      final remotes = <PrediccionLugar>[];

      if (json != null) {
        final status = (json['status'] ?? '').toString();
        if (status == 'OK' || status == 'ZERO_RESULTS') {
          final List list = (json['predictions'] as List?) ?? const [];
          for (final e in list) {
            final m = e as Map<String, dynamic>;
            final placeId = (m['place_id'] ?? '').toString();
            final desc = (m['description'] ?? '').toString();

            String primary = desc;
            String? secondary;
            final sf = m['structured_formatting'] as Map<String, dynamic>?;
            final mainText = sf?['main_text']?.toString();
            final secText = sf?['secondary_text']?.toString();
            if (mainText != null && mainText.trim().isNotEmpty) {
              primary = mainText.trim();
              secondary = (secText ?? '').trim().isEmpty
                  ? null
                  : secText!.trim();
            } else {
              final parts = desc.split(',').map((s) => s.trim()).toList();
              if (parts.length > 1) {
                primary = parts.first;
                secondary = parts.sublist(1).join(', ');
              }
            }
            remotes.add(
              PrediccionLugar(
                placeId: placeId.isNotEmpty ? placeId : desc,
                primary: primary.isNotEmpty ? primary : desc,
                secondary: secondary,
              ),
            );
          }
        }
      }

      // 3) Merge locales + remotos (sin duplicados)
      final out = <PrediccionLugar>[];
      final seen = <String>{};
      for (final p in [...locals, ...remotes]) {
        final k = p.primary.toLowerCase();
        if (seen.contains(k)) continue;
        seen.add(k);
        out.add(p);
      }

      // Añadir eco al final para geocoding si el usuario escribe algo muy libre
      if (out.isEmpty || _norm(q).length >= 2) {
        out.add(PrediccionLugar(placeId: q, primary: q, secondary: country));
      }

      return out;
    } catch (_) {
      return [
        ...locals,
        PrediccionLugar(placeId: q, primary: q, secondary: country),
      ];
    }
  }

  Future<DetalleLugar?> detalle(String placeId) async {
    final pid = placeId.trim();
    if (pid.isEmpty) return null;

    // POI local sin red
    if (pid.startsWith('local:poi:')) {
      final code = pid.split(':').last;
      final found = _ALL_LOCAL.where((p) => p.id == code);
      if (found.isNotEmpty) {
        final p = found.first;
        return DetalleLugar(
          placeId: pid,
          name: p.name,
          address: p.address,
          lat: p.lat,
          lon: p.lon,
        );
      }
    }

    // Sin Places -> geocoding
    if (!_placesEnabled) {
      try {
        final locs = await geocoding.locationFromAddress(pid);
        if (locs.isEmpty) return null;
        final loc = locs.first;

        final marks = await geocoding.placemarkFromCoordinates(
          loc.latitude,
          loc.longitude,
        );

        String name = pid;
        String? addr;
        if (marks.isNotEmpty) {
          final fm = _formatearPlacemarkRD(
            marks.first,
          ); // devuelve _FormattedRD
          name = fm.titulo;
          addr = fm.resto;
        }

        return DetalleLugar(
          placeId: pid,
          name: name,
          address: addr,
          lat: loc.latitude,
          lon: loc.longitude,
        );
      } catch (_) {
        return null;
      }
    }

    // Place Details (con address_components)
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        <String, String>{
          'place_id': pid,
          'fields': 'name,formatted_address,geometry,address_components',
          'language': 'es',
          'key': kGooglePlacesApiKey,
        },
      );
      final json = await _getJson(uri);
      if (json == null) return null;
      final status = (json['status'] ?? '').toString();
      if (status != 'OK') return null;

      final r = json['result'] as Map<String, dynamic>?;
      if (r == null) return null;

      final comps =
          (r['address_components'] as List?)?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];

      String? get(String type) {
        for (final c in comps) {
          final t = (c['types'] as List?)?.cast<String>() ?? const <String>[];
          if (t.contains(type)) return (c['long_name'] ?? '').toString();
        }
        return null;
      }

      final streetNumber = get('street_number');
      final route = get('route');
      final neighborhood = get('neighborhood');
      final sublocality = get('sublocality');
      final locality = get('locality') ?? get('administrative_area_level_2');
      final adminArea = get('administrative_area_level_1');
      final country = get('country');

      final street = [
        if ((route ?? '').trim().isNotEmpty) route!.trim(),
        if ((streetNumber ?? '').trim().isNotEmpty) '#${streetNumber!.trim()}',
      ].join(' ').trim();

      final sector = (neighborhood ?? sublocality ?? '').trim();

      final niceAddress = [
        if (sector.isNotEmpty) sector,
        if ((locality ?? '').trim().isNotEmpty) locality!.trim(),
        if ((adminArea ?? '').trim().isNotEmpty) adminArea!.trim(),
        if ((country ?? '').trim().isNotEmpty) country!.trim(),
      ].join(', ');

      final geometry = r['geometry'] as Map<String, dynamic>?;
      final loc = geometry?['location'] as Map<String, dynamic>?;
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lon = (loc?['lng'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;

      String name = (r['name'] ?? '').toString().trim();
      if (name.isEmpty || name == route) {
        name = street.isNotEmpty
            ? street
            : (sector.isNotEmpty ? sector : (locality ?? '').trim());
      }

      final formatted = (r['formatted_address'] ?? '').toString().trim();
      final address = niceAddress.isNotEmpty
          ? niceAddress
          : (formatted.isNotEmpty ? formatted : null);

      return DetalleLugar(
        placeId: pid,
        name: name,
        address: address,
        lat: lat,
        lon: lon,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------- helpers ----------
  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  /// Formato RD a partir de un Placemark
  _FormattedRD _formatearPlacemarkRD(geocoding.Placemark p) {
    final calle = [
      (p.thoroughfare ?? '').trim(),
      (p.subThoroughfare ?? '').trim(),
    ].where((s) => s.isNotEmpty).join(' ').trim();

    final sector = (p.subLocality ?? '').trim();
    final ciudad =
        ((p.locality ?? '').trim().isNotEmpty
                ? p.locality!.trim()
                : (p.subAdministrativeArea ?? '').trim())
            .trim();
    final prov = (p.administrativeArea ?? '').trim();
    final pais = (p.country ?? '').trim();

    String titulo;
    if (calle.isNotEmpty) {
      titulo = calle;
    } else if (sector.isNotEmpty && ciudad.isNotEmpty) {
      titulo = '$sector, $ciudad';
    } else if (ciudad.isNotEmpty) {
      titulo = ciudad;
    } else {
      titulo = [prov, pais].where((s) => s.isNotEmpty).join(', ');
    }

    final resto = [
      if (sector.isNotEmpty && titulo != sector) sector,
      if (ciudad.isNotEmpty && !titulo.contains(ciudad)) ciudad,
      if (prov.isNotEmpty) prov,
      if (pais.isNotEmpty) pais,
    ].where((s) => s.isNotEmpty).join(', ');

    return _FormattedRD(titulo, resto.isNotEmpty ? resto : null);
  }
}
