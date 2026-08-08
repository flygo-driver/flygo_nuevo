import 'liquidacion_semanal.dart';

/// Viaje individual pendiente de liquidar (transferencia o tarjeta verificada).
class ViajePendienteLiquidacion {
  final String viajeId;
  final String uidTaxista;
  final String nombreTaxista;
  final String metodo;
  final int precioCents;
  final int comisionCents;
  final int gananciaCents;
  final DateTime? finalizadoEn;
  final String periodoIso;

  const ViajePendienteLiquidacion({
    required this.viajeId,
    required this.uidTaxista,
    required this.nombreTaxista,
    required this.metodo,
    this.precioCents = 0,
    this.comisionCents = 0,
    this.gananciaCents = 0,
    this.finalizadoEn,
    this.periodoIso = '',
  });

  double get netoRd => gananciaCents / 100.0;
  double get comisionRd => comisionCents / 100.0;
  double get brutoRd => precioCents / 100.0;
}

/// Agregado por taxista: cuánto liquidar y cuánto retiene RAI.
class ResumenPorLiquidarTaxista {
  final String uidTaxista;
  final String nombreTaxista;
  final List<ViajePendienteLiquidacion> viajes;
  final int totalBrutoCents;
  final int comisionRaiCents;
  final int totalNetoCents;
  final TotalesPorMetodoLiquidacion totalesPorMetodo;

  const ResumenPorLiquidarTaxista({
    required this.uidTaxista,
    required this.nombreTaxista,
    this.viajes = const <ViajePendienteLiquidacion>[],
    this.totalBrutoCents = 0,
    this.comisionRaiCents = 0,
    this.totalNetoCents = 0,
    this.totalesPorMetodo = const TotalesPorMetodoLiquidacion(),
  });

  int get viajesCount => viajes.length;

  double get totalNetoRd => totalNetoCents / 100.0;
  double get comisionRaiRd => comisionRaiCents / 100.0;
  double get totalBrutoRd => totalBrutoCents / 100.0;

  /// Períodos ISO distintos con viajes pendientes.
  List<String> get periodosIso {
    return viajes
        .map((v) => v.periodoIso)
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  ResumenPorLiquidarTaxista resumenParaPeriodo(String periodo) {
    final subset =
        viajes.where((v) => v.periodoIso == periodo).toList(growable: false);
    return ResumenPorLiquidarTaxista.fromViajes(
      uidTaxista: uidTaxista,
      nombreTaxista: nombreTaxista,
      viajes: subset,
    );
  }

  static ResumenPorLiquidarTaxista fromViajes({
    required String uidTaxista,
    required String nombreTaxista,
    required List<ViajePendienteLiquidacion> viajes,
  }) {
    var bruto = 0;
    var com = 0;
    var neto = 0;
    var tCount = 0;
    var tBruto = 0;
    var tCom = 0;
    var tNeto = 0;
    var cCount = 0;
    var cBruto = 0;
    var cCom = 0;
    var cNeto = 0;

    for (final v in viajes) {
      bruto += v.precioCents;
      com += v.comisionCents;
      neto += v.gananciaCents;
      if (v.metodo == 'transferencia') {
        tCount++;
        tBruto += v.precioCents;
        tCom += v.comisionCents;
        tNeto += v.gananciaCents;
      } else if (v.metodo == 'tarjeta') {
        cCount++;
        cBruto += v.precioCents;
        cCom += v.comisionCents;
        cNeto += v.gananciaCents;
      }
    }

    return ResumenPorLiquidarTaxista(
      uidTaxista: uidTaxista,
      nombreTaxista: nombreTaxista,
      viajes: viajes,
      totalBrutoCents: bruto,
      comisionRaiCents: com,
      totalNetoCents: neto,
      totalesPorMetodo: TotalesPorMetodoLiquidacion(
        transferencia: TotalesMetodoLiquidacion(
          viajesCount: tCount,
          totalBrutoCents: tBruto,
          comisionRaiCents: tCom,
          totalNetoCents: tNeto,
        ),
        tarjeta: TotalesMetodoLiquidacion(
          viajesCount: cCount,
          totalBrutoCents: cBruto,
          comisionRaiCents: cCom,
          totalNetoCents: cNeto,
        ),
      ),
    );
  }
}
