import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/servicios/negocio_aliado_geo.dart';

void main() {
  group('NegocioAliadoGeo', () {
    test('viaje local cuando origen y destino contienen el pueblo', () {
      expect(
        NegocioAliadoGeo.viajeEsLocalEnPuebloNegocio(
          ciudadNegocio: 'San Juan',
          origen: 'Calle 1, San Juan de la Maguana',
          destino: 'Plaza, San Juan',
        ),
        isTrue,
      );
    });

    test('acepta varias variantes de ciudad separadas por coma', () {
      expect(
        NegocioAliadoGeo.viajeEsLocalEnPuebloNegocio(
          ciudadNegocio: 'Higüey, La Altagracia',
          origen: 'Centro, Higuey',
          destino: 'Terminal, Higüey RD',
        ),
        isTrue,
      );
    });

    test('no aplica si solo origen está en el pueblo', () {
      expect(
        NegocioAliadoGeo.viajeEsLocalEnPuebloNegocio(
          ciudadNegocio: 'Bonao',
          origen: 'Bonao centro',
          destino: 'Santiago',
        ),
        isFalse,
      );
    });

    test('geo extra desde coordenadas enriquece la validación', () {
      expect(
        NegocioAliadoGeo.viajeEsLocalEnPuebloNegocio(
          ciudadNegocio: 'Moca',
          origen: 'Calle principal',
          destino: 'Avenida 27',
          origenGeoExtra: 'MOCA ESPAILLAT',
          destinoGeoExtra: 'MOCA',
        ),
        isTrue,
      );
    });
  });
}
