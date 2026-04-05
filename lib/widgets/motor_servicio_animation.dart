import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Motocicleta con pasajero que se desplaza — solo tarjeta Motor (selección de servicio).
class MotorServicioAnimation extends StatefulWidget {
  const MotorServicioAnimation({super.key});

  @override
  State<MotorServicioAnimation> createState() => _MotorServicioAnimationState();
}

class _MotorServicioAnimationState extends State<MotorServicioAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Pedir viaje en motor',
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
                    painter: _MotorRiderPainter(t: _controller.value),
                    child: child,
                  );
                },
                child: const SizedBox.expand(),
              ),
              Positioned(
                top: 6,
                right: 8,
                child: Text(
                  '¡Pedí motor!',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    shadows: const [
                      Shadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 1)),
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

class _MotorRiderPainter extends CustomPainter {
  _MotorRiderPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Fondo suave
    final Paint bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.18),
          Colors.black.withValues(alpha: 0.06),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    // Líneas de velocidad (parallax)
    final Paint streak = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final double scroll = (1 - t) * 40;
    for (double x = -20; x < w + 40; x += 14) {
      canvas.drawLine(Offset(x + scroll, h * 0.35), Offset(x + scroll - 10, h * 0.5), streak);
    }

    // Asfalto
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.62, w, h * 0.38),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );
    final Paint roadLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 2;
    for (double x = -30 + t * 50; x < w + 20; x += 22) {
      canvas.drawLine(Offset(x, h * 0.78), Offset(x + 10, h * 0.78), roadLine);
    }

    // Desplazamiento horizontal del conjunto moto + persona (t 0→1 ida y vuelta)
    final double dx = (t - 0.5) * 2 * math.min(38, w * 0.14);
    final double bob = math.sin(t * math.pi) * 2.2;

    canvas.save();
    canvas.translate(w * 0.5 + dx, h * 0.48 + bob);

    // --- Motocicleta (vista lateral simple) ---
    const double groundY = 18.0;

    void wheel(double cx, double cy, double r) {
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = const Color(0xFF37474F)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      final double spin = t * math.pi * 4;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + math.cos(spin) * (r - 2), cy + math.sin(spin) * (r - 2)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 1.2,
      );
    }

    wheel(-22, groundY, 9);
    wheel(20, groundY, 9);

    final Paint frame = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(const Offset(-22, groundY), const Offset(-4, groundY - 8), frame);
    canvas.drawLine(const Offset(-4, groundY - 8), const Offset(16, groundY - 4), frame);
    canvas.drawLine(const Offset(16, groundY - 4), const Offset(20, groundY), frame);

    // Asiento / depósito
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(2, groundY - 14), width: 22, height: 8),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.orange.shade100,
    );

    // Manillar
    canvas.drawLine(
      const Offset(14, groundY - 10),
      const Offset(22, groundY - 16),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );

    // --- Pasajero (hombresito) encima del asiento ---
    const Offset seat = Offset(-2, groundY - 18);
    // Torso
    canvas.drawLine(
      seat,
      Offset(seat.dx - 2, seat.dy - 14),
      Paint()
        ..color = const Color(0xFFFFF9C4)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
    // Cabeza
    canvas.drawCircle(Offset(seat.dx - 2, seat.dy - 20), 6, Paint()..color = const Color(0xFFFFE0B2));
    canvas.drawCircle(
      Offset(seat.dx - 2, seat.dy - 20),
      6,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Brazos al manillar
    canvas.drawLine(
      Offset(seat.dx + 2, seat.dy - 8),
      const Offset(18, groundY - 14),
      Paint()
        ..color = const Color(0xFFFFF9C4)
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    // Piernas abrazando moto
    canvas.drawLine(
      seat,
      Offset(seat.dx - 6, groundY - 2),
      Paint()
        ..color = const Color(0xFF5D4037)
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      seat,
      Offset(seat.dx + 8, groundY - 1),
      Paint()
        ..color = const Color(0xFF5D4037)
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MotorRiderPainter oldDelegate) => oldDelegate.t != t;
}
