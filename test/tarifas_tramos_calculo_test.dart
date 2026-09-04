import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/modelo/tarifas_tramos_config.dart';
import 'package:flygo_nuevo/servicios/tarifas_tramos_calculo.dart';

void main() {
  final tramos = TarifasTramosConfig.defaultsPrueba().copyWithActivo(true);

  test('viaje local 12 km mantiene precio bajo', () {
    final r = TarifasTramosCalculo.calcular(
      distanciaKm: 12,
      baseRd: 50,
      porKmLocal: 22,
      minimoLocalRd: 150,
      tramos: tramos,
      claveVehiculo: 'Carro',
    );
    expect(r.nucleoRd, 314);
    expect(r.desglose['esLargaDistancia'], false);
  });

  test('viaje corto bajo 2 km aplica minimo 150', () {
    final r = TarifasTramosCalculo.calcular(
      distanciaKm: 1.5,
      baseRd: 50,
      porKmLocal: 22,
      minimoLocalRd: 150,
      tramos: tramos,
      claveVehiculo: 'Carro',
    );
    expect(r.nucleoRd, 150);
    expect(r.desglose['minimoAplicadoRd'], 150);
  });

  test('viaje desde 2 km aplica minimo 175', () {
    final r = TarifasTramosCalculo.calcular(
      distanciaKm: 2,
      baseRd: 50,
      porKmLocal: 22,
      minimoLocalRd: 150,
      tramos: tramos,
      claveVehiculo: 'Carro',
    );
    expect(r.nucleoRd, 175);
    expect(r.desglose['minimoAplicadoRd'], 175);
  });

  test('viaje 3 km sube al minimo 175 si calculo queda bajo', () {
    final r = TarifasTramosCalculo.calcular(
      distanciaKm: 3,
      baseRd: 50,
      porKmLocal: 22,
      minimoLocalRd: 150,
      tramos: tramos,
      claveVehiculo: 'Carro',
    );
    expect(r.nucleoRd, 175);
    expect(r.desglose['minimoAplicadoRd'], 175);
  });

  test('viaje 165 km aplica tramo 140+ sin tope artificial', () {
    final r = TarifasTramosCalculo.calcular(
      distanciaKm: 165,
      baseRd: 50,
      porKmLocal: 22,
      minimoLocalRd: 150,
      tramos: tramos,
      claveVehiculo: 'Carro',
    );
    expect(r.desglose['esLargaDistancia'], true);
    expect(r.nucleoRd, greaterThan(7000));
    final lineas = r.desglose['lineas'] as List;
    expect(lineas.length, 4);
    final ultima = lineas.last as Map;
    expect((ultima['km'] as num).toDouble(), 25); // 165-140
  });

  test('viaje 250 km sigue acumulando en tramo final', () {
    final r = TarifasTramosCalculo.calcular(
      distanciaKm: 250,
      baseRd: 50,
      porKmLocal: 22,
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
