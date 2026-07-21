import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flygo_nuevo/servicios/corporativo_tarifa_modelos.dart';

/// Parámetros globales de tarifa corporativa (`config/corporativo`).
class CorporativoTarifaConfig {
  const CorporativoTarifaConfig({
    this.modeloTarifa = CorporativoTarifaDinamicaModel.modeloId,
    this.minimoViajeRd = 550,
    this.factorKmCarretera = 1.15,
    this.recargoZonaDificilPorcentaje = 0,
    /// Compat: porcentaje DGII (0.20 = 0.20%). Preferir [tasaImpuestoTransferencia].
    this.recargoTransferenciaPorcentaje =
        CorporativoTarifaDinamicaModel.cuotaSolicitudPctDefault,
    /// Tasa fracción Ley 30-26 (0.002 = 0.20%). Variable global configurable.
    this.tasaImpuestoTransferencia =
        CorporativoTarifaDinamicaModel.tasaImpuestoTransferenciaDefault,
    this.retencionIsrPorcentaje =
        CorporativoTarifaDinamicaModel.retencionIsrPctDefault,
    this.itbisPorcentaje = 18,
    this.incluirItbisEnPrecioViaje = false,
    this.usarComisionGlobalViaje = false,
    this.comisionPlataformaPorcentaje =
        CorporativoTarifaDinamicaModel.comisionCompaniaPctDefault,
    this.dinamicaBaseRd = CorporativoTarifaDinamicaModel.baseDefault,
    this.dinamicaPorKmCortoRd = CorporativoTarifaDinamicaModel.porKmCortoDefault,
    this.dinamicaPorKmLargoRd = CorporativoTarifaDinamicaModel.porKmLargoDefault,
    this.dinamicaUmbralKmLargo =
        CorporativoTarifaDinamicaModel.umbralKmLargoDefault,
    this.dinamicaPorMinutoRd = CorporativoTarifaDinamicaModel.porMinutoDefault,
    this.dinamicaMinutosPorKm =
        CorporativoTarifaDinamicaModel.minutosPorKmDefault,
    this.dinamicaMinutosPorParada =
        CorporativoTarifaDinamicaModel.minutosPorParadaDefault,
    this.dinamicaMinutosMinimo =
        CorporativoTarifaDinamicaModel.minutosMinimoDefault,
    this.dinamicaMinutosEmbarqueEmpresa =
        CorporativoTarifaDinamicaModel.minutosEmbarqueEmpresaDefault,
    this.kmMinimoPorTramo =
        CorporativoTarifaDinamicaModel.kmMinimoPorTramoDefault,
    this.dinamicaCargoPorParadaRd =
        CorporativoTarifaDinamicaModel.cargoPorParadaRdDefault,
    this.precioCombustibleLitroRd =
        CorporativoTarifaDinamicaModel.precioCombustibleLitroDefault,
    this.rendimientoVehiculoKmPorLitro =
        CorporativoTarifaDinamicaModel.rendimientoKmPorLitroDefault,
    this.factorOperativoSobreCombustible =
        CorporativoTarifaDinamicaModel.factorOperativoCombustibleDefault,
    this.recargoEmpresaServicioPorcentaje =
        CorporativoTarifaDinamicaModel.recargoEmpresaServicioPctDefault,
  });

  /// `dinamica` (tarifa por km + tiempo) o `carro` (tarifa RAI clásica).
  final String modeloTarifa;
  final double minimoViajeRd;
  final double factorKmCarretera;
  final double recargoZonaDificilPorcentaje;
  final double recargoTransferenciaPorcentaje;
  final double tasaImpuestoTransferencia;
  final double retencionIsrPorcentaje;
  final double itbisPorcentaje;
  final bool incluirItbisEnPrecioViaje;
  final bool usarComisionGlobalViaje;
  final double comisionPlataformaPorcentaje;
  final double dinamicaBaseRd;
  final double dinamicaPorKmCortoRd;
  final double dinamicaPorKmLargoRd;
  final double dinamicaUmbralKmLargo;
  final double dinamicaPorMinutoRd;
  final double dinamicaMinutosPorKm;
  final double dinamicaMinutosPorParada;
  final double dinamicaMinutosMinimo;
  final double dinamicaMinutosEmbarqueEmpresa;
  final double kmMinimoPorTramo;
  final double dinamicaCargoPorParadaRd;
  final double precioCombustibleLitroRd;
  final double rendimientoVehiculoKmPorLitro;
  final double factorOperativoSobreCombustible;
  final double recargoEmpresaServicioPorcentaje;

