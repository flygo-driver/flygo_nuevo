import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/utils/rai_region_operativa.dart';

/// Lugar frecuente aprendido de viajes FlyGo (por región).
class LugarPopularFlygo {
  const LugarPopularFlygo({
    required this.id,
    required this.label,
    required this.placeId,
    required this.lat,
    required this.lon,
    required this.count,
    required this.region,
    required this.tipo,
  });

  final String id;
  final String label;
  final String placeId;
  final double lat;
  final double lon;
  final int count;
  final String region;
  final String tipo;
}

/// Ranking de lugares por zona — mejora el buscador con experiencia real FlyGo.
class LugaresPopularesService {
  LugaresPopularesService._();

  static final LugaresPopularesService instance = LugaresPopularesService._();

  static const Duration _cacheTtl = Duration(hours: 6);
  static const int _maxCache = 48;

  List<LugarPopularFlygo> _cache = const [];
  String? _regionCache;
  DateTime? _ultimaCarga;
  Future<void>? _cargaEnCurso;

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

  Future<void> precargarParaUbicacion({
    double? lat,
    double? lon,
  }) async {
    if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) return;
    final region = RaiRegionOperativa.resolver(lat, lon);
    if (_regionCache == region &&
        _ultimaCarga != null &&
        DateTime.now().difference(_ultimaCarga!) < _cacheTtl &&
        _cache.isNotEmpty) {
      return;
    }
    if (_cargaEnCurso != null) {
      await _cargaEnCurso;
      return;
    }
    _cargaEnCurso = _cargarDesdeFirestore(region);
    try {
      await _cargaEnCurso;
    } finally {
      _cargaEnCurso = null;
    }
  }

  Future<void> _cargarDesdeFirestore(String region) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('lugares_populares_flygo')
          .where('region', isEqualTo: region)
          .orderBy('count', descending: true)
          .limit(_maxCache)
          .get();

      final list = <LugarPopularFlygo>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final lat = (d['lat'] as num?)?.toDouble();
        final lon = (d['lon'] as num?)?.toDouble();
        final label = (d['label'] ?? '').toString().trim();
        if (lat == null || lon == null || label.isEmpty) continue;
        list.add(
          LugarPopularFlygo(
            id: doc.id,
            label: label,
            placeId: (d['placeId'] ?? '').toString().trim(),
            lat: lat,
            lon: lon,
            count: (d['count'] as num?)?.round() ?? 1,
            region: (d['region'] ?? region).toString(),
            tipo: (d['tipo'] ?? 'destino').toString(),
          ),
        );
      }
      _cache = list;
      _regionCache = region;
      _ultimaCarga = DateTime.now();
    } catch (_) {
      // Sin índice o sin red: el buscador sigue con Google + catálogo local.
    }
  }

  /// Registra selección en mapa/buscador (refuerzo antes de crear viaje).
  Future<void> registrarSeleccion({
    required DetalleLugar det,
    required bool esOrigen,
  }) async {
    if (kIsWeb) return;
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('registrarLugarPopularSeleccion');
      unawaited(
        fn.call(<String, dynamic>{
          'label': det.displayLabel,
          'lat': det.lat,
          'lon': det.lon,
          'placeId': det.placeId,
          'tipo': esOrigen ? 'origen' : 'destino',
        }),
      );
    } catch (_) {}
  }

  /// Bonus de ranking estilo Uber (viajes reales en la zona).
  int boostParaPrediccion(PrediccionLugar p) {
    if (_cache.isEmpty) return 0;
    final pid = p.placeId.trim();
    final primary = _norm(p.primary);
    final secondary = _norm(p.secondary ?? '');

    for (final pop in _cache) {
      var score = 0;
      if (pid.isNotEmpty &&
          pop.placeId.isNotEmpty &&
          pid == pop.placeId) {
        score = 40 + _bonusPorConteo(pop.count);
      } else if (primary.isNotEmpty &&
          _norm(pop.label) == primary) {
        score = 32 + _bonusPorConteo(pop.count);
      } else if (primary.isNotEmpty &&
          _norm(pop.label).contains(primary)) {
        score = 22 + _bonusPorConteo(pop.count);
      } else if (secondary.isNotEmpty &&
          _norm(pop.label).contains(secondary)) {
        score = 14 + _bonusPorConteo(pop.count);
      }

      if (p.lat != null &&
          p.lon != null &&
          (p.lat! - pop.lat).abs() < 0.0008 &&
          (p.lon! - pop.lon).abs() < 0.0008) {
        score = mathMax(score, 28 + _bonusPorConteo(pop.count));
      }

      if (score > 0) return score;
    }
    return 0;
  }

  int _bonusPorConteo(int count) {
    if (count >= 500) return 35;
    if (count >= 100) return 28;
    if (count >= 30) return 20;
    if (count >= 10) return 12;
    if (count >= 3) return 6;
    return 2;
  }

  int mathMax(int a, int b) => a > b ? a : b;

  /// Sugerencias FlyGo que coinciden con el texto (antes de Google).
  List<PrediccionLugar> sugerenciasParaQuery(
    String query, {
    String tipoPreferido = 'destino',
    int max = 6,
  }) {
    final nq = _norm(query.trim());
    if (nq.isEmpty || _cache.isEmpty) return const [];

    final scored = <({LugarPopularFlygo pop, int score})>[];
    for (final pop in _cache) {
      if (tipoPreferido.isNotEmpty &&
          pop.tipo.isNotEmpty &&
          pop.tipo != tipoPreferido) {
        continue;
      }
      final nl = _norm(pop.label);
      var score = 0;
      if (nl.startsWith(nq)) {
        score = 90;
      } else if (nl.contains(nq)) {
        score = 55;
      } else {
        final tokens = nq
            .split(RegExp(r'[\s,#]+'))
            .where((t) => t.length >= 2)
            .toList();
        for (final t in tokens) {
          if (nl.contains(t)) score += 18;
        }
      }
      if (score > 0) {
        score += _bonusPorConteo(pop.count);
        scored.add((pop: pop, score: score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(max).map((e) {
      final pop = e.pop;
      final pid = pop.placeId.isNotEmpty
          ? pop.placeId
          : 'flygo_popular:${pop.id}';
      return PrediccionLugar(
        placeId: pid,
        primary: pop.label,
        secondary: 'Frecuente en FlyGo · ${RaiRegionOperativa.etiqueta(pop.region)}',
        lat: pop.lat,
        lon: pop.lon,
      );
    }).toList(growable: false);
  }

  DetalleLugar? detalleDesdePlaceId(String placeId) {
    if (!placeId.startsWith('flygo_popular:')) return null;
    final id = placeId.substring('flygo_popular:'.length);
    for (final pop in _cache) {
      if (pop.id != id) continue;
      return DetalleLugar(
        placeId: pop.placeId.isNotEmpty ? pop.placeId : placeId,
        name: pop.label,
        address: 'Frecuente en FlyGo · ${RaiRegionOperativa.etiqueta(pop.region)}',
        lat: pop.lat,
        lon: pop.lon,
      );
    }
    return null;
  }
}
