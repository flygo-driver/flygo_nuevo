import 'package:flutter_test/flutter_test.dart';
import 'package:flygo_nuevo/servicios/corporativo_tarifa_config_service.dart';
import 'package:flygo_nuevo/servicios/corporativo_tarifa_modelos.dart';

void main() {
  group('Ley 30-26 facturación corporativa', () {
    test('caso RD\$10,000 — impuesto 0.20%, ISR 2%, comisión 10%, chofer 90%', () {
      const cfg = CorporativoTarifaConfig(
        tasaImpuestoTransferencia: 0.002,
        comisionPlataformaPorcentaje: 10,
        retencionIsrPorcentaje: 2,
      );

      final liq = CorporativoFacturaCalculo.desdePrecioBase(
        precioBaseServicio: 10000,
        cfg: cfg,
      );

      expect(liq.tasaImpuestoTransferencia, 0.002);
      expect(liq.impuestoTransferenciaRd, 20);
      expect(liq.montoTotalFacturaRd, 10020);
      expect(liq.retencionIsrRd, 200);
      expect(liq.comisionPlataformaRd, 1000);
      expect(liq.pagoChoferRd, 9000);
    });

    test('recargo empresa 5% sobre costo operativo', () {
      // Todos los cargos variables en cero: el costo operativo debe quedar en la
      // base (1000) para poder aislar el 5% de recargo de empresa.
      const cfg = CorporativoTarifaConfig(
        tasaImpuestoTransferencia: 0.002,
        comisionPlataformaPorcentaje: 10,
        recargoEmpresaServicioPorcentaje: 5,
        minimoViajeRd: 0,
        dinamicaBaseRd: 1000,
        dinamicaPorKmCortoRd: 0,
        dinamicaPorKmLargoRd: 0,
        dinamicaPorMinutoRd: 0,
        dinamicaMinutosMinimo: 0,
        dinamicaCargoPorParadaRd: 0,
        recargoZonaDificilPorcentaje: 0,
        precioCombustibleLitroRd: 0,
      );
      final d = CorporativoTarifaDinamicaModel.calcular(
        kmLineaRecta: 5,
        cfg: cfg,
        numParadas: 1,
      );
      expect(d.costoOperativoRd, 1000);
      expect(d.recargoEmpresaServicioRd, 50);
      expect(d.precioBaseServicioRd, 1050);
      expect(d.pagoChoferRd, 945);
      expect(d.cargoCompaniaRd, 105);
    });

    test('tasa_impuesto_transferencia global por defecto = 0.002', () {
      expect(
        CorporativoTarifaConfig.defaults.tasaImpuestoTransferencia,
        CorporativoTarifaDinamicaModel.tasaImpuestoTransferenciaDefault,
      );
      expect(CorporativoTarifaConfig.defaults.tasaImpuestoTransferencia, 0.002);
    });

    test('legacy Firestore 15% migra a 0.002', () {
      final cfg = CorporativoTarifaConfig.fromMap({
        'recargoTransferenciaPorcentaje': 15,
      });
      expect(cfg.tasaImpuestoTransferencia, 0.002);
    });

    test('lee tasa_impuesto_transferencia snake_case', () {
      final cfg = CorporativoTarifaConfig.fromMap({
        'tasa_impuesto_transferencia': 0.002,
      });
      expect(cfg.tasaImpuestoTransferencia, 0.002);
      expect(cfg.recargoTransferenciaPorcentaje, closeTo(0.2, 1e-9));
    });
    test('piso por combustible en ruta corta', () {
      const cfg = CorporativoTarifaConfig(
        tasaImpuestoTransferencia: 0.002,
        comisionPlataformaPorcentaje: 10,
        recargoEmpresaServicioPorcentaje: 5,
        minimoViajeRd: 0,
        dinamicaBaseRd: 50,
        dinamicaPorKmCortoRd: 5,
        dinamicaPorKmLargoRd: 5,
        dinamicaPorMinutoRd: 2,
        dinamicaMinutosMinimo: 5,
        precioCombustibleLitroRd: 330,
        rendimientoVehiculoKmPorLitro: 11,
        factorOperativoSobreCombustible: 1.35,
      );
      final d = CorporativoTarifaDinamicaModel.calcular(
        kmLineaRecta: 8,
        cfg: cfg,
        numParadas: 2,
      );
      expect(d.cargoCombustibleRd, greaterThan(0));
      expect(d.cargoKmRd, greaterThanOrEqualTo(d.cargoCombustibleRd));
      expect(d.pagoChoferRd, greaterThan(0));
    });
  });
}
