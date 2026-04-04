// lib/servicios/lugares_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:flygo_nuevo/keys.dart' as app_keys; // key centralizada

class PrediccionLugar {
  final String placeId;
  final String primary;
  final String? secondary;
  const PrediccionLugar({required this.placeId, required this.primary, this.secondary});
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

// ---------------- POIs locales (RD) con aliases ----------------
class _LocalPOI {
  final String id;
  final String name;
  final String address;
  final double lat;
  final double lon;
  final List<String> aliases;
  const _LocalPOI(this.id, this.name, this.address, this.lat, this.lon, {this.aliases = const []});
}

const List<_LocalPOI> _AIRPORTS_DO = [
  _LocalPOI('SDQ','Aeropuerto Internacional Las Américas (SDQ)','Boca Chica, Santo Domingo',18.4297,-69.6689,aliases:['ae','aer','aero','aerop','aeropuerto','las americas','las américas','sdq']),
  _LocalPOI('PUJ','Aeropuerto Internacional de Punta Cana (PUJ)','Punta Cana, La Altagracia',18.5674,-68.3634,aliases:['ae','aer','aero','aerop','aeropuerto','punta','aeropuerto punta','puj']),
  _LocalPOI('STI','Aeropuerto Internacional del Cibao (STI)','Santiago de los Caballeros',19.4061,-70.6047,aliases:['ae','aer','aero','aerop','aeropuerto','cibao','sti']),
  _LocalPOI('POP','Aeropuerto Internacional Gregorio Luperón (POP)','Puerto Plata',19.7579,-70.5697,aliases:['ae','aer','aero','aerop','aeropuerto','puerto plata','pop']),
  _LocalPOI('JBQ','Aeropuerto Internacional La Isabela (JBQ)','Santo Domingo (Higüero)',18.5725,-69.9856,aliases:['ae','aer','aero','aerop','aeropuerto','higuero','la isabela','jbq']),
  _LocalPOI('LRM','Aeropuerto Internacional La Romana (LRM)','La Romana',18.4510,-68.9117,aliases:['ae','aer','aero','aerop','aeropuerto','la romana aeropuerto','lrm']),
  _LocalPOI('AZS','Aeropuerto Internacional El Catey (AZS)','Samaná',19.2690,-69.7370,aliases:['ae','aer','aero','aerop','aeropuerto','catey','samana aeropuerto','azs']),
];

const List<_LocalPOI> _POIS_DO = [
  _LocalPOI('HTL_EMB','Hotel El Embajador','Piantini, Santo Domingo',18.4641,-69.9428,aliases:['emb','embajador','hotel emb']),
  _LocalPOI('HTL_JAR','Renaissance Jaragua Hotel','Malecón, Santo Domingo',18.4636,-69.8957,aliases:['jar','jaragua']),
  _LocalPOI('HTL_JWM','JW Marriott Santo Domingo','BlueMall, Piantini',18.4727,-69.9407,aliases:['jw','jw marriott','marriot','marr']),
  _LocalPOI('HTL_BBV','Barceló Bávaro Palace','Bávaro, Punta Cana',18.6576,-68.4015,aliases:['barcelo','bavaro','bbv']),
  _LocalPOI('HTL_HRH','Hard Rock Hotel & Casino Punta Cana','Macao, Punta Cana',18.7282,-68.4687,aliases:['hard','hard rock','hrh']),
  _LocalPOI('MALL_BM','BlueMall Santo Domingo','Piantini, Santo Domingo',18.4724,-69.9402,aliases:['blue','bluemall']),
  _LocalPOI('MALL_AG','Ágora Mall','Serrallés, Santo Domingo',18.4878,-69.9365,aliases:['ago','agora']),
  _LocalPOI('MALL_SA','Sambil Santo Domingo','Los Jardines, Santo Domingo',18.4870,-69.9218,aliases:['sam','sambil']),
  _LocalPOI('MALL_BMPC','BlueMall Punta Cana','Punta Cana',18.5670,-68.4033,aliases:['blue','bluemall']),
  _LocalPOI('ZN_COL','Zona Colonial','Santo Domingo',18.4764,-69.8833,aliases:['zona','colonial','zona col']),
  _LocalPOI('MLC_SD','Malecón de Santo Domingo','Santo Domingo',18.4605,-69.9048,aliases:['male','malecon']),
  _LocalPOI('UNI_UASD','UASD - Universidad Autónoma de Santo Domingo','Gazcue, Santo Domingo',18.4632,-69.9110,aliases:['uasd','universidad uasd']),
  _LocalPOI('HSP_CED','Centro de Diagnóstico CEDIMAT','Paseo de la Salud, SD',18.4707,-69.9537,aliases:['ced','cedimat']),
];

final List<_LocalPOI> _ALL_LOCAL = [..._AIRPORTS_DO, ..._POIS_DO];

String _norm(String s) {
  var x = s.toLowerCase();
  x = x.replaceAll(RegExp('[áàä]'),'a')
       .replaceAll(RegExp('[éèë]'),'e')
       .replaceAll(RegExp('[íìï]'),'i')
       .replaceAll(RegExp('[óòö]'),'o')
       .replaceAll(RegExp('[úùü]'),'u')
       .replaceAll('ñ','n');
  return x;
}

class _ScoredPOI { final _LocalPOI poi; final int score; const _ScoredPOI(this.poi, this.score); }

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
    if (name.startsWith(nq) || addr.startsWith(nq) || p.id.toLowerCase().startsWith(nq)) {
      return 3;
    }
    if (name.contains(nq) || addr.contains(nq) || p.id.toLowerCase().contains(nq)) {
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

  return scored.map((e) => PrediccionLugar(
    placeId: 'local:poi:${e.poi.id}',
    primary: e.poi.name,
    secondary: e.poi.address,
  )).toList(growable: false);
}

List<PrediccionLugar> _quickChips() {
  final base = <_LocalPOI>[
    ..._AIRPORTS_DO.take(4),
    _POIS_DO.firstWhere((p) => p.id=='MALL_BM', orElse: ()=>_POIS_DO.first),
    _POIS_DO.firstWhere((p) => p.id=='MALL_AG', orElse: ()=>_POIS_DO.first),
    _POIS_DO.firstWhere((p) => p.id=='ZN_COL', orElse: ()=>_POIS_DO.first),
    _POIS_DO.firstWhere((p) => p.id=='HTL_EMB', orElse: ()=>_POIS_DO.first),
  ];
  return base.map((p)=>PrediccionLugar(
    placeId:'local:poi:${p.id}', primary:p.name, secondary:p.address,
  )).toList(growable:false);
}

class _FormattedRD {
  final String titulo;
  final String? resto;
  const _FormattedRD(this.titulo, this.resto);
}

class LugaresService {
  LugaresService._();
  static final LugaresService instance = LugaresService._();

