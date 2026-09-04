import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_codigo_verificacion_helper.dart';

void main() {
  group('ViajeCodigoVerificacionHelper', () {
    test('pinExistenteEnMap lee camelCase y snake_case', () {
      expect(
        ViajeCodigoVerificacionHelper.pinExistenteEnMap(
          <String, dynamic>{'codigoVerificacion': '123456'},
        ),
        '123456',
      );
      expect(
        ViajeCodigoVerificacionHelper.pinExistenteEnMap(
          <String, dynamic>{'codigo_verificacion': '654-321'},
        ),
        '654321',
      );
      expect(
        ViajeCodigoVerificacionHelper.pinExistenteEnMap(
          <String, dynamic>{'boardingPin': '111111'},
        ),
        '111111',
      );
    });

    test('clienteDebeMostrarPin oculto en pickup sin abordo', () {
      final Map<String, dynamic> base = <String, dynamic>{
        'uidTaxista': 'tx1',
        'taxistaId': 'tx1',
        'tipoServicio': 'normal',
        'programado': false,
        'esAhora': true,
      };
      expect(
        ViajeCodigoVerificacionHelper.clienteDebeMostrarPin(
          viajeData: base,
          estadoNorm: EstadosViaje.aceptado,
          codigoVerificado: false,
        ),
        isFalse,
      );

      final Map<String, dynamic> motor = Map<String, dynamic>.from(base)
        ..['tipoServicio'] = 'motor';
      expect(
        ViajeCodigoVerificacionHelper.clienteDebeMostrarPin(
          viajeData: motor,
          estadoNorm: EstadosViaje.enCaminoPickup,
          codigoVerificado: false,
        ),
        isFalse,
      );

      final Map<String, dynamic> programado = Map<String, dynamic>.from(base)
        ..['programado'] = true
        ..['esAhora'] = false;
      expect(
        ViajeCodigoVerificacionHelper.clienteDebeMostrarPin(
          viajeData: programado,
          estadoNorm: EstadosViaje.aceptado,
          codigoVerificado: false,
        ),
        isFalse,
      );
    });

    test('clienteDebeMostrarPin visible con clienteAbordo y estado pickup crudo', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'uidTaxista': 'tx1',
        'estado': EstadosViaje.enCaminoPickup,
        'clienteAbordo': true,
      };
      expect(
        ViajeCodigoVerificacionHelper.clienteDebeMostrarPin(
          viajeData: doc,
          estadoNorm: EstadosViaje.aBordo,
          codigoVerificado: false,
        ),
        isTrue,
      );
    });

    test('clienteDebeMostrarPin visible tras cliente a bordo', () {
      final Map<String, dynamic> base = <String, dynamic>{
        'uidTaxista': 'tx1',
        'taxistaId': 'tx1',
        'tipoServicio': 'normal',
      };

      expect(
        ViajeCodigoVerificacionHelper.clienteDebeMostrarPin(
          viajeData: Map<String, dynamic>.from(base)
            ..['clienteAbordo'] = true,
          estadoNorm: EstadosViaje.enCaminoPickup,
          codigoVerificado: false,
        ),
        isTrue,
      );

      expect(
        ViajeCodigoVerificacionHelper.clienteDebeMostrarPin(
          viajeData: base,
          estadoNorm: EstadosViaje.aBordo,
          codigoVerificado: false,
        ),
        isTrue,
      );

      final Map<String, dynamic> multiparada = Map<String, dynamic>.from(base)
        ..['multiparadaLegsTotal'] = 3;
      expect(
        ViajeCodigoVerificacionHelper.clienteDebeMostrarPin(
          viajeData: multiparada,
          estadoNorm: EstadosViaje.aBordo,
          codigoVerificado: false,
        ),
        isTrue,
      );
    });

    test('clienteDebeMostrarPin oculto sin conductor o ya verificado', () {
      final Map<String, dynamic> sinTx = <String, dynamic>{
        'estado': EstadosViaje.pendiente,
      };
      expect(
        ViajeCodigoVerificacionHelper.clienteDebeMostrarPin(
          viajeData: sinTx,
          estadoNorm: EstadosViaje.pendiente,
          codigoVerificado: false,
        ),
        isFalse,
      );

      final Map<String, dynamic> conTx = <String, dynamic>{
        'uidTaxista': 'tx1',
        'codigoVerificado': true,
      };
      expect(
        ViajeCodigoVerificacionHelper.clienteDebeMostrarPin(
          viajeData: conTx,
          estadoNorm: EstadosViaje.enCurso,
          codigoVerificado: true,
        ),
        isFalse,
      );
    });

    test('pinDesdeViajeDoc prioriza modelo y luego doc', () {
      expect(
        ViajeCodigoVerificacionHelper.pinDesdeViajeDoc(
          viajeData: <String, dynamic>{'codigoVerificacion': '999999'},
          codigoDesdeModelo: '123456',
        ),
        '123456',
      );
      expect(
        ViajeCodigoVerificacionHelper.pinDesdeViajeDoc(
          viajeData: <String, dynamic>{'codigoVerificacion': '999999'},
        ),
        '999999',
      );
      expect(
        ViajeCodigoVerificacionHelper.pinDesdeViajeDoc(
          viajeData: <String, dynamic>{},
          bolaData: <String, dynamic>{'codigoVerificacionBola': '888888'},
        ),
        '888888',
      );
    });

    test('generarPinSeisDigitos siempre devuelve 6 dígitos', () {
      final String pin = ViajeCodigoVerificacionHelper.generarPinSeisDigitos();
      expect(pin.length, 6);
      expect(int.tryParse(pin), isNotNull);
    });
  });
}
