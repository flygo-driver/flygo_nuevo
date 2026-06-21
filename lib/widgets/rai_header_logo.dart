import 'package:flutter/material.dart';

/// Logo R compacto para la app **ya abierta** (cliente, taxista, Bola Ahorro).
/// No usar en splash «Movilidad inteligente» ni en login/bienvenida (ahí va
/// [logo_rai_vertical.png]).
class RaiHeaderLogo extends StatelessWidget {
  const RaiHeaderLogo({
    super.key,
    this.height = 40,
    this.semanticLabel = 'Rai',
  });

  final double height;

  /// Lectores de pantalla (no afecta el layout visual).
  final String? semanticLabel;

  static const String assetPath = 'assets/icon/logo_rai_app.png';

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color fallbackFg = cs.primary;

    final Widget image = Image.asset(
      assetPath,
      height: height,
      width: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      semanticLabel: semanticLabel,
      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
        return Container(
          height: height,
          width: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fallbackFg.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(height * 0.18),
          ),
          child: Text(
            'R',
            style: TextStyle(
              color: fallbackFg,
              fontWeight: FontWeight.w900,
              fontSize: height * 0.58,
              height: 1,
            ),
          ),
        );
      },
    );

    return SizedBox(
      height: height,
      width: height,
      child: Center(child: image),
    );
  }
}

/// Variante en línea para títulos compuestos (p. ej. «Bola · Rai · Ahorro»).
class RaiHeaderLogoInline extends StatelessWidget {
  const RaiHeaderLogoInline({super.key, this.height = 26});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: RaiHeaderLogo(height: height, semanticLabel: null),
    );
  }
}
