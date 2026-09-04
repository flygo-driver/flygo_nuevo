import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/servicios/active_trip_service.dart';

void main() {
  group('clienteYaEstaEnViajeEnCurso', () {
    test('overlay del shell cuenta como ya estar en el viaje', () {
      expect(
        ActiveTripService.clienteYaEstaEnViajeEnCurso(
          overlayActivo: true,
          pantallaViajeMontada: false,
          rutaNombradaEsViaje: false,
        ),
        isTrue,
      );
    });

    test('ViajeEnCursoCliente montado cuenta aunque la ruta sea el shell', () {
      expect(
        ActiveTripService.clienteYaEstaEnViajeEnCurso(
          overlayActivo: false,
          pantallaViajeMontada: true,
          rutaNombradaEsViaje: false,
        ),
        isTrue,
      );
    });

    test('ruta nombrada ViajeEnCursoCliente cuenta', () {
      expect(
        ActiveTripService.clienteYaEstaEnViajeEnCurso(
          overlayActivo: false,
          pantallaViajeMontada: false,
          rutaNombradaEsViaje: true,
        ),
        isTrue,
      );
    });

    test('en tabs/home sí hay que abrir overlay', () {
      expect(
        ActiveTripService.clienteYaEstaEnViajeEnCurso(
          overlayActivo: false,
          pantallaViajeMontada: false,
          rutaNombradaEsViaje: false,
        ),
        isFalse,
      );
    });

    test('no se debe destruir el shell al pasar a aceptado', () {
      expect(
        ActiveTripService.clienteYaEstaEnViajeEnCurso(
          overlayActivo: true,
          pantallaViajeMontada: true,
          rutaNombradaEsViaje: false,
        ),
        isTrue,
      );
    });
  });
}
