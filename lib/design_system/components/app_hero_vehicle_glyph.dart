import 'package:flutter/material.dart';

/// Sedán moderno vectorial (sin PNG, sin fondo).
class AppHeroVehicleGlyph extends StatelessWidget {
  const AppHeroVehicleGlyph({
    super.key,
    required this.color,
    this.width = 96,
    this.height = 52,
  });

  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _ModernSedanPainter(color: color),
      ),
    );
  }
}

class _ModernSedanPainter extends CustomPainter {
  _ModernSedanPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Path body = Path()
      ..moveTo(w * 0.04, h * 0.66)
      ..cubicTo(w * 0.02, h * 0.54, w * 0.08, h * 0.46, w * 0.17, h * 0.44)
      ..lineTo(w * 0.29, h * 0.44)
      ..cubicTo(w * 0.31, h * 0.30, w * 0.42, h * 0.20, w * 0.56, h * 0.18)
      ..cubicTo(w * 0.70, h * 0.16, w * 0.82, h * 0.20, w * 0.88, h * 0.30)
      ..lineTo(w * 0.94, h * 0.44)
      ..cubicTo(w * 0.98, h * 0.54, w * 0.96, h * 0.66, w * 0.90, h * 0.70)
      ..lineTo(w * 0.06, h * 0.70)
      ..close();

    final Rect bounds = Rect.fromLTWH(0, 0, w, h);
    final Paint bodyFill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.95),
          color.withValues(alpha: 0.72),
        ],
      ).createShader(bounds);
    canvas.drawPath(body, bodyFill);

    final Paint bodyLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(body, bodyLine);

    // Franja LED delantera
    final Paint led = Paint()..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.86, h * 0.42, w * 0.06, h * 0.025),
        Radius.circular(h * 0.012),
      ),
      led,
    );

    // Ventanas panorámicas
    final Paint glass = Paint()..color = const Color(0xFF1A2332).withValues(alpha: 0.88);
    final Path cabin = Path()
      ..moveTo(w * 0.33, h * 0.44)
      ..lineTo(w * 0.40, h * 0.26)
      ..lineTo(w * 0.58, h * 0.24)
      ..lineTo(w * 0.72, h * 0.30)
      ..lineTo(w * 0.68, h * 0.44)
      ..close();
    canvas.drawPath(cabin, glass);

    // Línea cromada bajo ventanas
    final Paint chrome = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(w * 0.10, h * 0.52),
      Offset(w * 0.88, h * 0.52),
      chrome,
    );

    // Ruedas deportivas
    for (final cx in [w * 0.24, w * 0.74]) {
      _drawWheel(canvas, Offset(cx, h * 0.70), h * 0.13, color);
    }
  }

  void _drawWheel(Canvas canvas, Offset center, double radius, Color accent) {
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF2A2A2A));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(center, radius * 0.62, Paint()..color = accent.withValues(alpha: 0.35));
    canvas.drawCircle(
      center,
      radius * 0.28,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _ModernSedanPainter oldDelegate) =>
      oldDelegate.color != color;
}
