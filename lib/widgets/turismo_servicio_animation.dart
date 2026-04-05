import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Cielo, nubes y avión — solo tarjeta Turismo (selección de servicio).
class TurismoServicioAnimation extends StatefulWidget {
  const TurismoServicioAnimation({super.key});

  @override
  State<TurismoServicioAnimation> createState() =>
      _TurismoServicioAnimationState();
}

class _TurismoServicioAnimationState extends State<TurismoServicioAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Turismo, traslados y aeropuerto',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 104,
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _TurismoPlanePainter(t: _controller.value),
                    child: child,
                  );
                },
                child: const SizedBox.expand(),
              ),
              Positioned(
                top: 6,
                right: 8,
                child: Text(
                  'Turismo',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    shadows: const [
                      Shadow(
                          color: Colors.black45,
                          blurRadius: 3,
                          offset: Offset(0, 1)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TurismoPlanePainter extends CustomPainter {
  _TurismoPlanePainter({required this.t});

  final double t;

  void _cloud(Canvas canvas, Offset c, double r, Paint p) {
    canvas.drawCircle(c, r, p);
    canvas.drawCircle(c + Offset(r * 0.7, r * 0.15), r * 0.85, p);
    canvas.drawCircle(c + Offset(-r * 0.65, r * 0.1), r * 0.75, p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Paint bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.22),
          Colors.cyanAccent.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final Paint cloud = Paint()..color = Colors.white.withValues(alpha: 0.35);
    final double scroll = t * 80;
    final double cloudSpan = w + 50;
    for (var i = 0; i < 4; i++) {
      double baseX = (i * 55.0 - scroll) % cloudSpan;
      if (baseX < 0) baseX += cloudSpan;
      baseX -= 20;
      _cloud(canvas, Offset(baseX, 18 + i * 6.0), 10 + i * 1.5, cloud);
    }

    final double dx = math.sin(t * math.pi * 2) * math.min(28.0, w * 0.12);
    final double dy = math.sin(t * math.pi * 2 + 0.8) * 3.2;

    canvas.save();
    canvas.translate(w * 0.52 + dx, h * 0.52 + dy);
    canvas.rotate(-0.11);

    // Avión simplificado (vista lateral)
    final Path fuselage = Path()
      ..moveTo(-26, 0)
      ..quadraticBezierTo(-8, -5, 18, -2)
      ..quadraticBezierTo(24, 0, 18, 3)
      ..quadraticBezierTo(-8, 6, -26, 2)
      ..close();

    canvas.drawPath(
      fuselage,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.95)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      fuselage,
      Paint()
        ..color = const Color(0xFF4A148C).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Ala
    final Path wing = Path()
      ..moveTo(-4, 1)
      ..lineTo(10, 14)
      ..lineTo(4, 16)
      ..lineTo(-14, 4)
      ..close();
    canvas.drawPath(
        wing, Paint()..color = Colors.white.withValues(alpha: 0.88));

    // Estabilizador
    canvas.drawPath(
      Path()
        ..moveTo(-18, -1)
        ..lineTo(-24, -12)
        ..lineTo(-20, -13)
        ..lineTo(-14, -2)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.82),
    );

    // Ventanillas
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(-6.0 + i * 9.0, -1.5),
        2.2,
        Paint()..color = const Color(0xFF81D4FA).withValues(alpha: 0.9),
      );
    }

    // Estela suave
    final double trailPhase = (t * math.pi * 4) % (math.pi * 2);
    final Paint trail = Paint()
      ..color =
          Colors.white.withValues(alpha: 0.15 + 0.12 * math.sin(trailPhase))
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-32, 1), const Offset(-52, 4), trail);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TurismoPlanePainter oldDelegate) =>
      oldDelegate.t != t;
}
