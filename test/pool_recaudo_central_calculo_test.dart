import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/utils/pool_recaudo_central.dart';

void main() {
  const pool = <String, dynamic>{
    'recaudoModelo': 'central',
    'precioPorAsiento': 1000,
    'sentido': 'ida',
    'comisionGiraPctUsado': 10,
  };

  test('total = asientos × precio por asiento', () {
    expect(
      PoolRecaudoCentral.totalReservaRd(pool: pool, asientos: 2),
      2000,
    );
    expect(PoolRecaudoCentral.precioPorPersona(pool), 1000);
  });

  test('comisión = % sobre total de asientos vendidos, no gira entera', () {
    expect(
      PoolRecaudoCentral.comisionRaiRd(
        pool: pool,
        asientos: 2,
        pctComision: 10,
      ),
      200,
    );
    expect(
      PoolRecaudoCentral.netoOrganizadorRd(
        pool: pool,
        asientos: 2,
        pctComision: 10,
      ),
      1800,
    );
  });

  test('ida y vuelta duplica precio por persona', () {
    final poolIv = <String, dynamic>{
      ...pool,
      'sentido': 'ida_y_vuelta',
    };
    expect(PoolRecaudoCentral.precioPorPersona(poolIv), 2000);
    expect(
      PoolRecaudoCentral.totalReservaRd(pool: poolIv, asientos: 1),
      2000,
    );
    expect(
      PoolRecaudoCentral.comisionRaiRd(
        pool: poolIv,
        asientos: 1,
        pctComision: 10,
      ),
      200,
    );
  });

  test('desglose resumen efectivo', () {
    final d = PoolRecaudoCentral.desgloseReserva(
      pool: pool,
      asientos: 2,
      pctComision: 10,
    );
    expect(d.totalBruto, 2000);
    expect(d.comisionRai, 200);
    expect(d.netoOrganizador, 1800);
    expect(
      d.resumenLinea(efectivoAlAbordar: true),
      contains('2 asientos × RD\$ 1000 = RD\$ 2000'),
    );
  });
}