  bool get esModeloDinamica => CorporativoTarifaDinamicaModel.esId(modeloTarifa);

  static const CorporativoTarifaConfig defaults = CorporativoTarifaConfig();

  /// Resuelve tasa 0.002 desde Firestore (nuevos + legacy 15%/6%).
  static double resolverTasaImpuestoTransferencia(Map<String, dynamic> m) {
    double d(dynamic v, double? fallback) {
      if (v is num && v.isFinite) return v.toDouble();
      return fallback ?? double.nan;
    }

    final fromSnake = d(m['tasa_impuesto_transferencia'], null);
    if (fromSnake.isFinite && fromSnake >= 0 && fromSnake <= 1) {
      return fromSnake;
    }
    final fromCamel = d(m['tasaImpuestoTransferencia'], null);
    if (fromCamel.isFinite && fromCamel >= 0 && fromCamel <= 1) {
      return fromCamel;
    }

    final pct = d(m['recargoTransferenciaPorcentaje'], null);
    if (pct.isFinite) {
      // Legacy: 15 o 6 = antigua “cuota grande” → Ley 30-26 = 0.20%.
      if (pct == 15 || pct == 6) {
        return CorporativoTarifaDinamicaModel.tasaImpuestoTransferenciaDefault;
      }
      // 0.20 o 0.2 → 0.20% = 0.002
      if (pct > 0 && pct <= 1) {
        return pct / 100.0;
      }
      // Ya en fracción por error (0.002)
      if (pct > 0 && pct < 0.01) {
        return pct;
      }
      // Porcentaje tipo 0.20
      if (pct > 0 && pct < 5) {
        return pct / 100.0;
      }
    }
    return CorporativoTarifaDinamicaModel.tasaImpuestoTransferenciaDefault;
  }

  static String _modeloFromMap(Map<String, dynamic> m) {
    final raw = (m['modeloTarifa'] ?? defaults.modeloTarifa).toString().trim();
    final lower = raw.toLowerCase();
    if (lower == CorporativoTarifaCarroModel.modeloId) {
      return CorporativoTarifaCarroModel.modeloId;
    }
    if (lower == CorporativoTarifaDinamicaModel.legacyModeloId ||
        lower.isEmpty) {
      return CorporativoTarifaDinamicaModel.modeloId;
    }
    return raw;
  }

