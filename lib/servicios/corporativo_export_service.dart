import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/modelos/corporativo_models.dart';
import 'package:flygo_nuevo/utils/corporativo_archivo_download_stub.dart'
    if (dart.library.html) 'package:flygo_nuevo/utils/corporativo_archivo_download_web.dart';
import 'package:flygo_nuevo/utils/corporativo_ciclo_facturacion.dart';
import 'package:flygo_nuevo/utils/corporativo_historial_labels.dart';

/// Exportación de liquidación / factura a pagar para contabilidad y auditoría.
abstract final class CorporativoExportService {
  CorporativoExportService._();

  static final _fmtFecha = DateFormat('dd/MM/yyyy', 'es');
  static final _fmtFechaArchivo = DateFormat('yyyy-MM-dd', 'es');
  static final _fmtMonto = NumberFormat.currency(
    locale: 'es_DO',
    symbol: 'RD\$',
    decimalDigits: 2,
  );

  static List<Map<String, dynamic>> historialEnPeriodo({
    required List<Map<String, dynamic>> historial,
    DateTime? inicio,
    DateTime? fin,
  }) {
    if (inicio == null || fin == null) return historial;
    final ini = DateTime(inicio.year, inicio.month, inicio.day);
    final end = DateTime(fin.year, fin.month, fin.day, 23, 59, 59);
    return historial.where((h) {
      final f = h['fechaRecogida'];
      if (f is! DateTime) return false;
      return !f.isBefore(ini) && !f.isAfter(end);
    }).toList(growable: false);
  }

