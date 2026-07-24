import 'dart:async';

import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/rai_connectivity_service.dart';

/// Resultado de distancia para cotizar (online con Directions o estimado local).
class RaiDistanciaCotizacion {
  const RaiDistanciaCotizacion({
    required this.km,
    required this.estimadoOffline,
    this.directions,
    this.fuente = 'desconocida',
  });

  final double km;
  final bool estimadoOffline;

  /// `directions` = Google carretera; `haversine` = línea recta (offline/fallback).
  final String fuente;
  final DirectionsResult? directions;
}

/// Cotización offline inteligente: GPS + línea recta + tarifas locales/caché.
/// No confirma viajes sin internet — solo evita pantalla bloqueada sin precio.
class RaiOfflineCotizacionService {
  RaiOfflineCotizacionService._();

  static const String mensajeBannerEstimado =
      'Precio estimado sin internet (distancia aproximada). '
      'Para confirmar el viaje necesitas conexión.';

  static const String mensajeNoConfirmar =
      'Sin internet no puedes confirmar el viaje. '
      'El precio mostrado es solo referencia hasta que vuelva la conexión.';

  static bool get estaOffline => RaiConnectivityService.instance.isOffline;

  static bool _kmValido(double km, double maxKm) =>
      km.isFinite && km > 0 && !DistanciaService.tramoEsImposible(km, maxKm: maxKm);

  /// Distancia para cotizar: con red usa **km por carretera** (Directions); sin red, haversine.
  static Future<RaiDistanciaCotizacion?> resolverDistancia({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    bool useDirections = true,
    bool withTraffic = true,
    String region = 'do',
    double maxKmCotizable = DistanciaService.maxKmCotizableDefault,
  }) async {
    final double haversine = DistanciaService.calcularDistancia(
      originLat,
      originLon,
      destLat,
      destLon,
    );
    if (haversine <= 0) return null;

    if (estaOffline || !useDirections) {
      if (!_kmValido(haversine, maxKmCotizable)) return null;
      return RaiDistanciaCotizacion(
        km: haversine,
        estimadoOffline: estaOffline,
        fuente: 'haversine',
      );
    }

    try {
      final DirectionsResult? dir = await DirectionsService.drivingDistanceKm(
        originLat: originLat,
        originLon: originLon,
        destLat: destLat,
        destLon: destLon,
        withTraffic: withTraffic,
        region: region,
      ).timeout(const Duration(seconds: 14));
      if (dir != null && dir.km > 0 && _kmValido(dir.km, maxKmCotizable)) {
        return RaiDistanciaCotizacion(
          km: dir.km,
          estimadoOffline: false,
          directions: dir,
          fuente: 'directions',
        );
      }
    } catch (_) {
      // Timeout / red inestable → haversine (no congelar "Calculando precio…").
    }

    if (!_kmValido(haversine, maxKmCotizable)) return null;
    return RaiDistanciaCotizacion(
      km: haversine,
      estimadoOffline: false,
      fuente: 'haversine',
    );
  }
}
