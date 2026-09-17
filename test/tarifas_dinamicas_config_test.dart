import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/modelo/tarifas_dinamicas_config.dart';

void main() {
  test('por minuto sube con severidad de tapón', () {
    expect(
      TarifasDinamicasConfig.porMinutoDesdeRatio(
        ratio: 1.05,
        claveVehiculo: 'Carro',
      ),
      2.2,
    );
    expect(
      TarifasDinamicasConfig.porMinutoDesdeRatio(
        ratio: 1.87,
        claveVehiculo: 'Carro',
      ),
      4.4,
    );
  });

  test('piso urbano en condiciones adversas', () {
    expect(
      TarifasDinamicasConfig.pisoUrbanoCondicionesAdversas(
        km: 11,
        minimoLocalRd: 175,
        condicionesAdversas: true,
      ),
      380,
    );
    expect(
      TarifasDinamicasConfig.pisoUrbanoCondicionesAdversas(
        km: 22,
        minimoLocalRd: 175,
        condicionesAdversas: true,
      ),
      520,
    );
  });
}
