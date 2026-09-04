import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/pantallas/comun/factura_viaje.dart';
import 'package:flygo_nuevo/utils/metodo_pago_viaje.dart';

void main() {
  group('MetodoPagoViaje.cobroClienteBloqueaApp', () {
    test('efectivo no bloquea aunque cobroClientePendiente quede en true', () {
      expect(
        MetodoPagoViaje.cobroClienteBloqueaApp(<String, dynamic>{
          'metodoPago': 'Efectivo',
          'cobroClientePendiente': true,
          'cobroClienteEstado': 'pendiente',
        }),
        isFalse,
      );
    });

    test('tarjeta sin cobrar sigue bloqueando', () {
      expect(
        MetodoPagoViaje.cobroClienteBloqueaApp(<String, dynamic>{
          'metodoPago': 'Tarjeta',
          'cobroClientePendiente': true,
          'payment': {'status': 'pending'},
        }),
        isTrue,
      );
    });

    test('impago registrado no bloquea cierre', () {
      expect(
        MetodoPagoViaje.cobroClienteBloqueaApp(<String, dynamic>{
          'metodoPago': 'Tarjeta',
          'cobroClientePendiente': true,
          'cobroClienteEstado': 'impago_registrado',
        }),
        isFalse,
      );
    });
  });

  group('facturaViajeListaParaContinuarFlujo', () {
    Map<String, dynamic> baseCompletado() => <String, dynamic>{
          'completado': true,
          'estado': 'completado',
          'precio': 450.0,
        };

    test('cliente multiparada efectivo puede continuar de inmediato', () {
      expect(
        facturaViajeListaParaContinuarFlujo(
          data: <String, dynamic>{
            ...baseCompletado(),
            'categoria': 'multi',
            'metodoPago': 'Efectivo',
          },
          role: 'cliente',
        ),
        isTrue,
      );
    });

    test('cliente tarjeta pendiente no puede continuar', () {
      expect(
        facturaViajeListaParaContinuarFlujo(
          data: <String, dynamic>{
            ...baseCompletado(),
            'metodoPago': 'Tarjeta',
            'cobroClientePendiente': true,
            'payment': {'status': 'pending'},
          },
          role: 'cliente',
        ),
        isFalse,
      );
    });

    test('cliente cambió a efectivo con flag pendiente stale puede continuar', () {
      expect(
        facturaViajeListaParaContinuarFlujo(
          data: <String, dynamic>{
            ...baseCompletado(),
            'metodoPago': 'Efectivo',
            'metodoPagoAnterior': 'tarjeta',
            'tarjetaCambioEfectivoEn': DateTime.now(),
            'cobroClientePendiente': true,
            'cobroClienteEstado': 'pendiente',
          },
          role: 'cliente',
        ),
        isTrue,
      );
    });

    test('taxista siempre puede continuar si viaje completado', () {
      expect(
        facturaViajeListaParaContinuarFlujo(
          data: <String, dynamic>{
            ...baseCompletado(),
            'metodoPago': 'Tarjeta',
            'cobroClientePendiente': true,
          },
          role: 'taxista',
        ),
        isTrue,
      );
    });
  });

  group('facturaBotonContinuarActivo', () {
    Map<String, dynamic> efectivoCerrado() => <String, dynamic>{
          'completado': true,
          'estado': 'completado',
          'precio': 450.0,
          'metodoPago': 'Efectivo',
        };

    test('viaje normal en efectivo: el botón queda activo', () {
      expect(
        facturaBotonContinuarActivo(
          data: efectivoCerrado(),
          role: 'cliente',
          cerrandoFactura: false,
        ),
        isTrue,
      );
    });

    test('solo se apaga mientras el cierre está en vuelo', () {
      expect(
        facturaBotonContinuarActivo(
          data: efectivoCerrado(),
          role: 'cliente',
          cerrandoFactura: true,
        ),
        isFalse,
      );
    });

    test('tras un cierre que no sacó la factura sigue activo para reintentar', () {
      // Antes se apagaba con `_facturaCerrada` y la única salida era la X.
      expect(
        facturaBotonContinuarActivo(
          data: efectivoCerrado(),
          role: 'cliente',
          cerrandoFactura: false,
        ),
        isTrue,
      );
    });

    test('tarjeta sin pagar sí bloquea al cliente pero no al taxista', () {
      final Map<String, dynamic> tarjetaPendiente = <String, dynamic>{
        'completado': true,
        'estado': 'completado',
        'precio': 450.0,
        'metodoPago': 'Tarjeta',
        'cobroClientePendiente': true,
        'payment': <String, dynamic>{'status': 'pending'},
      };
      expect(
        facturaBotonContinuarActivo(
          data: tarjetaPendiente,
          role: 'cliente',
          cerrandoFactura: false,
        ),
        isFalse,
      );
      expect(
        facturaBotonContinuarActivo(
          data: tarjetaPendiente,
          role: 'taxista',
          cerrandoFactura: false,
        ),
        isTrue,
      );
    });
  });
}
