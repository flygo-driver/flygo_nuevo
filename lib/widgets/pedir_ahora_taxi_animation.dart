import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Mini escena “mapa en movimiento + taxi” para la tarjeta PEDIR AHORA (solo UI).
class PedirAhoraTaxiAnimation extends StatefulWidget {
  const PedirAhoraTaxiAnimation({super.key});

  @override
  State<PedirAhoraTaxiAnimation> createState() =>
      _PedirAhoraTaxiAnimationState();
}

class _PedirAhoraTaxiAnimationState extends State<PedirAhoraTaxiAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _TaxiMapPainter(progress: _controller.value),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _TaxiMapPainter extends CustomPainter {
  _TaxiMapPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double scroll = progress * 44;

    final RRect clip = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    canvas.clipRRect(clip);

    // Fondo tipo mapa nocturno sobre la tarjeta verde
    final bg = Paint()..color = const Color(0x33000000);
    canvas.drawRect(Offset.zero & size, bg);

    // Cuadrícula / calles que se desplazan
    final street = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (double x = -w; x < w * 2; x += 22) {
      final double sx = x + scroll;
      canvas.drawLine(Offset(sx, 0), Offset(sx, h), street);
    }
    for (double y = 0; y < h + 30; y += 18) {
      final double sy = y + (scroll * 0.35) % 18;
      canvas.drawLine(Offset(0, sy), Offset(w, sy), street);
    }

    // “Bloques” de ciudad
    final block = Paint()..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.05 + scroll * 0.08, h * 0.12, w * 0.22, h * 0.35),
        const Radius.circular(4),
      ),
      block,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.62 - scroll * 0.06, h * 0.48, w * 0.28, h * 0.38),
        const Radius.circular(4),
      ),
      block,
    );

    // Ruta curva (línea punteada animada)
    final path = Path();
    path.moveTo(w * 0.08, h * 0.72);
    path.quadraticBezierTo(w * 0.45, h * 0.2, w * 0.88, h * 0.55);

    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    _drawDashedPath(canvas, path, dashPaint, dashOffset: progress * 24);

    // Taxi recorre la ruta en bucle (0 → 1 cada ciclo del controlador)
    final double t = progress.clamp(0.0, 1.0);
    final Offset p = _quadraticPoint(
      Offset(w * 0.08, h * 0.72),
      Offset(w * 0.45, h * 0.2),
      Offset(w * 0.88, h * 0.55),
      t,
    );

    // Sombra bajo el taxi
    final shadow = Paint()..color = Colors.black.withValues(alpha: 0.35);
    canvas.drawOval(
      Rect.fromCenter(center: p.translate(0, 10), width: 34, height: 10),
      shadow,
    );

    canvas.save();
    canvas.translate(p.dx, p.dy);
    final double angle = -0.35 + 0.2 * math.sin(progress * math.pi * 2);
    canvas.rotate(angle);

    // Cuerpo taxi (amarillo)
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-20, -12, 40, 22),
      const Radius.circular(5),
    );
    final taxiYellow = Paint()..color = const Color(0xFFFFD54F);
    final taxiBorder = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(body, taxiYellow);
    canvas.drawRRect(body, taxiBorder);

    // Techo / señal
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-12, -16, 24, 8),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    final signPaint = Paint()..color = const Color(0xFF00E676);
    canvas.drawRect(const Rect.fromLTWH(-4, -18, 8, 4), signPaint);

    // Ruedas
    final wheel = Paint()..color = const Color(0xFF263238);
    canvas.drawCircle(const Offset(-12, 12), 4.5, wheel);
    canvas.drawCircle(const Offset(12, 12), 4.5, wheel);

    canvas.restore();

    // Pin de origen pequeño
    final pinCenter = Offset(w * 0.1, h * 0.78);
    final pinPaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawCircle(pinCenter, 4, pinPaint);
    canvas.drawCircle(
        pinCenter,
        6,
        Paint()
          ..color = Colors.redAccent.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  Offset _quadraticPoint(Offset p0, Offset p1, Offset p2, double t) {
    final double u = 1 - t;
    return Offset(
      u * u * p0.dx + 2 * u * t * p1.dx + t * t * p2.dx,
      u * u * p0.dy + 2 * u * t * p1.dy + t * t * p2.dy,
    );
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint,
      {required double dashOffset}) {
    for (final metric in path.computeMetrics()) {
      double d = dashOffset % 12;
      while (d < metric.length) {
        final double start = d;
        final double end = math.min(d + 6, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TaxiMapPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
