import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Bienvenida tras registro de cliente (email/contraseña).
class RaiBienvenidaRegistroDialog {
  RaiBienvenidaRegistroDialog._();

  static Future<void> mostrar(
    BuildContext context, {
    String? nombre,
  }) async {
    final String titulo = (nombre != null && nombre.trim().isNotEmpty)
        ? '¡Bienvenido, ${nombre.trim()}!'
        : '¡Bienvenido a RAI!';

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _BienvenidaRegistroCard(titulo: titulo),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BienvenidaRegistroCard extends StatefulWidget {
  const _BienvenidaRegistroCard({required this.titulo});

  final String titulo;

  @override
  State<_BienvenidaRegistroCard> createState() => _BienvenidaRegistroCardState();
}

class _BienvenidaRegistroCardState extends State<_BienvenidaRegistroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _golCtrl;

  @override
  void initState() {
    super.initState();
    _golCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..forward();
  }

  @override
  void dispose() {
    _golCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 52),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF0D1F14),
                      Color(0xFF06120C),
                      Color(0xFF0A0A0A),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: const Color(0xFF49F18B).withValues(alpha: 0.45),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF49F18B).withValues(alpha: 0.18),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF49F18B).withValues(alpha: 0.25),
                              const Color(0xFF0F9D58).withValues(alpha: 0.12),
                            ],
                          ),
                          border: Border.all(
                            color:
                                const Color(0xFF49F18B).withValues(alpha: 0.55),
                          ),
                        ),
                        child: const Icon(
                          Icons.directions_car_filled_rounded,
                          color: Color(0xFF49F18B),
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        widget.titulo,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'RAI Driver',
                        style: TextStyle(
                          color:
                              const Color(0xFF49F18B).withValues(alpha: 0.95),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Tu viaje, tu ritmo.\nMoverte en República Dominicana nunca fue tan simple.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 15,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF49F18B),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Entrar a la app',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 8,
            width: 168,
            height: 118,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _golCtrl,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _GolBienvenidaPainter(progress: _golCtrl.value),
                    size: const Size(168, 118),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Portería grande + balón que entra a gol y desaparece en la red.
class _GolBienvenidaPainter extends CustomPainter {
  _GolBienvenidaPainter({required this.progress});

  final double progress;

  static const double _golAt = 0.74;

  @override
  void paint(Canvas canvas, Size size) {
    final _GoalGeom g = _GoalGeom.fromSize(size);
    _drawPorteria(canvas, g);
    _drawBalon(canvas, g, size);
    if (progress >= _golAt - 0.02) {
      _drawCelebracionGol(canvas, g);
    }
  }

  void _drawPorteria(Canvas canvas, _GoalGeom g) {
    final double intro = (progress / 0.14).clamp(0.0, 1.0);
    if (intro <= 0) return;

    final Paint shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.35 * intro)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRect(
      Rect.fromLTWH(g.left + 6, g.groundY + 2, g.width, 6),
      shadow,
    );

    final Paint post = Paint()
      ..shader = ui.Gradient.linear(
        Offset(g.left, g.top),
        Offset(g.left, g.groundY),
        [
          Colors.white.withValues(alpha: 0.98 * intro),
          const Color(0xFFD8DEE6).withValues(alpha: 0.92 * intro),
        ],
      )
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final Paint postInner = Paint()
      ..color = Colors.white.withValues(alpha: 0.35 * intro)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Postes y travesaño (perspectiva ligera).
    canvas.drawLine(Offset(g.left, g.groundY), Offset(g.left, g.top), post);
    canvas.drawLine(Offset(g.right, g.groundY), Offset(g.right, g.top), post);
    canvas.drawLine(Offset(g.left, g.top), Offset(g.right, g.top), post);

    canvas.drawLine(
      Offset(g.backLeft, g.groundY - 4),
      Offset(g.backLeft, g.top + 8),
      postInner,
    );
    canvas.drawLine(
      Offset(g.backRight, g.groundY - 4),
      Offset(g.backRight, g.top + 8),
      postInner,
    );
    canvas.drawLine(
      Offset(g.backLeft, g.top + 8),
      Offset(g.backRight, g.top + 8),
      postInner,
    );

    _drawNet(canvas, g, intro);
  }

  void _drawNet(Canvas canvas, _GoalGeom g, double intro) {
    final Paint net = Paint()
      ..color = Colors.white.withValues(alpha: 0.22 * intro)
      ..strokeWidth = 1.1;

    const int cols = 9;
    const int rows = 6;
    for (int c = 0; c <= cols; c++) {
      final double t = c / cols;
      final Offset top = Offset(
        ui.lerpDouble(g.left, g.right, t)!,
        ui.lerpDouble(g.top, g.top + 6, t)!,
      );
      final Offset bottom = Offset(
        ui.lerpDouble(g.left, g.right, t)!,
        g.groundY,
      );
      canvas.drawLine(top, bottom, net);
    }
    for (int r = 0; r <= rows; r++) {
      final double t = r / rows;
      final double y = ui.lerpDouble(g.top, g.groundY, t)!;
      canvas.drawLine(Offset(g.left, y), Offset(g.right, y), net);
    }

    final Paint netDepth = Paint()
      ..color = const Color(0xFF49F18B).withValues(alpha: 0.12 * intro)
      ..style = PaintingStyle.fill;
    final Path netFill = Path()
      ..moveTo(g.left, g.top)
      ..lineTo(g.right, g.top)
      ..lineTo(g.right, g.groundY)
      ..lineTo(g.left, g.groundY)
      ..close();
    canvas.drawPath(netFill, netDepth);
  }

  void _drawBalon(Canvas canvas, _GoalGeom g, Size size) {
    if (progress <= 0.1) return;

    final double kickT = ((progress - 0.1) / (_golAt - 0.1)).clamp(0.0, 1.0);
    final double fly = Curves.easeInCubic.transform(kickT);

    final Offset start = Offset(size.width * 0.02, size.height * 1.05);
    final Offset control = Offset(size.width * 0.38, size.height * -0.15);
    final Offset end = g.mouthCenter;

    final Offset pos = _quadBezier(start, control, end, fly);
    final double rot = fly * math.pi * 4.5;

    double ballAlpha = 1;
    double ballScale = 1;
    if (progress >= _golAt) {
      final double fade =
          ((progress - _golAt) / 0.14).clamp(0.0, 1.0);
      ballAlpha = 1 - fade;
      ballScale = 1 - fade * 0.55;
      if (ballAlpha <= 0.02) return;
    }

    if (fly < 0.92) {
      final Paint groundShadow = Paint()
        ..color = Colors.black.withValues(alpha: 0.25 * ballAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      final double shadowX = ui.lerpDouble(start.dx, end.dx, fly)!;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(shadowX, g.groundY + 3),
          width: 28 * (1 - fly * 0.5),
          height: 8,
        ),
        groundShadow,
      );
    }

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(rot);
    canvas.scale(ballScale);

    const double r = 24;
    final Paint ballBase = Paint()
      ..shader = ui.Gradient.radial(
        const Offset(-6, -8),
        r * 1.2,
        [
          Colors.white.withValues(alpha: ballAlpha),
          const Color(0xFFF0F2F5).withValues(alpha: ballAlpha),
          const Color(0xFFD0D5DC).withValues(alpha: ballAlpha * 0.95),
        ],
      );
    canvas.drawCircle(Offset.zero, r, ballBase);

    final Paint seam = Paint()
      ..color = const Color(0xFF2B2F36).withValues(alpha: 0.5 * ballAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(Offset.zero, r, seam);
    canvas.drawLine(const Offset(-r, 0), const Offset(r, 0), seam);
    canvas.drawLine(const Offset(0, -r), const Offset(0, r), seam);
    canvas.drawLine(Offset(-r * 0.72, -r * 0.72), Offset(r * 0.72, r * 0.72), seam);
    canvas.drawLine(Offset(-r * 0.72, r * 0.72), Offset(r * 0.72, -r * 0.72), seam);

    final Paint pent = Paint()
      ..color = const Color(0xFF1E2228).withValues(alpha: 0.4 * ballAlpha);
    canvas.drawCircle(Offset.zero, r * 0.32, pent);
    for (int i = 0; i < 5; i++) {
      final double a = -math.pi / 2 + i * (2 * math.pi / 5);
      canvas.drawCircle(
        Offset(math.cos(a) * r * 0.58, math.sin(a) * r * 0.58),
        r * 0.11,
        pent,
      );
    }

    canvas.restore();
  }

  void _drawCelebracionGol(Canvas canvas, _GoalGeom g) {
    final double t = ((progress - _golAt) / 0.22).clamp(0.0, 1.0);
    if (t <= 0) return;

    final double flash = t < 0.35 ? (t / 0.35) : (1 - ((t - 0.35) / 0.65));
    final Paint burst = Paint()
      ..color = const Color(0xFF49F18B).withValues(alpha: 0.28 * flash)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawCircle(g.mouthCenter, 38 * (0.6 + t * 0.5), burst);

    final TextPainter gol = TextPainter(
      text: TextSpan(
        text: '¡GOL!',
        style: TextStyle(
          color: const Color(0xFF49F18B).withValues(alpha: flash.clamp(0, 1)),
          fontSize: 22 + 6 * flash,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.6 * flash),
              blurRadius: 8,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    gol.paint(
      canvas,
      Offset(
        g.mouthCenter.dx - gol.width / 2,
        g.top - 28 - 8 * (1 - flash),
      ),
    );
  }

  Offset _quadBezier(Offset p0, Offset p1, Offset p2, double t) {
    final double u = 1 - t;
    return Offset(
      u * u * p0.dx + 2 * u * t * p1.dx + t * t * p2.dx,
      u * u * p0.dy + 2 * u * t * p1.dy + t * t * p2.dy,
    );
  }

  @override
  bool shouldRepaint(covariant _GolBienvenidaPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _GoalGeom {
  _GoalGeom({
    required this.left,
    required this.right,
    required this.top,
    required this.groundY,
    required this.backLeft,
    required this.backRight,
    required this.mouthCenter,
    required this.width,
  });

  final double left;
  final double right;
  final double top;
  final double groundY;
  final double backLeft;
  final double backRight;
  final Offset mouthCenter;
  final double width;

  factory _GoalGeom.fromSize(Size size) {
    final double left = size.width * 0.08;
    final double right = size.width * 0.92;
    final double top = size.height * 0.18;
    final double groundY = size.height * 0.88;
    return _GoalGeom(
      left: left,
      right: right,
      top: top,
      groundY: groundY,
      backLeft: left + 14,
      backRight: right - 14,
      mouthCenter: Offset((left + right) / 2, (top + groundY) / 2 + 4),
      width: right - left,
    );
  }
}
