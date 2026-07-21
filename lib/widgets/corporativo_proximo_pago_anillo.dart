import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flygo_nuevo/pantallas/corporativo/corporativo_ui.dart';
import 'package:flygo_nuevo/utils/corporativo_ciclo_facturacion.dart';

/// Anillo profesional de liquidación: días hasta el próximo pago a RAI.
class CorporativoProximoPagoAnillo extends StatelessWidget {
  const CorporativoProximoPagoAnillo({
    super.key,
    required this.fechaCorte,
    required this.cicloDias,
    required this.montoRd,
    required this.formaPagoRai,
    this.fechaInicioPeriodo,
    this.onReportarPago,
  });

  final DateTime fechaCorte;
  final int cicloDias;
  final double montoRd;
  final String formaPagoRai;
  /// Si existe, el anillo usa la duración real del período abierto.
  final DateTime? fechaInicioPeriodo;
  final VoidCallback? onReportarPago;

  static int diasHastaCorte(DateTime fin) {
    final hoy = DateTime.now();
    final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
    final finDia = DateTime(fin.year, fin.month, fin.day);
    return finDia.difference(hoyDia).inDays;
  }

  static Color colorUrgencia(int diasRestantes) {
    if (diasRestantes < 0) return const Color(0xFFDC2626);
    if (diasRestantes <= 2) return const Color(0xFFDC2626);
    if (diasRestantes <= 7) return const Color(0xFFD97706);
    return const Color(0xFF059669);
  }

  static String etiquetaUrgencia(int diasRestantes) {
    if (diasRestantes < 0) {
      final n = -diasRestantes;
      return n == 1 ? 'Vencido hace 1 día' : 'Vencido hace $n días';
    }
    if (diasRestantes == 0) return 'Vence hoy';
    if (diasRestantes == 1) return 'Vence mañana';
    return 'Pago en $diasRestantes días';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.corporativoPalette;
    final fmtMonto = NumberFormat.currency(
      locale: 'es_DO',
      symbol: 'RD\$',
      decimalDigits: 0,
    );
    final fmtFecha = DateFormat('EEE d MMM', 'es');
    final dias = diasHastaCorte(fechaCorte);
    final ciclo = CorporativoCicloFacturacion.normalizarDias(cicloDias);
    final duracionReal = fechaInicioPeriodo == null
        ? ciclo
        : fechaCorte
            .difference(fechaInicioPeriodo!)
            .inDays
            .clamp(1, CorporativoCicloFacturacion.diasMax);
    final progreso = dias < 0
        ? 1.0
        : (1.0 - (dias / duracionReal)).clamp(0.08, 1.0);
    final accent = colorUrgencia(dias);
    final tituloCentro = etiquetaUrgencia(dias);
    final urgenciaAlta = dias <= 2;

    return corporativoCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Próximo pago a RAI',
                  style: TextStyle(
                    color: p.onCard,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              Text(
                CorporativoCicloFacturacion.etiqueta(ciclo),
                style: TextStyle(
                  color: p.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Liquidación empresarial del período en curso',
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 168,
              height: 168,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(168, 168),
                    painter: _AnilloPagoPainter(
                      progress: progreso,
                      trackColor: accent.withValues(alpha: 0.14),
                      progressColor: accent,
                      stroke: 11,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tituloCentro,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            fontSize: dias.abs() >= 10 ? 15 : 16,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          fmtFecha.format(fechaCorte),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: p.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (montoRd > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            fmtMonto.format(montoRd),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: p.onCard,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: urgenciaAlta ? 0.12 : 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.28)),
            ),
            child: Row(
              children: [
                Icon(
                  urgenciaAlta
                      ? Icons.priority_high_rounded
                      : Icons.event_available_outlined,
                  color: accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    urgenciaAlta
                        ? (dias < 0
                            ? 'El corte ya pasó. Reportá el pago a RAI lo antes posible.'
                            : 'Quedan pocos días. Prepará el comprobante de pago.')
                        : 'Ciclo ${CorporativoCicloFacturacion.descripcion(ciclo)}'
                            ' · ${CorporativoCicloFacturacion.etiquetaFormaPago(formaPagoRai)}',
                    style: TextStyle(
                      color: p.onCard,
                      fontSize: 12.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (onReportarPago != null && (montoRd > 0 || dias <= 7)) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onReportarPago,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text(
                  montoRd > 0 ? 'Reportar pago a RAI' : 'Ver pago a RAI',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnilloPagoPainter extends CustomPainter {
  _AnilloPagoPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.stroke,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // Empieza arriba (-90°) y avanza en sentido horario visual (Flutter es antihorario con sweep positivo desde start).
    const start = -math.pi / 2;
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(rect, start, sweep, false, arc);
  }

  @override
  bool shouldRepaint(covariant _AnilloPagoPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.stroke != stroke;
  }
}
