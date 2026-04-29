import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Indica visualmente “viaje para más tarde” (calendario + reloj). Solo UI.
class ProgramarViajeFuturoAnimation extends StatefulWidget {
  const ProgramarViajeFuturoAnimation({super.key});

  @override
  State<ProgramarViajeFuturoAnimation> createState() =>
      _ProgramarViajeFuturoAnimationState();
}

class _ProgramarViajeFuturoAnimationState
    extends State<ProgramarViajeFuturoAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'Programar viaje para otra fecha u hora',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 88,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                clipBehavior: Clip.hardEdge,
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _FuturoPainter(
                      t: _controller.value,
                      isDark: isDark,
                    ),
                    child: const SizedBox.expand(),
                  ),
                  Positioned(
                    left: 108,
                    right: 76,
                    top: 10,
                    child: Text(
                      'Para después',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.96),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        shadows: const [
                          Shadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 1)),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 108,
                    right: 76,
                    bottom: 10,
                    child: Text(
                      'Elegí fecha y hora abajo',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FuturoPainter extends CustomPainter {
  _FuturoPainter({required this.t, required this.isDark});

  final double t;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Paint bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? const [Color(0xFF1A237E), Color(0xFF0D1642)]
            : const [Color(0xFF5C6BC0), Color(0xFF3949AB)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    final double sweep = (t * 2 - 1).clamp(-1.0, 1.0);
    final Paint gloss = Paint()
      ..shader = LinearGradient(
        begin: Alignment(sweep, -0.5),
        end: Alignment(sweep + 0.8, 1.2),
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.11),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, gloss);

    final double calW = math.min(92, w * 0.36);
    final double calH = h * 0.76;
    const double calLeft = 10;
    final double calTop = (h - calH) * 0.5;
    final RRect calR = RRect.fromRectAndRadius(
      Rect.fromLTWH(calLeft, calTop, calW, calH),
      const Radius.circular(8),
    );
    canvas.drawRRect(
        calR, Paint()..color = Colors.white.withValues(alpha: 0.92));
    canvas.drawRRect(
      calR,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final Paint hook = Paint()
      ..color = const Color(0xFF3949AB)
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(calLeft + calW * 0.35, calTop + 2),
          width: 12,
          height: 8),
      math.pi * 0.85,
      math.pi * 0.65,
      false,
      hook,
    );
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(calLeft + calW * 0.65, calTop + 2),
          width: 12,
          height: 8),
      math.pi * 0.85,
      math.pi * 0.65,
      false,
      hook,
    );

    final double headerH = calH * 0.22;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(calLeft, calTop, calW, headerH),
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
        bottomLeft: Radius.zero,
        bottomRight: Radius.zero,
      ),
      Paint()..color = const Color(0xFF5C6BC0),
    );

    final Paint cellStroke = Paint()
      ..color = Colors.black12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    const cols = 4;
    const rows = 3;
    final double gridTop = calTop + headerH + 4;
    final double gridH = calTop + calH - gridTop - 4;
    final double cw = (calW - 8) / cols;
    final double ch = gridH / rows;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final Rect rct = Rect.fromLTWH(
          calLeft + 4 + c * cw,
          gridTop + r * ch,
          cw - 2,
          ch - 2,
        );
        final double pulse = (t * (cols * rows) - (r * cols + c)).abs();
        final double a = (1.0 - pulse.clamp(0.0, 1.0)) * 0.4;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rct, const Radius.circular(2)),
          Paint()
            ..color = Color.lerp(Colors.white, const Color(0xFF7986CB), a)!,
        );
        canvas.drawRRect(
            RRect.fromRectAndRadius(rct, const Radius.circular(2)), cellStroke);
      }
    }

    final double cx = w - math.min(34, w * 0.09);
    final double cy = h * 0.5;
    final double rClock = math.min(26.0, h * 0.30);
    canvas.drawCircle(Offset(cx, cy), rClock,
        Paint()..color = Colors.white.withValues(alpha: 0.95));
    canvas.drawCircle(
      Offset(cx, cy),
      rClock,
      Paint()
        ..color = const Color(0xFF3949AB).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final double ang = -math.pi / 2 + t * math.pi * 2;
    final Paint hand = Paint()
      ..color = const Color(0xFF283593)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(
          cx + math.cos(ang) * (rClock - 5), cy + math.sin(ang) * (rClock - 5)),
      hand,
    );
    canvas.drawCircle(
        Offset(cx, cy), 3.2, Paint()..color = const Color(0xFF5C6BC0));
  }

  @override
  bool shouldRepaint(covariant _FuturoPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.isDark != isDark;
}
