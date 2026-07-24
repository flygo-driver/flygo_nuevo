// lib/servicios/lugares_service.dart
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:http/http.dart' as http;
import 'package:flygo_nuevo/keys.dart' as app_keys; // key centralizada
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

Map<String, dynamic>? _asStringKeyedMap(dynamic value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return null;
}

class PrediccionLugar {
  final String placeId;
  final String primary;
  final String? secondary;

  /// Distancia (metros) al punto de origen/sesgo cuando Google la provee.
  /// Se usa para ordenar por cercanía (estilo Uber). Null si no aplica.
  final int? distanceMeters;

  const PrediccionLugar(
      {required this.placeId,
      required this.primary,
      this.secondary,
      this.distanceMeters});
}

class DetalleLugar {
  final String placeId;
  final String name;
  final String? address;
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
    if (a.isEmpty) {
      return n;
    }
    if (a.toLowerCase().contains(n.toLowerCase())) {
      return a;
    }
    return '$n, $a';
  }
}

/// Búsqueda reciente compartida en toda la app (mismo prefs que [CampoLugarAutocomplete]).
class RecienteLugar {
  const RecienteLugar({
    required this.label,
    required this.placeId,
    this.lat,
    this.lon,
    this.name,
  });

  final String label;
  final String placeId;
  final double? lat;
  final double? lon;
  final String? name;

  bool get tieneCoordenadas =>
      lat != null && lon != null && lat!.abs() > 1e-6 && lon!.abs() > 1e-6;
}

// ---------------- POIs locales (RD) con aliases ----------------
class _LocalPOI {
  final String id;
  final String name;
  final String address;
  final double lat;
  final double lon;
  final List<String> aliases;
  const _LocalPOI(this.id, this.name, this.address, this.lat, this.lon,
      {this.aliases = const []});
}

const List<_LocalPOI> _AIRPORTS_DO = [
  _LocalPOI('SDQ', 'Aeropuerto Internacional Las Américas (SDQ)',
      'Boca Chica, Santo Domingo', 18.4297, -69.6689,
      aliases: [
        'ae',
        'aer',
        'aero',
        'aerop',
        'aeropuerto',
        'las americas',
        'las américas',
        'sdq'
      ]),
  _LocalPOI('PUJ', 'Aeropuerto Internacional de Punta Cana (PUJ)',
      'Punta Cana, La Altagracia', 18.5674, -68.3634, aliases: [
    'ae',
    'aer',
    'aero',
    'aerop',
    'aeropuerto',
    'punta',
    'aeropuerto punta',
    'puj'
  ]),
  _LocalPOI('STI', 'Aeropuerto Internacional del Cibao (STI)',
      'Santiago de los Caballeros', 19.4061, -70.6047,
      aliases: ['ae', 'aer', 'aero', 'aerop', 'aeropuerto', 'cibao', 'sti']),
  _LocalPOI('POP', 'Aeropuerto Internacional Gregorio Luperón (POP)',
      'Puerto Plata', 19.7579, -70.5697, aliases: [
    'ae',
    'aer',
    'aero',
    'aerop',
    'aeropuerto',
    'puerto plata',
    'pop'
  ]),
  _LocalPOI('JBQ', 'Aeropuerto Internacional La Isabela (JBQ)',
      'Santo Domingo (Higüero)', 18.5725, -69.9856, aliases: [
    'ae',
    'aer',
    'aero',
    'aerop',
    'aeropuerto',
    'higuero',
    'la isabela',
    'jbq'
  ]),
  _LocalPOI('LRM', 'Aeropuerto Internacional La Romana (LRM)', 'La Romana',
      18.4510, -68.9117, aliases: [
    'ae',
    'aer',
    'aero',
    'aerop',
    'aeropuerto',
    'la romana aeropuerto',
    'lrm'
  ]),
  _LocalPOI('AZS', 'Aeropuerto Internacional El Catey (AZS)', 'Samaná', 19.2690,
      -69.7370, aliases: [
    'ae',
    'aer',
    'aero',
    'aerop',
    'aeropuerto',
    'catey',
    'samana aeropuerto',
    'azs'
  ]),
];

