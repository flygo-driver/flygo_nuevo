import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/utils/multiparada_ruta_helper.dart';

void main() {
  group('MultiparadaRutaHelper — guardar ruta', () {
    test('construirRutaPuntos orden origen → paradas → destino', () {
      final waypoints = MultiparadaRutaHelper.sanitizarWaypoints(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'lat': 18.48,
            'lon': -69.93,
            'label': 'Parada 1',
            'orden': 1,
          },
        ],
      );
      final ruta = MultiparadaRutaHelper.construirRutaPuntos(
        latOrigen: 18.47,
        lonOrigen: -69.92,
        labelOrigen: 'Origen',
        latDestino: 18.49,
        lonDestino: -69.94,
        labelDestino: 'Destino',
        waypoints: waypoints,
      );
      expect(ruta.length, 3);
      expect(ruta.first['rol'], 'origen');
      expect(ruta[1]['rol'], 'parada');
      expect(ruta.last['rol'], 'destino');
    });

    test('alinearSegmentosConPuntos sincroniza labels y coords', () {
      final segmentos = <Map<String, dynamic>>[
        <String, dynamic>{
          'tramo': 1,
          'origen': 'Viejo A',
          'destino': 'Viejo B',
          'km': 2.5,
        },
        <String, dynamic>{
          'tramo': 2,
          'origen': 'Viejo B',
          'destino': 'Viejo C',
          'km': 3.1,
        },
      ];
      final puntos = <({String label, double lat, double lon})>[
        (label: 'Origen real', lat: 18.47, lon: -69.92),
        (label: 'Parada real', lat: 18.48, lon: -69.93),
        (label: 'Destino real', lat: 18.49, lon: -69.94),
      ];
      final out = MultiparadaRutaHelper.alinearSegmentosConPuntos(
        segmentos: segmentos,
        puntosOrdenados: puntos,
      );
      expect(out.length, 2);
      expect(out.first['origen'], 'Origen real');
      expect(out.first['destino'], 'Parada real');
      expect(out.last['destino'], 'Destino real');
      expect(out.first['latOrigen'], 18.47);
      expect(out.last['lonDestino'], -69.94);
    });

    test('validarSecuenciaRuta rechaza paradas duplicadas', () {
      final err = MultiparadaRutaHelper.validarSecuenciaRuta(
        latOrigen: 18.47,
        lonOrigen: -69.92,
        labelOrigen: 'Origen',
        latDestino: 18.49,
        lonDestino: -69.94,
        labelDestino: 'Destino',
        paradas: <({double lat, double lon, String label})>[
          (lat: 18.48, lon: -69.93, label: 'Parada 1'),
          (lat: 18.480001, lon: -69.930001, label: 'Parada 2'),
        ],
      );
      expect(err, isNotNull);
    });

    test('sanitizarWaypoints renumera orden 1..n', () {
      final wps = MultiparadaRutaHelper.sanitizarWaypoints(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'lat': 18.48,
            'lon': -69.93,
            'label': 'B',
            'orden': 5,
          },
          <String, dynamic>{
            'lat': 18.481,
            'lon': -69.931,
            'label': 'A',
            'orden': 2,
          },
        ],
      );
      expect(wps.length, 2);
      expect(wps.first['orden'], 1);
      expect(wps.last['orden'], 2);
    });

    test('origenParaNavegacion toma origen de rutaPuntos si latCliente es 0', () {
      final doc = <String, dynamic>{
        'latCliente': 0,
        'lonCliente': 0,
        'extras': <String, dynamic>{
          'rutaPuntos': <Map<String, dynamic>>[
            <String, dynamic>{
              'lat': 18.47,
              'lon': -69.92,
              'label': 'Origen real',
              'rol': 'origen',
            },
          ],
        },
      };
      final origen = MultiparadaRutaHelper.origenParaNavegacion(
        viajeData: doc,
        latClienteModelo: 0,
        lonClienteModelo: 0,
      );
      expect(origen, isNotNull);
      expect(origen!.lat, 18.47);
    });

    test('fusiona rutaPuntos con waypoints para paradas 2 y 3', () {
      final doc = <String, dynamic>{
        'waypoints': <Map<String, dynamic>>[
          <String, dynamic>{
            'lat': 18.47,
            'lon': -69.92,
            'label': 'Parada 1',
            'orden': 1,
          },
          <String, dynamic>{
            'lat': 0,
            'lon': 0,
            'label': 'Parada 2 sin gps',
            'orden': 2,
          },
        ],
        'rutaPuntos': <Map<String, dynamic>>[
          <String, dynamic>{
            'lat': 18.47,
            'lon': -69.92,
            'label': 'Parada 1',
            'rol': 'parada',
          },
          <String, dynamic>{
            'lat': 18.48,
            'lon': -69.93,
            'label': 'Parada 2',
            'rol': 'parada',
          },
          <String, dynamic>{
            'lat': 18.49,
            'lon': -69.94,
            'label': 'Parada 3',
            'rol': 'parada',
          },
        ],
      };
      final paradas = MultiparadaRutaHelper.paradasIntermediasParaNavegacion(
        viajeData: doc,
      );
      expect(paradas.length, 3);
      expect(paradas[1].lat, 18.48);
      expect(paradas[2].lat, 18.49);
      final legs = MultiparadaRutaHelper.legsNavegacionMultiparada(
        viajeData: doc,
        latDestinoModelo: 18.50,
        lonDestinoModelo: -69.95,
      );
      expect(legs.length, 4);
      expect(legs[2].lat, 18.49);
    });

    test('legsNavegacionMultiparada toma destino de rutaPuntos si latDestino es 0',
        () {
      final doc = <String, dynamic>{
        'waypoints': <Map<String, dynamic>>[
          <String, dynamic>{'lat': 18.48, 'lon': -69.93, 'label': 'Parada 1'},
        ],
        'extras': <String, dynamic>{
          'rutaPuntos': <Map<String, dynamic>>[
            <String, dynamic>{
              'lat': 18.49,
              'lon': -69.94,
              'label': 'Destino final',
              'rol': 'destino',
            },
          ],
        },
      };
      final legs = MultiparadaRutaHelper.legsNavegacionMultiparada(
        viajeData: doc,
        latDestinoModelo: 0,
        lonDestinoModelo: 0,
      );
      expect(legs.length, 2);
      expect(legs.last.esFinal, isTrue);
      expect(legs.last.lat, 18.49);
    });
  });
}
