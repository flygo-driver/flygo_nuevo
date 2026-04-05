import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Franja inferior discreta: vehículo sobre trazo suave — tono sobrio para producción.
class PromoTaxiPistaAnimation extends StatefulWidget {
  const PromoTaxiPistaAnimation({super.key});

  @override
  State<PromoTaxiPistaAnimation> createState() =>
      _PromoTaxiPistaAnimationState();
}

class _PromoTaxiPistaAnimationState extends State<PromoTaxiPistaAnimation>
    with SingleTickerProviderStateMixin {
  static const double _carW = 40;
  static const double _carH = 25;
  static const double _edgePad = 12;

  static const double _waveAmp = 2.8;
  static const double _waves = 1.35;

  late final AnimationController _controller;
  late final CurvedAnimation _easeAlong;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16800),
    )..repeat();
    _easeAlong = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _easeAlong.dispose();
    _controller.dispose();
    super.dispose();
  }

  double _roadCenterYFromBottom(double width, double u) {
    final double xNorm = u * width;
    return 8.0 +
        _waveAmp * math.sin(2 * math.pi * _waves * xNorm / math.max(1, width));
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: 44,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.04),
                  Colors.white.withValues(alpha: 0.02),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double w = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _WavyTrackPainter(
                          waveAmp: _waveAmp,
                          waves: _waves,
                          lineBottomInset: 8,
                        ),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _easeAlong,
                      builder: (context, child) {
                        final double u = _easeAlong.value;
                        final double travel = w + _carW + _edgePad * 2;
                        final double left = (u * travel) - _carW - _edgePad;
                        final double roadY =
                            _roadCenterYFromBottom(w, (left + _carW * 0.5) / w);
                        final double bob = math.sin(u * math.pi * 2) * 0.2;
                        return Positioned(
                          left: left,
                          bottom: roadY - 1.5 + bob,
                          child: SizedBox(
                            width: _carW,
                            height: _carH,
                            child: CustomPaint(
                              painter: _SedanProPainter(
                                t: _controller.value,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _WavyTrackPainter extends CustomPainter {
  _WavyTrackPainter({
    required this.waveAmp,
    required this.waves,
    required this.lineBottomInset,
  });

  final double waveAmp;
  final double waves;
  final double lineBottomInset;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Path path = Path();
    const int steps = 40;
    for (var i = 0; i <= steps; i++) {
      final double t = i / steps;
      final double x = t * w;
      final double y =
          h - lineBottomInset - waveAmp * math.sin(2 * math.pi * waves * t);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.06)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _WavyTrackPainter oldDelegate) =>
      oldDelegate.waveAmp != waveAmp || oldDelegate.waves != waves;
}

/// Silueta tipo sedán / servicio — grises neutros, sin colores llamativos.
class _SedanProPainter extends CustomPainter {
  _SedanProPainter({required this.t});

  final double t;

  static const Color _body = Color(0xFF4A5568);
  static const Color _bodyDark = Color(0xFF3D4555);
  static const Color _glass = Color(0xFF9CA3AF);
  static const Color _accent = Color(0xFFD4A574);

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    void wheel(double cx, double cy, double r) {
      canvas.drawCircle(Offset(cx, cy), r + 0.5,
          Paint()..color = Colors.black.withValues(alpha: 0.35));
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..color = const Color(0xFF2D3748),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
      final double spin = t * math.pi * 2.2;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(
          cx + math.cos(spin) * (r - 1),
          cy + math.sin(spin) * (r - 1),
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.15)
          ..strokeWidth = 0.8,
      );
    }

    wheel(9, h - 3.5, 4);
    wheel(w - 9, h - 3.5, 4);

    final RRect body = RRect.fromRectAndRadius(
      Rect.fromLTWH(1.5, h * 0.42, w - 3, h * 0.38),
      const Radius.circular(3),
    );
    canvas.drawRRect(body, Paint()..color = _bodyDark);
    canvas.drawRRect(
      body,
      Paint()
        ..color = _body
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final RRect roof = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.14, w * 0.5, h * 0.36),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(roof, Paint()..color = _body);
    canvas.drawRRect(
      roof,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.16, h * 0.2, w * 0.26, h * 0.2),
        const Radius.circular(1.5),
      ),
      Paint()..color = _glass.withValues(alpha: 0.45),
    );

    canvas.drawCircle(
      Offset(w * 0.42, h * 0.22),
      2.2,
      Paint()..color = const Color(0xFFE8D5C4).withValues(alpha: 0.85),
    );

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.12),
        width: 5,
        height: 2,
      ),
      Paint()..color = _accent.withValues(alpha: 0.65),
    );

    canvas.drawCircle(
      Offset(w - 4, h * 0.55),
      1.2,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _SedanProPainter oldDelegate) =>
      oldDelegate.t != t;
}
