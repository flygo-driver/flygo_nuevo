// lib/servicios/lugares_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:http/http.dart' as http;
import 'package:flygo_nuevo/data/lugares_rd_pois.dart';
import 'package:flygo_nuevo/keys.dart' as app_keys; // key centralizada
import 'package:flygo_nuevo/servicios/google_places_sdk_adapter.dart';
import 'package:flygo_nuevo/servicios/lugares_populares_service.dart';
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

  /// Coordenadas cuando la sugerencia viene del catálogo local RD.
  final double? lat;
  final double? lon;

  const PrediccionLugar({
    required this.placeId,
    required this.primary,
    this.secondary,
    this.distanceMeters,
    this.lat,
    this.lon,
  });
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

const List<String> _quickChipIdsRd = [
  'SDQ',
  'PUJ',
  'STI',
  'POP',
  'MALL_BM',
  'MALL_AG',
  'ZN_COL',
  'SEC_PIANT',
  'SEC_NACO',
  'SEC_ELUZ',
  'CIU_SD',
  'CIU_STI',
];

LugarRdPoi? _lugarRdPorId(String id) {
  for (final p in lugaresRdCatalogoCompleto) {
    if (p.id == id) return p;
  }
  return null;
}

int _distanciaMetrosLocal(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return (r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))).round();
}

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

class _ScoredLugarRd {
  final LugarRdPoi poi;
  final int score;
  const _ScoredLugarRd(this.poi, this.score);
}

List<PrediccionLugar> _filterLocalPOIs(
  String q, {
  double? biasLat,
  double? biasLon,
}) {
  final nq = _norm(q.trim());
  if (nq.isEmpty) {
    return const [];
  }

  int scoreFor(LugarRdPoi p) {
    final name = _norm(p.name);
    final addr = _norm(p.address);
    final aliases = p.aliases.map(_norm).toList();
    final tags = p.tags.map(_norm).toList();
    final id = p.id.toLowerCase();

    int score = 0;
    if (name.startsWith(nq)) {
      score += 120;
    } else if (name.contains(nq)) {
      score += 70;
    }

    if (addr.startsWith(nq)) {
      score += 55;
    } else if (addr.contains(nq)) {
      score += 35;
    }

    if (id.startsWith(nq) || id.contains(nq)) {
      score += 45;
    }

    for (final a in aliases) {
      if (a.startsWith(nq)) {
        score += 95;
        break;
      }
      if (a.contains(nq)) {
        score += 50;
      }
    }

    for (final t in tags) {
      if (t.startsWith(nq) || t.contains(nq)) {
        score += 30;
      }
    }

    final tokens = nq
        .split(RegExp(r'[\s,#]+'))
        .map((t) => t.trim())
        .where((t) => t.length >= 2)
        .toList();
    for (final t in tokens) {
      if (name.contains(t)) score += 18;
      if (addr.contains(t)) score += 12;
      if (aliases.any((a) => a.contains(t))) score += 22;
      if (tags.any((tag) => tag.contains(t))) score += 15;
    }

    final sinPrefijoBarrio = nq.replaceFirst(
      RegExp(r'^(?:barrio|sector)\s+'),
      '',
    );
    if (sinPrefijoBarrio.length >= 3 && sinPrefijoBarrio != nq) {
      if (name.contains(sinPrefijoBarrio)) score += 80;
      if (aliases.any((a) => a.contains(sinPrefijoBarrio))) score += 75;
    }

    if (nq.contains('ensanche') && tags.contains('ensanche')) {
      score += 40;
    }
    if (nq.contains('aeropuerto') && tags.contains('aeropuerto')) {
      score += 50;
    }

    if (biasLat != null &&
        biasLon != null &&
        biasLat.isFinite &&
        biasLon.isFinite) {
      final meters = _distanciaMetrosLocal(biasLat, biasLon, p.lat, p.lon);
      score += _proximityBoostLocal(meters);
    }

    return score;
  }

  final scored = <_ScoredLugarRd>[];
  for (final p in lugaresRdCatalogoCompleto) {
    final s = scoreFor(p);
    if (s > 0) {
      scored.add(_ScoredLugarRd(p, s));
    }
  }
  scored.sort((a, b) => b.score.compareTo(a.score));

  return scored
      .take(15)
      .map(
        (e) => PrediccionLugar(
          placeId: 'local:poi:${e.poi.id}',
          primary: e.poi.name,
          secondary: e.poi.address,
          lat: e.poi.lat,
          lon: e.poi.lon,
        ),
      )
      .toList(growable: false);
}

int _proximityBoostLocal(int meters) {
  if (meters <= 3000) return 35;
  if (meters <= 8000) return 28;
  if (meters <= 20000) return 18;
  if (meters <= 50000) return 10;
  if (meters <= 120000) return 4;
  return 0;
}

