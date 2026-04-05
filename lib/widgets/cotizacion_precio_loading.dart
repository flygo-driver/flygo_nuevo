import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ondas tipo radar (rojo, azul, púrpura, cian, naranja) — animación local, sin tocar pantallas.
class _RadarWavesPainter extends CustomPainter {
  _RadarWavesPainter({required this.progress});

  final double progress;

  static const List<Color> _waveColors = [
    Color(0xFFE53935), // rojo
    Color(0xFF1E88E5), // azul
    Color(0xFF8E24AA), // púrpura
    Color(0xFF00ACC1), // cian
    Color(0xFFFF6D00), // naranja
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) * 0.46;

    final core = Paint()..color = const Color(0xFF49F18B).withValues(alpha: 0.95);
    canvas.drawCircle(c, math.max(2.5, maxR * 0.09), core);

    void drawWaves(double tShift, double alphaMul) {
      for (var wave = 0; wave < 5; wave++) {
        final phase = (progress + tShift + wave * 0.17) % 1.0;
        final r = maxR * phase;
        if (r < 3) continue;
        final alpha =
            ((1.0 - phase) * 0.58 * alphaMul).clamp(0.0, 1.0);
        final paint = Paint()
            ..color =
                _waveColors[wave % _waveColors.length].withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2;
        canvas.drawCircle(c, r, paint);
      }
    }

    drawWaves(0, 1.0);
    drawWaves(0.5, 0.35);

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(progress * 2 * math.pi);
    canvas.translate(-c.dx, -c.dy);
    final beam = Paint()
      ..color = const Color(0xFF7C4DFF).withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: maxR * 0.82),
      -0.55,
      1.0,
      false,
      beam,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RadarWavesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _AnimatedRadar extends StatefulWidget {
  const _AnimatedRadar({required this.dimension});

  final double dimension;

  @override
  State<_AnimatedRadar> createState() => _AnimatedRadarState();
}

class _AnimatedRadarState extends State<_AnimatedRadar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            size: Size(widget.dimension, widget.dimension),
            painter: _RadarWavesPainter(progress: _controller.value),
          );
        },
      ),
    );
  }
}

/// Indicador de cotización: radar con ondas multicolor + líneas suaves.
class CotizacionPrecioLoadingStrip extends StatelessWidget {
  const CotizacionPrecioLoadingStrip({
    super.key,
    required this.accentColor,
    required this.isDark,
    this.compact = false,
    this.message = 'Calculando precio…',
  });

  final Color accentColor;
  final bool isDark;
  final bool compact;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSubtle = scheme.onSurface.withValues(alpha: 0.68);
    final track = accentColor.withValues(alpha: isDark ? 0.22 : 0.14);
    final trackThin = accentColor.withValues(alpha: isDark ? 0.14 : 0.1);

    Widget lineMain() => ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: compact ? 3 : 4,
            width: double.infinity,
            child: LinearProgressIndicator(
              backgroundColor: track,
              color: accentColor,
              minHeight: compact ? 3 : 4,
            ),
          ),
        );

    Widget lineThin() => ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 2,
            width: double.infinity,
            child: LinearProgressIndicator(
              backgroundColor: trackThin,
              color: accentColor.withValues(alpha: 0.85),
              minHeight: 2,
            ),
          ),
        );

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: Center(
              child: _AnimatedRadar(dimension: 44),
            ),
          ),
          const SizedBox(height: 6),
          lineMain(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 96,
          child: Center(
            child: _AnimatedRadar(dimension: 88),
          ),
        ),
        const SizedBox(height: 6),
        lineMain(),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: onSubtle,
          ),
        ),
        const SizedBox(height: 8),
        lineThin(),
      ],
    );
  }
}

/// Bloque donde irá el total: mismo estilo que la tarjeta de precio, en estado “esperando”.
class CotizacionPrecioLoadingPlaceholder extends StatelessWidget {
  const CotizacionPrecioLoadingPlaceholder({
    super.key,
    required this.accentColor,
    required this.isDark,
    this.message = 'Calculando precio…',
  });

  final Color accentColor;
  final bool isDark;
  final String message;

  @override
  Widget build(BuildContext context) {
    final border = accentColor.withValues(alpha: isDark ? 0.4 : 0.35);
    final fill = accentColor.withValues(alpha: isDark ? 0.12 : 0.06);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border, width: 1.5),
      ),
      child: CotizacionPrecioLoadingStrip(
        accentColor: accentColor,
        isDark: isDark,
        message: message,
      ),
    );
  }
}

/// Overlay con fondo atenuado (turismo / mensajes de progreso con texto).
class CotizacionPrecioLoadingDimmed extends StatelessWidget {
  const CotizacionPrecioLoadingDimmed({
    super.key,
    required this.accentColor,
    required this.isDark,
    this.message = 'Calculando precio…',
  });

  final Color accentColor;
  final bool isDark;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: CotizacionPrecioLoadingStrip(
            accentColor: accentColor,
            isDark: isDark,
            message: message,
          ),
        ),
      ),
    );
  }
}
