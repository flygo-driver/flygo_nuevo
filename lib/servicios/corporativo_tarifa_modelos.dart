import 'dart:math' as math;

import 'package:flygo_nuevo/servicios/corporativo_tarifa_config_service.dart';
import 'package:flygo_nuevo/servicios/distancia_service.dart';

/// Facturación corporativa (Ley 30-26 / DGII transferencia).
///
/// Precio_Base_Servicio = costo del transporte.
/// Impuesto_Transferencia = base × tasa_impuesto_transferencia (0.002 = 0.20%).
/// Monto_Total_Factura = base + impuesto (lo que paga la empresa).
/// Comisión 10%, pago chofer 90% e ISR 2% se calculan sobre el Precio_Base.
abstract final class CorporativoFacturaCalculo {
  CorporativoFacturaCalculo._();

  static CorporativoLiquidacionMontos desdePrecioBase({
    required double precioBaseServicio,
    required CorporativoTarifaConfig cfg,
  }) {
    final base = precioBaseServicio.isFinite && precioBaseServicio > 0
        ? precioBaseServicio
        : 0.0;
    final impuesto = base * cfg.tasaImpuestoTransferencia;
    final total = base + impuesto;
    final comisionPct =
        cfg.comisionPlataformaPorcentaje.clamp(0, 100).toDouble();
    final comision = base * (comisionPct / 100.0);
    final pagoChofer = base * ((100.0 - comisionPct) / 100.0);
    final isrPct = cfg.retencionIsrPorcentaje.clamp(0, 100).toDouble();
    final isr = base * (isrPct / 100.0);
    return CorporativoLiquidacionMontos(
      precioBaseServicioRd: base,
      impuestoTransferenciaRd: impuesto,
      montoTotalFacturaRd: total,
      comisionPlataformaRd: comision,
      pagoChoferRd: pagoChofer,
      retencionIsrRd: isr,
      tasaImpuestoTransferencia: cfg.tasaImpuestoTransferencia,
      comisionPlataformaPorcentaje: comisionPct,
      retencionIsrPorcentaje: isrPct,
    );
  }
}

class CorporativoLiquidacionMontos {
  const CorporativoLiquidacionMontos({
    required this.precioBaseServicioRd,
    required this.impuestoTransferenciaRd,
    required this.montoTotalFacturaRd,
    required this.comisionPlataformaRd,
    required this.pagoChoferRd,
    required this.retencionIsrRd,
    required this.tasaImpuestoTransferencia,
    required this.comisionPlataformaPorcentaje,
    required this.retencionIsrPorcentaje,
  });

  final double precioBaseServicioRd;
  final double impuestoTransferenciaRd;
  final double montoTotalFacturaRd;
  final double comisionPlataformaRd;
  final double pagoChoferRd;
  final double retencionIsrRd;
  final double tasaImpuestoTransferencia;
  final double comisionPlataformaPorcentaje;
  final double retencionIsrPorcentaje;
}

/// Tarifa corporativa dinámica: base + km + tiempo → Precio_Base,
/// luego + impuesto transferencia (0.20%) en la factura al cliente.
abstract final class CorporativoTarifaDinamicaModel {
  CorporativoTarifaDinamicaModel._();

  static const String modeloId = 'dinamica';
  static const String legacyModeloId = 'uber_x';

  static const double baseDefault = 200;
  static const double porKmCortoDefault = 18;
  static const double porKmLargoDefault = 24;
  static const double umbralKmLargoDefault = 12;
  static const double porMinutoDefault = 7;
  static const double minutosPorKmDefault = 1.4;
  static const double minutosPorParadaDefault = 5;
  static const double minutosMinimoDefault = 10;
  /// Espera en empresa: empleados suben a la guagua (RD).
  static const double minutosEmbarqueEmpresaDefault = 12;
  /// Km mínimo por tramo ordenado (empresa→P1, P1→P2…) aunque GPS estén cerca.
  static const double kmMinimoPorTramoDefault = 0.85;
  /// Cargo fijo por cada pasajero/destino en la ruta (bajada + maniobra).
  static const double cargoPorParadaRdDefault = 75;
  /// Tasa DGII transferencia/cheque (Ley 30-26): 0.20% = 0.002.
  static const double tasaImpuestoTransferenciaDefault = 0.002;
  /// Compat: porcentaje equivalente (0.20).
  static const double cuotaSolicitudPctDefault = 0.2;
  static const double comisionCompaniaPctDefault = 10;
  static const double retencionIsrPctDefault = 2;
  static const double precioCombustibleLitroDefault = 330;
  static const double rendimientoKmPorLitroDefault = 11;
  static const double factorOperativoCombustibleDefault = 1.35;
  static const double recargoEmpresaServicioPctDefault = 5;

