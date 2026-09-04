// El selector de pago se dibuja en varias ramas del sheet del cliente y cada
// rama crea un State nuevo. La elección vive fuera del árbol para que cambiar
// de efectivo a transferencia (o al revés) no se deshaga solo en pantalla.
import 'package:flutter_test/flutter_test.dart';

import 'package:flygo_nuevo/servicios/cliente_metodo_pago_viaje_ui.dart';

void main() {
  late DateTime reloj;

  setUp(() {
    reloj = DateTime(2026, 8, 13, 12, 0, 0);
    ClienteMetodoPagoViajeUi.ahora = () => reloj;
    ClienteMetodoPagoViajeUi.limpiarTodo();
  });

  tearDown(() {
    ClienteMetodoPagoViajeUi.ahora = DateTime.now;
    ClienteMetodoPagoViajeUi.limpiarTodo();
  });

  test('la elección manda mientras el doc todavía dice lo viejo', () {
    ClienteMetodoPagoViajeUi.marcar(viajeId: 'v1', categoria: 'efectivo');

    expect(
      ClienteMetodoPagoViajeUi.resolver(
        viajeId: 'v1',
        metodoRemoto: 'Transferencia',
      ),
      'Efectivo',
    );
  });

  test('aplicarla dos veces (pantalla y selector) da lo mismo', () {
    ClienteMetodoPagoViajeUi.marcar(viajeId: 'v1', categoria: 'efectivo');

    final String pantalla = ClienteMetodoPagoViajeUi.resolver(
      viajeId: 'v1',
      metodoRemoto: 'Transferencia',
    );
    final String selector = ClienteMetodoPagoViajeUi.resolver(
      viajeId: 'v1',
      metodoRemoto: pantalla,
    );

    expect(selector, 'Efectivo');
  });

  test('cuando el servidor confirma, se muestra el documento', () {
    ClienteMetodoPagoViajeUi.marcar(viajeId: 'v1', categoria: 'efectivo');

    expect(
      ClienteMetodoPagoViajeUi.resolver(
        viajeId: 'v1',
        metodoRemoto: 'Efectivo',
      ),
      'Efectivo',
    );
  });

  test('cambiar de opción reemplaza la elección anterior', () {
    ClienteMetodoPagoViajeUi.marcar(viajeId: 'v1', categoria: 'transferencia');
    ClienteMetodoPagoViajeUi.marcar(viajeId: 'v1', categoria: 'efectivo');

    expect(
      ClienteMetodoPagoViajeUi.resolver(
        viajeId: 'v1',
        metodoRemoto: 'Transferencia',
      ),
      'Efectivo',
    );
  });

  test('la elección de un viaje no se cuela en otro', () {
    ClienteMetodoPagoViajeUi.marcar(viajeId: 'v1', categoria: 'efectivo');

    expect(
      ClienteMetodoPagoViajeUi.resolver(
        viajeId: 'v2',
        metodoRemoto: 'Transferencia',
      ),
      'Transferencia',
    );
  });

  test('si el servidor nunca confirma, la UI vuelve a la verdad', () {
    ClienteMetodoPagoViajeUi.marcar(viajeId: 'v1', categoria: 'efectivo');
    reloj = reloj.add(ClienteMetodoPagoViajeUi.ventana +
        const Duration(seconds: 1));

    expect(
      ClienteMetodoPagoViajeUi.resolver(
        viajeId: 'v1',
        metodoRemoto: 'Transferencia',
      ),
      'Transferencia',
    );
  });

  test('si el callable falla, se descarta la elección', () {
    ClienteMetodoPagoViajeUi.marcar(viajeId: 'v1', categoria: 'efectivo');
    ClienteMetodoPagoViajeUi.limpiar('v1');

    expect(
      ClienteMetodoPagoViajeUi.resolver(
        viajeId: 'v1',
        metodoRemoto: 'Transferencia',
      ),
      'Transferencia',
    );
  });

  test('limpiar el viaje equivocado no borra la elección vigente', () {
    ClienteMetodoPagoViajeUi.marcar(viajeId: 'v1', categoria: 'efectivo');
    ClienteMetodoPagoViajeUi.limpiar('v2');

    expect(ClienteMetodoPagoViajeUi.categoriaPara('v1'), 'efectivo');
  });

  test('ignora categorías inválidas', () {
    ClienteMetodoPagoViajeUi.marcar(viajeId: 'v1', categoria: 'cheque');

    expect(ClienteMetodoPagoViajeUi.categoriaPara('v1'), '');
  });
}