const List<_LocalPOI> _POIS_DO = [
  _LocalPOI('HTL_EMB', 'Hotel El Embajador', 'Piantini, Santo Domingo', 18.4641,
      -69.9428,
      aliases: ['emb', 'embajador', 'hotel emb']),
  _LocalPOI('HTL_JAR', 'Renaissance Jaragua Hotel', 'Malecón, Santo Domingo',
      18.4636, -69.8957,
      aliases: ['jar', 'jaragua']),
  _LocalPOI('HTL_JWM', 'JW Marriott Santo Domingo', 'BlueMall, Piantini',
      18.4727, -69.9407,
      aliases: ['jw', 'jw marriott', 'marriot', 'marr']),
  _LocalPOI('HTL_BBV', 'Barceló Bávaro Palace', 'Bávaro, Punta Cana', 18.6576,
      -68.4015,
      aliases: ['barcelo', 'bavaro', 'bbv']),
  _LocalPOI('HTL_HRH', 'Hard Rock Hotel & Casino Punta Cana',
      'Macao, Punta Cana', 18.7282, -68.4687,
      aliases: ['hard', 'hard rock', 'hrh']),
  _LocalPOI('MALL_BM', 'BlueMall Santo Domingo', 'Piantini, Santo Domingo',
      18.4724, -69.9402,
      aliases: ['blue', 'bluemall']),
  _LocalPOI(
      'MALL_AG', 'Ágora Mall', 'Serrallés, Santo Domingo', 18.4878, -69.9365,
      aliases: ['ago', 'agora']),
  _LocalPOI('MALL_SA', 'Sambil Santo Domingo', 'Los Jardines, Santo Domingo',
      18.4870, -69.9218,
      aliases: ['sam', 'sambil']),
  _LocalPOI('MALL_BMPC', 'BlueMall Punta Cana', 'Punta Cana', 18.5670, -68.4033,
      aliases: ['blue', 'bluemall']),
  _LocalPOI('ZN_COL', 'Zona Colonial', 'Santo Domingo', 18.4764, -69.8833,
      aliases: ['zona', 'colonial', 'zona col']),
  _LocalPOI(
      'MLC_SD', 'Malecón de Santo Domingo', 'Santo Domingo', 18.4605, -69.9048,
      aliases: ['male', 'malecon']),
  _LocalPOI('UNI_UASD', 'UASD - Universidad Autónoma de Santo Domingo',
      'Gazcue, Santo Domingo', 18.4632, -69.9110,
      aliases: ['uasd', 'universidad uasd']),
  _LocalPOI('HSP_CED', 'Centro de Diagnóstico CEDIMAT', 'Paseo de la Salud, SD',
      18.4707, -69.9537,
      aliases: ['ced', 'cedimat']),
];

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

class _ScoredPOI {
  final _LocalPOI poi;
  final int score;
  const _ScoredPOI(this.poi, this.score);
}

List<PrediccionLugar> _filterLocalPOIs(String q) {
  final nq = _norm(q.trim());
  if (nq.isEmpty) {
    return const [];
  }
  final scored = <_ScoredPOI>[];

  int scoreFor(_LocalPOI p) {
    final name = _norm(p.name);
    final addr = _norm(p.address);
    final aliases = p.aliases.map(_norm).toList();
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
    if (aliases.any((a) => a.startsWith(nq))) {
      return 2;
    }
    if (aliases.any((a) => a.contains(nq))) {
      return 1;
    }
    return 0;
  }

  for (final p in _ALL_LOCAL) {
    final s = scoreFor(p);
    if (s > 0) {
      scored.add(_ScoredPOI(p, s));
    }
  }
  scored.sort((a, b) => b.score.compareTo(a.score));

  return scored
      .map((e) => PrediccionLugar(
            placeId: 'local:poi:${e.poi.id}',
            primary: e.poi.name,
            secondary: e.poi.address,
          ))
      .toList(growable: false);
}