  static double costoCombustibleRdPorKm(CorporativoTarifaConfig cfg) {
    final litro = cfg.precioCombustibleLitroRd.clamp(0, 9999);
    final rend = cfg.rendimientoVehiculoKmPorLitro.clamp(1, 40);
    return litro / rend;
  }

  static double cargoCombustibleOperativoRd(
    double kmCotizados,
    CorporativoTarifaConfig cfg,
  ) {
    final factor = cfg.factorOperativoSobreCombustible.clamp(1, 3);
    return (kmCotizados * costoCombustibleRdPorKm(cfg) * factor).roundToDouble();
  }

  static bool esId(String? id) {
    final m = (id ?? '').trim().toLowerCase();
    if (m == CorporativoTarifaCarroModel.modeloId) return false;
    if (m == modeloId || m == legacyModeloId || m.isEmpty) return true;
    return m != 'carro';
  }

  static double cargoKm(double km, CorporativoTarifaConfig cfg) {
    final k = km.clamp(0, 500);
    final umbral = cfg.dinamicaUmbralKmLargo;
    if (k <= umbral) return k * cfg.dinamicaPorKmCortoRd;
    return umbral * cfg.dinamicaPorKmCortoRd +
        (k - umbral) * cfg.dinamicaPorKmLargoRd;
  }

  static double minutosEstimados({
    required double km,
    required CorporativoTarifaConfig cfg,
    int numParadas = 1,
  }) {
    final paradas = math.max(1, numParadas);
    final embarque = cfg.dinamicaMinutosEmbarqueEmpresa;
    final porTiempo = km * cfg.dinamicaMinutosPorKm;
    // Cada pasajero activo: entrega en su destino (ruta en orden).
    final porEntregas = paradas * cfg.dinamicaMinutosPorParada;
    return math.max(
      cfg.dinamicaMinutosMinimo,
      embarque + porTiempo + porEntregas,
    );
  }

  static CorporativoTarifaDesglose calcular({
    required double kmLineaRecta,
    required CorporativoTarifaConfig cfg,
    int numParadas = 1,
  }) {
    if (kmLineaRecta <= 0) {
      return CorporativoTarifaDesglose.cero(modeloTarifa: modeloId);
    }

    final kmCotizados =
        (kmLineaRecta * cfg.factorKmCarretera).clamp(0.1, 500.0);
    final base = cfg.dinamicaBaseRd;
    final cargoCombustible =
        CorporativoTarifaDinamicaModel.cargoCombustibleOperativoRd(
      kmCotizados,
      cfg,
    );
    final cargoKmTabla = CorporativoTarifaDinamicaModel.cargoKm(kmCotizados, cfg);
    final cargoKmRd = math.max(cargoKmTabla, cargoCombustible);
    final minutos = minutosEstimados(
      km: kmCotizados,
      cfg: cfg,
      numParadas: numParadas,
    );
    final cargoTiempo = minutos * cfg.dinamicaPorMinutoRd;
    final paradas = math.max(1, numParadas);
    final cargoParadas = paradas * cfg.dinamicaCargoPorParadaRd;
    final nucleo = base + cargoKmRd + cargoTiempo + cargoParadas;
    final recargoZona = nucleo * (cfg.recargoZonaDificilPorcentaje / 100.0);
    var costoOperativo = nucleo + recargoZona;
    if (cfg.minimoViajeRd > 0) {
      costoOperativo = math.max(costoOperativo, cfg.minimoViajeRd);
    }
    final recargoEmpPct =
        cfg.recargoEmpresaServicioPorcentaje.clamp(0, 50).toDouble();
    final recargoEmpresa = costoOperativo * (recargoEmpPct / 100.0);
    final precioBase = costoOperativo + recargoEmpresa;

    final liq = CorporativoFacturaCalculo.desdePrecioBase(
      precioBaseServicio: precioBase,
      cfg: cfg,
    );

    return CorporativoTarifaDesglose(
      kmLineaRecta: kmLineaRecta,
      kmCotizados: kmCotizados,
      tarifaBaseRd: base,
      recargoZonaRd: recargoZona,
      subtotalFacturaRd: liq.precioBaseServicioRd,
      cargoCompaniaRd: liq.comisionPlataformaRd,
      recargoFacturaRd: liq.impuestoTransferenciaRd,
      precioViajeRd: liq.montoTotalFacturaRd,
      gananciaRaiEstimadaRd: liq.comisionPlataformaRd,
      itbisRaiEstimadoRd: 0,
      modeloTarifa: modeloId,
      cargoKmRd: cargoKmRd,
      cargoTiempoRd: cargoTiempo,
      minutosEstimados: minutos,
      numParadas: numParadas,
      cargoParadasRd: cargoParadas,
      precioBaseServicioRd: liq.precioBaseServicioRd,
      impuestoTransferenciaRd: liq.impuestoTransferenciaRd,
      retencionIsrRd: liq.retencionIsrRd,
      pagoChoferRd: liq.pagoChoferRd,
      tasaImpuestoTransferencia: liq.tasaImpuestoTransferencia,
      costoOperativoRd: costoOperativo,
      recargoEmpresaServicioRd: recargoEmpresa,
      cargoCombustibleRd: cargoCombustible,
    );
  }
}

