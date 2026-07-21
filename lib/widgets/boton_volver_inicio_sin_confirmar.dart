import 'package:flutter/material.dart';

/// Botón secundario para salir del flujo de cotización sin crear el viaje.
class BotonVolverInicioSinConfirmar extends StatelessWidget {
  const BotonVolverInicioSinConfirmar({
    super.key,
    required this.onPressed,
    this.mapFloating = false,
    this.compact = false,
  });

  final VoidCallback onPressed;
  final bool mapFloating;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color foreground = mapFloating
        ? Colors.white.withValues(alpha: 0.94)
        : isDark
            ? const Color(0xFFE4E7EC)
            : const Color(0xFF344054);

    final Color border = mapFloating
        ? Colors.white.withValues(alpha: 0.45)
        : isDark
            ? Colors.white.withValues(alpha: 0.24)
            : const Color(0xFFD0D5DD);

    final Color background = mapFloating
        ? const Color(0xFF0F172A).withValues(alpha: 0.55)
        : isDark
            ? const Color(0xFF1F2937)
            : Colors.white;

    final Color iconBg = mapFloating
        ? Colors.white.withValues(alpha: 0.14)
        : isDark
            ? Colors.white.withValues(alpha: 0.1)
            : const Color(0xFFF2F4F7);

    return Padding(
      padding: EdgeInsets.only(top: compact ? 6 : 10),
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: background,
          elevation: mapFloating ? 0 : (isDark ? 0 : 0.5),
          shadowColor: Colors.black.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            splashColor: foreground.withValues(alpha: 0.08),
            highlightColor: foreground.withValues(alpha: 0.05),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border, width: 1.35),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: compact ? 12 : 14,
                  horizontal: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.home_rounded,
                        size: 18,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Volver al inicio sin confirmar',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 14 : 15,
                          height: 1.2,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