List<PrediccionLugar> _quickChips() {
  final base = <_LocalPOI>[
    ..._AIRPORTS_DO.take(4),
    _POIS_DO.firstWhere((p) => p.id == 'MALL_BM', orElse: () => _POIS_DO.first),
    _POIS_DO.firstWhere((p) => p.id == 'MALL_AG', orElse: () => _POIS_DO.first),
    _POIS_DO.firstWhere((p) => p.id == 'ZN_COL', orElse: () => _POIS_DO.first),
    _POIS_DO.firstWhere((p) => p.id == 'HTL_EMB', orElse: () => _POIS_DO.first),
  ];
  return base
      .map((p) => PrediccionLugar(
            placeId: 'local:poi:${p.id}',
            primary: p.name,
            secondary: p.address,
          ))
      .toList(growable: false);
}

class _FormattedRD {
  final String titulo;
  final String? resto;
  const _FormattedRD(this.titulo, this.resto);
}

class LugaresService {
  LugaresService._();
  static final LugaresService instance = LugaresService._();

  static const String prefsRecientesGlobal = 'lugares_recientes_v2';
  static const String prefsRecientesLegacy = 'lugares_recientes';
  static const int maxRecientesGlobal = 12;

  final Uuid _uuid = const Uuid();
  String? _sessionToken;

  bool get _placesEnabled => app_keys.kGooglePlacesApiKey.trim().isNotEmpty;

  static List<PrediccionLugar> get sugerenciasRapidasDO => _quickChips();

  void _ensureSessionToken() {
    _sessionToken ??= _uuid.v4();
  }

  /// Cierra sesión de facturación Places tras elegir un lugar (Place Details).
  void cerrarSesionPlaces() {
    _sessionToken = null;
  }

