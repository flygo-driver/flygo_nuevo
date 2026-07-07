// Recaudo central RAI para salidas por cupos (giras).

/// Genera referencia alineada con `functions/src/pool_referencia.ts`.
class PoolReferenciaRecaudo {
  PoolReferenciaRecaudo._();

  static final RegExp _formato =
      RegExp(r'^RAI-P-[A-Z0-9]{1,8}-[A-Z0-9]{1,8}-[0-9A-F]{2}$');

  static String generar(String poolId, String reservaId) {
    final p = poolId.trim();
    final r = reservaId.trim();
    if (p.isEmpty || r.isEmpty) {
      throw ArgumentError('poolId o reservaId vacío');
    }
    final poolSlug = _slug8(p);
    final resSlug = _slug8(r);
    final cs = _checksum2Hex('$p:$r');
    return 'RAI-P-$poolSlug-$resSlug-$cs';
  }

  static bool esFormatoValido(String? raw) {
    final ref = (raw ?? '').trim().toUpperCase();
    return ref.isNotEmpty && _formato.hasMatch(ref);
  }

  static String _slug8(String id) {
    final raw = (id.length <= 8 ? id : id.substring(0, 8)).toUpperCase();
    final slug = raw.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (slug.isEmpty) return 'P';
    return slug.length <= 8 ? slug : slug.substring(0, 8);
  }

  static String _checksum2Hex(String seed) {
    var sum = 0;
    for (final unit in seed.codeUnits) {
      sum = (sum + unit) & 0xff;
    }
    return sum.toRadixString(16).padLeft(2, '0').toUpperCase();
  }
}

/// Pool con pago del cliente a cuenta RAI (100% por transferencia).
abstract final class PoolRecaudoCentral {
  PoolRecaudoCentral._();

  static bool esPoolCentral(Map<String, dynamic> pool) {
    return (pool['recaudoModelo'] ?? '').toString().trim().toLowerCase() ==
        'central';
  }

  /// Siempre 1: [precioPorAsiento] ya es el precio final por persona.
  static double multSentido(Map<String, dynamic> pool) => 1.0;

  /// Precio por persona mostrado al cliente.
  static double precioPorPersona(Map<String, dynamic> pool) {
    return ((pool['precioPorAsiento'] ?? 0) as num).toDouble();
  }

  /// Total bruto reserva = asientos × precio asiento.
  static double totalReservaRd({
    required Map<String, dynamic> pool,
    required int asientos,
  }) {
    if (asientos <= 0) return 0;
    final precio = ((pool['precioPorAsiento'] ?? 0) as num).toDouble();
    if (precio <= 0) return 0;
    return _round2(asientos * precio);
  }

  /// % comisión guardado en la gira o fallback externo.
  static double pctComisionPool(
    Map<String, dynamic> pool, {
    required double fallbackPct,
  }) {
    final raw = pool['comisionGiraPctUsado'];
    if (raw is num && raw.isFinite && raw > 1e-6) {
      return raw.toDouble().clamp(0.0, 100.0);
    }
    return fallbackPct.clamp(0.0, 100.0);
  }

  /// Comisión RAI = % × (asientos × precio × sentido). No es % de toda la gira.
  static double comisionRaiRd({
    required Map<String, dynamic> pool,
    required int asientos,
    required double pctComision,
  }) {
    if (asientos <= 0) return 0;
    final base = totalReservaRd(pool: pool, asientos: asientos);
    if (base <= 0) return 0;
    return _round2(base * (pctComision / 100.0));
  }

  static double netoOrganizadorRd({
    required Map<String, dynamic> pool,
    required int asientos,
    required double pctComision,
  }) {
    final bruto = totalReservaRd(pool: pool, asientos: asientos);
    return _round2(bruto - comisionRaiRd(
      pool: pool,
      asientos: asientos,
      pctComision: pctComision,
    ));
  }