/// Desglose unificado: tarifa contratada, plantilla o cálculo automático RD.
abstract final class CorporativoTarifaDesgloseBuilder {
  CorporativoTarifaDesgloseBuilder._();

  static CorporativoTarifaDesglose construir({
    required double kmLineaRecta,
    required CorporativoTarifaConfig cfg,
    int numParadas = 1,
    double tarifaContratadaEmpresa = 0,
    double precioAcordadoPlantilla = 0,
  }) {
    final contratada = tarifaContratadaEmpresa > 0
        ? tarifaContratadaEmpresa.roundToDouble()
        : 0.0;
    if (contratada > 0) {
      final kmCotizados =
          (kmLineaRecta * cfg.factorKmCarretera).clamp(0.1, 500.0);
      final liq = CorporativoFacturaCalculo.desdePrecioBase(
        precioBaseServicio: contratada,
        cfg: cfg,
      );
      return CorporativoTarifaDesglose(
        kmLineaRecta: kmLineaRecta,
        kmCotizados: kmCotizados,
        tarifaBaseRd: contratada,
        recargoZonaRd: 0,
        subtotalFacturaRd: liq.precioBaseServicioRd,
        cargoCompaniaRd: liq.comisionPlataformaRd,
        recargoFacturaRd: liq.impuestoTransferenciaRd,
        precioViajeRd: liq.montoTotalFacturaRd,
        gananciaRaiEstimadaRd: liq.comisionPlataformaRd,
        itbisRaiEstimadoRd: 0,
        modeloTarifa: cfg.modeloTarifa,
        numParadas: numParadas,
        precioBaseServicioRd: liq.precioBaseServicioRd,
        impuestoTransferenciaRd: liq.impuestoTransferenciaRd,
        retencionIsrRd: liq.retencionIsrRd,
        pagoChoferRd: liq.pagoChoferRd,
        tasaImpuestoTransferencia: liq.tasaImpuestoTransferencia,
      );
    }
    final acordado =
        precioAcordadoPlantilla > 0 ? precioAcordadoPlantilla.roundToDouble() : 0.0;
    if (acordado > 0) {
      final kmCotizados =
          (kmLineaRecta * cfg.factorKmCarretera).clamp(0.1, 500.0);
      final liq = CorporativoFacturaCalculo.desdePrecioBase(
        precioBaseServicio: acordado,
        cfg: cfg,
      );
      return CorporativoTarifaDesglose(
        kmLineaRecta: kmLineaRecta,
        kmCotizados: kmCotizados,
        tarifaBaseRd: acordado,
        recargoZonaRd: 0,
        subtotalFacturaRd: liq.precioBaseServicioRd,
        cargoCompaniaRd: liq.comisionPlataformaRd,
        recargoFacturaRd: liq.impuestoTransferenciaRd,
        precioViajeRd: liq.montoTotalFacturaRd,
        gananciaRaiEstimadaRd: liq.comisionPlataformaRd,
        itbisRaiEstimadoRd: 0,
        modeloTarifa: cfg.modeloTarifa,
        numParadas: numParadas,
        precioBaseServicioRd: liq.precioBaseServicioRd,
        impuestoTransferenciaRd: liq.impuestoTransferenciaRd,
        retencionIsrRd: liq.retencionIsrRd,
        pagoChoferRd: liq.pagoChoferRd,
        tasaImpuestoTransferencia: liq.tasaImpuestoTransferencia,
      );
    }
    if (cfg.esModeloDinamica) {
      return CorporativoTarifaDinamicaModel.calcular(
        kmLineaRecta: kmLineaRecta,
        cfg: cfg,
        numParadas: numParadas,
      );
    }
    return CorporativoTarifaCarroModel.calcular(
      kmLineaRecta: kmLineaRecta,
      cfg: cfg,
      numParadas: numParadas,
    );
  }
}