  factory CorporativoTarifaConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null || m.isEmpty) return defaults;
    double d(dynamic v, double fallback) {
      if (v is num && v.isFinite) return v.toDouble();
      return fallback;
    }

    double din(String nue, String leg, double fallback) =>
        d(m[nue] ?? m[leg], fallback);

    bool b(dynamic v, bool fallback) => v is bool ? v : fallback;

    final tasa = resolverTasaImpuestoTransferencia(m);
    return CorporativoTarifaConfig(
      modeloTarifa: _modeloFromMap(m),
      minimoViajeRd: d(m['minimoViajeRd'], defaults.minimoViajeRd),
      factorKmCarretera: d(m['factorKmCarretera'], defaults.factorKmCarretera)
          .clamp(1.0, 2.5),
      recargoZonaDificilPorcentaje: d(
        m['recargoZonaDificilPorcentaje'],
        defaults.recargoZonaDificilPorcentaje,
      ).clamp(0, 100),
      tasaImpuestoTransferencia: tasa.clamp(0.0, 1.0),
      recargoTransferenciaPorcentaje: (tasa * 100.0).clamp(0.0, 100.0),
      retencionIsrPorcentaje: d(
        m['retencionIsrPorcentaje'] ?? m['retencion_isr_porcentaje'],
        defaults.retencionIsrPorcentaje,
      ).clamp(0, 100),
      itbisPorcentaje:
          d(m['itbisPorcentaje'], defaults.itbisPorcentaje).clamp(0, 100),
      incluirItbisEnPrecioViaje:
          b(m['incluirItbisEnPrecioViaje'], defaults.incluirItbisEnPrecioViaje),
      usarComisionGlobalViaje:
          b(m['usarComisionGlobalViaje'], defaults.usarComisionGlobalViaje),
      comisionPlataformaPorcentaje: d(
        m['comisionPlataformaPorcentaje'],
        defaults.comisionPlataformaPorcentaje,
      ).clamp(0, 100),
      dinamicaBaseRd: din('dinamicaBaseRd', 'uberBaseRd', defaults.dinamicaBaseRd),
      dinamicaPorKmCortoRd: din(
        'dinamicaPorKmCortoRd',
        'uberPorKmCortoRd',
        defaults.dinamicaPorKmCortoRd,
      ),
      dinamicaPorKmLargoRd: din(
        'dinamicaPorKmLargoRd',
        'uberPorKmLargoRd',
        defaults.dinamicaPorKmLargoRd,
      ),
      dinamicaUmbralKmLargo: din(
        'dinamicaUmbralKmLargo',
        'uberUmbralKmLargo',
        defaults.dinamicaUmbralKmLargo,
      ),
      dinamicaPorMinutoRd: din(
        'dinamicaPorMinutoRd',
        'uberPorMinutoRd',
        defaults.dinamicaPorMinutoRd,
      ),
      dinamicaMinutosPorKm: din(
        'dinamicaMinutosPorKm',
        'uberMinutosPorKm',
        defaults.dinamicaMinutosPorKm,
      ),
      dinamicaMinutosPorParada: din(
        'dinamicaMinutosPorParada',
        'uberMinutosPorParada',
        defaults.dinamicaMinutosPorParada,
      ),
      dinamicaMinutosMinimo: din(
        'dinamicaMinutosMinimo',
        'uberMinutosMinimo',
        defaults.dinamicaMinutosMinimo,
      ),
      dinamicaMinutosEmbarqueEmpresa: d(
        m['dinamicaMinutosEmbarqueEmpresa'],
        defaults.dinamicaMinutosEmbarqueEmpresa,
      ).clamp(0, 120),
      kmMinimoPorTramo: d(
        m['kmMinimoPorTramo'],
        defaults.kmMinimoPorTramo,
      ).clamp(0, 5),
      dinamicaCargoPorParadaRd: d(
        m['dinamicaCargoPorParadaRd'],
        defaults.dinamicaCargoPorParadaRd,
      ).clamp(0, 9999),
      precioCombustibleLitroRd: d(
        m['precioCombustibleLitroRd'],
        defaults.precioCombustibleLitroRd,
      ).clamp(0, 9999),
      rendimientoVehiculoKmPorLitro: d(
        m['rendimientoVehiculoKmPorLitro'],
        defaults.rendimientoVehiculoKmPorLitro,
      ).clamp(1, 40),
      factorOperativoSobreCombustible: d(
        m['factorOperativoSobreCombustible'],
        defaults.factorOperativoSobreCombustible,
      ).clamp(1, 3),
      recargoEmpresaServicioPorcentaje: d(
        m['recargoEmpresaServicioPorcentaje'],
        defaults.recargoEmpresaServicioPorcentaje,
      ).clamp(0, 50),
    );
  }

  Map<String, dynamic> toMap() => {
        'modeloTarifa': modeloTarifa,
        'minimoViajeRd': minimoViajeRd.round(),
        'factorKmCarretera': factorKmCarretera,
        'recargoZonaDificilPorcentaje': recargoZonaDificilPorcentaje,
        // Fuente de verdad + aliases para admin / CF.
        'tasa_impuesto_transferencia': tasaImpuestoTransferencia,
        'tasaImpuestoTransferencia': tasaImpuestoTransferencia,
        'recargoTransferenciaPorcentaje': tasaImpuestoTransferencia * 100.0,
        'retencionIsrPorcentaje': retencionIsrPorcentaje,
        'retencion_isr_porcentaje': retencionIsrPorcentaje,
        'itbisPorcentaje': itbisPorcentaje,
        'incluirItbisEnPrecioViaje': incluirItbisEnPrecioViaje,
        'usarComisionGlobalViaje': usarComisionGlobalViaje,
        'comisionPlataformaPorcentaje': comisionPlataformaPorcentaje,
        'dinamicaBaseRd': dinamicaBaseRd.round(),
        'dinamicaPorKmCortoRd': dinamicaPorKmCortoRd,
        'dinamicaPorKmLargoRd': dinamicaPorKmLargoRd,
        'dinamicaUmbralKmLargo': dinamicaUmbralKmLargo,
        'dinamicaPorMinutoRd': dinamicaPorMinutoRd,
        'dinamicaMinutosPorKm': dinamicaMinutosPorKm,
        'dinamicaMinutosPorParada': dinamicaMinutosPorParada,
        'dinamicaMinutosMinimo': dinamicaMinutosMinimo,
        'dinamicaMinutosEmbarqueEmpresa': dinamicaMinutosEmbarqueEmpresa.round(),
        'kmMinimoPorTramo': kmMinimoPorTramo,
        'dinamicaCargoPorParadaRd': dinamicaCargoPorParadaRd.round(),
        'precioCombustibleLitroRd': precioCombustibleLitroRd.round(),
        'rendimientoVehiculoKmPorLitro': rendimientoVehiculoKmPorLitro,
        'factorOperativoSobreCombustible': factorOperativoSobreCombustible,
        'recargoEmpresaServicioPorcentaje': recargoEmpresaServicioPorcentaje,
      };
}

