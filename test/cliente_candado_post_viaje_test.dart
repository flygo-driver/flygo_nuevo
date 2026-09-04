import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flygo_nuevo/servicios/active_trip_service.dart';

/// El candado post-viaje dura 20 minutos. Si no está atado al viaje que
/// terminó, el viaje siguiente hereda el bloqueo: el shell manda al inicio y
/// el abordaje nunca muestra el PIN al pasajero.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  setUp(() {
    ActiveTripService.cancelarForzarInicioClienteShellForzado();
  });

  tearDownAll(() {
    ActiveTripService.cancelarForzarInicioClienteShellForzado();
  });

  group('candado post-viaje del cliente', () {
    test('bloquea el viaje que acaba de terminar', () {
      ActiveTripService.marcarFlujoPostViajeCliente('viajeA');

      expect(ActiveTripService.flujoPostViajeClienteActivo, isTrue);
      expect(ActiveTripService.flujoPostViajeClienteBloquea('viajeA'), isTrue);
      expect(ActiveTripService.debeForzarInicioClienteShell, isTrue);
    });

    test('no bloquea un viaje distinto', () {
      ActiveTripService.marcarFlujoPostViajeCliente('viajeA');

      expect(ActiveTripService.flujoPostViajeClienteBloquea('viajeB'), isFalse);
    });

    test('un viaje operativo nuevo libera el candado y el forzar inicio', () {
      ActiveTripService.marcarFlujoPostViajeCliente('viajeA');

      ActiveTripService.registrarViajeOperativoCliente('viajeB');

      expect(ActiveTripService.flujoPostViajeClienteActivo, isFalse);
      expect(ActiveTripService.debeForzarInicioClienteShell, isFalse);
      expect(ActiveTripService.flujoPostViajeClienteBloquea('viajeB'), isFalse);
      expect(ActiveTripService.flujoPostViajeClienteViajeId, isEmpty);
    });

    test('el mismo viaje no libera el candado (factura sigue abierta)', () {
      ActiveTripService.marcarFlujoPostViajeCliente('viajeA');

      ActiveTripService.registrarViajeOperativoCliente('viajeA');

      expect(ActiveTripService.flujoPostViajeClienteActivo, isTrue);
      expect(ActiveTripService.flujoPostViajeClienteBloquea('viajeA'), isTrue);
      expect(ActiveTripService.debeForzarInicioClienteShell, isTrue);
    });

    test('un viaje nuevo previo no debilita el candado del viaje siguiente',
        () {
      ActiveTripService.registrarViajeOperativoCliente('viajeB');
      ActiveTripService.marcarFlujoPostViajeCliente('viajeB');

      expect(ActiveTripService.flujoPostViajeClienteActivo, isTrue);
      expect(ActiveTripService.flujoPostViajeClienteBloquea('viajeB'), isTrue);
    });

    test('cerrar el flujo post-viaje desbloquea todo', () {
      ActiveTripService.marcarFlujoPostViajeCliente('viajeA');

      ActiveTripService.cerrarFlujoPostViajeCliente();

      expect(ActiveTripService.flujoPostViajeClienteActivo, isFalse);
      expect(ActiveTripService.flujoPostViajeClienteBloquea('viajeA'), isFalse);
    });
  });
}
