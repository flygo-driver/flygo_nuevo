import 'package:flygo_nuevo/servicios/lugares_service.dart';
import 'package:flygo_nuevo/servicios/rai_asistente_kb.dart';
import 'package:flygo_nuevo/servicios/rai_asistente_service.dart';
import 'package:geocoding/geocoding.dart';

/// Resultado de resolver una dirección compleja → coordenadas para cotizar.
class RaiDireccionResolucion {
  const RaiDireccionResolucion({
    required this.lugares,
    required this.queriesUsadas,
    this.mejor,
  });

  final List<DetalleLugar> lugares;
  final List<String> queriesUsadas;
  final DetalleLugar? mejor;

  bool get encontroAlgo => lugares.isNotEmpty;
}

/// Búsqueda inteligente: IA normaliza + Google Places + geocoding de respaldo.
class RaiBusquedaDireccionInteligente {
  RaiBusquedaDireccionInteligente._();

  static final RaiBusquedaDireccionInteligente instance =
      RaiBusquedaDireccionInteligente._();

  /// Resuelve descripción libre del cliente a lugares con lat/lon para tarifa exacta.
  Future<RaiDireccionResolucion> resolver({
    required String descripcion,
    double? biasLat,
    double? biasLon,
    bool usarIa = true,
  }) async {
    final base = descripcion.trim();
    if (base.length < 2) {
      return const RaiDireccionResolucion(lugares: [], queriesUsadas: []);
    }

    final queries = await _variantesBusqueda(base, usarIa: usarIa);
    final lugares = <DetalleLugar>[];
    final seen = <String>{};

    for (final q in queries) {
      final batch = await _buscarPlaces(
        q,
        biasLat: biasLat,
        biasLon: biasLon,
      );
      for (final d in batch) {
        final key =
            '${d.lat.toStringAsFixed(5)}|${d.lon.toStringAsFixed(5)}|${_norm(d.displayLabel)}';
        if (seen.add(key)) lugares.add(d);
      }
      if (lugares.length >= 6) break;
    }

    if (lugares.isEmpty) {
      for (final q in queries) {
        final geo = await _geocodeFallback(q);
        if (geo != null) {
          final key =
              '${geo.lat.toStringAsFixed(5)}|${geo.lon.toStringAsFixed(5)}';
          if (seen.add(key)) lugares.add(geo);
        }
        if (lugares.isNotEmpty) break;
      }
    }

    return RaiDireccionResolucion(
      lugares: lugares,
      queriesUsadas: queries,
      mejor: lugares.isNotEmpty ? lugares.first : null,
    );
  }

  Future<List<String>> _variantesBusqueda(
    String base, {
    required bool usarIa,
  }) async {
    final out = <String>[];
    void add(String? s) {
      final t = (s ?? '').trim();
      if (t.length < 2) return;
      if (!out.any((e) => _norm(e) == _norm(t))) out.add(t);
    }

    add(base);
    add(RaiAsistenteKb.normalizarBusquedaDireccionPublica(base));

    final lower = base.toLowerCase();
    if (!lower.contains('república dominicana') &&
        !lower.contains('republica dominicana') &&
        !lower.contains(', rd')) {
      add('$base, República Dominicana');
      add('$base, Santo Domingo');
    }

    if (base.contains(',')) {
      add(base.split(',').first.trim());
      if (base.split(',').length >= 2) {
        add(base.split(',').take(2).join(', ').trim());
      }
    }

    if (usarIa) {
      try {
        final resp = await RaiAsistenteService.instance.preguntar(
          message:
              'Solo normaliza esta dirección en RD para Google Places (responde JSON): «$base»',
        );
        add(resp.addressQuery);
        for (final q in resp.addressQueries) {
          add(q);
        }
      } catch (_) {}
    }

    return out.take(8).toList(growable: false);
  }

  Future<List<DetalleLugar>> _buscarPlaces(
    String query, {
    double? biasLat,
    double? biasLon,
  }) async {
    final preds = await LugaresService.instance.autocompletar(
      query,
      country: 'República Dominicana',
      biasLat: biasLat,
      biasLon: biasLon,
    );

    final out = <DetalleLugar>[];
    for (final p in preds.take(6)) {
      if (p.placeId.startsWith('recent:')) continue;
      final det = await LugaresService.instance.detalleDesdePrediccion(p);
      if (det != null && det.lat.abs() > 0.000001 && det.lon.abs() > 0.000001) {
        out.add(det);
      }
      if (out.length >= 4) break;
    }
    return out;
  }

  Future<DetalleLugar?> _geocodeFallback(String query) async {
    final intentos = <String>{
      query.trim(),
      '${query.trim()}, República Dominicana',
      '${query.trim()}, Dominican Republic',
    }.where((e) => e.length >= 3).toList();

    for (final q in intentos) {
      try {
        final results = await locationFromAddress(q);
        if (results.isEmpty) continue;
        final p = results.first;
        if (p.latitude.abs() < 0.000001 && p.longitude.abs() < 0.000001) {
          continue;
        }
        return DetalleLugar(
          placeId: 'geocoded:${_norm(q)}',
          name: query.trim(),
          address: q,
          lat: p.latitude,
          lon: p.longitude,
        );
      } catch (_) {}
    }
    return null;
  }

  static String _norm(String s) => s.toLowerCase().trim();
}