/// Desglose interno (UI de encargado: solo total + km; detalle oculto).
class CorporativoTarifaDesglose {
  const CorporativoTarifaDesglose({
    required this.kmLineaRecta,
    required this.kmCotizados,
    required this.tarifaBaseRd,
    required this.recargoZonaRd,
    required this.subtotalFacturaRd,
    required this.recargoFacturaRd,
    required this.precioViajeRd,
    required this.gananciaRaiEstimadaRd,
    required this.itbisRaiEstimadoRd,
    this.modeloTarifa = CorporativoTarifaDinamicaModel.modeloId,
    this.cargoKmRd = 0,
    this.cargoTiempoRd = 0,
    this.minutosEstimados = 0,
    this.numParadas = 1,
    this.cargoCompaniaRd = 0,
    this.precioBaseServicioRd = 0,
    this.impuestoTransferenciaRd = 0,
    this.retencionIsrRd = 0,
    this.pagoChoferRd = 0,
    this.tasaImpuestoTransferencia =
        CorporativoTarifaDinamicaModel.tasaImpuestoTransferenciaDefault,
    this.costoOperativoRd = 0,
    this.recargoEmpresaServicioRd = 0,
    this.cargoCombustibleRd = 0,
    this.cargoParadasRd = 0,
  });

  factory CorporativoTarifaDesglose.cero({String modeloTarifa = 'dinamica'}) {
    return CorporativoTarifaDesglose(
      kmLineaRecta: 0,
      kmCotizados: 0,
      tarifaBaseRd: 0,
      recargoZonaRd: 0,
      subtotalFacturaRd: 0,
      recargoFacturaRd: 0,
      precioViajeRd: 0,
      gananciaRaiEstimadaRd: 0,
      itbisRaiEstimadoRd: 0,
      modeloTarifa: modeloTarifa,
      cargoKmRd: 0,
      cargoTiempoRd: 0,
      minutosEstimados: 0,
      numParadas: 0,
      cargoCompaniaRd: 0,
      precioBaseServicioRd: 0,
      impuestoTransferenciaRd: 0,
      retencionIsrRd: 0,
      pagoChoferRd: 0,
    );
  }