  /// Desglose por reserva (transferencia verificada o efectivo al abordar).
  static PoolReservaDesglose desgloseReserva({
    required Map<String, dynamic> pool,
    required int asientos,
    required double pctComision,
  }) {
    final precioAsiento = ((pool['precioPorAsiento'] ?? 0) as num).toDouble();
    final mult = multSentido(pool);
    final bruto = totalReservaRd(pool: pool, asientos: asientos);
    final comision =
        comisionRaiRd(pool: pool, asientos: asientos, pctComision: pctComision);
    return PoolReservaDesglose(
      asientos: asientos,
      precioPorAsiento: precioAsiento,
      multSentido: mult,
      precioPorPersona: _round2(precioAsiento * mult),
      totalBruto: bruto,
      pctComision: pctComision,
      comisionRai: comision,
      netoOrganizador: _round2(bruto - comision),
    );
  }

  static double _round2(double v) =>
      double.parse(v.clamp(-1e12, 1e12).toStringAsFixed(2));

  static double _firstPositiveNum(List<dynamic> vals) {
    for (final v in vals) {
      final n = v is num ? v.toDouble() : 0.0;
      if (n > 1e-9) return n;
    }
    return 0;
  }

  /// Monto que el cliente debe transferir a RAI (hoy: total de la reserva).
  static double montoRecaudoCliente({
    required Map<String, dynamic> pool,
    required double totalReserva,
  }) {
    if (!esPoolCentral(pool)) {
      final pct =
          ((pool['depositPct'] ?? 0.3) as num).toDouble().clamp(0.0, 1.0);
      return totalReserva * pct;
    }
    final montoPct = ((pool['montoRecaudoPct'] ?? 1.0) as num)
        .toDouble()
        .clamp(0.0, 1.0);
    return totalReserva * montoPct;
  }

  /// Cierre contable: comisión 10% ventas − prepago ya consumido = retención del recaudo.
  static PoolCierreRecaudoCentral cierreDesdePool(Map<String, dynamic> pool) {
    final bruto =
        ((pool['montoRecaudadoRaiRd'] ?? 0) as num).toDouble().clamp(0.0, 1e12);
    final comisionVentas =
        ((pool['montoComisionRaiRd'] ?? 0) as num).toDouble().clamp(0.0, 1e12);
    final recargaComprada = _firstPositiveNum([
      pool['prepagoComisionAplicadaRd'],
      pool['comisionGiraRealRd'],
      pool['comisionGiraEstimadaRd'],
      pool['montoComisionCobradaPrepago'],
    ]);
    final prepagoAplicado = _round2(
      recargaComprada.clamp(0.0, comisionVentas),
    );
    final comisionRetenida =
        _round2((comisionVentas - prepagoAplicado).clamp(0.0, 1e12));
    final netoOrganizador = _round2((bruto - comisionRetenida).clamp(0.0, 1e12));
    final superoRecarga = comisionVentas > recargaComprada + 1e-9;
    return PoolCierreRecaudoCentral(
      brutoRecaudadoRd: _round2(bruto),
      comisionVentasRd: _round2(comisionVentas),
      recargaCompradaRd: _round2(recargaComprada),
      prepagoAplicadoRd: prepagoAplicado,
      comisionRetenidaRecaudoRd: comisionRetenida,
      netoOrganizadorFinalRd: netoOrganizador,
      superoRecargaComprada: superoRecarga,
      montoFaltaRetenerDelRecaudoRd: comisionRetenida,
    );
  }

  /// Recaudo central: no exige `comisionGiraEstimadaRd` al iniciar (prepago solo efectivo).
  static bool poolPuedeIniciarEnApp(Map<String, dynamic>? pool) {
    if (pool == null) return false;
    if (esPoolCentral(pool)) return true;
    final v = pool['comisionGiraEstimadaRd'];
    if (v is num && v.isFinite && v > 1e-9) return true;
    if (v is String) {
      final d = double.tryParse(v);
      return d != null && d.isFinite && d > 1e-9;
    }
    return false;
  }
}

