import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/tarifa_urbana_tiempo.dart';

void main() {
  DirectionsResult ruta({
    required double km,
    required int minLibre,
    required int minTrafico,
  }) {
    return DirectionsResult(
      km: km,
      seconds: minLibre * 60,
      secondsInTraffic: minTrafico * 60,
    );
  }

  test('sambil a 8 independencia con tapón ~30 min', () {
    // ~11 km, 16 min libre, 30 min con tráfico (hora pico)
    final res = TarifaUrbanaTiempo.calcular(
      directions: ruta(km: 11, minLibre: 16, minTrafico: 30),
      baseRd: 50,
      porKmLocal: 22,
      minimoLocalRd: 150,
      claveVehiculo: 'Carro',
    );
    expect(res.nucleoRd, greaterThan(300));
    expect(res.nucleoRd, lessThan(400));
    expect(res.desglose['minutosConTrafico'], 30);
    expect(res.desglose['traficoFluido'], isFalse);
  });

  test('mismo trayecto domingo sin tapón baja precio', () {
    final pico = TarifaUrbanaTiempo.calcular(
      directions: ruta(km: 11, minLibre: 16, minTrafico: 30),
      baseRd: 50,
      porKmLocal: 22,
      minimoLocalRd: 150,
      claveVehiculo: 'Carro',
    );
    final domingo = TarifaUrbanaTiempo.calcular(
      directions: ruta(km: 11, minLibre: 16, minTrafico: 17),
      baseRd: 50,
      porKmLocal: 22,
      minimoLocalRd: 150,
      claveVehiculo: 'Carro',
    );
    expect(domingo.nucleoRd, lessThan(pico.nucleoRd));
    expect(domingo.desglose['traficoFluido'], isTrue);
    expect(domingo.desglose['descuentoTraficoFluidoPct'], 7.0);
  });

  test('viaje corto respeta mínimo 175 desde 2 km', () {
    final res = TarifaUrbanaTiempo.calcular(
      directions: ruta(km: 2.2, minLibre: 8, minTrafico: 9),
      baseRd: 50,
      porKmLocal: 22,
      minimoLocalRd: 150,
      claveVehiculo: 'Carro',
    );
    expect(res.nucleoRd, greaterThanOrEqualTo(175));
  });
}