  final double kmLineaRecta;
  final double kmCotizados;
  final double tarifaBaseRd;
  final double recargoZonaRd;
  /// Precio_Base_Servicio (transporte).
  final double subtotalFacturaRd;
  /// Impuesto_Transferencia_Cliente (0.20%).
  final double recargoFacturaRd;
  /// Monto_Total_Factura (base + impuesto).
  final double precioViajeRd;
  final double gananciaRaiEstimadaRd;
  final double itbisRaiEstimadoRd;
  final String modeloTarifa;
  final double cargoKmRd;
  final double cargoTiempoRd;
  final double minutosEstimados;
  final int numParadas;
  /// Comisión plataforma 10% sobre Precio_Base (no se suma al cliente).
  final double cargoCompaniaRd;
  final double precioBaseServicioRd;
  final double impuestoTransferenciaRd;
  final double retencionIsrRd;
  final double pagoChoferRd;
  final double tasaImpuestoTransferencia;
  final double costoOperativoRd;
  final double recargoEmpresaServicioRd;
  final double cargoCombustibleRd;
  final double cargoParadasRd;

  double get recargoTransferenciaRd => recargoFacturaRd;

  double get itbisRd => itbisRaiEstimadoRd;

  double get precioConItbisRd => precioViajeRd;

  Map<String, dynamic> toMap() => {
        'modeloTarifa': modeloTarifa,
        'kmLineaRecta': double.parse(kmLineaRecta.toStringAsFixed(2)),
        'kmCotizados': double.parse(kmCotizados.toStringAsFixed(2)),
        'tarifaBaseRd': tarifaBaseRd.round(),
        'cargoKmRd': cargoKmRd.round(),
        'cargoTiempoRd': cargoTiempoRd.round(),
        'minutosEstimados': minutosEstimados.round(),
        'numParadas': numParadas,
        'cargoParadasRd': cargoParadasRd.round(),
        'recargoZonaRd': recargoZonaRd.round(),
        'precioBaseServicioRd': (precioBaseServicioRd > 0
                ? precioBaseServicioRd
                : subtotalFacturaRd)
            .round(),
        'subtotalFacturaRd': subtotalFacturaRd.round(),
        'impuestoTransferenciaRd': (impuestoTransferenciaRd > 0
                ? impuestoTransferenciaRd
                : recargoFacturaRd)
            .round(),
        'tasa_impuesto_transferencia': tasaImpuestoTransferencia,
        'tasaImpuestoTransferencia': tasaImpuestoTransferencia,
        'cargoCompaniaRd': cargoCompaniaRd.round(),
        'comisionPlataformaRd': cargoCompaniaRd.round(),
        'pagoChoferRd': pagoChoferRd.round(),
        'retencionIsrRd': retencionIsrRd.round(),
        'recargoFacturaRd': recargoFacturaRd.round(),
        'recargoTransferenciaRd': recargoFacturaRd.round(),
        'montoTotalFacturaRd': precioViajeRd.round(),
        'precioViajeRd': precioViajeRd.round(),
        'gananciaRaiEstimadaRd': gananciaRaiEstimadaRd.round(),
        'itbisRaiEstimadoRd': itbisRaiEstimadoRd.round(),
        'itbisRd': itbisRaiEstimadoRd.round(),
        'precioConItbisRd': precioViajeRd.round(),
      };

  static CorporativoTarifaDesglose calcular({
    required double kmLineaRecta,
    required CorporativoTarifaConfig cfg,
    int numParadas = 1,
  }) {
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

class CorporativoTarifaConfigService {
  CorporativoTarifaConfigService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static CorporativoTarifaConfig _cached = CorporativoTarifaConfig.defaults;
  static DateTime? _lastFetch;
  static const Duration _ttl = Duration(seconds: 60);

  static CorporativoTarifaConfig get vigente => _cached;

  static Future<CorporativoTarifaConfig> refresh({bool force = false}) async {
    if (!force &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _ttl) {
      return _cached;
    }
    try {
      final snap = await _db.collection('config').doc('corporativo').get();
      _cached = CorporativoTarifaConfig.fromMap(snap.data());
      _lastFetch = DateTime.now();
    } catch (_) {
      // Mantener cache / defaults.
    }
    return _cached;
  }
}
