import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/cliente_viaje_data_merge.dart';
import 'package:flygo_nuevo/utils/cliente_viaje_estado_efectivo.dart';
import 'package:flygo_nuevo/utils/viaje_codigo_verificacion_helper.dart';

void main() {
  group('ClienteViajeDataMerge — servidor adelantado', () {
    test('en_curso en servidor corrige aceptado en stream local', () {
      final Map<String, dynamic> stream = <String, dynamic>{
        'estado': 'aceptado',
        'codigoVerificado': false,
        'uidTaxista': 'tax1',
      };
      final Map<String, dynamic> server = <String, dynamic>{
        'estado': 'en_curso',
        'codigoVerificado': true,
        'clienteAbordo': true,
        'uidTaxista': 'tax1',
      };

      expect(ClienteViajeDataMerge.serverEstaAdelante(stream, server), isTrue);

      final Map<String, dynamic> merged =
          ClienteViajeDataMerge.merge(stream, server);
      expect(merged['estado'], 'en_curso');
      expect(merged['codigoVerificado'], isTrue);
    });

    test('stream al día no se pisa', () {
      final Map<String, dynamic> stream = <String, dynamic>{
        'estado': 'en_curso',
        'codigoVerificado': true,
      };
      final Map<String, dynamic> server = <String, dynamic>{
        'estado': 'aceptado',
        'codigoVerificado': false,
      };

      expect(ClienteViajeDataMerge.serverEstaAdelante(stream, server), isFalse);
      expect(
        ClienteViajeDataMerge.merge(stream, server)['estado'],
        'en_curso',
      );
    });

    test('clienteAbordo solo en extras del servidor corrige stream', () {
      final Map<String, dynamic> stream = <String, dynamic>{
        'estado': 'aceptado',
        'aceptado': true,
        'uidTaxista': 'tax1',
      };
      final Map<String, dynamic> server = <String, dynamic>{
        'estado': 'aceptado',
        'aceptado': true,
        'uidTaxista': 'tax1',
        'extras': <String, dynamic>{'clienteAbordo': true},
      };

      expect(ClienteViajeDataMerge.serverEstaAdelante(stream, server), isTrue);
      final Map<String, dynamic> merged =
          ClienteViajeDataMerge.merge(stream, server);
      expect((merged['extras'] as Map)['clienteAbordo'], isTrue);
    });

    test('PIN en servidor y stream sin PIN → servidor adelantado', () {
      final Map<String, dynamic> stream = <String, dynamic>{
        'estado': 'aceptado',
        'aceptado': true,
        'uidTaxista': 'tax1',
      };
      final Map<String, dynamic> server = <String, dynamic>{
        'estado': 'a_bordo',
        'aceptado': true,
        'clienteAbordo': true,
        'codigoVerificacion': '106075',
        'uidTaxista': 'tax1',
      };

      expect(ClienteViajeDataMerge.serverEstaAdelante(stream, server), isTrue);
      final Map<String, dynamic> merged =
          ClienteViajeDataMerge.merge(stream, server);
      expect(merged['estado'], 'a_bordo');
      expect(merged['codigoVerificacion'], '106075');
      expect(
        ClienteViajeEstadoEfectivo.resolver(merged),
        EstadosViaje.aBordo,
      );
    });

    test('codigoVerificado en servidor con estado aceptado → UI en_curso', () {
      final Map<String, dynamic> stream = <String, dynamic>{
        'estado': 'aceptado',
        'aceptado': true,
        'codigoVerificado': false,
        'uidTaxista': 'tax1',
      };
      final Map<String, dynamic> server = <String, dynamic>{
        'estado': 'aceptado',
        'aceptado': true,
        'codigoVerificado': true,
        'clienteAbordo': true,
        'uidTaxista': 'tax1',
      };

      expect(ClienteViajeDataMerge.serverEstaAdelante(stream, server), isTrue);
      expect(
        ClienteViajeEstadoEfectivo.resolver(
          ClienteViajeDataMerge.merge(stream, server),
        ),
        EstadosViaje.enCurso,
      );
    });
  });

  group('ClienteViajeEstadoEfectivo — UI coherente con taxista', () {
    test('PIN verificado + estado aceptado → cliente ve en_curso', () {
      final String est = ClienteViajeEstadoEfectivo.resolver(<String, dynamic>{
        'estado': 'aceptado',
        'aceptado': true,
        'codigoVerificado': true,
        'clienteAbordo': true,
      });
      expect(est, EstadosViaje.enCurso);
    });

    test('solo aceptado sin PIN → cliente ve aceptado', () {
      final String est = ClienteViajeEstadoEfectivo.resolver(<String, dynamic>{
        'estado': 'aceptado',
        'aceptado': true,
        'codigoVerificado': false,
      });
      expect(est, EstadosViaje.aceptado);
    });

    test('abordo sin PIN → cliente ve a_bordo', () {
      final String est = ClienteViajeEstadoEfectivo.resolver(<String, dynamic>{
        'estado': 'aceptado',
        'aceptado': true,
        'clienteAbordo': true,
        'codigoVerificado': false,
      });
      expect(est, EstadosViaje.aBordo);
    });

    test('en_curso en Firestore → cliente ve en_curso', () {
      final String est = ClienteViajeEstadoEfectivo.resolver(<String, dynamic>{
        'estado': 'en_curso',
        'codigoVerificado': true,
      });
      expect(est, EstadosViaje.enCurso);
    });

    test('doc real usuario: a_bordo + clienteAbordo + PIN 106075 → mostrar PIN', () {
      final Map<String, dynamic> doc = <String, dynamic>{
        'estado': 'a_bordo',
        'aceptado': true,
        'clienteAbordo': true,
        'codigoVerificacion': '106075',
        'codigoVerificado': false,
        'uidTaxista': 'yoX43bWU1WQ8Q4Yd0px9HCXFBx03',
        'taxistaId': 'yoX43bWU1WQ8Q4Yd0px9HCXFBx03',
        'tipoServicio': 'normal',
        'metodoPago': 'Transferencia',
      };

      final String est = ClienteViajeEstadoEfectivo.resolver(doc);
      expect(est, EstadosViaje.aBordo);

      expect(
        ViajeCodigoVerificacionHelper.clienteDebeMostrarPin(
          viajeData: doc,
          estadoNorm: est,
          codigoVerificado: false,
          uidTaxistaModelo: doc['uidTaxista'] as String,
        ),
        isTrue,
      );

      final String pin = ViajeCodigoVerificacionHelper.pinDesdeViajeDoc(
        viajeData: doc,
      );
      expect(pin, '106075');
    });

    test('taxista finaliza, servidor en_curso, stream aceptado', () {
      final Map<String, dynamic> streamLocal = <String, dynamic>{
        'estado': 'aceptado',
        'aceptado': true,
        'codigoVerificado': false,
        'uidTaxista': 'tax1',
      };
      final Map<String, dynamic> servidor = <String, dynamic>{
        'estado': 'en_curso',
        'codigoVerificado': true,
        'clienteAbordo': true,
        'uidTaxista': 'tax1',
      };

      final Map<String, dynamic> corregido =
          ClienteViajeDataMerge.merge(streamLocal, servidor);
      final String ui =
          ClienteViajeEstadoEfectivo.resolver(corregido);

      expect(ui, EstadosViaje.enCurso);
      expect(ui, isNot(EstadosViaje.aceptado));
    });
  });
}
