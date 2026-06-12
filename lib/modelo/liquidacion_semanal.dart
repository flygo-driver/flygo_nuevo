import 'package:cloud_firestore/cloud_firestore.dart';

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
  final DateTime? pagadoEn;
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
    this.pagadoEn,
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
      pagadoEn: (map['pagadoEn'] as Timestamp?)?.toDate(),
      referenciaAch: map['referenciaAch']?.toString(),
      notaAdmin: map['notaAdmin']?.toString(),
    );
  }

  double get totalNetoRd => totalNetoCents / 100.0;

  bool get esPendiente =>
      estado == 'borrador' || estado == 'pendiente_pago';

  bool get esPagada => estado == 'pagado';
}
