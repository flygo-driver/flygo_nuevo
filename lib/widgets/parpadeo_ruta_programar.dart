import 'package:flutter/material.dart';

/// Pulso suave alrededor de origen/destino en programar viaje (solo UI).
class ParpadeoRutaProgramar extends StatefulWidget {
  const ParpadeoRutaProgramar({
    super.key,
    required this.pulseColor,
    required this.child,
    this.borderRadius = 15,
  });

  final Color pulseColor;
  final Widget child;
  final double borderRadius;

  @override
  State<ParpadeoRutaProgramar> createState() => _ParpadeoRutaProgramarState();
}

class _ParpadeoRutaProgramarState extends State<ParpadeoRutaProgramar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1650),
    )..repeat(reverse: true);
    _t = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final v = _t.value;
        final glow = 0.2 + 0.5 * v;
        // La sombra en un [Container] puede capturar el área de toque; el hijo
        // queda debajo y el buscador no responde. Capa de pulso ignorada + hijo encima.
        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.passthrough,
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: widget.pulseColor.withValues(alpha: glow * 0.62),
                        blurRadius: 7 + 16 * v,
                        spreadRadius: 0.4 + 1.8 * v,
                      ),
                    ],
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }
}
