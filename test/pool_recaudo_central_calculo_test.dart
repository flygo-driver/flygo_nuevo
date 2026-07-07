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

  test('ida y vuelta no duplica precio (monto final por persona)', () {
    final poolIv = <String, dynamic>{
      ...pool,
      'sentido': 'ida_y_vuelta',
    };
    expect(PoolRecaudoCentral.precioPorPersona(poolIv), 1000);
    expect(
      PoolRecaudoCentral.totalReservaRd(pool: poolIv, asientos: 1),
      1000,
    );
    expect(
      PoolRecaudoCentral.comisionRaiRd(
        pool: poolIv,
        asientos: 1,
        pctComision: 10,
      ),
      100,
    );
  });

  test('cierre contable: prepago descuenta retención del recaudo', () {
    final pool = <String, dynamic>{
      'recaudoModelo': 'central',
      'montoRecaudadoRaiRd': 10000,
      'montoComisionRaiRd': 1000,
      'prepagoComisionAplicadaRd': 200,
    };
    final c = PoolRecaudoCentral.cierreDesdePool(pool);
    expect(c.brutoRecaudadoRd, 10000);
    expect(c.comisionVentasRd, 1000);
    expect(c.recargaCompradaRd, 200);
    expect(c.prepagoAplicadoRd, 200);
    expect(c.superoRecargaComprada, isTrue);
    expect(c.montoFaltaRetenerDelRecaudoRd, 800);
    expect(c.netoOrganizadorFinalRd, 9200);
    expect(c.formulaTransferenciaExacta, contains('9200'));
  });

  test('cierre: recarga cubre toda la comisión', () {
    final pool = <String, dynamic>{
      'montoRecaudadoRaiRd': 500,
      'montoComisionRaiRd': 50,
      'comisionGiraEstimadaRd': 200,
    };
    final c = PoolRecaudoCentral.cierreDesdePool(pool);
    expect(c.superoRecargaComprada, isFalse);
    expect(c.montoFaltaRetenerDelRecaudoRd, 0);
    expect(c.netoOrganizadorFinalRd, 500);
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