  static double totalConsolidado({
    required CorporativoPeriodoActual? periodo,
    required List<Map<String, dynamic>> liquidacionesPendientes,
  }) {
    var total = periodo?.montoTotalRd ?? 0;
    for (final lq in liquidacionesPendientes) {
      if ((lq['estado'] ?? '').toString().trim().toLowerCase() !=
          'pendiente_cobro') {
        continue;
      }
      total += (lq['montoTotalRd'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  static String generarFacturaLiquidacionCsv({
    required CorporativoEmpresa empresa,
    CorporativoPeriodoActual? periodo,
    List<Map<String, dynamic>> historial = const [],
    List<Map<String, dynamic>> liquidacionesPendientes = const [],
    List<Map<String, dynamic>> liquidacionesPagadas = const [],
    bool soloPeriodoActual = false,
  }) {
    final buf = StringBuffer();
    final p = periodo ?? empresa.periodoActual;
    final doc = empresa.documentoLegal.trim();
    final ciclo = CorporativoCicloFacturacion.descripcion(
      empresa.facturacionCicloDias,
    );
    final histPeriodo = historialEnPeriodo(
      historial: historial,
      inicio: p?.inicio,
      fin: p?.fin,
    );
    final montoPeriodo = p?.montoTotalRd ?? 0;
    final viajesPeriodo = p?.viajesCount ?? 0;
    final deudaArchivada = liquidacionesPendientes.fold<double>(
      0,
      (sum, lq) => sum + ((lq['montoTotalRd'] as num?)?.toDouble() ?? 0),
    );
    final totalPagar = montoPeriodo + deudaArchivada;

    buf.writeln('RAI DRIVER — FACTURA A LIQUIDAR (CORPORATIVO)');
    buf.writeln('Documento para contabilidad y auditoría interna de la empresa');
    buf.writeln('Beneficiario del pago: RAI Driver / FlyGo RD');
    buf.writeln('Emitido;${_fmtFecha.format(DateTime.now())}');
    buf.writeln('');

    buf.writeln('DATOS DE LA EMPRESA CONTRATANTE');
    buf.writeln('Empresa;${_csv(empresa.nombre)}');
    if (doc.isNotEmpty) {
      buf.writeln('${empresa.etiquetaDocumento};${_csv(doc)}');
    }
    if (empresa.emailEmpresa.isNotEmpty) {
      buf.writeln('Correo;${_csv(empresa.emailEmpresa)}');
    }
    if (empresa.telefonoEmpresa.isNotEmpty) {
      buf.writeln('Teléfono;${_csv(empresa.telefonoEmpresa)}');
    }
    buf.writeln('Ciclo de facturación;${_csv(ciclo)}');
    if (empresa.tarifaViajeContratadaRd > 0) {
      buf.writeln(
        'Tarifa contratada por viaje;${_fmtMonto.format(empresa.tarifaViajeContratadaRd)}',
      );
    }
    buf.writeln('');

    buf.writeln('COTEJO — PERÍODO ACTUAL (ACUMULADO EN CURSO)');
    if (p?.inicio != null) {
      buf.writeln('Desde;${_fmtFecha.format(p!.inicio!)}');
    }
    if (p?.fin != null) {
      buf.writeln('Fecha de corte;${_fmtFecha.format(p!.fin!)}');
    }
    buf.writeln('Viajes acumulados;$viajesPeriodo');
    buf.writeln('Monto acumulado período;${_montoCsv(montoPeriodo)}');
    if ((p?.codigoAcceso ?? '').isNotEmpty) {
      buf.writeln('Código verificación empleados;${p!.codigoAcceso}');
    }

    final choferes = p?.porChofer.values.toList() ?? [];
    if (choferes.isNotEmpty) {
      buf.writeln('');
      buf.writeln('DESGLOSE POR CHOFER (período actual)');
      buf.writeln('Chofer;Viajes;Monto RD\$');
      for (final ch in choferes) {
        buf.writeln(
          '${_csv(ch.nombre)};${ch.viajes};${ch.montoRd.toStringAsFixed(2)}',
        );
      }
      final sumaChoferes = choferes.fold<double>(0, (s, c) => s + c.montoRd);
      buf.writeln('Subtotal choferes;${sumaChoferes.toStringAsFixed(2)}');
    }

    if (histPeriodo.isNotEmpty) {
      buf.writeln('');
      buf.writeln('DETALLE DE VIAJES (período actual — cotejo línea a línea)');
      buf.writeln(
        'Fecha;Ruta;Referencia;Chofer;Pasajeros;Monto RD\$;Estado',
      );
      var sumaViajes = 0.0;
      for (final h in histPeriodo) {
        final fecha = h['fechaRecogida'];
        final fechaStr = fecha is DateTime ? _fmtFecha.format(fecha) : '';
        final pas = h['pasajeros'];
        final nPas = pas is List ? pas.length : 0;
        final monto = (h['precio'] as num?)?.toDouble() ?? 0;
        sumaViajes += monto;
        final estado = CorporativoHistorialLabels.etiqueta(
          (h['estado'] ?? '').toString(),
        );
        buf.writeln(
          '${_csv(fechaStr)};'
          '${_csv((h['plantillaNombre'] ?? '').toString())};'
          '${_csv((h['referencia'] ?? '').toString())};'
          '${_csv((h['choferNombre'] ?? '').toString())};'
          '$nPas;'
          '${monto.toStringAsFixed(2)};'
          '${_csv(estado)}',
        );
      }
      buf.writeln('Subtotal detalle viajes;${sumaViajes.toStringAsFixed(2)}');
      buf.writeln(
        'Diferencia vs acumulado;${(montoPeriodo - sumaViajes).toStringAsFixed(2)}',
      );
    }

    if (!soloPeriodoActual && liquidacionesPendientes.isNotEmpty) {
      buf.writeln('');
      buf.writeln('PERÍODOS ANTERIORES — PENDIENTES DE PAGO A RAI');
      buf.writeln('Período;Viajes;Monto RD\$;Estado');
      for (final lq in liquidacionesPendientes) {
        final ini = lq['periodoInicio'];
        final fin = lq['periodoFin'];
        var rango = '—';
        if (ini is DateTime && fin is DateTime) {
          rango = '${_fmtFecha.format(ini)} - ${_fmtFecha.format(fin)}';
        }
        buf.writeln(
          '${_csv(rango)};${lq['viajesCount'] ?? 0};'
          '${((lq['montoTotalRd'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)};'
          'Pendiente de cobro',
        );
      }
      buf.writeln('Subtotal períodos anteriores;${deudaArchivada.toStringAsFixed(2)}');
    }

    if (!soloPeriodoActual) {
      buf.writeln('');
      buf.writeln('TOTAL CONSOLIDADO A PAGAR A RAI');
      buf.writeln('Concepto;Monto RD\$');
      buf.writeln('Período actual (acumulado);${montoPeriodo.toStringAsFixed(2)}');
      if (deudaArchivada > 0) {
        buf.writeln(
          'Períodos anteriores pendientes;${deudaArchivada.toStringAsFixed(2)}',
        );
      }
      buf.writeln('TOTAL A LIQUIDAR;${totalPagar.toStringAsFixed(2)}');
    }

    if (liquidacionesPagadas.isNotEmpty) {
      buf.writeln('');
      buf.writeln('HISTORIAL DE LIQUIDACIONES PAGADAS (referencia auditoría)');
      buf.writeln('Período;Viajes;Monto RD\$;Estado');
      for (final lq in liquidacionesPagadas.take(12)) {
        final ini = lq['periodoInicio'];
        final fin = lq['periodoFin'];
        var rango = '—';
        if (ini is DateTime && fin is DateTime) {
          rango = '${_fmtFecha.format(ini)} - ${_fmtFecha.format(fin)}';
        }
        buf.writeln(
          '${_csv(rango)};${lq['viajesCount'] ?? 0};'
          '${((lq['montoTotalRd'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)};'
          'Pagado',
        );
      }
    }

    buf.writeln('');
    buf.writeln(
      'Nota: Resumen de acumulado corporativo RAI. '
      'Al cierre del período RAI emite el comprobante fiscal (e-CF) correspondiente.',
    );
    return buf.toString();
  }

  static String generarFacturaLiquidacionHtml({
    required CorporativoEmpresa empresa,
    CorporativoPeriodoActual? periodo,
    List<Map<String, dynamic>> historial = const [],
    List<Map<String, dynamic>> liquidacionesPendientes = const [],
    bool soloPeriodoActual = false,
  }) {
    final p = periodo ?? empresa.periodoActual;
    final ciclo = CorporativoCicloFacturacion.descripcion(
      empresa.facturacionCicloDias,
    );
    final histPeriodo = historialEnPeriodo(
      historial: historial,
      inicio: p?.inicio,
      fin: p?.fin,
    );
    final montoPeriodo = p?.montoTotalRd ?? 0;
    final deudaArchivada = liquidacionesPendientes.fold<double>(
      0,
      (sum, lq) => sum + ((lq['montoTotalRd'] as num?)?.toDouble() ?? 0),
    );
    final totalPagar = montoPeriodo + deudaArchivada;
    final choferes = p?.porChofer.values.toList() ?? [];

    String filasViajes = '';
    var sumaViajes = 0.0;
    for (final h in histPeriodo) {
      final fecha = h['fechaRecogida'];
      final fechaStr = fecha is DateTime ? _fmtFecha.format(fecha) : '—';
      final pas = h['pasajeros'];
      final nPas = pas is List ? pas.length : 0;
      final monto = (h['precio'] as num?)?.toDouble() ?? 0;
      sumaViajes += monto;
      filasViajes += '''
        <tr>
          <td>$fechaStr</td>
          <td>${_html((h['plantillaNombre'] ?? '').toString())}</td>
          <td>${_html((h['referencia'] ?? '').toString())}</td>
          <td>${_html((h['choferNombre'] ?? '').toString())}</td>
          <td class="num">$nPas</td>
          <td class="num">${_fmtMonto.format(monto)}</td>
        </tr>''';
    }

    String filasChoferes = '';
    for (final ch in choferes) {
      filasChoferes += '''
        <tr>
          <td>${_html(ch.nombre)}</td>
          <td class="num">${ch.viajes}</td>
          <td class="num">${_fmtMonto.format(ch.montoRd)}</td>
        </tr>''';
    }

    String filasLiqPend = '';
    for (final lq in liquidacionesPendientes) {
      final ini = lq['periodoInicio'];
      final fin = lq['periodoFin'];
      var rango = '—';
      if (ini is DateTime && fin is DateTime) {
        rango = '${_fmtFecha.format(ini)} – ${_fmtFecha.format(fin)}';
      }
      filasLiqPend += '''
        <tr>
          <td>$rango</td>
          <td class="num">${lq['viajesCount'] ?? 0}</td>
          <td class="num">${_fmtMonto.format((lq['montoTotalRd'] as num?)?.toDouble() ?? 0)}</td>
          <td>Pendiente de cobro</td>
        </tr>''';
    }

    return '''
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <title>RAI — Factura a liquidar · ${_html(empresa.nombre)}</title>
  <style>
    body { font-family:Segoe UI,Arial,sans-serif; margin:32px; color:#1a1a1a; }
    h1 { font-size:20px; margin:0 0 4px; }
    .sub { color:#555; font-size:13px; margin-bottom:24px; }
    .box { border:1px solid #ddd; border-radius:8px; padding:16px; margin-bottom:20px; }
    h2 { font-size:15px; margin:0 0 12px; color:#0d47a1; }
    table { width:100%; border-collapse:collapse; font-size:13px; }
    th,td { border:1px solid #e0e0e0; padding:8px; text-align:left; }
    th { background:#f5f7fa; }
    .num { text-align:right; }
    .total { font-size:18px; font-weight:700; color:#0d47a1; }
    .nota { font-size:11px; color:#666; margin-top:24px; }
    @media print { body { margin:16px; } }
  </style>
</head>
<body>
  <h1>RAI Driver — Factura a liquidar (Corporativo)</h1>
  <p class="sub">Documento para contabilidad y auditoría · Ciclo: $ciclo · Emitido ${_fmtFecha.format(DateTime.now())}</p>

  <div class="box">
    <h2>Empresa contratante</h2>
    <p><strong>${_html(empresa.nombre)}</strong></p>
    ${empresa.documentoLegal.trim().isNotEmpty ? '<p>${empresa.etiquetaDocumento}: ${_html(empresa.documentoLegal)}</p>' : ''}
    ${empresa.emailEmpresa.isNotEmpty ? '<p>Correo: ${_html(empresa.emailEmpresa)}</p>' : ''}
    <p>Pago a: <strong>RAI Driver / FlyGo RD</strong></p>
  </div>

  <div class="box">
    <h2>Cotejo — período actual</h2>
    <p>Desde: ${p?.inicio != null ? _fmtFecha.format(p!.inicio!) : '—'} · Corte: ${p?.fin != null ? _fmtFecha.format(p!.fin!) : '—'}</p>
    <p>Viajes acumulados: <strong>${p?.viajesCount ?? 0}</strong></p>
    <p class="total">Monto acumulado: ${_fmtMonto.format(montoPeriodo)}</p>
    ${(p?.codigoAcceso ?? '').isNotEmpty ? '<p>Código empleados: <strong>${p!.codigoAcceso}</strong></p>' : ''}
  </div>

  ${choferes.isNotEmpty ? '''
  <div class="box">
    <h2>Desglose por chofer</h2>
    <table><thead><tr><th>Chofer</th><th>Viajes</th><th>Monto</th></tr></thead><tbody>$filasChoferes</tbody></table>
  </div>''' : ''}

  ${histPeriodo.isNotEmpty ? '''
  <div class="box">
    <h2>Detalle de viajes (cotejo)</h2>
    <table>
      <thead><tr><th>Fecha</th><th>Ruta</th><th>Ref.</th><th>Chofer</th><th>Pax</th><th>Monto</th></tr></thead>
      <tbody>$filasViajes</tbody>
      <tfoot><tr><td colspan="5"><strong>Subtotal viajes</strong></td><td class="num"><strong>${_fmtMonto.format(sumaViajes)}</strong></td></tr></tfoot>
    </table>
  </div>''' : ''}

  ${!soloPeriodoActual && liquidacionesPendientes.isNotEmpty ? '''
  <div class="box">
    <h2>Períodos anteriores pendientes</h2>
    <table><thead><tr><th>Período</th><th>Viajes</th><th>Monto</th><th>Estado</th></tr></thead><tbody>$filasLiqPend</tbody></table>
  </div>''' : ''}

  ${!soloPeriodoActual ? '''
  <div class="box">
    <h2>Total consolidado a pagar a RAI</h2>
    <table>
      <tr><td>Período actual</td><td class="num">${_fmtMonto.format(montoPeriodo)}</td></tr>
      ${deudaArchivada > 0 ? '<tr><td>Períodos anteriores pendientes</td><td class="num">${_fmtMonto.format(deudaArchivada)}</td></tr>' : ''}
      <tr><td><strong>TOTAL A LIQUIDAR</strong></td><td class="num total">${_fmtMonto.format(totalPagar)}</td></tr>
    </table>
  </div>''' : ''}

  <p class="nota">Resumen de acumulado corporativo RAI para auditoría interna. Al cierre del período RAI emite el e-CF correspondiente.</p>
</body>
</html>''';
  }

  static Future<void> descargarFacturaLiquidacion({
    required CorporativoEmpresa empresa,
    CorporativoPeriodoActual? periodo,
    List<Map<String, dynamic>> historial = const [],
    List<Map<String, dynamic>> liquidacionesPendientes = const [],
    List<Map<String, dynamic>> liquidacionesPagadas = const [],
    required FormatoLiquidacion formato,
    bool soloPeriodoActual = false,
  }) async {
    final slug = _slugArchivo(empresa.nombre);
    final fecha = _fmtFechaArchivo.format(DateTime.now());

    if (formato == FormatoLiquidacion.csv) {
      final csv = generarFacturaLiquidacionCsv(
        empresa: empresa,
        periodo: periodo,
        historial: historial,
        liquidacionesPendientes: liquidacionesPendientes,
        liquidacionesPagadas: liquidacionesPagadas,
        soloPeriodoActual: soloPeriodoActual,
      );
      final filename = 'RAI_Liquidacion_${slug}_$fecha.csv';
      await _compartirArchivo(
        contenido: csv,
        filename: filename,
        mimeType: 'text/csv',
        subject: 'RAI — Factura a liquidar ${empresa.nombre}',
        texto: 'Liquidación corporativa RAI para contabilidad',
      );
      return;
    }

    final html = generarFacturaLiquidacionHtml(
      empresa: empresa,
      periodo: periodo,
      historial: historial,
      liquidacionesPendientes: liquidacionesPendientes,
      soloPeriodoActual: soloPeriodoActual,
    );
    final filename = 'RAI_Liquidacion_${slug}_$fecha.html';
    await _compartirArchivo(
      contenido: html,
      filename: filename,
      mimeType: 'text/html',
      subject: 'RAI — Factura a liquidar ${empresa.nombre}',
      texto: 'Abre e imprime como PDF desde el navegador (Ctrl+P)',
    );
  }

  static Future<void> descargarLiquidacionArchivada({
    required CorporativoEmpresa empresa,
    required Map<String, dynamic> liquidacion,
    required FormatoLiquidacion formato,
    List<Map<String, dynamic>> historial = const [],
  }) async {
    final ini = liquidacion['periodoInicio'];
    final fin = liquidacion['periodoFin'];
    final periodo = CorporativoPeriodoActual(
      inicio: ini is DateTime ? ini : null,
      fin: fin is DateTime ? fin : null,
      viajesCount: (liquidacion['viajesCount'] as num?)?.toInt() ?? 0,
      montoTotalRd: (liquidacion['montoTotalRd'] as num?)?.toDouble() ?? 0,
      porChofer: _choferesDesdeLiquidacion(liquidacion),
    );
    final histFiltrado = historialEnPeriodo(
      historial: historial,
      inicio: periodo.inicio,
      fin: periodo.fin,
    );

    await descargarFacturaLiquidacion(
      empresa: empresa,
      periodo: periodo,
      historial: histFiltrado,
      formato: formato,
      soloPeriodoActual: true,
    );
  }

  static Map<String, CorporativoPeriodoChofer> _choferesDesdeLiquidacion(
    Map<String, dynamic> lq,
  ) {
    final raw = lq['porChofer'];
    if (raw is! Map) return const {};
    final out = <String, CorporativoPeriodoChofer>{};
    raw.forEach((key, value) {
      if (value is Map) {
        out[key.toString()] = CorporativoPeriodoChofer.fromEntry(
          key.toString(),
          Map<String, dynamic>.from(value),
        );
      }
    });
    return out;
  }

  static Future<void> _compartirArchivo({
    required String contenido,
    required String filename,
    required String mimeType,
    required String subject,
    required String texto,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(contenido));
    await descargarArchivoCorporativo(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
      subject: subject,
      texto: texto,
    );
  }

  static String _slugArchivo(String nombre) {
    final s = nombre
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    return s.isEmpty ? 'empresa' : s.substring(0, s.length.clamp(0, 32));
  }

  static String _csv(String v) {
    final s = v.replaceAll('"', '""');
    if (s.contains(';') || s.contains('\n')) return '"$s"';
    return s;
  }

  static String _montoCsv(double m) => m.toStringAsFixed(2);

  static String _html(String v) =>
      v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

enum FormatoLiquidacion { csv, html }
