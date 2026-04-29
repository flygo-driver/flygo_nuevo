import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Guagua con varios pasajeros — solo tarjeta Giras / cupos (selección de servicio).
class GirasCuposAnimation extends StatefulWidget {
  const GirasCuposAnimation({super.key});

  @override
  State<GirasCuposAnimation> createState() => _GirasCuposAnimationState();
}

class _GirasCuposAnimationState extends State<GirasCuposAnimation>
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
    return Semantics(
      label: 'Giras por cupos, tours compartidos',
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
                    painter: _BusCrowdPainter(t: _controller.value),
                    child: child,
                  );
                },
                child: const SizedBox.expand(),
              ),
              Positioned(
                top: 6,
                right: 8,
                child: Text(
                  'Giras por cupos',
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

class _BusCrowdPainter extends CustomPainter {
  _BusCrowdPainter({required this.t});

  final double t;

  static const List<Color> _skins = [
    Color(0xFFFFE0B2),
    Color(0xFFFFCC80),
    Color(0xFFD7CCC8),
    Color(0xFFC8E6C9),
    Color(0xFFFFF9C4),
    Color(0xFFCE93D8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Paint bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.2),
          Colors.black.withValues(alpha: 0.05),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final Paint streak = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final double scroll = (1 - t) * 36;
    for (double x = -20; x < w + 40; x += 16) {
      canvas.drawLine(Offset(x + scroll, h * 0.28),
          Offset(x + scroll - 8, h * 0.42), streak);
    }

    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.62, w, h * 0.38),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );
    final Paint roadLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..strokeWidth = 2;
    for (double x = -30 + t * 48; x < w + 20; x += 22) {
      canvas.drawLine(Offset(x, h * 0.78), Offset(x + 10, h * 0.78), roadLine);
    }

    final double dx = (t - 0.5) * 2 * math.min(36, w * 0.13);
    final double bob = math.sin(t * math.pi) * 2.0;

    canvas.save();
    canvas.translate(w * 0.5 + dx, h * 0.5 + bob);

    const double groundY = 17;
    const double busW = 112;
    const double busH = 36;
    const double cx = 0;
    const double cy = -6;
    final Rect busRect =
        Rect.fromCenter(center: const Offset(0, -6), width: busW, height: busH);

    void wheel(double wx, double wy, double r) {
      canvas.drawCircle(
        Offset(wx, wy),
        r + 1,
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
      canvas.drawCircle(
        Offset(wx, wy),
        r,
        Paint()..color = const Color(0xFF37474F),
      );
      canvas.drawCircle(
        Offset(wx, wy),
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      final double spin = t * math.pi * 3;
      canvas.drawLine(
        Offset(wx, wy),
        Offset(wx + math.cos(spin) * (r - 2), wy + math.sin(spin) * (r - 2)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45)
          ..strokeWidth = 1.1,
      );
    }

    wheel(cx - busW * 0.32, groundY, 7);
    wheel(cx + busW * 0.28, groundY, 7);

    final RRect body =
        RRect.fromRectAndRadius(busRect, const Radius.circular(8));
    canvas.drawRRect(
      body,
      Paint()..color = const Color(0xFFFFD54F),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..color = const Color(0xFFF9A825)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Franja “tour”
    canvas.drawRect(
      Rect.fromCenter(center: const Offset(0, -4), width: 104, height: 5),
      Paint()..color = const Color(0xFF00838F).withValues(alpha: 0.85),
    );

    // Ventanas con pasajeros (cabecitas)
    final List<Rect> wins = [
      Rect.fromCenter(center: const Offset(-38, -12), width: 18, height: 16),
      Rect.fromCenter(center: const Offset(-14, -12), width: 18, height: 16),
      Rect.fromCenter(center: const Offset(10, -12), width: 18, height: 16),
      Rect.fromCenter(center: const Offset(34, -12), width: 18, height: 16),
    ];

    int skinI = 0;
    void headsInWindow(Rect wr, List<Offset> locals) {
      final RRect wrR = RRect.fromRectAndRadius(wr, const Radius.circular(3));
      canvas.drawRRect(
        wrR,
        Paint()..color = const Color(0xFFB2EBF2).withValues(alpha: 0.92),
      );
      canvas.drawRRect(
        wrR,
        Paint()
          ..color = const Color(0xFF006064).withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      for (var i = 0; i < locals.length; i++) {
        final Offset p = locals[i];
        final double wobble =
            math.sin(t * math.pi * 2 + p.dx * 0.4 + i * 0.7) * 1.6;
        final Offset c = wr.center + p + Offset(0, wobble);
        const double headR = 3.2;
        canvas.drawCircle(
          c,
          headR,
          Paint()..color = _skins[skinI % _skins.length],
        );
        skinI++;
        canvas.drawCircle(
          c,
          headR,
          Paint()
            ..color = Colors.black26
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
      }
    }

    headsInWindow(wins[0], const [Offset(-4, 2), Offset(4, 1), Offset(0, -3)]);
    headsInWindow(wins[1],
        const [Offset(-3, 0), Offset(5, 2), Offset(-1, -4), Offset(2, -2)]);
    headsInWindow(wins[2], const [Offset(-4, 1), Offset(3, -2), Offset(4, 3)]);
    headsInWindow(wins[3],
        const [Offset(-2, 0), Offset(4, 1), Offset(0, -3), Offset(-4, -2)]);

    // Parabrisas / frente
    final Path front = Path()
      ..moveTo(cx + busW * 0.48, cy - busH * 0.35)
      ..lineTo(cx + busW * 0.52, cy - busH * 0.2)
      ..lineTo(cx + busW * 0.52, cy + busH * 0.25)
      ..lineTo(cx + busW * 0.48, cy + busH * 0.32)
      ..close();
    canvas.drawPath(
      front,
      Paint()..color = const Color(0xFF4DD0E1).withValues(alpha: 0.75),
    );
    canvas.drawPath(
      front,
      Paint()
        ..color = const Color(0xFF006064)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BusCrowdPainter oldDelegate) =>
      oldDelegate.t != t;
}
