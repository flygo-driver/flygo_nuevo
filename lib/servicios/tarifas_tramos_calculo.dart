import '../modelo/tarifas_tramos_config.dart';

/// Resultado del núcleo tarifario (antes peaje, ida/vuelta y promo).
class TarifaNucleoResult {
  const TarifaNucleoResult({
    required this.nucleoRd,
    required this.desglose,
    required this.usoTramos,
  });

  final double nucleoRd;
  final Map<String, dynamic> desglose;
  final bool usoTramos;
}

/// Cálculo puro de tramos — no toca Firestore ni promos.
abstract final class TarifasTramosCalculo {
  static TarifaNucleoResult calcular({
    required double distanciaKm,
    required double baseRd,
    required double porKmLocal,
    required double minimoLocalRd,
    required TarifasTramosConfig tramos,
    required String claveVehiculo,
  }) {
    final km = distanciaKm.isFinite && distanciaKm > 0 ? distanciaKm : 0.0;

    if (!tramos.activo || km <= 0) {
      return _lineal(
        km: km,
        baseRd: baseRd,
        porKm: porKmLocal,
        minimoRd: minimoLocalRd,
        modo: 'lineal',
      );
    }

    final expectedBands = tramos.tramosKm.length + 1;
    final claveNorm = TarifasTramosConfig.normalizarClaveVehiculo(claveVehiculo);
    var rates = tramos.ratesFor(claveNorm, porKmLocal: porKmLocal) ??
        tramos.ratesFor(claveVehiculo, porKmLocal: porKmLocal) ??
        TarifasTramosConfig.defaultRatesFor(
          porKmLocal: porKmLocal,
          tramos: tramos.tramosKm,
        );
    if (rates.length != expectedBands) {
      rates = TarifasTramosConfig.defaultRatesFor(
        porKmLocal: porKmLocal,
        tramos: tramos.tramosKm,
      );
    }

    final lineas = <Map<String, dynamic>>[];
    var kmRestante = km;
    var cursor = 0.0;
    var subtotalKm = 0.0;

    final etiquetas = tramos.etiquetasTramos();

    for (var i = 0; i < expectedBands; i++) {
      if (kmRestante <= 1e-9) break;
      final upper = i < tramos.tramosKm.length ? tramos.tramosKm[i] : double.infinity;
      final ancho = upper.isFinite ? (upper - cursor).clamp(0.0, double.infinity) : kmRestante;
      final kmTramo = kmRestante < ancho ? kmRestante : ancho;
      if (kmTramo <= 1e-9) {
        if (upper.isFinite) cursor = upper;
        continue;
      }
      final importe = kmTramo * rates[i];
      subtotalKm += importe;
      lineas.add(<String, dynamic>{
        'indice': i,
        'etiquetaTramo': i < etiquetas.length ? etiquetas[i] : 'Tramo $i',
        'desdeKm': double.parse(cursor.toStringAsFixed(2)),
        'hastaKm': double.parse((cursor + kmTramo).toStringAsFixed(2)),
        'km': double.parse(kmTramo.toStringAsFixed(2)),
        'porKm': rates[i],
        'importeRd': double.parse(importe.toStringAsFixed(2)),
      });
      kmRestante -= kmTramo;
      cursor += kmTramo;
      if (upper.isFinite && cursor >= upper - 1e-9) cursor = upper;
    }

    var nucleo = baseRd + subtotalKm;
    final bool esLarga = km > tramos.tramosKm.first;
    final minimoAplicado = esLarga ? tramos.minimoLargaDistanciaRd : minimoLocalRd;
    final antesMinimo = nucleo;
    if (nucleo < minimoAplicado) nucleo = minimoAplicado;

    return TarifaNucleoResult(
      nucleoRd: double.parse(nucleo.toStringAsFixed(2)),
      usoTramos: true,
      desglose: <String, dynamic>{
        'modo': 'tramos',
        'distanciaKm': double.parse(km.toStringAsFixed(2)),
        'distanciaMedidaKm': double.parse(km.toStringAsFixed(2)),
        'claveVehiculo': claveNorm.isNotEmpty ? claveNorm : claveVehiculo,
        'baseRd': double.parse(baseRd.toStringAsFixed(2)),
        'subtotalKmRd': double.parse(subtotalKm.toStringAsFixed(2)),
        'minimoAplicadoRd': double.parse(minimoAplicado.toStringAsFixed(2)),
        'minimoForzado': nucleo > antesMinimo + 1e-6,
        'esLargaDistancia': esLarga,
        'tramosKm': tramos.tramosKm,
        'lineas': lineas,
        'nucleoRd': double.parse(nucleo.toStringAsFixed(2)),
      },
    );
  }

  static TarifaNucleoResult _lineal({
    required double km,
    required double baseRd,
    required double porKm,
    required double minimoRd,
    required String modo,
  }) {
    var nucleo = baseRd + (km * porKm);
    final antes = nucleo;
    if (nucleo < minimoRd) nucleo = minimoRd;
    return TarifaNucleoResult(
      nucleoRd: double.parse(nucleo.toStringAsFixed(2)),
      usoTramos: false,
      desglose: <String, dynamic>{
        'modo': modo,
        'distanciaKm': double.parse(km.toStringAsFixed(2)),
        'baseRd': double.parse(baseRd.toStringAsFixed(2)),
        'porKm': porKm,
        'subtotalKmRd': double.parse((km * porKm).toStringAsFixed(2)),
        'minimoAplicadoRd': double.parse(minimoRd.toStringAsFixed(2)),
        'minimoForzado': nucleo > antes + 1e-6,
        'esLargaDistancia': false,
        'nucleoRd': double.parse(nucleo.toStringAsFixed(2)),
      },
    );
  }
}
