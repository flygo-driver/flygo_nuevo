import '../modelo/tarifas_dinamicas_config.dart';
import '../modelo/tarifas_tramos_config.dart';
import 'directions_service.dart';
import 'tarifas_tramos_calculo.dart';

/// Tarifa urbana: distancia por carretera + minutos con tráfico (Google).
/// RD$/min sube con la severidad del tapón; sin tapón aplica descuento fluido.
class TarifaUrbanaTiempoResult {
  const TarifaUrbanaTiempoResult({
    required this.nucleoRd,
    required this.desglose,
  });

  final double nucleoRd;
  final Map<String, dynamic> desglose;
}

abstract final class TarifaUrbanaTiempo {
  TarifaUrbanaTiempo._();

  static double porMinutoParaVehiculo(String claveVehiculo, double ratio) {
    return TarifasDinamicasConfig.porMinutoDesdeRatio(
      ratio: ratio,
      claveVehiculo: claveVehiculo,
    );
  }

  /// Núcleo urbano con km + minutos reales. Requiere [DirectionsResult] con tráfico.
  static TarifaUrbanaTiempoResult calcular({
    required DirectionsResult directions,
    required double baseRd,
    required double porKmLocal,
    required double minimoLocalRd,
    required String claveVehiculo,
    double? minimoDesdeUmbralUrbanoRd,
    double umbralMinimoUrbanoKm = TarifasTramosCalculo.kmUmbralMinimoUrbano,
  }) {
    final km = directions.km.isFinite && directions.km > 0
        ? directions.km
        : 0.0;
    final int segLibre = directions.seconds > 0 ? directions.seconds : 0;
    final int segTraf = directions.secondsInTraffic ?? directions.seconds;
    final double minLibre =
        segLibre > 0 ? segLibre / 60.0 : 0.0;
    final double minTraf =
        segTraf > 0 ? segTraf / 60.0 : minLibre;
    final double ratio =
        minLibre > 0 ? (minTraf / minLibre) : 1.0;

    final double subtotalKm = baseRd + (km * porKmLocal);
    final double porMin = porMinutoParaVehiculo(claveVehiculo, ratio);
    final double subtotalTiempo = minTraf * porMin;

    var nucleo = subtotalKm + subtotalTiempo;
    final double antesDescuento = nucleo;

    final bool traficoFluido = ratio.isFinite &&
        ratio > 0 &&
        ratio < TarifasDinamicasConfig.ratioTraficoFluidoMax;
    double descuentoPct = 0;
    if (traficoFluido) {
      descuentoPct = TarifasDinamicasConfig.descuentoTraficoFluidoPct;
      nucleo *= 1.0 - (descuentoPct / 100.0);
    }

    final minimoUrbano = minimoDesdeUmbralUrbanoRd ??
        TarifasTramosCalculo.minimoDesdeUmbralUrbanoPara(claveVehiculo);
    final minimoRd = TarifasTramosCalculo.resolverMinimoAplicado(
      km: km,
      minimoLocalRd: minimoLocalRd,
      minimoLargaDistanciaRd: minimoLocalRd,
      umbralLargaKm: double.infinity,
      minimoDesdeUmbralUrbano: minimoUrbano,
      umbralMinimoUrbanoKm: umbralMinimoUrbanoKm,
    );

    final antesMinimo = nucleo;
    if (nucleo < minimoRd) nucleo = minimoRd;

    final int minExtra =
        (minTraf - minLibre).ceil().clamp(0, 999);

    final String severidadTrafico = traficoFluido
        ? 'fluido'
        : ratio < TarifasDinamicasConfig.ratioTaponModerado
            ? 'leve'
            : ratio < TarifasDinamicasConfig.ratioTaponFuerte
                ? 'moderado'
                : 'fuerte';

    return TarifaUrbanaTiempoResult(
      nucleoRd: double.parse(nucleo.toStringAsFixed(2)),
      desglose: <String, dynamic>{
        'modo': 'urbano_tiempo',
        'zonaUrbana': true,
        'distanciaKm': double.parse(km.toStringAsFixed(2)),
        'distanciaMedidaKm': double.parse(km.toStringAsFixed(2)),
        'baseRd': double.parse(baseRd.toStringAsFixed(2)),
        'porKm': porKmLocal,
        'subtotalKmRd': double.parse(subtotalKm.toStringAsFixed(2)),
        'porMinutoTrafico': porMin,
        'severidadTrafico': severidadTrafico,
        'minutosSinTrafico': minLibre.ceil(),
        'minutosConTrafico': minTraf.ceil(),
        'minutosExtraTapon': minExtra,
        'ratioTrafico': double.parse(ratio.toStringAsFixed(3)),
        'subtotalTiempoRd': double.parse(subtotalTiempo.toStringAsFixed(2)),
        'traficoFluido': traficoFluido,
        'descuentoTraficoFluidoPct':
            traficoFluido ? descuentoPct : 0.0,
        'antesDescuentoFluidoRd':
            double.parse(antesDescuento.toStringAsFixed(2)),
        'minimoAplicadoRd': double.parse(minimoRd.toStringAsFixed(2)),
        'minimoForzado': nucleo > antesMinimo + 1e-6,
        'esLargaDistancia': false,
        'nucleoRd': double.parse(nucleo.toStringAsFixed(2)),
      },
    );
  }
}