List<PrediccionLugar> _quickChips() {
  return _quickChipIdsRd
      .map(_lugarRdPorId)
      .whereType<LugarRdPoi>()
      .map(
        (p) => PrediccionLugar(
          placeId: 'local:poi:${p.id}',
          primary: p.name,
          secondary: p.address,
          lat: p.lat,
          lon: p.lon,
        ),
      )
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

  GooglePlacesSdkAdapter get _placesSdk => GooglePlacesSdkAdapter.instance;

  /// SDK nativo (mismo motor que Google Maps) en Android/iOS; web usa REST.
  bool get _usePlacesSdk => !kIsWeb && _placesSdk.disponible;

  static List<PrediccionLugar> get sugerenciasRapidasDO => _quickChips();

  void _ensureSessionToken() {
    _sessionToken ??= _uuid.v4();
  }

  /// Cierra sesión de facturación Places tras elegir un lugar (Place Details).
  void cerrarSesionPlaces() {
    _sessionToken = null;
    if (_usePlacesSdk) {
      _placesSdk.cerrarSesion();
    }
  }

  Future<List<PrediccionLugar>> _autocompletarPlacesSdk(
    String q, {
    double? biasLat,
    double? biasLon,
    bool sinSesgoUbicacion = false,
    bool sesgoCercano = false,
  }) async {
    try {
      final preds = await _placesSdk.autocompletar(
        query: q,
        biasLat: biasLat,
        biasLon: biasLon,
        sinSesgoUbicacion: sinSesgoUbicacion,
        sesgoCercano: sesgoCercano,
      );
      if (preds.isEmpty) return const [];
      return preds
          .map(
            (p) => PrediccionLugar(
              placeId: _normalizarPlaceId(p.placeId),
              primary: p.primary,
              secondary: p.secondary,
              distanceMeters: p.distanceMeters,
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  String _normalizarPlaceId(String raw) {
    final id = raw.trim();
    if (id.startsWith('places/')) return id.substring('places/'.length);
    return id;
  }

  /// Places API (nueva) — el motor más reciente de Google (mismo backend que Maps web).
  Future<List<PrediccionLugar>> _autocompletarPlacesApiNueva(
    String input, {
    String? country,
    double? biasLat,
    double? biasLon,
    bool direccionDetallada = false,
    bool modoMapa = false,
  }) async {
    final q = input.trim();
    if (q.isEmpty || kIsWeb) return const [];

    try {
      final body = <String, dynamic>{
        'input': q,
        'languageCode': 'es',
        if (_sessionToken != null && _sessionToken!.trim().isNotEmpty)
          'sessionToken': _sessionToken,
        'includedRegionCodes': [
          (country ?? 'do').trim().toLowerCase(),
        ],
      };

      if (!direccionDetallada) {
        final lat = biasLat ?? 18.7357;
        final lon = biasLon ?? -70.1627;
        final radio = modoMapa ? 120000.0 : 380000.0;
        body['origin'] = {'latitude': lat, 'longitude': lon};
        body['locationBias'] = {
          'circle': {
            'center': {'latitude': lat, 'longitude': lon},
            'radius': radio,
          },
        };
      }

      final res = await http
          .post(
            Uri.parse('https://places.googleapis.com/v1/places:autocomplete'),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': app_keys.kGooglePlacesApiKey,
              'X-Goog-FieldMask':
                  'suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat,suggestions.placePrediction.distanceMeters',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 7));

      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return const [];
      final json = _asStringKeyedMap(decoded);
      if (json == null) return const [];

      final suggestions = (json['suggestions'] as List?) ?? const [];
      final out = <PrediccionLugar>[];
      for (final e in suggestions) {
        final s = _asStringKeyedMap(e);
        if (s == null) continue;
        final pred = _asStringKeyedMap(s['placePrediction']);
        if (pred == null) continue;

        final placeId = _normalizarPlaceId(
          (pred['placeId'] ?? '').toString(),
        );
        if (placeId.isEmpty) continue;

        final sf = _asStringKeyedMap(pred['structuredFormat']);
        final main = _asStringKeyedMap(sf?['mainText']);
        final sec = _asStringKeyedMap(sf?['secondaryText']);
        final text = _asStringKeyedMap(pred['text']);

        final primary = (main?['text'] ?? text?['text'] ?? '').toString().trim();
        if (primary.isEmpty) continue;
        final secondary = (sec?['text'] ?? '').toString().trim();
        final distanceMeters = (pred['distanceMeters'] as num?)?.round();

        out.add(
          PrediccionLugar(
            placeId: placeId,
            primary: primary,
            secondary: secondary.isEmpty ? null : secondary,
            distanceMeters: distanceMeters,
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<List<PrediccionLugar>> _autocompletarRestVariante(
    String input, {
    String? country,
    double? biasLat,
    double? biasLon,
    bool direccionDetallada = false,
    bool modoMapa = false,
  }) async {
    final v = input.trim();
    if (v.isEmpty) return const [];

    final params = <String, String>{
      'key': app_keys.kGooglePlacesApiKey,
      'language': 'es',
      'input': v,
      if (_sessionToken != null && _sessionToken!.trim().isNotEmpty)
        'sessiontoken': _sessionToken!,
    };
    if (country != null && country.trim().isNotEmpty) {
      params['components'] = 'country:${country.trim().toLowerCase()}';
    }
    if (!direccionDetallada && biasLat != null && biasLon != null) {
      params['location'] =
          '${biasLat.toStringAsFixed(6)},${biasLon.toStringAsFixed(6)}';
      params['radius'] = modoMapa ? '120000' : '350000';
      params['origin'] =
          '${biasLat.toStringAsFixed(6)},${biasLon.toStringAsFixed(6)}';
    }

    Map<String, dynamic>? json;
    if (kIsWeb) {
      json = await _placesAutocompleteViaFunctions(
        input: v,
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

    return _prediccionesDesdeAutocompleteJson(json);
  }

  List<PrediccionLugar> _prediccionesDesdeAutocompleteJson(
    Map<String, dynamic>? json,
  ) {
    if (json == null) return const [];
    final status = (json['status'] ?? '').toString();
    if (status != 'OK' && status != 'ZERO_RESULTS') return const [];

    final list = (json['predictions'] as List?) ?? const [];
    final out = <PrediccionLugar>[];
    for (final e in list) {
      final m = _asStringKeyedMap(e);
      if (m == null) continue;
      final placeId = _normalizarPlaceId((m['place_id'] ?? '').toString());
      if (placeId.isEmpty) continue;

      final desc = (m['description'] ?? '').toString();
      final distanceMeters = (m['distance_meters'] as num?)?.round();
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

      out.add(
        PrediccionLugar(
          placeId: placeId,
          primary: primary.isNotEmpty ? primary : desc,
          secondary: secondary,
          distanceMeters: distanceMeters,
        ),
      );
    }
    return out;
  }

  Future<List<PrediccionLugar>> _recolectarFindPlace(
    String input, {
    String? country,
  }) async {
    final q = input.trim();
    if (q.length < 3) return const [];

    final remotes = <PrediccionLugar>[];
    final seenIds = <String>{};
    await _agregarDesdeFindPlace(
      q,
      country: country,
      seenIds: seenIds,
      remotes: remotes,
    );
    return remotes;
  }

  Future<List<PrediccionLugar>> _recolectarGeocode(String input) async {
    final q = input.trim();
    if (q.length < 3) return const [];

    final remotes = <PrediccionLugar>[];
    final seenIds = <String>{};
    await _agregarDesdeGeocode(
      q,
      seenIds: seenIds,
      remotes: remotes,
    );
    return remotes;
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
    String query, {
    /// Google primero (mapa / móvil / RAI): catálogo local como refuerzo, no tapa Google.
    bool priorizarGoogle = false,
  }) {
    final nq = _norm(_normalizarTyposDireccionRD(query.trim()));
    if (nq.isEmpty) return preds;

    final scored = preds.map((p) {
      final primary = _norm(p.primary);
      final secondary = _norm(p.secondary ?? '');
      final full = '$primary $secondary';
      int score = 0;
      if (p.placeId.startsWith('local:poi:')) {
        score += priorizarGoogle ? 6 : 15;
      }
      if (p.placeId.startsWith('flygo_popular:') ||
          (p.secondary ?? '').toLowerCase().contains('frecuente en flygo')) {
        score += priorizarGoogle ? 12 : 25;
      }
      if (primary.startsWith(nq)) score += 120;
      if (secondary.isNotEmpty && secondary.startsWith(nq)) score += 80;
      if (secondary.contains(nq)) score += 40;
      if (primary.contains(nq)) score += 20;
      final tokens = nq
          .split(RegExp(r'[\s,#]+'))
          .map((t) => t.trim())
          .where((t) => t.length >= 2)
          .toList();
      for (final t in tokens) {
        if (primary.contains(t)) score += 18;
        if (secondary.contains(t)) score += 12;
      }
      // Refuerzo dirección RD: "23 este" + "39" + "luperon"
      final orient = _extraerCalleOrientacionRD(nq);
      if (orient != null) {
        if (full.contains(orient.numero) &&
            full.contains(orient.orientacion)) {
          score += 70;
        }
      }
      final puerta = _extraerNumeroPuertaRD(nq, calleNum: orient?.numero);
      if (puerta != null && full.contains(puerta)) score += 45;
      final ensanche = _extraerEnsancheRD(nq);
      if (ensanche != null) {
        final ne = _norm(ensanche);
        if (full.contains(ne) || full.contains(ne.replaceAll(' ', ''))) {
          score += 95;
        }
      }
      if (nq.contains('luperon') && full.contains('luperon')) score += 80;
      score += LugaresPopularesService.instance.boostParaPrediccion(p);
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

  String? _extraerNombreBarrioBusqueda(String q) {
    final m = RegExp(
      r'\b(?:barrio|sector)\s+([^,]+)',
      caseSensitive: false,
    ).firstMatch(q.trim());
    final nombre = m?.group(1)?.trim();
    if (nombre == null || nombre.length < 2) return null;
    return nombre;
  }

  /// Calle + sector + número: no sesgar por GPS (el usuario busca en todo RD).
  bool _esBusquedaDireccionDetallada(String q) {
    final lower = q.toLowerCase();
    if (RegExp(r'\d').hasMatch(lower)) return true;
    if (RegExp(
      r'\b(este|oeste|norte|sur)\b',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }
    return RegExp(
      r'\b(calle|avenida|av\.|sector|numero|n[uú]mero|urbanizaci|residencial|ensanche|ensanchez|barrio|villa|ens\.)\b',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  /// Corrige typos frecuentes al escribir direcciones en RD.
  String _normalizarTyposDireccionRD(String input) {
    return input
        .replaceAll(RegExp(r'\bensanchez\b', caseSensitive: false), 'ensanche')
        .replaceAll(RegExp(r'\bensanch\b', caseSensitive: false), 'ensanche')
        .replaceAll(RegExp(r'\bnumero\b', caseSensitive: false), '#')
        .replaceAll(RegExp(r'\s+#\s*', caseSensitive: false), ' #')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Patrón SDQ muy común: "23 este" = Calle 23 Este (sin escribir "calle").
  ({String numero, String orientacion})? _extraerCalleOrientacionRD(String lower) {
    final m = RegExp(
      r'\b(\d{1,4})\s+(este|oeste|norte|sur)\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (m == null) return null;
    final num = m.group(1);
    final ori = m.group(2)?.toLowerCase();
    if (num == null || ori == null) return null;
    return (numero: num, orientacion: ori);
  }

  String? _extraerNumeroPuertaRD(String lower, {String? calleNum}) {
    final hash = RegExp(r'#\s*(\d{1,6})\b', caseSensitive: false).firstMatch(lower);
    if (hash != null) return hash.group(1);
    final num = RegExp(
      r'\b(?:n[uú]mero|numero)\s*#?\s*(\d{1,6})\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (num != null) return num.group(1);
    // "23 este 39" sin la palabra número.
    final trasOrient = RegExp(
      r'\b\d{1,4}\s+(?:este|oeste|norte|sur)\s+#?\s*(\d{1,6})\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (trasOrient != null) {
      final p = trasOrient.group(1);
      if (p != null && p != calleNum) return p;
    }
    return null;
  }

  String? _extraerEnsancheRD(String lower) {
    final m = RegExp(
      r'\b(?:ensanche|ensanchez|ensanch)\s+([a-záéíóúñ0-9][a-záéíóúñ0-9\s.-]{1,40})',
      caseSensitive: false,
    ).firstMatch(lower);
    var nombre = m?.group(1)?.trim();
    if (nombre == null || nombre.isEmpty) return null;
    // Quitar restos de "numero/#" si quedaron pegados.
    nombre = nombre
        .replaceAll(RegExp(r'\s+#.*$'), '')
        .replaceAll(RegExp(r'\s+numero.*$', caseSensitive: false), '')
        .trim();
    return nombre.isEmpty ? null : nombre;
  }

  List<String> _variantesCalleOrientacionRD({
    required String calleNum,
    required String orientacion,
    String? puerta,
    String? ensanche,
    bool santoDomingo = true,
  }) {
    final ori = orientacion[0].toUpperCase() + orientacion.substring(1);
    final out = <String>[
      'Calle $calleNum $ori${puerta != null ? ' $puerta' : ''}',
      'C. $calleNum $ori${puerta != null ? ' $puerta' : ''}',
      '$calleNum $ori${puerta != null ? ' $puerta' : ''}',
    ];
    if (puerta != null) {
      out.addAll([
        'Calle $calleNum $ori #$puerta',
        'Calle $calleNum $ori, #$puerta',
        '$calleNum $ori #$puerta',
      ]);
    }
    if (ensanche != null && ensanche.isNotEmpty) {
      final e = ensanche
          .split(' ')
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
          .join(' ');
      out.addAll([
        'Calle $calleNum $ori${puerta != null ? ' $puerta' : ''} Ensanche $e',
        'Ensanche $e Calle $calleNum $ori${puerta != null ? ' $puerta' : ''}',
        'Ensanche $e, Calle $calleNum $ori${puerta != null ? ' #$puerta' : ''}',
        'Ensanche $e, Santo Domingo',
      ]);
    }
    if (santoDomingo) {
      out.add(
        'Calle $calleNum $ori${puerta != null ? ' $puerta' : ''}, Santo Domingo',
      );
    }
    return out;
  }

  void _agregarPrediccionSiNueva(
    List<PrediccionLugar> out,
    Set<String> seenIds,
    PrediccionLugar p,
  ) {
    final placeId = _normalizarPlaceId(p.placeId);
    if (placeId.isEmpty) return;
    if (!seenIds.add(placeId)) return;
    out.add(
      PrediccionLugar(
        placeId: placeId,
        primary: p.primary,
        secondary: p.secondary,
        distanceMeters: p.distanceMeters,
      ),
    );
  }

  Future<void> _agregarDesdeFindPlace(
    String input, {
    String? country,
    required Set<String> seenIds,
    required List<PrediccionLugar> remotes,
  }) async {
    final q = input.trim();
    if (q.length < 3 || remotes.length >= 35) return;

    try {
      Map<String, dynamic>? json;
      if (kIsWeb) {
        json = await _placesFindFromTextViaFunctions(
          input: q,
          country: country ?? 'do',
        );
      } else {
        final params = <String, String>{
          'input': q,
          'inputtype': 'textquery',
          'fields': 'place_id,name,formatted_address,geometry',
          'language': 'es',
          'locationbias': 'circle:450000@18.7357,-70.1627',
          'key': app_keys.kGooglePlacesApiKey,
        };
        final cc = (country ?? 'do').trim().toLowerCase();
        if (cc.isNotEmpty) params['region'] = cc;
        final uri = Uri.https(
          'maps.googleapis.com',
          '/maps/api/place/findplacefromtext/json',
          params,
        );
        json = await _getJson(uri);
      }
      if (json == null) return;
      final status = (json['status'] ?? '').toString();
      if (status != 'OK') return;

      final candidates = (json['candidates'] as List?) ?? const [];
      for (final e in candidates) {
        final m = _asStringKeyedMap(e);
        if (m == null) continue;
        final placeId = (m['place_id'] ?? '').toString();
        if (placeId.isEmpty) continue;
        final name = (m['name'] ?? '').toString().trim();
        final formatted = (m['formatted_address'] ?? '').toString().trim();
        final primary = name.isNotEmpty ? name : formatted;
        if (primary.isEmpty) continue;
        _agregarPrediccionSiNueva(
          remotes,
          seenIds,
          PrediccionLugar(
            placeId: placeId,
            primary: primary,
            secondary: formatted.isNotEmpty && formatted != primary
                ? formatted
                : 'República Dominicana',
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _agregarDesdeGeocode(
    String address, {
    required Set<String> seenIds,
    required List<PrediccionLugar> remotes,
  }) async {
    final q = address.trim();
    if (q.length < 3 || remotes.length >= 35 || kIsWeb) return;

    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/geocode/json',
        <String, String>{
          'address': q,
          'components': 'country:DO',
          'language': 'es',
          'key': app_keys.kGooglePlacesApiKey,
        },
      );
      final json = await _getJson(uri);
      if (json == null) return;
      final status = (json['status'] ?? '').toString();
      if (status != 'OK') return;

      final results = (json['results'] as List?) ?? const [];
      for (final e in results.take(5)) {
        final m = _asStringKeyedMap(e);
        if (m == null) continue;
        final formatted = (m['formatted_address'] ?? '').toString().trim();
        if (formatted.isEmpty) continue;
        final placeId = (m['place_id'] ?? '').toString();
        final pid = placeId.isNotEmpty
            ? placeId
            : 'geocoded:${_norm(formatted)}';
        final parts = formatted.split(',').map((s) => s.trim()).toList();
        final primary = parts.isNotEmpty ? parts.first : formatted;
        final secondary =
            parts.length > 1 ? parts.sublist(1).join(', ') : null;
        double? lat;
        double? lon;
        final geom = _asStringKeyedMap(m['geometry']);
        final loc = geom != null ? _asStringKeyedMap(geom['location']) : null;
        if (loc != null) {
          lat = double.tryParse('${loc['lat']}');
          lon = double.tryParse('${loc['lng']}');
        }
        _agregarPrediccionSiNueva(
          remotes,
          seenIds,
          PrediccionLugar(
            placeId: pid,
            primary: primary,
            secondary: secondary,
            lat: lat,
            lon: lon,
          ),
        );
      }
    } catch (_) {}
  }

  // Cuando el usuario escribe una dirección "larga" tipo:
  // "calle 15 sector villa maria numero 45 santo domingo..."
  // Google puede devolver ZERO_RESULTS para ese input completo.
  // Generamos variantes más cortas para aumentar tasa de acierto.
  List<String> _buildAddressVariants(String input) {
    var q = _normalizarTyposDireccionRD(input.trim());
    if (q.isEmpty) return const <String>[];

    q = q
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\bcasa\s+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bno\.?\s*', caseSensitive: false), '# ')
        .replaceAllMapped(
          RegExp(r'#\s*(\d+)', caseSensitive: false),
          (m) => '#${m.group(1)}',
        );

    final lower = q.toLowerCase();

    final calleOrient = _extraerCalleOrientacionRD(lower);
    final puertaNum =
        _extraerNumeroPuertaRD(lower, calleNum: calleOrient?.numero);
    final ensancheNombre = _extraerEnsancheRD(lower);

    final calleNumMatch = RegExp(
      r'\b(?:calle|av\.|avenida|av)\s*#?\s*(\d{1,6})\b',
      caseSensitive: false,
    ).firstMatch(lower);

    final calleNombreMatch = RegExp(
      r'\b(?:calle|av\.|avenida|av)\s+([a-záéíóúñ0-9][a-záéíóúñ0-9\s.-]{1,45}?)(?=\s*(?:sector|numero|n[uú]mero|#|,|santo|sdq|distrito|provincia|$))',
      caseSensitive: false,
    ).firstMatch(lower);

    final numeroMatch = RegExp(
      r'\b(?:n[uú]mero|numero|#)\s*#?\s*(\d{1,6})\b',
      caseSensitive: false,
    ).firstMatch(lower);

    final sectorMatch = RegExp(
      r'\bsector\s+([^,]+)',
      caseSensitive: false,
    ).firstMatch(lower);

    final barrioMatch = RegExp(
      r'\b(?:urbanizaci[oó]n|urb\.?|residencial|ensanche|ensanchez|ensanch|barrio|villa|ens\.)\s+([^,]+)',
      caseSensitive: false,
    ).firstMatch(lower);

    final hasSantoDomingo =
        RegExp(r'\bsanto\s+domingo\b|\bsdq\b|\bsd\b', caseSensitive: false)
            .hasMatch(lower);

    final calleNum = calleNumMatch?.group(1) ?? calleOrient?.numero;
    final calleNombre = calleNombreMatch?.group(1)?.trim();
    final numeroNum = puertaNum ?? numeroMatch?.group(1);
    final sector = sectorMatch?.group(1)?.trim();
    final barrio = barrioMatch?.group(1)?.trim() ?? ensancheNombre;

    final variants = <String>[q, input.trim()];

    void add(String v) {
      final t = v.trim();
      if (t.length >= 3) variants.add(t);
    }

    // Variantes prioritarias: "23 este #39 ensanche luperon"
    if (calleOrient != null) {
      for (final v in _variantesCalleOrientacionRD(
        calleNum: calleOrient.numero,
        orientacion: calleOrient.orientacion,
        puerta: numeroNum,
        ensanche: ensancheNombre ?? barrio,
        santoDomingo: hasSantoDomingo || ensancheNombre != null,
      )) {
        add(v);
      }
    }

    if (sector != null && sector.isNotEmpty) {
      add('sector $sector');
      add('$sector, República Dominicana');
      if (hasSantoDomingo) add('sector $sector, Santo Domingo');
    }

    if (barrio != null && barrio.isNotEmpty) {
      add(barrio);
      add('$barrio, República Dominicana');
      add('Barrio $barrio, Santo Domingo Este');
      add('Barrio $barrio, Santo Domingo');
      add('barrio $barrio, República Dominicana');
    }

    if (calleNum != null && sector != null && sector.isNotEmpty) {
      add('calle $calleNum sector $sector');
      add('sector $sector calle $calleNum');
    }

    if (calleNombre != null &&
        calleNombre.isNotEmpty &&
        sector != null &&
        sector.isNotEmpty &&
        calleNum == null) {
      add('calle $calleNombre sector $sector');
      add('sector $sector calle $calleNombre');
    }

    if (calleNum != null && numeroNum != null) {
      add('calle $calleNum numero $numeroNum');
      if (hasSantoDomingo) {
        add('calle $calleNum numero $numeroNum santo domingo');
      }
    }

    if (calleNombre != null && numeroNum != null) {
      add('calle $calleNombre numero $numeroNum');
    }

    if (sector != null && numeroNum != null) {
      add('sector $sector numero $numeroNum');
    }

    if (calleNum != null && sector == null && barrio != null) {
      add('calle $calleNum $barrio');
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

  List<PrediccionLugar> _fusionarSinDuplicar(
    List<PrediccionLugar> a,
    List<PrediccionLugar> b,
  ) {
    final out = <PrediccionLugar>[...a];
    final seen = <String>{
      for (final p in a) '${p.placeId}|${_norm(p.primary)}',
    };
    for (final p in b) {
      final k = '${p.placeId}|${_norm(p.primary)}';
      if (seen.add(k)) out.add(p);
    }
    return out;
  }

  List<PrediccionLugar> _ensamblarSalidaAutocompletar({
    required List<PrediccionLugar> locals,
    required List<PrediccionLugar> remotes,
    required String cq,
    required String q,
    String? country,
    bool priorizarGoogle = false,
  }) {
    final mergedRemote = rankearPredicciones(
      remotes,
      cq,
      priorizarGoogle: priorizarGoogle,
    );
    final out = <PrediccionLugar>[];
    final seenPrimary = <String>{};
    final orden = priorizarGoogle
        ? [...mergedRemote, ...locals]
        : [...locals, ...mergedRemote];
    for (final p in orden) {
      final k = '${p.placeId}|${_norm(p.primary)}';
      if (seenPrimary.contains(k)) continue;
      seenPrimary.add(k);
      out.add(p);
    }
    if (remotes.isEmpty && cq.length >= 2) {
      out.add(PrediccionLugar(placeId: q, primary: q, secondary: country));
    }
    return rankearPredicciones(out, cq, priorizarGoogle: priorizarGoogle);
  }

  void _fusionarRemotos(
    List<PrediccionLugar> remotes,
    Set<String> seenIds,
    List<PrediccionLugar> nuevos,
  ) {
    for (final p in nuevos) {
      _agregarPrediccionSiNueva(remotes, seenIds, p);
    }
  }

  Future<List<PrediccionLugar>> autocompletar(
    String query, {
    String? country,
    double? biasLat,
    double? biasLon,
    /// Pantalla mapa: sesgo al centro de cámara y más resultados de Google.
    /// En móvil siempre se usa el stack completo de Google (mismo motor que el mapa).
    bool modoMapa = false,
    void Function(List<PrediccionLugar> parcial)? onParcial,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const [];
    }

    final locals = _filterLocalPOIs(
      q,
      biasLat: biasLat,
      biasLon: biasLon,
    );

    unawaited(
      LugaresPopularesService.instance.precargarParaUbicacion(
        lat: biasLat,
        lon: biasLon,
      ),
    );
    final populares = LugaresPopularesService.instance.sugerenciasParaQuery(q);
    final localesYPopulares = _fusionarSinDuplicar(locals, populares);

    if (!_placesEnabled) {
      final merged = <PrediccionLugar>[
        ...localesYPopulares,
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
      final direccionDetallada = _esBusquedaDireccionDetallada(q);
      // Móvil: mismo motor que mapa/RAI (Places SDK + API nueva + geocode).
      final busquedaGoogleCompleta = modoMapa || !kIsWeb;
      final sesgoSdkCercano = busquedaGoogleCompleta &&
          !direccionDetallada &&
          biasLat != null &&
          biasLon != null;
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
      final variantList = expanded.toList();
      final cc = (country ?? 'do').trim().toLowerCase();

      final remotes = <PrediccionLugar>[];
      final seenIds = <String>{};

      void emitirParcial() {
        if (onParcial == null) return;
        onParcial(
          _ensamblarSalidaAutocompletar(
            locals: localesYPopulares,
            remotes: List<PrediccionLugar>.from(remotes),
            cq: cq,
            q: q,
            country: country,
            priorizarGoogle: busquedaGoogleCompleta,
          ),
        );
      }

      // Catálogo RD local: resultados al instante (sin esperar Google).
      emitirParcial();

      // ── Fase 1 (rápida): 1–2 consultas con el texto tal cual ──
      final faseRapida = <Future<List<PrediccionLugar>>>[
        _autocompletarRestVariante(
          cq,
          country: country,
          biasLat: biasLat,
          biasLon: biasLon,
          direccionDetallada: direccionDetallada,
          modoMapa: busquedaGoogleCompleta,
        ),
      ];
      if (_usePlacesSdk) {
        faseRapida.insert(
          0,
          _autocompletarPlacesSdk(
            cq,
            biasLat: biasLat,
            biasLon: biasLon,
            sinSesgoUbicacion: direccionDetallada,
            sesgoCercano: sesgoSdkCercano,
          ),
        );
      }
      if (busquedaGoogleCompleta && cq.length >= 2 && !kIsWeb) {
        faseRapida.add(
          _autocompletarPlacesApiNueva(
            cq,
            country: cc,
            biasLat: biasLat,
            biasLon: biasLon,
            direccionDetallada: direccionDetallada,
            modoMapa: busquedaGoogleCompleta,
          ),
        );
      }

      final rapidos = await Future.wait(faseRapida);
      for (final lista in rapidos) {
        _fusionarRemotos(remotes, seenIds, lista);
      }
      emitirParcial();

      // Barrios/sectores: geocode temprano si autocomplete no devuelve nada.
      if (busquedaGoogleCompleta && remotes.isEmpty && cq.length >= 3) {
        final barrioNombre = _extraerNombreBarrioBusqueda(cq);
        final geoQueries = <String>{
          cq,
          if (barrioNombre != null) ...[
            barrioNombre,
            'Barrio $barrioNombre, Santo Domingo Este',
            'Barrio $barrioNombre, República Dominicana',
          ],
        };
        for (final gq in geoQueries) {
          await _agregarDesdeGeocode(
            gq,
            seenIds: seenIds,
            remotes: remotes,
          );
          if (remotes.isNotEmpty) break;
        }
        if (remotes.isEmpty) {
          final fp = await _recolectarFindPlace(
            barrioNombre ?? cq,
            country: country,
          );
          _fusionarRemotos(remotes, seenIds, fp);
        }
        emitirParcial();
      }

      // Si ya hay buenas sugerencias y el texto es corto, no saturar APIs (solo web).
      final bool textoCorto = cq.length < 5;
      if (!busquedaGoogleCompleta && textoCorto && remotes.length >= 4) {
        return _ensamblarSalidaAutocompletar(
          locals: localesYPopulares,
          remotes: remotes,
          cq: cq,
          q: q,
          country: country,
          priorizarGoogle: busquedaGoogleCompleta,
        );
      }

      // ── Fase 2 (enriquecimiento): variantes RD, sin bloquear la UI ──
      final tareas = <Future<List<PrediccionLugar>>>[];
      final extraVariants = variantList
          .where((v) => v.trim().toLowerCase() != cq.toLowerCase())
          .take(direccionDetallada ? 5 : 3)
          .toList();

      if (_usePlacesSdk) {
        for (final v in extraVariants.take(2)) {
          tareas.add(
            _autocompletarPlacesSdk(
              v,
              biasLat: biasLat,
              biasLon: biasLon,
              sinSesgoUbicacion: direccionDetallada,
              sesgoCercano: sesgoSdkCercano,
            ),
          );
        }
      }

      for (final v in extraVariants.take(3)) {
          tareas.add(
            _autocompletarRestVariante(
              v,
              country: country,
              biasLat: biasLat,
              biasLon: biasLon,
              direccionDetallada: direccionDetallada,
              modoMapa: busquedaGoogleCompleta,
            ),
          );
      }

      // API nueva y geocoding: direcciones largas o búsqueda completa (móvil/mapa).
      if (direccionDetallada && cq.length >= 6) {
        tareas.add(
          _autocompletarPlacesApiNueva(
            cq,
            country: cc,
            biasLat: biasLat,
            biasLon: biasLon,
            direccionDetallada: direccionDetallada,
            modoMapa: busquedaGoogleCompleta,
          ),
        );
        final mejorVariante = extraVariants.isNotEmpty ? extraVariants.first : cq;
        tareas.add(_recolectarFindPlace(mejorVariante, country: country));
        if (remotes.length < 6) {
          tareas.add(_recolectarGeocode(mejorVariante));
        }
      } else if (busquedaGoogleCompleta && cq.length >= 3) {
        final mejorVariante = extraVariants.isNotEmpty ? extraVariants.first : cq;
        tareas.add(_recolectarFindPlace(mejorVariante, country: country));
        if (remotes.length < 6) {
          tareas.add(_recolectarGeocode(mejorVariante));
        }
      }

      if (tareas.isNotEmpty) {
        final lotes = await Future.wait(tareas);
        for (final lista in lotes) {
          _fusionarRemotos(remotes, seenIds, lista);
        }
        emitirParcial();
      }

      return _ensamblarSalidaAutocompletar(
        locals: localesYPopulares,
        remotes: remotes,
        cq: cq,
        q: q,
        country: country,
        priorizarGoogle: busquedaGoogleCompleta,
      );
    } catch (_) {
      return [
        ...localesYPopulares,
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

  /// Expuesto para UI mapa (enriquecer sugerencias Google con coordenadas).
  bool esPlaceIdGooglePublico(String pid) => _esPlaceIdGoogle(pid);

  /// Resuelve texto libre → coordenadas (Google Geocoding / Find Place; mismo motor que mapa).
  Future<DetalleLugar?> geocodeDireccion(String texto) async {
    final base = texto.trim();
    if (base.length < 2) return null;

    if (!kIsWeb) {
      final remotes = <PrediccionLugar>[];
      final seen = <String>{};
      final intentos = <String>{
        base,
        '$base, República Dominicana',
        '$base, Dominican Republic',
      };
      final barrio = _extraerNombreBarrioBusqueda(base);
      if (barrio != null) {
        intentos.add('Barrio $barrio, Santo Domingo Este');
        intentos.add('Barrio $barrio, República Dominicana');
      }
      for (final q in intentos) {
        await _agregarDesdeGeocode(q, seenIds: seen, remotes: remotes);
        if (remotes.isNotEmpty) break;
      }
      if (remotes.isNotEmpty) {
        final p = remotes.first;
        if (p.lat != null && p.lon != null) {
          return DetalleLugar(
            placeId: p.placeId,
            name: p.primary,
            address: p.secondary ?? p.primary,
            lat: p.lat!,
            lon: p.lon!,
          );
        }
        return await detalleDesdePrediccion(p);
      }

      final fp = await _recolectarFindPlace(base, country: 'do');
      if (fp.isNotEmpty) {
        return await detalleDesdePrediccion(fp.first);
      }
    }

    return _geocodeComoDetalle(base);
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

  Future<DetalleLugar?> _detallePlacesApiNueva(String pid) async {
    if (kIsWeb) return null;
    final id = _normalizarPlaceId(pid);
    if (id.isEmpty) return null;

    try {
      final res = await http
          .get(
            Uri.parse(
              'https://places.googleapis.com/v1/places/${Uri.encodeComponent(id)}',
            ),
            headers: {
              'X-Goog-Api-Key': app_keys.kGooglePlacesApiKey,
              'X-Goog-FieldMask':
                  'id,displayName,formattedAddress,location',
            },
          )
          .timeout(const Duration(seconds: 7));
      if (res.statusCode != 200) return null;

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final r = _asStringKeyedMap(decoded);
      if (r == null) return null;

      final loc = _asStringKeyedMap(r['location']);
      final lat = (loc?['latitude'] as num?)?.toDouble();
      final lon = (loc?['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;

      final displayName = _asStringKeyedMap(r['displayName']);
      final name = (displayName?['text'] ?? '').toString().trim();
      final formatted = (r['formattedAddress'] ?? '').toString().trim();

      cerrarSesionPlaces();
      return DetalleLugar(
        placeId: id,
        name: name.isNotEmpty ? name : formatted,
        address: formatted.isNotEmpty ? formatted : null,
        lat: lat,
        lon: lon,
      );
    } catch (_) {
      return null;
    }
  }

  Future<DetalleLugar?> _detalleGoogle(String pid) async {
    final placeId = _normalizarPlaceId(pid);

    if (_usePlacesSdk) {
      try {
        final d = await _placesSdk.detalle(placeId);
        if (d != null) {
          cerrarSesionPlaces();
          return DetalleLugar(
            placeId: d.placeId,
            name: d.name,
            address: d.address,
            lat: d.lat,
            lon: d.lon,
          );
        }
      } catch (_) {}
    }

    final desdeApiNueva = await _detallePlacesApiNueva(placeId);
    if (desdeApiNueva != null) return desdeApiNueva;

    try {
      Map<String, dynamic>? json;
      if (kIsWeb) {
        json = await _placesDetailsViaFunctions(
          placeId: placeId,
          sessiontoken: _sessionToken,
        );
      } else {
        final params = <String, String>{
          'place_id': placeId,
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
        placeId: placeId,
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

  Future<Map<String, dynamic>?> _reverseGeocodeViaFunctions({
    required double lat,
    required double lon,
  }) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('placesReverseGeocode');
      final res = await fn.call(<String, dynamic>{
        'lat': lat,
        'lon': lon,
      });
      final data = res.data;
      if (data is Map) {
        return _asStringKeyedMap(data);
      }
    } catch (_) {}
    return null;
  }

  DetalleLugar? _detalleDesdeReverseGeocodeJson(
    Map<String, dynamic>? json, {
    double? preserveLat,
    double? preserveLon,
  }) {
    if (json == null) return null;
    final status = (json['status'] ?? '').toString();
    if (status != 'OK') return null;
    final results = (json['results'] as List?) ?? const [];
    if (results.isEmpty) return null;

    for (final e in results) {
      final m = _asStringKeyedMap(e);
      if (m == null) continue;
      final geometry = _asStringKeyedMap(m['geometry']);
      final loc = _asStringKeyedMap(geometry?['location']);
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lon = (loc?['lng'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;

      final formatted = (m['formatted_address'] ?? '').toString().trim();
      if (formatted.isEmpty) continue;

      final placeId = (m['place_id'] ?? '').toString();
      final parts = formatted.split(',').map((s) => s.trim()).toList();
      final name = parts.isNotEmpty ? parts.first : formatted;

      return DetalleLugar(
        placeId: placeId.isNotEmpty
            ? placeId
            : 'geocoded:${_norm('$lat,$lon')}',
        name: name,
        address: formatted,
        lat: preserveLat ?? lat,
        lon: preserveLon ?? lon,
      );
    }
    return null;
  }

  /// Resuelve la dirección de un punto tocado en el mapa.
  /// Las coordenadas devueltas son las del toque (no las del centro de la calle).
  Future<DetalleLugar?> detalleDesdeCoordenadas(double lat, double lon) async {
    if (!lat.isFinite || !lon.isFinite) return null;

    if (_placesEnabled) {
      if (kIsWeb) {
        final json = await _reverseGeocodeViaFunctions(lat: lat, lon: lon);
        final desdeWeb = _detalleDesdeReverseGeocodeJson(
          json,
          preserveLat: lat,
          preserveLon: lon,
        );
        if (desdeWeb != null) return desdeWeb;
      } else {
        final uri = Uri.https(
          'maps.googleapis.com',
          '/maps/api/geocode/json',
          <String, String>{
            'latlng': '${lat.toStringAsFixed(6)},${lon.toStringAsFixed(6)}',
            'language': 'es',
            'key': app_keys.kGooglePlacesApiKey,
          },
        );
        final json = await _getJson(uri);
        final desdeApi = _detalleDesdeReverseGeocodeJson(
          json,
          preserveLat: lat,
          preserveLon: lon,
        );
        if (desdeApi != null) return desdeApi;
      }
    }

    try {
      final marks = await geocoding.placemarkFromCoordinates(lat, lon);
      if (marks.isEmpty) return null;
      final fm = _formatearPlacemarkRD(marks.first);
      return DetalleLugar(
        placeId: 'geocoded:${_norm('${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}')}',
        name: fm.titulo,
        address: fm.resto,
        lat: lat,
        lon: lon,
      );
    } catch (_) {
      return null;
    }
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
      final found = _lugarRdPorId(code);
      if (found != null) {
        return DetalleLugar(
          placeId: pid,
          name: found.name,
          address: found.address,
          lat: found.lat,
          lon: found.lon,
        );
      }
    }

    if (pid.startsWith('flygo_popular:')) {
      final det = LugaresPopularesService.instance.detalleDesdePlaceId(pid);
      if (det != null) return det;
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
      final res = await http.get(uri).timeout(const Duration(seconds: 7));
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