/// Montos por reserva: comisión sobre asientos vendidos × precio, no sobre la gira entera.
class PoolReservaDesglose {
  const PoolReservaDesglose({
    required this.asientos,
    required this.precioPorAsiento,
    required this.multSentido,
    required this.precioPorPersona,
    required this.totalBruto,
    required this.pctComision,
    required this.comisionRai,
    required this.netoOrganizador,
  });

  final int asientos;
  final double precioPorAsiento;
  final double multSentido;
  final double precioPorPersona;
  final double totalBruto;
  final double pctComision;
  final double comisionRai;
  final double netoOrganizador;

  String resumenLinea({required bool efectivoAlAbordar}) {
    final asientoTxt = asientos == 1 ? '1 asiento' : '$asientos asientos';
    final base =
        '$asientoTxt × RD\$ ${precioPorPersona.toStringAsFixed(0)} = RD\$ ${totalBruto.toStringAsFixed(0)}';
    final comTxt =
        'Comisión RAI ${pctComision.toStringAsFixed(0)}%: RD\$ ${comisionRai.toStringAsFixed(0)}';
    if (efectivoAlAbordar) {
      return '$base · $comTxt (prepago organizador al iniciar) · '
          'Neto en mano: RD\$ ${netoOrganizador.toStringAsFixed(0)}';
    }
    return '$base · $comTxt · Neto organizador: RD\$ ${netoOrganizador.toStringAsFixed(0)}';
  }
}

/// Cierre contable recaudo central (ventas − retención neta tras prepago).
class PoolCierreRecaudoCentral {
  const PoolCierreRecaudoCentral({
    required this.brutoRecaudadoRd,
    required this.comisionVentasRd,
    required this.recargaCompradaRd,
    required this.prepagoAplicadoRd,
    required this.comisionRetenidaRecaudoRd,
    required this.netoOrganizadorFinalRd,
    required this.superoRecargaComprada,
    required this.montoFaltaRetenerDelRecaudoRd,
  });

  final double brutoRecaudadoRd;
  final double comisionVentasRd;
  /// Monto de la recarga que compró el organizador (prepago reservado/consumido).
  final double recargaCompradaRd;
  final double prepagoAplicadoRd;
  final double comisionRetenidaRecaudoRd;
  final double netoOrganizadorFinalRd;
  /// `true` si la comisión de ventas superó lo que pagó en recarga.
  final bool superoRecargaComprada;
  /// Lo que RAI aún retiene del recaudo (comisión − recarga aplicada).
  final double montoFaltaRetenerDelRecaudoRd;

  double get comisionTotalRaiRd => comisionVentasRd;

  String get formulaTransferenciaExacta {
    if (brutoRecaudadoRd <= 1e-9) {
      return 'Sin ventas verificadas aún';
    }
    if (superoRecargaComprada) {
      return 'RD\$ ${brutoRecaudadoRd.toStringAsFixed(2)} − '
          'RD\$ ${montoFaltaRetenerDelRecaudoRd.toStringAsFixed(2)} '
          '(comisión menos recarga) = '
          'RD\$ ${netoOrganizadorFinalRd.toStringAsFixed(2)}';
    }
    return 'RD\$ ${brutoRecaudadoRd.toStringAsFixed(2)} '
        '(la recarga cubrió toda la comisión)';
  }

  String get alertaSuperoRecarga {
    if (!superoRecargaComprada) {
      return 'La comisión NO superó la recarga (RD\$ ${recargaCompradaRd.toStringAsFixed(2)}). '
          'No retener nada más del recaudo por comisión.';
    }
    return 'SÍ superó la recarga: comisión RD\$ ${comisionVentasRd.toStringAsFixed(2)} > '
        'recarga RD\$ ${recargaCompradaRd.toStringAsFixed(2)}. '
        'RAI retiene RD\$ ${montoFaltaRetenerDelRecaudoRd.toStringAsFixed(2)} '
        'adicional del recaudo (ya cobró RD\$ ${prepagoAplicadoRd.toStringAsFixed(2)} en prepago).';
  }
}
