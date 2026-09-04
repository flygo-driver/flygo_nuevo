import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/modelo/viaje.dart';
import 'package:flygo_nuevo/utils/viaje_navegacion_resolver.dart';

void main() {
  group('ViajeNavegacionResolver', () {
    test('legs con 3 paradas desde rutaPuntos aunque waypoints parcial', () {
      final viaje = Viaje.fromMap('t1', <String, dynamic>{
        'origen': 'Origen',
        'destino': 'Destino final',
        'latCliente': 18.47,
        'lonCliente': -69.92,
        'latDestino': 18.50,
        'lonDestino': -69.95,
        'waypoints': <Map<String, dynamic>>[
          <String, dynamic>{
            'lat': 18.471,
            'lon': -69.921,
            'label': 'P1',
            'orden': 1,
          },
          <String, dynamic>{'lat': 0, 'lon': 0, 'label': 'P2', 'orden': 2},
        ],
        'rutaPuntos': <Map<String, dynamic>>[
          <String, dynamic>{
            'lat': 18.47,
            'lon': -69.92,
            'rol': 'origen',
            'label': 'Origen',
          },
          <String, dynamic>{
            'lat': 18.471,
            'lon': -69.921,
            'rol': 'parada',
            'label': 'P1',
          },
          <String, dynamic>{
            'lat': 18.48,
            'lon': -69.93,
            'rol': 'parada',
            'label': 'P2',
          },
          <String, dynamic>{
            'lat': 18.49,
            'lon': -69.94,
            'rol': 'parada',
            'label': 'P3',
          },
          <String, dynamic>{
            'lat': 18.50,
            'lon': -69.95,
            'rol': 'destino',
            'label': 'Destino final',
          },
        ],
      });

      final legs = ViajeNavegacionResolver.legs(viaje);
      expect(legs.length, 4);
      expect(legs[2].lat, 18.49);
      expect(ViajeNavegacionResolver.coordsValidas(legs[1].lat, legs[1].lon),
          isTrue);
    });
  });
}