  bool get _placesEnabled => app_keys.kGooglePlacesApiKey.trim().isNotEmpty;

  static List<PrediccionLugar> get sugerenciasRapidasDO => _quickChips();

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

    final hasSantoDomingo = RegExp(r'\bsanto\s+domingo\b|\bsdq\b|\bsd\b', caseSensitive: false)
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
    return out;
  }

  Future<List<PrediccionLugar>> autocompletar(
    String query, { String? country, double? biasLat, double? biasLon }
  ) async {
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
      // Sin `types`: cobertura tipo buscador de Google (sectores, barrios, villas,
      // calles, puntos de interés), no solo direcciones con número.
      final baseParams = <String, String>{
        'key': app_keys.kGooglePlacesApiKey,
        'language': 'es',
      };
      if (country != null && country.trim().isNotEmpty) {
        baseParams['components'] = 'country:${country.trim()}';
      }
      if (biasLat != null && biasLon != null) {
        baseParams['location'] =
            '${biasLat.toStringAsFixed(6)},${biasLon.toStringAsFixed(6)}';
        // Sesgo amplio (RD); no restringe fuera del radio, solo prioriza la zona.
        baseParams['radius'] = '150000';
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
          final m = e as Map<String, dynamic>;
          final placeId = (m['place_id'] ?? '').toString();
          if (placeId.isEmpty) continue;
          if (!seenIds.add(placeId)) continue;

          final desc = (m['description'] ?? '').toString();
          String primary = desc;
          String? secondary;
          final sf = m['structured_formatting'] as Map<String, dynamic>?;
          final mainText = sf?['main_text']?.toString();
          final secText = sf?['secondary_text']?.toString();
          if ((mainText ?? '').trim().isNotEmpty) {
            primary = mainText!.trim();
            secondary =
                (secText ?? '').trim().isEmpty ? null : secText!.trim();
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
          ));
        }
      }

      for (final v in expanded) {
        if (v.trim().isEmpty) continue;
        final params = <String, String>{...baseParams, 'input': v.trim()};
        final uri = Uri.https(
          'maps.googleapis.com',
          '/maps/api/place/autocomplete/json',
          params,
        );
        parseAndAdd(await _getJson(uri));
        if (remotes.length >= 15) break;
      }

      final out = <PrediccionLugar>[];
      final seenPrimary = <String>{};
      for (final p in [...locals, ...remotes]) {
        final k = '${p.placeId}|${_norm(p.primary)}';
        if (seenPrimary.contains(k)) continue;
        seenPrimary.add(k);
        out.add(p);
      }
      // Solo ofrecer texto libre si Google no devolvió sugerencias (evita duplicar la lista).
      if (remotes.isEmpty && cq.length >= 2) {
        out.add(PrediccionLugar(placeId: q, primary: q, secondary: country));
      }
      return out;
    } catch (_) {
      return [...locals, PrediccionLugar(placeId: q, primary: q, secondary: country)];
    }
  }

  Future<DetalleLugar?> detalle(String placeId) async {
    final pid = placeId.trim();
    if (pid.isEmpty) {
      return null;
    }

    if (pid.startsWith('local:poi:')) {
      final code = pid.split(':').last;
      final found = _ALL_LOCAL.where((p) => p.id == code);
      if (found.isNotEmpty) {
        final p = found.first;
        return DetalleLugar(placeId: pid, name: p.name, address: p.address, lat: p.lat, lon: p.lon);
      }
    }

    if (!_placesEnabled) {
      try {
        final locs = await geocoding.locationFromAddress(pid);
        if (locs.isEmpty) {
          return null;
        }
        final loc = locs.first;

        final marks = await geocoding.placemarkFromCoordinates(loc.latitude, loc.longitude);

        String name = pid;
        String? addr;
        if (marks.isNotEmpty) {
          final fm = _formatearPlacemarkRD(marks.first);
          name = fm.titulo;
          addr = fm.resto;
        }
        return DetalleLugar(placeId: pid, name: name, address: addr, lat: loc.latitude, lon: loc.longitude);
      } catch (_) {
        return null;
      }
    }

    try {
      final uri = Uri.https('maps.googleapis.com','/maps/api/place/details/json',<String,String>{
        'place_id': pid,
        'fields': 'name,formatted_address,geometry,address_components',
        'language': 'es',
        'key': app_keys.kGooglePlacesApiKey,
      });
      final json = await _getJson(uri);
      if (json == null) {
        return null;
      }
      final status = (json['status'] ?? '').toString();
      if (status != 'OK') {
        return null;
      }

      final r = json['result'] as Map<String, dynamic>?;
      if (r == null) {
        return null;
      }

      final geometry = r['geometry'] as Map<String, dynamic>?;
      final loc = geometry?['location'] as Map<String, dynamic>?;
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lon = (loc?['lng'] as num?)?.toDouble();
      if (lat == null || lon == null) {
        return null;
      }

      final formatted = (r['formatted_address'] ?? '').toString().trim();
      final name = (r['name'] ?? '').toString().trim();

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

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) {
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  _FormattedRD _formatearPlacemarkRD(geocoding.Placemark p) {
    final calle = [(p.thoroughfare ?? '').trim(), (p.subThoroughfare ?? '').trim()]
        .where((s) => s.isNotEmpty).join(' ').trim();
    final sector = (p.subLocality ?? '').trim();
    final ciudad = ((p.locality ?? '').trim().isNotEmpty ? p.locality!.trim() : (p.subAdministrativeArea ?? '').trim()).trim();
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