  /// Recientes globales (Mis pagos, pool, paradas múltiples, programar viaje…).
  Future<List<RecienteLugar>> cargarRecientes() async {
    final prefs = await SharedPreferences.getInstance();
    final rawV2 = prefs.getString(prefsRecientesGlobal);
    final list = <RecienteLugar>[];
    if (rawV2 != null && rawV2.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawV2);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is! Map) continue;
            final m = Map<String, dynamic>.from(e);
            final l = (m['l'] ?? m['label'] ?? '').toString().trim();
            if (l.isEmpty) continue;
            final p = (m['p'] ?? m['placeId'] ?? '').toString().trim();
            final lat = (m['lat'] as num?)?.toDouble();
            final lon = (m['lon'] as num?)?.toDouble();
            final name = (m['n'] ?? m['name'] ?? '').toString().trim();
            list.add(
              RecienteLugar(
                label: l,
                placeId: p,
                lat: lat,
                lon: lon,
                name: name.isNotEmpty ? name : null,
              ),
            );
          }
        }
      } catch (_) {}
    }
    if (list.isEmpty) {
      final legacy = prefs.getStringList(prefsRecientesLegacy) ?? [];
      for (final l in legacy) {
        final t = l.trim();
        if (t.isNotEmpty) list.add(RecienteLugar(label: t, placeId: ''));
      }
    }
    if (list.length > maxRecientesGlobal) {
      return list.sublist(0, maxRecientesGlobal);
    }
    return list;
  }

  Future<void> guardarReciente(DetalleLugar det) async {
    final prefs = await SharedPreferences.getInstance();
    var list = await cargarRecientes();
    list = List<RecienteLugar>.from(list);
    list.removeWhere((e) {
      if (det.placeId.isNotEmpty && e.placeId == det.placeId) return true;
      return _norm(e.label) == _norm(det.displayLabel);
    });
    list.insert(
      0,
      RecienteLugar(
        label: det.displayLabel,
        placeId: det.placeId,
        lat: det.lat,
        lon: det.lon,
        name: det.name,
      ),
    );
    if (list.length > maxRecientesGlobal) {
      list = list.sublist(0, maxRecientesGlobal);
    }
    final encoded = jsonEncode(
      list
          .map(
            (e) => {
              'l': e.label,
              'p': e.placeId,
              if (e.lat != null) 'lat': e.lat,
              if (e.lon != null) 'lon': e.lon,
              if (e.name != null && e.name!.trim().isNotEmpty) 'n': e.name,
            },
          )
          .toList(),
    );
    await prefs.setString(prefsRecientesGlobal, encoded);
    await prefs.remove(prefsRecientesLegacy);
  }

  /// Ordena sugerencias: prefijo > contiene > secundario (misma lógica en toda la app).
  List<PrediccionLugar> rankearPredicciones(
    List<PrediccionLugar> preds,
    String query,
  ) {
    final nq = _norm(query.trim());
    if (nq.isEmpty) return preds;

    final scored = preds.map((p) {
      final primary = _norm(p.primary);
      final secondary = _norm(p.secondary ?? '');
      int score = 0;
      if (p.placeId.startsWith('local:poi:')) score += 8;
      if (primary.startsWith(nq)) score += 120;
      if (secondary.isNotEmpty && secondary.startsWith(nq)) score += 80;
      if (secondary.contains(nq)) score += 40;
      if (primary.contains(nq)) score += 20;
      // Cercanía (estilo Uber): entre coincidencias parecidas, lo más cerca sube.
      score += _proximityBoost(p.distanceMeters);
      return MapEntry(p, score);
    }).toList();

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList(growable: false);
  }

  /// Bonus por cercanía usando `distance_meters` de Google (si viene).
  /// Es secundario a la coincidencia de texto: solo desempata resultados
  /// parecidos priorizando lo más próximo al usuario (como Uber).
  int _proximityBoost(int? meters) {
    if (meters == null) return 0;
    if (meters <= 1500) return 30;
    if (meters <= 4000) return 24;
    if (meters <= 10000) return 16;
    if (meters <= 25000) return 9;
    if (meters <= 60000) return 4;
    return 0;
  }

  // Cuando el usuario escribe una dirección "larga" tipo:
  // "calle 15 sector villa maria numero 45 santo domingo..."
  // Google puede devolver ZERO_RESULTS para ese input completo.
  // Generamos variantes más cortas para aumentar tasa de acierto.
  List<String> _buildAddressVariants(String input) {
    final q = input.trim();
    if (q.isEmpty) return const <String>[];

    final lower = q.toLowerCase();

    final calleMatch = RegExp(
      r'\b(?:calle|av\.|avenida|av)\s*#?\s*(\d{1,6})\b',
      caseSensitive: false,
    ).firstMatch(lower);

    final numeroMatch = RegExp(
      r'\b(?:n[uú]mero|numero|#)\s*#?\s*(\d{1,6})\b',
      caseSensitive: false,
    ).firstMatch(lower);

    final sectorMatch = RegExp(
      r'\bsector\s+([a-z0-9áéíóúñ\s-]{2,50}?)(?=\s+(?:n[uú]mero|numero|#|calle|av\.|avenida|av|santo\s+domingo|sdq|sd)\b|\s*,|$)',
      caseSensitive: false,
    ).firstMatch(lower);

    final hasSantoDomingo =
        RegExp(r'\bsanto\s+domingo\b|\bsdq\b|\bsd\b', caseSensitive: false)
            .hasMatch(lower);

    final calleNum = calleMatch?.group(1);
    final numeroNum = numeroMatch?.group(1);
    final sector = sectorMatch?.group(1)?.trim();

    final variants = <String>[q];

    if (sector != null && sector.isNotEmpty) {
      variants.add('sector $sector');
    }

    if (calleNum != null && sector != null && sector.isNotEmpty) {
      final v = 'calle $calleNum sector $sector';
      if (v.toLowerCase() != q.toLowerCase()) variants.add(v);
    }

    if (calleNum != null && numeroNum != null && hasSantoDomingo) {
      final v = 'calle $calleNum numero $numeroNum santo domingo';
      if (v.toLowerCase() != q.toLowerCase()) variants.add(v);
    } else if (calleNum != null && numeroNum != null) {
      final v = 'calle $calleNum numero $numeroNum';
      if (v.toLowerCase() != q.toLowerCase()) variants.add(v);
    }

    // Quitar duplicados preservando orden
    final seen = <String>{};
    final out = <String>[];
    for (final v in variants) {
      final k = v.toLowerCase();
      if (seen.contains(k)) continue;
      seen.add(k);
      out.add(v);
    }

    // Variantes por palabras (referencias parciales de dirección).
    final words = q
        .split(RegExp(r'[\s,;]+'))
        .map((w) => w.trim())
        .where((w) => w.length >= 2)
        .toList();
    if (words.length >= 2) {
      final tail2 = words.sublist(words.length - 2).join(' ');
      if (tail2.length >= 3) out.add(tail2);
      if (words.length >= 3) {
        final tail3 = words.sublist(words.length - 3).join(' ');
        if (tail3.length >= 4) out.add(tail3);
      }
      final first = words.first;
      if (first.length >= 3 && first.toLowerCase() != q.toLowerCase()) {
        out.add(first);
      }
    }
    if (words.length == 1 && words.first.length >= 3) {
      out.add(words.first);
    }

    // Partes separadas por coma (barrio, ciudad…).
    for (final part in q.split(',')) {
      final t = part.trim();
      if (t.length >= 3 && t.toLowerCase() != q.toLowerCase()) {
        out.add(t);
      }
    }

    final seen2 = <String>{};
    final deduped = <String>[];
    for (final v in out) {
      final k = v.toLowerCase();
      if (seen2.contains(k)) continue;
      seen2.add(k);
      deduped.add(v);
    }
    return deduped;
  }

  Future<List<PrediccionLugar>> autocompletar(String query,
      {String? country, double? biasLat, double? biasLon}) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const [];
    }

    final locals = _filterLocalPOIs(q);

    if (!_placesEnabled) {
      final merged = <PrediccionLugar>[
        ...locals,
        PrediccionLugar(placeId: q, primary: q, secondary: country),
      ];
      final seen = <String>{};
      return merged.where((p) {
        final k = p.primary.toLowerCase();
        if (seen.contains(k)) {
          return false;
        }
        seen.add(k);
        return true;
      }).toList(growable: false);
    }

    try {
      _ensureSessionToken();
      // Sin `types`: cobertura amplia (sectores, barrios, POI, calles), como buscador Google.
      final baseParams = <String, String>{
        'key': app_keys.kGooglePlacesApiKey,
        'language': 'es',
        'sessiontoken': _sessionToken!,
      };
      if (country != null && country.trim().isNotEmpty) {
        baseParams['components'] = 'country:${country.trim().toLowerCase()}';
      }
      if (biasLat != null && biasLon != null) {
        baseParams['location'] =
            '${biasLat.toStringAsFixed(6)},${biasLon.toStringAsFixed(6)}';
        baseParams['radius'] = '200000';
        baseParams['origin'] =
            '${biasLat.toStringAsFixed(6)},${biasLon.toStringAsFixed(6)}';
      }

      final variants = _buildAddressVariants(q);
      final expanded = <String>{...variants};
      final cq = q.trim();
      if (country != null &&
          country.trim().isNotEmpty &&
          cq.isNotEmpty &&
          !RegExp(
            r'república|republica|dominicana|dominican|\b(rd|do)\b',
            caseSensitive: false,
          ).hasMatch(cq)) {
        expanded.add('$cq, República Dominicana');
        expanded.add('$cq, Dominican Republic');
      }

      final remotes = <PrediccionLugar>[];
      final seenIds = <String>{};

      void parseAndAdd(Map<String, dynamic>? json) {
        if (json == null) return;
        final status = (json['status'] ?? '').toString();
        if (status != 'OK' && status != 'ZERO_RESULTS') return;
        final List list = (json['predictions'] as List?) ?? const [];
        for (final e in list) {
          final m = _asStringKeyedMap(e);
          if (m == null) continue;
          final placeId = (m['place_id'] ?? '').toString();
          if (placeId.isEmpty) continue;
          if (!seenIds.add(placeId)) continue;

          final desc = (m['description'] ?? '').toString();
          final int? distanceMeters = (m['distance_meters'] as num?)?.round();
          String primary = desc;
          String? secondary;
          final sf = _asStringKeyedMap(m['structured_formatting']);
          final mainText = sf?['main_text']?.toString();
          final secText = sf?['secondary_text']?.toString();
          if ((mainText ?? '').trim().isNotEmpty) {
            primary = mainText!.trim();
            secondary = (secText ?? '').trim().isEmpty ? null : secText!.trim();
          } else {
            final parts = desc.split(',').map((s) => s.trim()).toList();
            if (parts.length > 1) {
              primary = parts.first;
              secondary = parts.sublist(1).join(', ');
            }
          }

          remotes.add(PrediccionLugar(
            placeId: placeId,
            primary: primary.isNotEmpty ? primary : desc,
            secondary: secondary,
            distanceMeters: distanceMeters,
          ));
        }
      }

      Future<void> fetchVariant(String v) async {
        if (v.trim().isEmpty || remotes.length >= 30) return;
        final params = <String, String>{...baseParams, 'input': v.trim()};
        Map<String, dynamic>? json;
        if (kIsWeb) {
          json = await _placesAutocompleteViaFunctions(
            input: v.trim(),
            country: country,
            sessiontoken: _sessionToken,
            biasLat: biasLat,
            biasLon: biasLon,
          );
        } else {
          final uri = Uri.https(
            'maps.googleapis.com',
            '/maps/api/place/autocomplete/json',
            params,
          );
          json = await _getJson(uri);
        }
        parseAndAdd(json);
      }

      final variantList = expanded.toList();
      // Consulta principal + variantes en paralelo (más resultados al escribir).
      final batch1 = variantList.take(5).map(fetchVariant).toList();
      await Future.wait(batch1);
      if (remotes.length < 12 && variantList.length > 5) {
        await Future.wait(variantList.skip(5).take(5).map(fetchVariant));
      }
      if (remotes.length < 6 && variantList.length > 10) {
        for (final v in variantList.skip(10)) {
          await fetchVariant(v);
          if (remotes.length >= 12) break;
        }
      }

      final mergedRemote = rankearPredicciones(remotes, cq);
      final out = <PrediccionLugar>[];
      final seenPrimary = <String>{};
      for (final p in [...locals, ...mergedRemote]) {
        final k = '${p.placeId}|${_norm(p.primary)}';
        if (seenPrimary.contains(k)) continue;
        seenPrimary.add(k);
        out.add(p);
      }
      if (remotes.isEmpty && cq.length >= 2) {
        out.add(PrediccionLugar(placeId: q, primary: q, secondary: country));
      }
      return rankearPredicciones(out, cq);
    } catch (_) {
      return [
        ...locals,
        PrediccionLugar(placeId: q, primary: q, secondary: country)
      ];
    }
  }

  /// Resuelve coordenadas a partir de una sugerencia del autocomplete (texto + placeId).
  Future<DetalleLugar?> detalleDesdePrediccion(PrediccionLugar p) async {
    if (_esPrediccionReciente(p)) {
      final desdeCache = await detalleDesdeReciente(p);
      if (desdeCache != null) return desdeCache;
    }
    return detalle(p.placeId, hintDireccion: _hintDesdePrediccion(p));
  }

  bool _esPrediccionReciente(PrediccionLugar p) =>
      p.secondary == 'Reciente' || p.placeId.startsWith('recent:');

  /// Reciente con coords guardadas al elegir el lugar (evita geocodificar de nuevo).
  Future<DetalleLugar?> detalleDesdeReciente(PrediccionLugar p) async {
    final list = await cargarRecientes();
    RecienteLugar? match;
    final pid = p.placeId.trim();
    final primary = p.primary.trim();
    for (final e in list) {
      if (pid.isNotEmpty && e.placeId.isNotEmpty && e.placeId == pid) {
        match = e;
        break;
      }
      if (pid.startsWith('recent:') &&
          _norm(e.label) == _norm(pid.substring('recent:'.length))) {
        match = e;
        break;
      }
      if (_norm(e.label) == _norm(primary)) {
        match = e;
        break;
      }
    }
    if (match == null) return null;
    if (match.tieneCoordenadas) {
      final nombre = (match.name ?? match.label).trim();
      return DetalleLugar(
        placeId: match.placeId.isNotEmpty
            ? match.placeId
            : 'recent:${match.label}',
        name: nombre.isNotEmpty ? nombre : match.label,
        address: match.label,
        lat: match.lat!,
        lon: match.lon!,
      );
    }
    if (match.placeId.isNotEmpty && _esPlaceIdGoogle(match.placeId)) {
      return _detalleGoogle(match.placeId);
    }
    return null;
  }

  String _hintDesdePrediccion(PrediccionLugar p) {
    final pri = p.primary.trim();
    final sec = (p.secondary ?? '').trim();
    if (sec.isEmpty ||
        sec == 'Reciente' ||
        sec == 'Sugerencia por voz' ||
        sec == 'DO' ||
        sec == 'República Dominicana') {
      return pri;
    }
    if (sec.toLowerCase().contains(pri.toLowerCase())) return sec;
    return '$pri, $sec';
  }

  bool _esPlaceIdGoogle(String pid) {
    if (pid.startsWith('local:poi:') ||
        pid.startsWith('geocoded:') ||
        pid.startsWith('recent:') ||
        pid == '__rai_inteligente__') {
      return false;
    }
    if (pid.contains(' ') || pid.contains(',')) return false;
    return pid.length >= 10;
  }

  Future<DetalleLugar?> _geocodeComoDetalle(
    String texto, {
    String? placeId,
  }) async {
    final base = texto.trim();
    if (base.length < 2) return null;

    // En web el plugin geocoding no funciona: usamos Places vía Functions.
    if (kIsWeb) {
      final json = await _placesFindFromTextViaFunctions(
        input: base,
        country: 'do',
      );
      if (json != null && (json['status'] ?? '').toString() == 'OK') {
        final candidates = (json['candidates'] as List?) ?? const [];
        if (candidates.isNotEmpty) {
          final c = _asStringKeyedMap(candidates.first);
          if (c != null) {
            final geometry = _asStringKeyedMap(c['geometry']);
            final loc = _asStringKeyedMap(geometry?['location']);
            final lat = (loc?['lat'] as num?)?.toDouble();
            final lon = (loc?['lng'] as num?)?.toDouble();
            if (lat != null && lon != null) {
              final name = (c['name'] ?? '').toString().trim();
              final formatted =
                  (c['formatted_address'] ?? '').toString().trim();
              final pid = (c['place_id'] ?? placeId ?? 'geocoded:${_norm(base)}')
                  .toString();
              return DetalleLugar(
                placeId: pid,
                name: name.isNotEmpty ? name : (formatted.isNotEmpty ? formatted : base),
                address: formatted.isNotEmpty ? formatted : base,
                lat: lat,
                lon: lon,
              );
            }
          }
        }
      }
      return null;
    }

    final intentos = <String>{
      base,
      '$base, República Dominicana',
      '$base, Dominican Republic',
    }.where((e) => e.trim().length >= 3).toList();

    for (final q in intentos) {
      try {
        final locs = await geocoding.locationFromAddress(q);
        if (locs.isEmpty) continue;
        final loc = locs.first;
        if (loc.latitude.abs() < 0.000001 && loc.longitude.abs() < 0.000001) {
          continue;
        }

        String name = base;
        String? addr;
        try {
          final marks = await geocoding.placemarkFromCoordinates(
            loc.latitude,
            loc.longitude,
          );
          if (marks.isNotEmpty) {
            final fm = _formatearPlacemarkRD(marks.first);
            name = fm.titulo;
            addr = fm.resto;
          }
        } catch (_) {}

        return DetalleLugar(
          placeId: placeId ?? 'geocoded:${_norm(base)}',
          name: name,
          address: addr ?? q,
          lat: loc.latitude,
          lon: loc.longitude,
        );
      } catch (_) {}
    }
    return null;
  }

  Future<DetalleLugar?> _detalleGoogle(String pid) async {
    try {
      Map<String, dynamic>? json;
      if (kIsWeb) {
        json = await _placesDetailsViaFunctions(
          placeId: pid,
          sessiontoken: _sessionToken,
        );
      } else {
        final params = <String, String>{
          'place_id': pid,
          'fields': 'name,formatted_address,geometry,address_components',
          'language': 'es',
          'key': app_keys.kGooglePlacesApiKey,
        };
        if (_sessionToken != null && _sessionToken!.trim().isNotEmpty) {
          params['sessiontoken'] = _sessionToken!;
        }
        final uri = Uri.https(
          'maps.googleapis.com',
          '/maps/api/place/details/json',
          params,
        );
        json = await _getJson(uri);
      }
      if (json == null) return null;
      final status = (json['status'] ?? '').toString();
      if (status != 'OK') return null;

      final r = _asStringKeyedMap(json['result']);
      if (r == null) return null;

      final geometry = _asStringKeyedMap(r['geometry']);
      final loc = _asStringKeyedMap(geometry?['location']);
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lon = (loc?['lng'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;

      final formatted = (r['formatted_address'] ?? '').toString().trim();
      final name = (r['name'] ?? '').toString().trim();

      cerrarSesionPlaces();
      return DetalleLugar(
        placeId: pid,
        name: name.isNotEmpty ? name : formatted,
        address: formatted.isNotEmpty ? formatted : null,
        lat: lat,
        lon: lon,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _placesAutocompleteViaFunctions({
    required String input,
    String? country,
    String? sessiontoken,
    double? biasLat,
    double? biasLon,
  }) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('placesAutocomplete');
      final res = await fn.call(<String, dynamic>{
        'input': input,
        if (country != null && country.trim().isNotEmpty) 'country': country,
        if (sessiontoken != null && sessiontoken.trim().isNotEmpty)
          'sessiontoken': sessiontoken,
        if (biasLat != null) 'biasLat': biasLat,
        if (biasLon != null) 'biasLon': biasLon,
      });
      final data = res.data;
      if (data is Map) {
        return _asStringKeyedMap(data);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _placesDetailsViaFunctions({
    required String placeId,
    String? sessiontoken,
  }) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('placesDetails');
      final res = await fn.call(<String, dynamic>{
        'placeId': placeId,
        if (sessiontoken != null && sessiontoken.trim().isNotEmpty)
          'sessiontoken': sessiontoken,
      });
      final data = res.data;
      if (data is Map) {
        return _asStringKeyedMap(data);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _placesFindFromTextViaFunctions({
    required String input,
    String? country,
  }) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('placesFindFromText');
      final res = await fn.call(<String, dynamic>{
        'input': input,
        if (country != null && country.trim().isNotEmpty) 'country': country,
      });
      final data = res.data;
      if (data is Map) {
        return _asStringKeyedMap(data);
      }
    } catch (_) {}
    return null;
  }

  Future<DetalleLugar?> detalle(
    String placeId, {
    String? hintDireccion,
  }) async {
    final pid = placeId.trim();
    if (pid.isEmpty) {
      return null;
    }

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
            lon: p.lon);
      }
    }

    final hint = (hintDireccion ?? pid).trim();

    if (pid.startsWith('geocoded:') || pid.startsWith('recent:')) {
      return _geocodeComoDetalle(hint, placeId: pid);
    }

    if (!_placesEnabled) {
      return _geocodeComoDetalle(hint, placeId: pid);
    }

    if (_esPlaceIdGoogle(pid)) {
      final fromGoogle = await _detalleGoogle(pid);
      if (fromGoogle != null) return fromGoogle;
    }

    return _geocodeComoDetalle(hint, placeId: pid);
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  _FormattedRD _formatearPlacemarkRD(geocoding.Placemark p) {
    final calle = [
      (p.thoroughfare ?? '').trim(),
      (p.subThoroughfare ?? '').trim()
    ].where((s) => s.isNotEmpty).join(' ').trim();
    final sector = (p.subLocality ?? '').trim();
    final ciudad = ((p.locality ?? '').trim().isNotEmpty
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
