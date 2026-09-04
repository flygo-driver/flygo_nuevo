import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/servicios/comision_prepago_config_service.dart';
import 'package:flygo_nuevo/servicios/pagos_taxista_repo.dart';
import 'package:flygo_nuevo/utils/calculos/estados.dart';
import 'package:flygo_nuevo/utils/viaje_codigo_verificacion_helper.dart';

void main() {
  group('Prepago estricto por defecto', () {
    setUp(() {
      ComisionPrepagoConfigService.permitirViajeConPrepagoParcial = false;
    });

    Map<String, dynamic> billetera({
      double saldo = 20,
      double pendiente = 0,
      bool primerGratisConsumido = true,
    }) {
      return <String, dynamic>{
        'saldoPrepagoComisionRd': saldo,
        'comisionPendiente': pendiente,
        'primerViajeComisionGratisConsumido': primerGratisConsumido,
      };
    }

    Map<String, dynamic> viaje({
      String metodoPago = 'Efectivo',
      String tipoServicio = 'normal',
      double precio = 1000,
      Map<String, dynamic> extra = const <String, dynamic>{},
    }) {
      return <String, dynamic>{
        'metodoPago': metodoPago,
        'tipoServicio': tipoServicio,
        'precio': precio,
        ...extra,
      };
    }

    test('la configuración arranca en estricto sin leer Firestore', () {
      expect(
        ComisionPrepagoConfigService.permitirViajeConPrepagoParcial,
        isFalse,
      );
    });

    test('efectivo sin prepago suficiente se rechaza', () {
      expect(
        PagosTaxistaRepo.codigoRechazoPrepagoInsuficienteComisionViaje(
          billeData: billetera(),
          viajeData: viaje(),
          pctComision: 20,
        ),
        'prepago-insuficiente-comision-viaje',
      );
    });

    test('multiparada, motor y programado exigen el mismo prepago', () {
      for (final Map<String, dynamic> v in <Map<String, dynamic>>[
        viaje(extra: <String, dynamic>{
          'waypoints': <Map<String, dynamic>>[
            <String, dynamic>{'orden': 1},
            <String, dynamic>{'orden': 2},
          ],
        }),
        viaje(tipoServicio: 'motor'),
        viaje(extra: <String, dynamic>{'programado': true}),
      ]) {
        expect(
          PagosTaxistaRepo.codigoRechazoPrepagoInsuficienteComisionViaje(
            billeData: billetera(),
            viajeData: v,
            pctComision: 20,
          ),
          'prepago-insuficiente-comision-viaje',
        );
      }
    });

    test('bola y corporativo no exigen prepago por viaje', () {
      for (final Map<String, dynamic> v in <Map<String, dynamic>>[
        viaje(tipoServicio: 'bola_ahorro'),
        viaje(extra: <String, dynamic>{'corporativo': true}),
        viaje(extra: <String, dynamic>{'categoria': 'corporativo'}),
        viaje(extra: <String, dynamic>{'exentoBloqueoPrepago': true}),
      ]) {
        expect(
          PagosTaxistaRepo.codigoRechazoPrepagoInsuficienteComisionViaje(
            billeData: billetera(),
            viajeData: v,
            pctComision: 20,
          ),
          isNull,
        );
      }
    });

    test('transferencia P2P exige prepago igual que efectivo', () {
      expect(
        PagosTaxistaRepo.codigoRechazoPrepagoInsuficienteComisionViaje(
          billeData: billetera(),
          viajeData: viaje(metodoPago: 'Transferencia'),
          pctComision: 20,
        ),
        'prepago-insuficiente-comision-viaje',
      );
    });

    test('tarjeta y recaudo RAI se liquidan semanal: no exigen prepago', () {
      expect(
        PagosTaxistaRepo.codigoRechazoPrepagoInsuficienteComisionViaje(
          billeData: billetera(),
          viajeData: viaje(metodoPago: 'Tarjeta'),
          pctComision: 20,
        ),
        isNull,
      );
      expect(
        PagosTaxistaRepo.codigoRechazoPrepagoInsuficienteComisionViaje(
          billeData: billetera(),
          viajeData: viaje(
            metodoPago: 'Transferencia',
            extra: <String, dynamic>{'recaudoDestino': 'rai'},
          ),
          pctComision: 20,
        ),
        isNull,
      );
    });

    test('primer viaje gratis sigue permitido sin prepago', () {
      expect(
        PagosTaxistaRepo.codigoRechazoPrepagoInsuficienteComisionViaje(
          billeData: billetera(saldo: 0, primerGratisConsumido: false),
          viajeData: viaje(),
          pctComision: 20,
        ),
        isNull,
      );
    });

    test('prepago suficiente deja aceptar', () {
      expect(
        PagosTaxistaRepo.codigoRechazoPrepagoInsuficienteComisionViaje(
          billeData: billetera(saldo: 300),
          viajeData: viaje(),
          pctComision: 20,
        ),
        isNull,
      );
    });

    test('modo parcial activado por ADM vuelve a permitir', () {
      ComisionPrepagoConfigService.permitirViajeConPrepagoParcial = true;
      expect(
        PagosTaxistaRepo.codigoRechazoPrepagoInsuficienteComisionViaje(
          billeData: billetera(),
          viajeData: viaje(),
          pctComision: 20,
        ),
        isNull,
      );
    });
  });

  group('PIN al marcar «Cliente a bordo»', () {
    Map<String, dynamic> viajeAbordo({
      String pin = '123456',
      bool clienteAbordo = true,
    }) {
      return <String, dynamic>{
        'uidTaxista': 'tx1',
        'taxistaId': 'tx1',
        'tipoServicio': 'normal',
        'programado': false,
        'esAhora': true,
        'clienteAbordo': clienteAbordo,
        if (pin.isNotEmpty) 'codigoVerificacion': pin,
      };
    }

    test('el cliente ve el PIN en cuanto el chofer marca abordo', () {
      expect(
        ViajeCodigoVerificacionHelper.clienteDebeMostrarPin(
          viajeData: viajeAbordo(),
          estadoNorm: EstadosViaje.aBordo,
          codigoVerificado: false,
        ),
        isTrue,
      );
    });

    test('abordo marcado con estado aún en pickup también muestra el PIN', () {
      expect(
        ViajeCodigoVerificacionHelper.clienteDebeMostrarPin(
          viajeData: viajeAbordo(),
          estadoNorm: EstadosViaje.enCaminoPickup,
          codigoVerificado: false,
        ),
        isTrue,
      );
    });

    test('el PIN se oculta cuando el servidor lo marca verificado', () {
      expect(
        ViajeCodigoVerificacionHelper.clienteDebeMostrarPin(
          viajeData: viajeAbordo(),
          estadoNorm: EstadosViaje.aBordo,
          codigoVerificado: true,
        ),
        isFalse,
      );
    });

    test('sin PIN emitido aún se pide generarlo', () {
      expect(
        ViajeCodigoVerificacionHelper.necesitaGenerarPin(''),
        isTrue,
      );
      expect(
        ViajeCodigoVerificacionHelper.necesitaGenerarPin('123456'),
        isFalse,
      );
    });
  });
}
