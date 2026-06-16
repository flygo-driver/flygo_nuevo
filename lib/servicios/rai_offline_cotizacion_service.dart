import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';
import 'package:flygo_nuevo/servicios/rai_connectivity_service.dart';

/// Resultado de distancia para cotizar (online con Directions o estimado local).
class RaiDistanciaCotizacion {
  const RaiDistanciaCotizacion({
    required this.km,
    required this.estimadoOffline,
    this.directions,
  });

  final double km;
  final bool estimadoOffline;
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

  /// Distancia para cotizar: sin red usa haversine; con red intenta Directions.
  static Future<RaiDistanciaCotizacion?> resolverDistancia({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    bool useDirections = true,
    bool withTraffic = true,
    String region = 'do',
  }) async {
    final double haversine = DistanciaService.calcularDistancia(
      originLat,
      originLon,
      destLat,
      destLon,
    );
    if (haversine <= 0 || DistanciaService.tramoEsImposible(haversine)) {
      return null;
    }

    if (estaOffline || !useDirections) {
      return RaiDistanciaCotizacion(
        km: haversine,
        estimadoOffline: estaOffline,
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
      );
      if (dir != null && dir.km > 0) {
        return RaiDistanciaCotizacion(
          km: dir.km,
          estimadoOffline: false,
          directions: dir,
        );
      }
    } catch (_) {
      // Fallback local si Directions falla con red inestable.
    }

    return RaiDistanciaCotizacion(
      km: haversine,
      estimadoOffline: false,
    );
  }
}
