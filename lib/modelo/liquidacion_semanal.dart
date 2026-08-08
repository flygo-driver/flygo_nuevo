import 'package:cloud_firestore/cloud_firestore.dart';

/// Snapshot congelado de la cuenta bancaria del taxista al generar el lote.
class CuentaDestinoSnapshot {
  final String banco;
  final String numeroCuenta;
  final String tipoCuenta;
  final String titular;
  final String ci;
  final DateTime? capturadoEn;

  const CuentaDestinoSnapshot({
    this.banco = '',
    this.numeroCuenta = '',
    this.tipoCuenta = '',
    this.titular = '',
    this.ci = '',
    this.capturadoEn,
  });

  factory CuentaDestinoSnapshot.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const CuentaDestinoSnapshot();
    return CuentaDestinoSnapshot(
      banco: (map['banco'] ?? '').toString(),
      numeroCuenta: (map['numeroCuenta'] ?? '').toString(),
      tipoCuenta: (map['tipoCuenta'] ?? '').toString(),
      titular: (map['titular'] ?? '').toString(),
      ci: (map['ci'] ?? '').toString(),
      capturadoEn: (map['capturadoEn'] as Timestamp?)?.toDate(),
    );
  }

  bool get estaCompleta =>
      banco.trim().isNotEmpty &&
      numeroCuenta.trim().isNotEmpty &&
      titular.trim().isNotEmpty;
}

/// Línea de detalle por viaje dentro de una liquidación semanal.
class LiquidacionSemanalLinea {
  final String viajeId;
  final String metodoPagoNormalizado;
  final String estadoPago;
  final String estadoViajeSnapshot;
  final int precioCents;
  final int comisionCents;
  final int gananciaCents;
  final DateTime? finalizadoEn;

  const LiquidacionSemanalLinea({
    required this.viajeId,
    this.metodoPagoNormalizado = '',
    this.estadoPago = '',
    this.estadoViajeSnapshot = '',
    this.precioCents = 0,
    this.comisionCents = 0,
    this.gananciaCents = 0,
    this.finalizadoEn,
  });

  factory LiquidacionSemanalLinea.fromMap(
    String viajeId,
    Map<String, dynamic> map,
  ) {
    return LiquidacionSemanalLinea(
      viajeId: viajeId.isNotEmpty ? viajeId : (map['viajeId'] ?? '').toString(),
      metodoPagoNormalizado: (map['metodoPagoNormalizado'] ?? '').toString(),
      estadoPago: (map['estadoPago'] ?? '').toString(),
      estadoViajeSnapshot: (map['estadoViajeSnapshot'] ?? '').toString(),
      precioCents: (map['precioCents'] as num?)?.toInt() ?? 0,
      comisionCents: (map['comisionCents'] as num?)?.toInt() ?? 0,
      gananciaCents: (map['gananciaCents'] as num?)?.toInt() ?? 0,
      finalizadoEn: (map['finalizadoEn'] as Timestamp?)?.toDate(),
    );
  }

  double get precioRd => precioCents / 100.0;
  double get comisionRd => comisionCents / 100.0;
  double get gananciaRd => gananciaCents / 100.0;
}

class TotalesMetodoLiquidacion {
  final int viajesCount;
  final int totalBrutoCents;
  final int comisionRaiCents;
  final int totalNetoCents;

  const TotalesMetodoLiquidacion({
    this.viajesCount = 0,
    this.totalBrutoCents = 0,
    this.comisionRaiCents = 0,
    this.totalNetoCents = 0,
  });

  factory TotalesMetodoLiquidacion.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const TotalesMetodoLiquidacion();
    return TotalesMetodoLiquidacion(
      viajesCount: (map['viajesCount'] as num?)?.toInt() ?? 0,
      totalBrutoCents: (map['totalBrutoCents'] as num?)?.toInt() ?? 0,
      comisionRaiCents: (map['comisionRaiCents'] as num?)?.toInt() ?? 0,
      totalNetoCents: (map['totalNetoCents'] as num?)?.toInt() ?? 0,
    );
  }

  double get totalNetoRd => totalNetoCents / 100.0;
}

class TotalesPorMetodoLiquidacion {
  final TotalesMetodoLiquidacion transferencia;
  final TotalesMetodoLiquidacion tarjeta;

  const TotalesPorMetodoLiquidacion({
    this.transferencia = const TotalesMetodoLiquidacion(),
    this.tarjeta = const TotalesMetodoLiquidacion(),
  });

