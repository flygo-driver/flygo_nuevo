import '../modelo/liquidacion_semanal.dart';

/// CSV para transferencias ACH al taxista (columnas estándar operaciones).
class LiquidacionSemanalAchExport {
  LiquidacionSemanalAchExport._();

  static String buildCsv(List<LiquidacionSemanal> liquidaciones) {
    final buf = StringBuffer();
    buf.writeln(
      'periodo,uid_taxista,nombre_taxista,neto_rd,'
      'neto_transferencia_rd,neto_tarjeta_rd,viajes,'
      'banco,tipo_cuenta,numero_cuenta,titular,ci,'
      'liquidacion_id,estado',
    );
    for (final liq in liquidaciones) {
      final c = liq.cuentaDestinoSnapshot;
      buf.writeln(
        [
          _csv(liq.periodo),
          _csv(liq.uidTaxista),
          _csv(liq.nombreTaxista),
          liq.totalNetoRd.toStringAsFixed(2),
          liq.totalesPorMetodo.transferencia.totalNetoRd.toStringAsFixed(2),
          liq.totalesPorMetodo.tarjeta.totalNetoRd.toStringAsFixed(2),
          '${liq.viajesCount}',
          _csv(c.banco),
          _csv(c.tipoCuenta),
          _csv(c.numeroCuenta),
          _csv(c.titular),
          _csv(c.ci),
          _csv(liq.id),
          _csv(liq.estado),
        ].join(','),
      );
    }
    return buf.toString();
  }

  static String _csv(String raw) {
    final s = raw.replaceAll('"', '""');
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"$s"';
    }
    return s;
  }
}
