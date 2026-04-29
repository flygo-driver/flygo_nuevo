import 'package:flutter/material.dart';

/// Cuerpo de carga con barra lineal indeterminada de borde a borde (sin spinner central).
class RaiLinearLoadingBody extends StatelessWidget {
  const RaiLinearLoadingBody({
    super.key,
    required this.backgroundColor,
    this.trackColor,
    this.barColor = Colors.greenAccent,
    this.minHeight = 3,
  });

  final Color backgroundColor;
  final Color? trackColor;
  final Color barColor;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final Brightness b = Theme.of(context).brightness;
    final Color track = trackColor ??
        (b == Brightness.dark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.08));

    return ColoredBox(
      color: backgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            height: minHeight,
            child: LinearProgressIndicator(
              minHeight: minHeight,
              backgroundColor: track,
              color: barColor,
            ),
          ),
          const Expanded(child: SizedBox.expand()),
        ],
      ),
    );
  }
}