/// Modelo legacy Carro RAI (respaldo).
abstract final class CorporativoTarifaCarroModel {
  CorporativoTarifaCarroModel._();

  static const String modeloId = 'carro';

  static CorporativoTarifaDesglose calcular({
    required double kmLineaRecta,
    required CorporativoTarifaConfig cfg,
    int numParadas = 1,
  }) {
    if (kmLineaRecta <= 0) {
      return CorporativoTarifaDesglose.cero(modeloTarifa: modeloId);
    }

    final kmCotizados =
        (kmLineaRecta * cfg.factorKmCarretera).clamp(0.1, 500.0);
    final tarifaBase = math.max(
      DistanciaService.calcularPrecio(kmCotizados),
      0,
    ).toDouble();
    final recargoZona =
        tarifaBase * (cfg.recargoZonaDificilPorcentaje / 100.0);
    var costoOperativo = tarifaBase + recargoZona;
    if (cfg.minimoViajeRd > 0) {
      costoOperativo = math.max(costoOperativo, cfg.minimoViajeRd);
    }
    final recargoEmpPct =
        cfg.recargoEmpresaServicioPorcentaje.clamp(0, 50).toDouble();
    final recargoEmpresa = costoOperativo * (recargoEmpPct / 100.0);
    final paradas = math.max(1, numParadas);
    final cargoParadas = paradas * cfg.dinamicaCargoPorParadaRd;
    final minutos = CorporativoTarifaDinamicaModel.minutosEstimados(
      km: kmCotizados,
      cfg: cfg,
      numParadas: numParadas,
    );
    final cargoTiempo = minutos * cfg.dinamicaPorMinutoRd;
    final precioBase =
        costoOperativo + recargoEmpresa + cargoParadas + cargoTiempo;

    final liq = CorporativoFacturaCalculo.desdePrecioBase(
      precioBaseServicio: precioBase,
      cfg: cfg,
    );

    return CorporativoTarifaDesglose(
      kmLineaRecta: kmLineaRecta,
      kmCotizados: kmCotizados,
      tarifaBaseRd: tarifaBase,
      recargoZonaRd: recargoZona,
      subtotalFacturaRd: liq.precioBaseServicioRd,
      cargoCompaniaRd: liq.comisionPlataformaRd,
      recargoFacturaRd: liq.impuestoTransferenciaRd,
      precioViajeRd: liq.montoTotalFacturaRd,
      gananciaRaiEstimadaRd: liq.comisionPlataformaRd,
      itbisRaiEstimadoRd: 0,
      modeloTarifa: modeloId,
      numParadas: numParadas,
      precioBaseServicioRd: liq.precioBaseServicioRd,
      impuestoTransferenciaRd: liq.impuestoTransferenciaRd,
      retencionIsrRd: liq.retencionIsrRd,
      pagoChoferRd: liq.pagoChoferRd,
      tasaImpuestoTransferencia: liq.tasaImpuestoTransferencia,
      costoOperativoRd: costoOperativo,
      recargoEmpresaServicioRd: recargoEmpresa,
      cargoParadasRd: cargoParadas,
      cargoTiempoRd: cargoTiempo,
      minutosEstimados: minutos,
    );
  }
}
