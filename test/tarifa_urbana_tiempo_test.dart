import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/modelo/recargo_condiciones_cotizacion.dart';
import 'package:flygo_nuevo/servicios/directions_service.dart';
import 'package:flygo_nuevo/servicios/recargo_condiciones_service.dart';
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

  test('sambil a juan baron con tapón ~30 min sube con tráfico fuerte', () {
    final res = TarifaUrbanaTiempo.calcular(
      directions: ruta(km: 11, minLibre: 16, minTrafico: 30),
      baseRd: 50,
      porKmLocal: 22,
      minimoLocalRd: 150,
      claveVehiculo: 'Carro',
    );
    expect(res.nucleoRd, greaterThan(400));
    expect(res.nucleoRd, lessThan(500));
    expect(res.desglose['minutosConTrafico'], 30);
    expect(res.desglose['traficoFluido'], isFalse);
    expect(res.desglose['severidadTrafico'], 'fuerte');
  });

  test('sambil a alcarrizos con tapón largo sube precio urbano', () {
    final res = TarifaUrbanaTiempo.calcular(
      directions: ruta(km: 16, minLibre: 28, minTrafico: 48),
      baseRd: 50,
      porKmLocal: 22,
      minimoLocalRd: 150,
      claveVehiculo: 'Carro',
    );
    expect(res.nucleoRd, greaterThan(580));
    expect(res.nucleoRd, lessThan(720));
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

  test('recargo multiplicativo lluvia y hora pico sobre urbano', () {
    const base = RecargoCondicionesCotizacion(
      horaPico: true,
      lluvia: true,
      tapon: true,
      pctHoraPico: 0,
      pctLluvia: 0,
      pctTapon: 0,
      pctTotal: 0,
      recargoRd: 0,
      precioAntesRecargoRd: 0,
      precioDespuesRecargoRd: 0,
      modoRecargo: 'multiplicativo',
    );
    final aplicado = RecargoCondicionesService.aplicar(base: base, precioRd: 424);
    expect(aplicado.factorMultiplicador, greaterThan(1.19));
    expect(aplicado.precioDespuesRecargoRd, greaterThan(500));
    expect(aplicado.precioDespuesRecargoRd, lessThan(540));
  });
}