  factory TotalesPorMetodoLiquidacion.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const TotalesPorMetodoLiquidacion();
    return TotalesPorMetodoLiquidacion(
      transferencia: TotalesMetodoLiquidacion.fromMap(
        (map['transferencia'] as Map<String, dynamic>?) ?? const {},
      ),
      tarjeta: TotalesMetodoLiquidacion.fromMap(
        (map['tarjeta'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}

class LiquidacionSemanal {
  final String id;
  final String uidTaxista;
  final String nombreTaxista;
  final String periodo;
  final DateTime periodoInicio;
  final DateTime periodoFin;
  final String estado;
  final List<String> viajeIds;
  final int viajesCount;
  final int viajesEfectivoExcluidosCount;
  final int totalBrutoCents;
  final int comisionRaiCents;
  final int totalNetoCents;
  final TotalesPorMetodoLiquidacion totalesPorMetodo;
  final String moneda;
  final bool cuentaDestinoCompleta;
  final CuentaDestinoSnapshot cuentaDestinoSnapshot;
  final DateTime? generadoEn;
  final String? generadoPor;
  final DateTime? pagadoEn;
  final String? pagadoPorUid;
  final String? referenciaAch;
  final String? notaAdmin;

  const LiquidacionSemanal({
    required this.id,
    required this.uidTaxista,
    required this.nombreTaxista,
    required this.periodo,
    required this.periodoInicio,
    required this.periodoFin,
    required this.estado,
    this.viajeIds = const <String>[],
    this.viajesCount = 0,
    this.viajesEfectivoExcluidosCount = 0,
    this.totalBrutoCents = 0,
    this.comisionRaiCents = 0,
    this.totalNetoCents = 0,
    this.totalesPorMetodo = const TotalesPorMetodoLiquidacion(),
    this.moneda = 'DOP',
    this.cuentaDestinoCompleta = false,
    this.cuentaDestinoSnapshot = const CuentaDestinoSnapshot(),
    this.generadoEn,
    this.generadoPor,
    this.pagadoEn,
    this.pagadoPorUid,
    this.referenciaAch,
    this.notaAdmin,
  });

  factory LiquidacionSemanal.fromMap(String id, Map<String, dynamic> map) {
    return LiquidacionSemanal(
      id: id,
      uidTaxista: (map['uidTaxista'] ?? '').toString(),
      nombreTaxista: (map['nombreTaxista'] ?? '').toString(),
      periodo: (map['periodo'] ?? '').toString(),
      periodoInicio:
          (map['periodoInicio'] as Timestamp?)?.toDate() ?? DateTime.now(),
      periodoFin: (map['periodoFin'] as Timestamp?)?.toDate() ?? DateTime.now(),
      estado: (map['estado'] ?? 'borrador').toString(),
      viajeIds: ((map['viajeIds'] as List<dynamic>?) ?? const <dynamic>[])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(growable: false),
      viajesCount: (map['viajesCount'] as num?)?.toInt() ?? 0,
      viajesEfectivoExcluidosCount:
          (map['viajesEfectivoExcluidosCount'] as num?)?.toInt() ?? 0,
      totalBrutoCents: (map['totalBrutoCents'] as num?)?.toInt() ?? 0,
      comisionRaiCents: (map['comisionRaiCents'] as num?)?.toInt() ?? 0,
      totalNetoCents: (map['totalNetoCents'] as num?)?.toInt() ?? 0,
      totalesPorMetodo: TotalesPorMetodoLiquidacion.fromMap(
        map['totalesPorMetodo'] as Map<String, dynamic>?,
      ),
      moneda: (map['moneda'] ?? 'DOP').toString(),
      cuentaDestinoCompleta: map['cuentaDestinoCompleta'] == true,
      cuentaDestinoSnapshot: CuentaDestinoSnapshot.fromMap(
        map['cuentaDestinoSnapshot'] as Map<String, dynamic>?,
      ),
      generadoEn: (map['generadoEn'] as Timestamp?)?.toDate(),
      generadoPor: map['generadoPor']?.toString(),
      pagadoEn: (map['pagadoEn'] as Timestamp?)?.toDate(),
      pagadoPorUid: map['pagadoPorUid']?.toString(),
      referenciaAch: map['referenciaAch']?.toString(),
      notaAdmin: map['notaAdmin']?.toString(),
    );
  }

  double get totalBrutoRd => totalBrutoCents / 100.0;
  double get comisionRaiRd => comisionRaiCents / 100.0;
  double get totalNetoRd => totalNetoCents / 100.0;

  /// Suma neta por método; debe coincidir con [totalNetoCents] (tolerancia 1 centavo).
  int get sumaNetoPorMetodoCents =>
      totalesPorMetodo.transferencia.totalNetoCents +
      totalesPorMetodo.tarjeta.totalNetoCents;

  bool get totalesCuadran =>
      (sumaNetoPorMetodoCents - totalNetoCents).abs() <= 1;

  bool get esPendiente =>
      estado == 'borrador' || estado == 'pendiente_pago';

  bool get esPagada => estado == 'pagado';
  bool get esCancelada => estado == 'cancelado';
  bool get esBorrador => estado == 'borrador';
}
