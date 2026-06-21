import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/modelo/tarifas_tramos_config.dart';
import 'package:flygo_nuevo/servicios/tarifas_tramos_calculo.dart';

void main() {
  final tramos = TarifasTramosConfig.defaultsPrueba().copyWithActivo(true);

  test('viaje local 12 km mantiene precio bajo', () {
    final r = TarifasTramosCalculo.calcular(
      distanciaKm: 12,
      baseRd: 50,
      porKmLocal: 25,
      minimoLocalRd: 150,
      tramos: tramos,
      claveVehiculo: 'Carro',
    );
    expect(r.nucleoRd, 350);
    expect(r.desglose['esLargaDistancia'], false);
  });

  test('viaje 165 km aplica tramo 140+ sin tope artificial', () {
    final r = TarifasTramosCalculo.calcular(
      distanciaKm: 165,
      baseRd: 50,
      porKmLocal: 25,
      minimoLocalRd: 150,
      tramos: tramos,
      claveVehiculo: 'Carro',
    );
    expect(r.desglose['esLargaDistancia'], true);
    expect(r.nucleoRd, greaterThan(8000));
    final lineas = r.desglose['lineas'] as List;
    expect(lineas.length, 4);
    final ultima = lineas.last as Map;
    expect((ultima['km'] as num).toDouble(), 25); // 165-140
  });

  test('viaje 250 km sigue acumulando en tramo final', () {
    final r = TarifasTramosCalculo.calcular(
      distanciaKm: 250,
      baseRd: 50,
      porKmLocal: 25,
      minimoLocalRd: 150,
      tramos: tramos,
      claveVehiculo: 'Carro',
    );
    expect(r.nucleoRd, greaterThan(12000));
    final lineas = r.desglose['lineas'] as List;
    final ultima = lineas.last as Map;
    expect((ultima['km'] as num).toDouble(), 110); // 250-140
  });
}

extension on TarifasTramosConfig {
  TarifasTramosConfig copyWithActivo(bool activo) => TarifasTramosConfig(
        activo: activo,
        tramosKm: tramosKm,
        minimoLargaDistanciaRd: minimoLargaDistanciaRd,
        promoAplicaSoloTramoLocal: promoAplicaSoloTramoLocal,
        porVehiculo: porVehiculo,
        distanciaMaximaCotizableKm: distanciaMaximaCotizableKm,
      );
}
